#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

USERNAME="${1:?Usage: $0 <username>}"

RESPONSE=$(ssh root@"${DUTCH_VM_IP}" "curl -s -X POST 'http://127.0.0.1:8443/api/remove-user' \
    -H 'Content-Type: application/json' \
    -H 'X-API-Key: ${SANGHA_API_KEY}' \
    -d '{\"username\": \"${USERNAME}\"}'")

echo "$RESPONSE" | python3 -m json.tool
