#!/usr/bin/env bash
# Bootstrap a fresh Debian/Ubuntu server: admin user, SSH hardening, UFW, fail2ban,
# unattended-upgrades. Idempotent. Use DRY_RUN=1 to preview.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --user NAME --pubkey "ssh-ed25519 AAAA..." [--ssh-port 22] [--allow PORT]...
  --user      admin user to create (sudo, key-only login)
  --pubkey    public key for the admin user (or --pubkey-file PATH)
  --ssh-port  SSH port (default 22)
  --allow     extra TCP port to open in UFW (repeatable), e.g. --allow 80 --allow 443
USAGE
}

USER_NAME="" PUBKEY="" SSH_PORT=22 ALLOW=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="$2"; shift 2 ;;
    --pubkey) PUBKEY="$2"; shift 2 ;;
    --pubkey-file) PUBKEY="$(<"$2")"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --allow) ALLOW+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
done

is_valid_username "$USER_NAME" || die "invalid or missing --user"
[[ "$PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-) ]] || die "missing or invalid --pubkey"
is_valid_port "$SSH_PORT" || die "invalid --ssh-port: $SSH_PORT"
for p in "${ALLOW[@]}"; do is_valid_port "$p" || die "invalid --allow port: $p"; done
require_root

log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
run_cmd apt-get update -qq
run_cmd apt-get install -y -qq ufw fail2ban unattended-upgrades sudo curl ca-certificates

log "Creating admin user $USER_NAME"
if ! id "$USER_NAME" >/dev/null 2>&1; then
  run_cmd useradd -m -s /bin/bash -G sudo "$USER_NAME"
fi
run_cmd install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "[dry-run] write authorized_keys for $USER_NAME"
else
  grep -qxF "$PUBKEY" "/home/$USER_NAME/.ssh/authorized_keys" 2>/dev/null \
    || echo "$PUBKEY" >> "/home/$USER_NAME/.ssh/authorized_keys"
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh/authorized_keys"
  chmod 600 "/home/$USER_NAME/.ssh/authorized_keys"
fi

log "Hardening SSH (port $SSH_PORT, keys only, no root login)"
SSHD_DROPIN="/etc/ssh/sshd_config.d/10-hardening.conf"
SSHD_CONF="Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers $USER_NAME"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf '[dry-run] write %s:\n%s\n' "$SSHD_DROPIN" "$SSHD_CONF"
else
  install_sshd_dropin "$SSHD_DROPIN" "$SSHD_CONF" || die "sshd config test failed, not reloading"
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
fi

log "Configuring UFW"
run_cmd ufw default deny incoming
run_cmd ufw default allow outgoing
run_cmd ufw limit "$SSH_PORT/tcp"
for p in "${ALLOW[@]}"; do run_cmd ufw allow "$p/tcp"; done
run_cmd ufw --force enable

log "Configuring fail2ban"
F2B="[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
findtime = 10m
bantime = 1h"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf '[dry-run] write /etc/fail2ban/jail.d/sshd.local:\n%s\n' "$F2B"
else
  printf '%s\n' "$F2B" > /etc/fail2ban/jail.d/sshd.local
fi
run_cmd systemctl enable --now fail2ban

log "Enabling unattended security upgrades"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "[dry-run] write /etc/apt/apt.conf.d/20auto-upgrades"
else
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
    > /etc/apt/apt.conf.d/20auto-upgrades
fi

ok "Bootstrap complete. Test login in a NEW session: ssh -p $SSH_PORT $USER_NAME@<server> before closing this one."
