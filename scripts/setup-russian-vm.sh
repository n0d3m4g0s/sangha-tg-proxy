#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

RUSSIAN_VM="${RUSSIAN_VM_IP}"

echo "=== Provisioning Russian VM ($RUSSIAN_VM) ==="

ssh root@"$RUSSIAN_VM" bash -s <<REMOTE
set -euo pipefail

echo "--- System update ---"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

echo "--- Install packages ---"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban ufw

systemctl enable --now fail2ban

echo "--- Firewall ---"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow ${PUBLIC_PORT:-443}/tcp
ufw allow ${VLESS_PORT:-8443}/tcp
ufw --force enable

echo "--- SSH keys for root (owner) ---"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
grep -qF '${OWNER_PUB_KEY}' /root/.ssh/authorized_keys 2>/dev/null || echo '${OWNER_PUB_KEY}' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "--- Harden SSH ---"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "=== Russian VM provisioned ==="
REMOTE

echo "Done."
