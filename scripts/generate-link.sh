#!/usr/bin/env bash
set -euo pipefail

SECRET="${1:?Usage: $0 <32-hex-char-secret>}"
TLS_DOMAIN="${TLS_DOMAIN:-www.google.com}"
SERVER="${PUBLIC_SERVER:-tg.rigpa.space}"
PORT="${PUBLIC_PORT:-443}"

DOMAIN_HEX=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"

echo "tg://proxy?server=${SERVER}&port=${PORT}&secret=${FULL_SECRET}"
echo "https://t.me/proxy?server=${SERVER}&port=${PORT}&secret=${FULL_SECRET}"
