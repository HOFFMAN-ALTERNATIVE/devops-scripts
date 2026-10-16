#!/usr/bin/env bash
# Reclaim disk: vacuum journald, delete old rotated logs, truncate oversized docker logs.
#   --days N        delete rotated logs (*.gz, *.1, *.old) older than N days (default 14)
#   --journal SIZE  journald size cap (default 500M)
#   --dir PATH      log directory (default /var/log)
#   --docker-max MB truncate docker container logs larger than MB (default 200; 0 = skip)
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

DAYS=14 JOURNAL=500M DIR=/var/log DOCKER_MAX=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --journal) JOURNAL="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --docker-max) DOCKER_MAX="$2"; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$DAYS" =~ ^[0-9]+$ ]] || die "--days must be an integer"
[[ "$DOCKER_MAX" =~ ^[0-9]+$ ]] || die "--docker-max must be an integer"
[[ -d "$DIR" ]] || die "not a directory: $DIR"

before=$(du -sk "$DIR" 2>/dev/null | cut -f1)

if command -v journalctl >/dev/null 2>&1 && [[ "$DIR" == /var/log ]]; then
  run_cmd journalctl --vacuum-size="$JOURNAL" >/dev/null 2>&1 || warn "journal vacuum failed"
fi

count=0
while IFS= read -r -d '' f; do
  run_cmd rm -f -- "$f"; count=$((count + 1))
done < <(find "$DIR" -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -mtime +"$DAYS" -print0)
log "Removed $count rotated log file(s) older than $DAYS days"

if (( DOCKER_MAX > 0 )) && [[ -d /var/lib/docker/containers ]]; then
  while IFS= read -r -d '' f; do
    log "Truncating $(basename "$f")"; run_cmd truncate -s 0 -- "$f"
  done < <(find /var/lib/docker/containers -name '*-json.log' -size +"${DOCKER_MAX}"M -print0 2>/dev/null)
fi

after=$(du -sk "$DIR" 2>/dev/null | cut -f1)
ok "Freed $(( (before - after) / 1024 )) MiB in $DIR"
