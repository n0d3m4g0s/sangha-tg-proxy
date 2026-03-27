#!/usr/bin/env bash
set -euo pipefail

# Config — passed as env vars or sourced from .env
BOT_TOKEN="${SANGHA_BOT_TOKEN:-}"
CHAT_ID="${SANGHA_ADMIN_CHAT_ID:-}"
RUSSIAN_VM_IP="${RUSSIAN_VM_IP:-}"
DUTCH_VM_IP="${DUTCH_VM_IP:-}"
PUBLIC_PORT="${PUBLIC_PORT:-443}"
PROXY_PORT="${PROXY_PORT:-3128}"

STATE_FILE="/tmp/sangha-proxy-alert-state"

alert() {
    local msg="$1"
    # Deduplicate: don't send same alert within 30 min
    local hash
    hash=$(echo "$msg" | md5sum | cut -d' ' -f1)
    if [ -f "$STATE_FILE" ] && grep -q "$hash" "$STATE_FILE" 2>/dev/null; then
        local last
        last=$(grep "$hash" "$STATE_FILE" | cut -d' ' -f2)
        local now
        now=$(date +%s)
        if [ $((now - last)) -lt 1800 ]; then
            return
        fi
    fi

    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="${CHAT_ID}" \
            -d text="${msg}" \
            -d parse_mode=HTML >/dev/null 2>&1 || true
    fi

    # Update state
    grep -v "$hash" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp" || true
    echo "$hash $(date +%s)" >> "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

ERRORS=0

# ── Russian VM checks ────────────────────────────────────
if [ -n "$RUSSIAN_VM_IP" ] && ip addr show 2>/dev/null | grep -q "$RUSSIAN_VM_IP"; then
    if ! systemctl is-active --quiet autossh-tunnel.service 2>/dev/null; then
        alert "🔴 <b>[RU VM]</b> autossh-tunnel DOWN — tunnel not running"
        ERRORS=$((ERRORS + 1))
    fi
    if ! ss -tlnp 2>/dev/null | grep -q ":${PUBLIC_PORT}"; then
        alert "🔴 <b>[RU VM]</b> Port ${PUBLIC_PORT} not listening — users can't connect"
        ERRORS=$((ERRORS + 1))
    fi
fi

# ── Dutch VM checks ──────────────────────────────────────
if [ -n "$DUTCH_VM_IP" ] && ip addr show 2>/dev/null | grep -q "$DUTCH_VM_IP"; then
    if ! docker inspect -f '{{.State.Running}}' sangha-mtproto 2>/dev/null | grep -q true; then
        alert "🔴 <b>[NL VM]</b> sangha-mtproto container DOWN — proxy offline"
        ERRORS=$((ERRORS + 1))
    fi
    if ! docker inspect -f '{{.State.Running}}' sangha-api 2>/dev/null | grep -q true; then
        alert "🟡 <b>[NL VM]</b> sangha-api container DOWN — user management unavailable"
        ERRORS=$((ERRORS + 1))
    fi
    if ! ss -tlnp 2>/dev/null | grep -q ":${PROXY_PORT}"; then
        alert "🔴 <b>[NL VM]</b> Port ${PROXY_PORT} not listening — proxy offline"
        ERRORS=$((ERRORS + 1))
    fi

    # Check disk space (alert if <10% free)
    local_free=$(df / | awk 'NR==2 {print 100-$5}' | tr -d '%')
    if [ "${local_free:-100}" -lt 10 ]; then
        alert "🟡 <b>[NL VM]</b> Disk space low: ${local_free}% free"
        ERRORS=$((ERRORS + 1))
    fi

    # Check RAM (alert if <10% free)
    mem_free_pct=$(free | awk '/Mem:/ {printf "%.0f", $7/$2*100}')
    if [ "${mem_free_pct:-100}" -lt 10 ]; then
        alert "🟡 <b>[NL VM]</b> RAM low: ${mem_free_pct}% available"
        ERRORS=$((ERRORS + 1))
    fi
fi

exit $ERRORS
