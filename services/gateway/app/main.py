import os
import json
import asyncio
from typing import Any, Dict, Optional

import httpx
import pymysql
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from .utils import (
    TokenBucket,
    CircuitBreaker,
    IdempotencyCache,
    call_with_retries,
    sanitize_text,
    basic_moderation,
    structured_output_or_fallback,
)


DB_HOST = os.getenv("DB_HOST", "mysql")
DB_USER = os.getenv("DB_USER", "root")
DB_PASS = os.getenv("DB_PASS", "password")
DB_NAME = os.getenv("DB_NAME", "ai_coach")

SYMANTO_API_BASE = os.getenv("SYMANTO_API_BASE", "https://symanto.example")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE", "https://openai.example")

SYMANTO_STUB = os.getenv("SYMANTO_STUB", "1") == "1"
OPENAI_STUB = os.getenv("OPENAI_STUB", "1") == "1"

app = FastAPI()

# Simple in-memory controls
token_buckets: Dict[str, TokenBucket] = {
    "symanto": TokenBucket(capacity=10, refill_per_sec=5),
    "openai": TokenBucket(capacity=10, refill_per_sec=5),
}
circuits: Dict[str, CircuitBreaker] = {
    "symanto": CircuitBreaker(),
    "openai": CircuitBreaker(),
}
idem = IdempotencyCache()


def audit(module: str, action: str, payload: Dict[str, Any], user_id: Optional[int] = None) -> None:
    try:
        conn = pymysql.connect(
            host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, autocommit=True
        )
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO audit_log(user_id, module, action, payload) VALUES(%s,%s,%s,%s)",
                (user_id, module, action, json.dumps(payload, ensure_ascii=False)),
            )
        conn.close()
    except Exception:
        # best-effort
        pass


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/symanto-proxy")
async def symanto_proxy(request: Request, idempotency_key: Optional[str] = Header(default=None)):
    body = await request.json()
    audit("gateway", "symanto-proxy:request", body)

    cached = idem.get(idempotency_key)
    if cached:
        return JSONResponse(cached)

    if not token_buckets["symanto"].allow():
        circuits["symanto"].on_failure()
        raise HTTPException(status_code=429, detail="rate limited")

    # Circuit breaker gate
    if not circuits["symanto"].can_call():
        raise HTTPException(status_code=503, detail="circuit open")

    async def do_call():
        if SYMANTO_STUB:
            # pseudo failure triggers
            mode = body.get("_mode")
            status = 200
            if mode == "429":
                status = 429
            elif mode == "500":
                status = 500
            content = {"O": 0.61, "C": 0.44, "E": 0.52, "A": 0.58, "N": 0.41}
            return httpx.Response(status_code=status, json=content)
        async with httpx.AsyncClient(timeout=10.0) as client:
            return await client.post(f"{SYMANTO_API_BASE}/big5", json=body)

    try:
        resp, attempts = await call_with_retries(do_call)
        if resp.status_code >= 400:
            circuits["symanto"].on_failure()
            raise HTTPException(status_code=resp.status_code, detail=resp.text)
        circuits["symanto"].on_success()
        data = resp.json()
    except Exception as e:
        circuits["symanto"].on_failure()
        raise HTTPException(status_code=502, detail=str(e))

    result = {"attempts": attempts + 1, "data": data}
    idem.set(idempotency_key, result)
    audit("gateway", "symanto-proxy:response", result)
    return JSONResponse(result)


@app.post("/openai-proxy")
async def openai_proxy(request: Request, idempotency_key: Optional[str] = Header(default=None)):
    body = await request.json()
    audit("gateway", "openai-proxy:request", body)

    cached = idem.get(idempotency_key)
    if cached:
        return JSONResponse(cached)

    prompt = str(body.get("prompt", "")).strip()
    schema = body.get("schema", {"type": "object", "required": [], "properties": {}})

    # Moderation
    ok, reason = basic_moderation(prompt)
    if not ok:
        safe = {"headline": "Content moderated", "steps": ["Rephrase request"], "reason": reason}
        audit("gateway", "openai-proxy:moderation_block", {"reason": reason})
        idem.set(idempotency_key, safe)
        return JSONResponse(safe, status_code=200)

    # Generate (stubbed) and Structured Outputs
    if OPENAI_STUB:
        # Very naive generation
        content = {
            "headline": prompt[:60] or "Daily suggestion",
            "steps": ["Small step", "Another small step"],
            "cta_time": "21:00"
        }
    else:
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(f"{OPENAI_API_BASE}/responses", json=body)
            content = r.json()

    # Structured Outputs validate or fallback
    structured, stage = structured_output_or_fallback(content, schema)
    # Sanitize text fields
    for k, v in list(structured.items()):
        if isinstance(v, str):
            structured[k] = sanitize_text(v)
        if isinstance(v, list):
            structured[k] = [sanitize_text(x) if isinstance(x, str) else x for x in v]

    result = {"stage": stage, "card": structured}
    audit("gateway", "openai-proxy:response", result)
    idem.set(idempotency_key, result)
    return JSONResponse(result)

