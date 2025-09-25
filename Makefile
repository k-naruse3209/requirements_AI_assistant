SHELL := /bin/bash

build:
	docker compose build

up:
	docker compose up --build

down:
	docker compose down -v

logs:
	docker compose logs -f gateway

test:
	docker compose up --build --exit-code-from tester tester

