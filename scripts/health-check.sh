#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

echo "=== Health Check ==="

echo ""
echo "--- Russian VM (${RUSSIAN_VM_HOST:-$RUSSIAN_VM_IP}) ---"
ssh root@"${RUSSIAN_VM_IP}" bash -s <<'REMOTE'
echo "nginx: $(systemctl is-active nginx 2>/dev/null || echo 'not running')"
if ss -tlnp | grep -q ':443'; then
    echo "port 443: LISTENING"
else
    echo "port 443: NOT LISTENING"
fi
REMOTE

echo ""
echo "--- Dutch VM (${DUTCH_VM_HOST:-$DUTCH_VM_IP}) ---"
ssh root@"${DUTCH_VM_IP}" bash -s <<'REMOTE'
if command -v docker &>/dev/null; then
    echo "sangha-mtproto: $(docker inspect -f '{{.State.Status}}' sangha-mtproto 2>/dev/null || echo 'not found')"
    echo "sangha-api: $(docker inspect -f '{{.State.Status}}' sangha-api 2>/dev/null || echo 'not found')"
else
    echo "docker: not installed"
fi
if ss -tlnp | grep -q ':3128'; then
    echo "port 3128: LISTENING"
else
    echo "port 3128: NOT LISTENING"
fi
if ss -tlnp | grep -q ':8443'; then
    echo "port 8443: LISTENING"
else
    echo "port 8443: NOT LISTENING"
fi
REMOTE

echo ""
echo "--- API Health ---"
ssh root@"${DUTCH_VM_IP}" "curl -s http://127.0.0.1:8443/api/health -H 'X-API-Key: ${SANGHA_API_KEY}'" 2>/dev/null | python3 -m json.tool || echo "API unreachable"
