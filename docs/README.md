# URL Shortener Microservices Runbook

## Stack
Java 21, Spring Boot 4.0.1, Spring Cloud 2025.1.0, Spring Security 7 / Authorization Server, Postgres + Redis + Vault.

## 1) Start infrastructure
```bash
docker compose up -d vault postgres redis
```

## 2) Bootstrap Vault and env vars
```bash
chmod +x scripts/vault-bootstrap.sh
./scripts/vault-bootstrap.sh
```
This creates `.env` (local only) with DB passwords and AppRole credentials.

## 3) Start all services
```bash
docker compose up -d --build
```

## 4) Obtain token (client credentials)
```bash
TOKEN=$(curl -s -u internal-service:${INTERNAL_CLIENT_SECRET} \
  -d grant_type=client_credentials \
  -d scope=internal \
  http://localhost:9000/oauth2/token | jq -r .access_token)
```

## 5) Create short link via gateway
```bash
USER_TOKEN="<token_for_user1_from_auth_code_pkce_or_password_grant_if_enabled>"
curl -X POST http://localhost:8080/api/links/links \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"longUrl":"https://spring.io"}'
```

## 6) Redirect
```bash
curl -i http://localhost:8080/r/<code>
```

## 7) Fetch analytics
```bash
curl -H "Authorization: Bearer $USER_TOKEN" http://localhost:8080/api/analytics/<code>
```

## PKCE note
Authorization Code + PKCE is enabled for `gateway-public` client in auth-server.
Use your browser client to initiate `/oauth2/authorize` with `code_challenge` and exchange `code_verifier` at `/oauth2/token`.
