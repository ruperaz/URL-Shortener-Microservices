#!/usr/bin/env bash
set -euo pipefail

# This script runs on the HOST (e.g. WSL). Vault's port is published to the
# host as localhost:8200, so always use that for host-side CLI calls.
# Do NOT inherit VAULT_ADDR from the shell: it may contain the
# container-internal hostname (http://vault:8200) which is unreachable here.
# Override VAULT_HOST_ADDR if your Vault is on a non-default address.
VAULT_ADDR=${VAULT_HOST_ADDR:-http://localhost:8200}
export VAULT_ADDR

# Path where the init keys (unseal key + root token) are persisted on the host.
# Kept outside version control — never commit this file.
VAULT_KEYS_FILE=${VAULT_KEYS_FILE:-.vault-keys}

rand() { openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24; }

# ---------------------------------------------------------------------------
# 1. Wait for the Vault process to be reachable (any HTTP response is fine;
#    501 = not initialised, 503 = sealed, 200 = ready).
# ---------------------------------------------------------------------------
wait_for_vault() {
  echo "Waiting for Vault to be reachable..."
  until curl -s -o /dev/null "$VAULT_ADDR/v1/sys/health"; do
    sleep 1
  done
  echo "Vault is reachable."
}

# ---------------------------------------------------------------------------
# 2. Initialise Vault (first run only).  Uses 1-of-1 Shamir shares to keep
#    local development simple.  Saves the unseal key and root token to
#    $VAULT_KEYS_FILE on the host.
# ---------------------------------------------------------------------------
init_vault() {
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health")

  if [ "$http_code" = "501" ]; then
    echo "Vault is uninitialised — running vault operator init..."
    local init_out
    init_out=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

    local unseal_key root_token
    unseal_key=$(printf '%s' "$init_out" | grep -o '"unseal_keys_b64":\["[^"]*"' | grep -o '[^"]*"$' | tr -d '"')
    root_token=$(printf '%s' "$init_out" | grep -o '"root_token":"[^"]*"' | grep -o '[^"]*"$' | tr -d '"')

    # Persist so we can unseal on every restart
    cat > "$VAULT_KEYS_FILE" <<KEYS
VAULT_UNSEAL_KEY=$unseal_key
VAULT_ROOT_TOKEN=$root_token
KEYS
    chmod 600 "$VAULT_KEYS_FILE"
    echo "Vault initialised. Keys saved to $VAULT_KEYS_FILE"
  fi
}

# ---------------------------------------------------------------------------
# 3. Unseal Vault if it is currently sealed.
# ---------------------------------------------------------------------------
unseal_vault() {
  if [ ! -f "$VAULT_KEYS_FILE" ]; then
    echo "ERROR: $VAULT_KEYS_FILE not found. Cannot unseal Vault." >&2
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$VAULT_KEYS_FILE"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health")

  if [ "$http_code" = "503" ]; then
    echo "Vault is sealed — unsealing..."
    vault operator unseal "$VAULT_UNSEAL_KEY"
    echo "Vault unsealed."
  else
    echo "Vault is already unsealed (status $http_code)."
  fi
}

# ---------------------------------------------------------------------------
# 4. Wait until Vault is fully unsealed (HTTP 200).
# ---------------------------------------------------------------------------
wait_for_unsealed() {
  echo "Waiting for Vault to become active..."
  until [ "$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health")" = "200" ]; do
    sleep 1
  done
  echo "Vault is active."
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
wait_for_vault
init_vault
unseal_vault
wait_for_unsealed

# Load root token for subsequent vault CLI calls
# shellcheck source=/dev/null
source "$VAULT_KEYS_FILE"
VAULT_TOKEN=$VAULT_ROOT_TOKEN
export VAULT_TOKEN

vault secrets enable -path=secret kv-v2 2>/dev/null || true

AUTH_DB_PASS=${AUTH_DB_PASS:-$(rand)}
LINKS_DB_PASS=${LINKS_DB_PASS:-$(rand)}
ANALYTICS_DB_PASS=${ANALYTICS_DB_PASS:-$(rand)}
INTERNAL_CLIENT_SECRET=${INTERNAL_CLIENT_SECRET:-$(rand)}

openssl genpkey -algorithm RSA -out /tmp/auth-private.pem -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1
PRIVATE_PEM=$(cat /tmp/auth-private.pem)

vault kv put secret/auth-server/keys private-pem="$PRIVATE_PEM"
vault kv put secret/auth-server/clients internal-service-secret="$INTERNAL_CLIENT_SECRET"
vault kv put secret/auth-server/db username=auth_user password="$AUTH_DB_PASS" schema=auth_schema
vault kv put secret/link-service/db username=links_user password="$LINKS_DB_PASS" schema=links_schema
vault kv put secret/analytics-service/db username=analytics_user password="$ANALYTICS_DB_PASS" schema=analytics_schema
vault kv put secret/redirect-service/oauth client-id=internal-service client-secret="$INTERNAL_CLIENT_SECRET"

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

make_approle() {
  local service=$1
  vault auth enable approle 2>/dev/null || true
  vault write auth/approle/role/$service token_policies=$service token_ttl=1h token_max_ttl=4h >/dev/null
  local role_id secret_id
  role_id=$(vault read -field=role_id auth/approle/role/$service/role-id)
  secret_id=$(vault write -f -field=secret_id auth/approle/role/$service/secret-id)
  echo "$role_id" "$secret_id"
}

read AUTH_SERVER_VAULT_ROLE_ID AUTH_SERVER_VAULT_SECRET_ID < <(make_approle auth-server)
read LINK_SERVICE_VAULT_ROLE_ID LINK_SERVICE_VAULT_SECRET_ID < <(make_approle link-service)
read REDIRECT_SERVICE_VAULT_ROLE_ID REDIRECT_SERVICE_VAULT_SECRET_ID < <(make_approle redirect-service)
read ANALYTICS_SERVICE_VAULT_ROLE_ID ANALYTICS_SERVICE_VAULT_SECRET_ID < <(make_approle analytics-service)
read API_GATEWAY_VAULT_ROLE_ID API_GATEWAY_VAULT_SECRET_ID < <(make_approle api-gateway)

cat > .env <<ENV
VAULT_ADDR=${VAULT_CONTAINER_ADDR:-http://vault:8200}
AUTH_DB_PASS=$AUTH_DB_PASS
LINKS_DB_PASS=$LINKS_DB_PASS
ANALYTICS_DB_PASS=$ANALYTICS_DB_PASS
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

# ---------------------------------------------------------------------------
# Sync the generated passwords into the running postgres instance so that
# Vault secrets and database credentials always match, regardless of whether
# postgres was started before or after this script ran.
# ---------------------------------------------------------------------------
sync_postgres_passwords() {
  local sql
  sql="ALTER ROLE auth_user WITH LOGIN PASSWORD '$AUTH_DB_PASS';"
  sql="$sql ALTER ROLE links_user WITH LOGIN PASSWORD '$LINKS_DB_PASS';"
  sql="$sql ALTER ROLE analytics_user WITH LOGIN PASSWORD '$ANALYTICS_DB_PASS';"

  local pg_host="${POSTGRES_HOST:-localhost}"
  local pg_port="${POSTGRES_PORT:-5432}"

  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD=postgres psql -h "$pg_host" -p "$pg_port" -U postgres -d url_shortener -c "$sql"
    return
  fi

  # Fall back to running psql inside the postgres container.
  local runtime container
  if command -v podman >/dev/null 2>&1; then
    runtime=podman
    container=$(podman ps --filter "name=postgres" --format "{{.Names}}" | head -1)
  elif command -v docker >/dev/null 2>&1; then
    runtime=docker
    container=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -1)
  fi

  if [ -n "${container:-}" ]; then
    "$runtime" exec "$container" psql -U postgres -d url_shortener -c "$sql"
  else
    echo "WARNING: psql not found and no running postgres container detected." >&2
    echo "Manually run the following against your postgres instance:" >&2
    echo "  $sql" >&2
    return 1
  fi
}

echo "Syncing passwords to postgres..."
sync_postgres_passwords
echo "Postgres passwords synchronized"
