#!/usr/bin/env bash
set -euo pipefail
openssl genpkey -algorithm RSA -out /tmp/auth-private.pem -pkeyopt rsa_keygen_bits:2048
echo "Generated /tmp/auth-private.pem"
