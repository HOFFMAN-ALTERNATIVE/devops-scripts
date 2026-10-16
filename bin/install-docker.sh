#!/usr/bin/env bash
# Install Docker Engine + Compose plugin from the official apt repository (Debian/Ubuntu).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ADD_USER="${1:-}"
[[ -z "$ADD_USER" ]] || is_valid_username "$ADD_USER" || die "invalid user: $ADD_USER"
require_root

if command -v docker >/dev/null 2>&1 && [[ "${DRY_RUN:-0}" != "1" ]]; then
  ok "Docker already installed: $(docker --version)"; exit 0
fi

# shellcheck source=/dev/null
. /etc/os-release
DISTRO="${ID:-ubuntu}"; CODENAME="${VERSION_CODENAME:-}"
[[ "$DISTRO" =~ ^(ubuntu|debian)$ ]] || die "unsupported distro: $DISTRO"

run_cmd apt-get update -qq
run_cmd apt-get install -y -qq ca-certificates curl gnupg
run_cmd install -m 0755 -d /etc/apt/keyrings
run_cmd curl -fsSL "https://download.docker.com/linux/$DISTRO/gpg" -o /etc/apt/keyrings/docker.asc
run_cmd chmod a+r /etc/apt/keyrings/docker.asc
REPO="deb [arch=$(dpkg --print-architecture 2>/dev/null || echo amd64) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO $CODENAME stable"
if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "[dry-run] apt source: $REPO"
else echo "$REPO" > /etc/apt/sources.list.d/docker.list; fi
run_cmd apt-get update -qq
run_cmd apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
run_cmd systemctl enable --now docker
[[ -n "$ADD_USER" ]] && run_cmd usermod -aG docker "$ADD_USER"
ok "Docker installed"
