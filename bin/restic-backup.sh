#!/usr/bin/env bash
# Encrypted, deduplicated backups to any S3-compatible storage via restic.
# Config: env vars or an env file passed with --env-file (mode 0600).
#   RESTIC_REPOSITORY=s3:https://s3.example.com/bucket/host
#   RESTIC_PASSWORD=...  AWS_ACCESS_KEY_ID=...  AWS_SECRET_ACCESS_KEY=...
#   BACKUP_PATHS="/etc /srv"   KEEP_DAILY=7 KEEP_WEEKLY=4 KEEP_MONTHLY=6
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

ACTION="backup"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ -f "$2" ]] || die "env file not found: $2"
      set -a; # shellcheck source=/dev/null
      source "$2"; set +a; shift 2 ;;
    --init) ACTION="init"; shift ;;
    --check) ACTION="check"; shift ;;
    --snapshots) ACTION="snapshots"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"
BACKUP_PATHS="${BACKUP_PATHS:-/etc}"
KEEP_DAILY="${KEEP_DAILY:-7}" KEEP_WEEKLY="${KEEP_WEEKLY:-4}" KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
[[ "${DRY_RUN:-0}" == "1" ]] || require_cmd restic

case "$ACTION" in
  init) run_cmd restic init ;;
  check) run_cmd restic check ;;
  snapshots) run_cmd restic snapshots ;;
  backup)
    read -r -a paths <<< "$BACKUP_PATHS"
    log "Backing up: ${paths[*]}"
    if ! run_cmd restic backup --one-file-system --exclude-caches --tag auto "${paths[@]}"; then
      notify "❌ backup failed on $(hostname)"; die "backup failed"
    fi
    run_cmd restic forget --prune --tag auto \
      --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" --keep-monthly "$KEEP_MONTHLY"
    ok "Backup finished" ;;
esac
