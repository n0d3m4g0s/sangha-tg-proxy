#!/usr/bin/env bash
set -euo pipefail

MESSAGE="${1:?Usage: $0 <message>}"

BOT_TOKEN="${SANGHA_BOT_TOKEN:?Set SANGHA_BOT_TOKEN}"
CHAT_ID="${SANGHA_ADMIN_CHAT_ID:?Set SANGHA_ADMIN_CHAT_ID}"

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode=HTML \
    >/dev/null
