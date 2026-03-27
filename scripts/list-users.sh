#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

RESPONSE=$(ssh root@"${DUTCH_VM_IP}" "curl -s 'http://127.0.0.1:8443/api/list-users' \
    -H 'X-API-Key: ${SANGHA_API_KEY}'")

echo "$RESPONSE" | python3 -m json.tool
