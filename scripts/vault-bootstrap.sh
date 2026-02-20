#!/usr/bin/env bash
set -euo pipefail
VAULT_ADDR_BOOTSTRAP=${VAULT_ADDR:-http://localhost:8200}
VAULT_TOKEN=${VAULT_DEV_ROOT_TOKEN_ID:-root}
export VAULT_ADDR="$VAULT_ADDR_BOOTSTRAP" VAULT_TOKEN

wait_for_vault() {
  until curl -sf "$VAULT_ADDR/v1/sys/health" >/dev/null; do sleep 1; done
}

rand() { openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24; }

wait_for_vault
vault secrets enable -path=secret kv-v2 2>/dev/null || true

AUTH_DB_USER=${AUTH_DB_USER:-auth_user}
LINKS_DB_USER=${LINKS_DB_USER:-links_user}
ANALYTICS_DB_USER=${ANALYTICS_DB_USER:-analytics_user}
AUTH_DB_PASS=${AUTH_DB_PASS:-$(rand)}
LINKS_DB_PASS=${LINKS_DB_PASS:-$(rand)}
ANALYTICS_DB_PASS=${ANALYTICS_DB_PASS:-$(rand)}
INTERNAL_CLIENT_ID=${INTERNAL_CLIENT_ID:-internal-service}
INTERNAL_CLIENT_SECRET=${INTERNAL_CLIENT_SECRET:-$(rand)}

openssl genpkey -algorithm RSA -out /tmp/auth-private.pem -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1
PRIVATE_PEM=$(cat /tmp/auth-private.pem)

vault kv put secret/auth-server   auth.keys.private-pem="$PRIVATE_PEM"   auth.clients.internal-service-secret="$INTERNAL_CLIENT_SECRET"   auth.db.username="$AUTH_DB_USER"   auth.db.password="$AUTH_DB_PASS"   auth.db.schema=auth_schema
vault kv put secret/link-service   links.db.username="$LINKS_DB_USER"   links.db.password="$LINKS_DB_PASS"   links.db.schema=links_schema
vault kv put secret/analytics-service   analytics.db.username="$ANALYTICS_DB_USER"   analytics.db.password="$ANALYTICS_DB_PASS"   analytics.db.schema=analytics_schema
vault kv put secret/redirect-service   redirect.oauth.client-id="$INTERNAL_CLIENT_ID"   redirect.oauth.client-secret="$INTERNAL_CLIENT_SECRET"
# Compatibility copies for subpath-style lookups
vault kv put secret/auth-server/keys private-pem="$PRIVATE_PEM"
vault kv put secret/auth-server/clients internal-service-secret="$INTERNAL_CLIENT_SECRET"
vault kv put secret/auth-server/db username="$AUTH_DB_USER" password="$AUTH_DB_PASS" schema=auth_schema
vault kv put secret/link-service/db username="$LINKS_DB_USER" password="$LINKS_DB_PASS" schema=links_schema
vault kv put secret/analytics-service/db username="$ANALYTICS_DB_USER" password="$ANALYTICS_DB_PASS" schema=analytics_schema
vault kv put secret/redirect-service/oauth client-id="$INTERNAL_CLIENT_ID" client-secret="$INTERNAL_CLIENT_SECRET"


sync_postgres_passwords() {
  local runner=""
  if command -v podman >/dev/null 2>&1; then
    runner="podman"
  elif command -v docker >/dev/null 2>&1; then
    runner="docker"
  else
    echo "No podman/docker CLI found; skipping postgres role password sync"
    return 0
  fi

  local pg_container="url-shortener-microservices_postgres_1"
  if ! "$runner" ps --format '{{.Names}}' | grep -qx "$pg_container"; then
    echo "Postgres container '$pg_container' not running; skipping role password sync"
    return 0
  fi

  "$runner" exec "$pg_container" psql -U postgres -d url_shortener <<SQL >/dev/null
ALTER ROLE auth_user WITH PASSWORD '${AUTH_DB_PASS}';
ALTER ROLE links_user WITH PASSWORD '${LINKS_DB_PASS}';
ALTER ROLE analytics_user WITH PASSWORD '${ANALYTICS_DB_PASS}';
SQL

  echo "Postgres role passwords synchronized with generated .env values"
}

make_policy() {
  local name=$1 path=$2
  cat <<POL | vault policy write "$name" -
path "secret/data/$path/*" { capabilities = ["read"] }
POL
}
make_policy auth-server auth-server
make_policy link-service link-service
make_policy redirect-service redirect-service
make_policy analytics-service analytics-service
make_policy api-gateway api-gateway

vault auth enable approle 2>/dev/null || true

create_approle() {
  local service=$1 role_var=$2 secret_var=$3
  local role_id secret_id
  vault write auth/approle/role/$service token_policies=$service token_ttl=1h token_max_ttl=4h >/dev/null
  role_id=$(vault read -field=role_id auth/approle/role/$service/role-id)
  secret_id=$(vault write -f -field=secret_id auth/approle/role/$service/secret-id)
  printf -v "$role_var" '%s' "$role_id"
  printf -v "$secret_var" '%s' "$secret_id"
}

sync_postgres_passwords

create_approle auth-server AUTH_SERVER_VAULT_ROLE_ID AUTH_SERVER_VAULT_SECRET_ID
create_approle link-service LINK_SERVICE_VAULT_ROLE_ID LINK_SERVICE_VAULT_SECRET_ID
create_approle redirect-service REDIRECT_SERVICE_VAULT_ROLE_ID REDIRECT_SERVICE_VAULT_SECRET_ID
create_approle analytics-service ANALYTICS_SERVICE_VAULT_ROLE_ID ANALYTICS_SERVICE_VAULT_SECRET_ID
create_approle api-gateway API_GATEWAY_VAULT_ROLE_ID API_GATEWAY_VAULT_SECRET_ID

cat > .env <<ENV
VAULT_ADDR=http://vault:8200
VAULT_DEV_ROOT_TOKEN_ID=$VAULT_TOKEN
AUTH_DB_USER=$AUTH_DB_USER
LINKS_DB_USER=$LINKS_DB_USER
ANALYTICS_DB_USER=$ANALYTICS_DB_USER
AUTH_DB_PASS=$AUTH_DB_PASS
LINKS_DB_PASS=$LINKS_DB_PASS
ANALYTICS_DB_PASS=$ANALYTICS_DB_PASS
INTERNAL_CLIENT_ID=$INTERNAL_CLIENT_ID
INTERNAL_CLIENT_SECRET=$INTERNAL_CLIENT_SECRET
AUTH_SERVER_VAULT_ROLE_ID=$AUTH_SERVER_VAULT_ROLE_ID
AUTH_SERVER_VAULT_SECRET_ID=$AUTH_SERVER_VAULT_SECRET_ID
LINK_SERVICE_VAULT_ROLE_ID=$LINK_SERVICE_VAULT_ROLE_ID
LINK_SERVICE_VAULT_SECRET_ID=$LINK_SERVICE_VAULT_SECRET_ID
REDIRECT_SERVICE_VAULT_ROLE_ID=$REDIRECT_SERVICE_VAULT_ROLE_ID
REDIRECT_SERVICE_VAULT_SECRET_ID=$REDIRECT_SERVICE_VAULT_SECRET_ID
ANALYTICS_SERVICE_VAULT_ROLE_ID=$ANALYTICS_SERVICE_VAULT_ROLE_ID
ANALYTICS_SERVICE_VAULT_SECRET_ID=$ANALYTICS_SERVICE_VAULT_SECRET_ID
API_GATEWAY_VAULT_ROLE_ID=$API_GATEWAY_VAULT_ROLE_ID
API_GATEWAY_VAULT_SECRET_ID=$API_GATEWAY_VAULT_SECRET_ID
ENV

echo ".env generated"
