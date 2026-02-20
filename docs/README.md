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


## WSL + Podman notes (important)
If you are running in WSL with Podman, use Podman Compose equivalents:
```bash
podman compose up -d vault postgres redis
./scripts/vault-bootstrap.sh
podman compose up -d --build
```
(If your distro uses `podman-compose`, use that command instead.)

### Fix for `/usr/bin/env: ‘bash\r’: No such file or directory`
This means the script has Windows CRLF line endings. Convert to LF and rerun:
```bash
sed -i 's/\r$//' scripts/vault-bootstrap.sh
chmod +x scripts/vault-bootstrap.sh
./scripts/vault-bootstrap.sh
```
You can normalize all shell scripts too:
```bash
find scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} +
```
A repository `.gitattributes` is included to keep LF line endings for shell/config files going forward.


### Podman short-name resolution fix
If you see errors like:
- `short-name "maven:3.9.9-eclipse-temurin-21" did not resolve`
- `short-name "url-shortener-microservices_api-gateway" did not resolve`

Use these steps:
1. Ensure image names are fully qualified (`docker.io/...`) for external base/infra images. App service images are built from local Dockerfiles via compose `build:`.
2. Pull base images explicitly once:
```bash
podman pull docker.io/library/maven:3.9.9-eclipse-temurin-21
podman pull docker.io/library/eclipse-temurin:21-jre
podman pull docker.io/hashicorp/vault:1.18
podman pull docker.io/library/postgres:17-alpine
podman pull docker.io/library/redis:7-alpine
```
3. Retry build/run:
```bash
podman compose down
podman compose build
podman compose up -d
```
4. If your host still enforces strict short-name mode for other projects, configure `/etc/containers/registries.conf` with unqualified registries (for example `docker.io`) or use fully-qualified image names everywhere.


If compose still tries to pull `localhost/...`, remove old cached compose state and retry:
```bash
podman compose down --remove-orphans
podman image prune -f
podman compose build
podman compose up -d
```


### Fix for `Non-resolvable parent POM ... com.example:url-shortener-microservices`
If podman-compose builds each module with only module-local context, Maven cannot see the root parent `pom.xml`.
This repo is configured so each service build uses **repo root context** with per-service Dockerfile, and each Dockerfile runs Maven with `-f <module>/pom.xml` so sibling modules are not required during image build.
Use:
```bash
podman compose build --no-cache
podman compose up -d
```
Note: Docker image builds use `-Dmaven.test.skip=true` in service Dockerfiles so Podman builds do not fail during test compilation in constrained/partial build contexts.

If an old podman-compose state persists, reset and rebuild:
```bash
podman compose down --remove-orphans
podman system prune -f
podman compose build --no-cache
podman compose up -d
```




### Podman-compose dependency graph error fix (`depends on container ... not found in input list`)
This is a known fragility in older `podman-compose` (1.0.6) when translating `depends_on`/healthcheck wiring to `podman --requires`.
This repo now avoids that path and uses restart policies.

Use this exact recovery flow:
```bash
podman compose down --remove-orphans
podman rm -f $(podman ps -aq --filter label=io.podman.compose.project=url-shortener-microservices) 2>/dev/null || true
podman network rm url-shortener-microservices_default 2>/dev/null || true

podman compose build --no-cache
podman compose up -d vault postgres redis
./scripts/vault-bootstrap.sh
podman compose up -d auth-server link-service analytics-service redirect-service api-gateway
```
