import asyncio
import json
import time
from typing import Any, Callable, Dict, Optional, Tuple

import httpx


class TokenBucket:
    def __init__(self, capacity: int, refill_per_sec: float):
        self.capacity = capacity
        self.refill_per_sec = refill_per_sec
        self.tokens = capacity
        self.last = time.monotonic()

    def allow(self, cost: float = 1.0) -> bool:
        now = time.monotonic()
        elapsed = now - self.last
        self.last = now
        self.tokens = min(self.capacity, self.tokens + elapsed * self.refill_per_sec)
        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False


class CircuitBreaker:
    def __init__(self, failure_threshold: int = 5, cooldown_sec: float = 30.0):
        self.failure_threshold = failure_threshold
        self.cooldown_sec = cooldown_sec
        self.failures = 0
        self.state = "CLOSED"  # CLOSED | OPEN | HALF_OPEN
        self.opened_at: Optional[float] = None

    def on_success(self):
        self.failures = 0
        self.state = "CLOSED"
        self.opened_at = None

    def on_failure(self):
        self.failures += 1
        if self.failures >= self.failure_threshold and self.state != "OPEN":
            self.state = "OPEN"
            self.opened_at = time.monotonic()

    def can_call(self) -> bool:
        if self.state == "CLOSED":
            return True
        if self.state == "OPEN":
            assert self.opened_at is not None
            if (time.monotonic() - self.opened_at) >= self.cooldown_sec:
                self.state = "HALF_OPEN"
                return True
            return False
        if self.state == "HALF_OPEN":
            return True
        return True


def _retry_after_delay(retry_after: str, default: float) -> float:
    try:
        # value in seconds
        return float(retry_after)
    except Exception:
        return default


async def call_with_retries(
    fetcher: Callable[[], Any],
    max_retries: int = 3,
    base: float = 0.5,
    cap: float = 20.0,
) -> Tuple[httpx.Response, int]:
    """Call fetcher with retry policy for 408/429/5xx/timeout. Returns (response, attempts)."""
    attempt = 0
    while True:
        try:
            resp = await fetcher()
            retryable = resp.status_code in (408, 429, 500, 502, 503, 504)
            if not retryable:
                return resp, attempt
            if attempt >= max_retries:
                return resp, attempt
            retry_after = resp.headers.get("retry-after") or resp.headers.get("Retry-After")
            delay = _retry_after_delay(retry_after, min(cap, base * (2 ** attempt))) if retry_after else min(cap, base * (2 ** attempt))
        except (httpx.ReadTimeout, httpx.ConnectTimeout):
            if attempt >= max_retries:
                raise
            delay = min(cap, base * (2 ** attempt))
        # jitter
        delay += (0.5 * (attempt + 1)) * 0.1
        await asyncio.sleep(delay)
        attempt += 1


class IdempotencyCache:
    def __init__(self):
        self._store: Dict[str, Dict[str, Any]] = {}

    def get(self, key: Optional[str]) -> Optional[Dict[str, Any]]:
        if not key:
            return None
        return self._store.get(key)

    def set(self, key: Optional[str], value: Dict[str, Any]) -> None:
        if not key:
            return
        self._store[key] = value


def sanitize_text(text: str) -> str:
    # simple server-side sanitize
    # remove script tags and on* handlers
    return (
        text.replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", " ")
    )


def basic_moderation(text: str) -> Tuple[bool, Optional[str]]:
    banned = ["suicide", "kill", "gun", "terror"]
    t = text.lower()
    for w in banned:
        if w in t:
            return False, f"flagged:{w}"
    return True, None


def structured_output_or_fallback(content: Dict[str, Any], schema: Dict[str, Any]) -> Tuple[Dict[str, Any], str]:
    """Validate content against a very small subset of JSON Schema; fallback if invalid."""
    try:
        # Minimal check: required keys and types if provided
        required = schema.get("required", [])
        for k in required:
            assert k in content
        props = schema.get("properties", {})
        for k, v in content.items():
            if k in props:
                typ = props[k].get("type")
                if typ == "string":
                    assert isinstance(v, str)
                if typ == "array":
                    assert isinstance(v, list)
                if typ == "object":
                    assert isinstance(v, dict)
        return content, "validated"
    except Exception:
        # fallback template
        fallback = {"headline": "Safe card", "steps": ["Take a breath", "One small step"], "cta_time": "tonight 21:00"}
        return fallback, "fallback"

