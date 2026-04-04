#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEYS_DIR="$PROJECT_DIR/keys"

mkdir -p "$KEYS_DIR"

# Deploy key (local → VMs)
if [ ! -f "$KEYS_DIR/deploy_ed25519" ]; then
    echo "Generating deploy SSH key..."
    ssh-keygen -t ed25519 -f "$KEYS_DIR/deploy_ed25519" -N "" -C "sangha-deploy"
    echo "Deploy key generated: $KEYS_DIR/deploy_ed25519"
else
    echo "Deploy key already exists, skipping."
fi

echo ""
echo "Keys are in: $KEYS_DIR"
echo "Deploy public key:"
cat "$KEYS_DIR/deploy_ed25519.pub"
