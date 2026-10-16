#!/usr/bin/env bash
# Check TLS certificate expiry for one or more hosts.
# Usage: ssl-expiry-check.sh [-w WARN_DAYS] [-c CRIT_DAYS] host[:port] ...
# Exit: 0 all OK, 1 warning, 2 critical/unreachable. Telegram alert if TG_TOKEN/TG_CHAT set.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

WARN=21 CRIT=7
while getopts ":w:c:h" o; do
  case "$o" in
    w) WARN="$OPTARG" ;;
    c) CRIT="$OPTARG" ;;
    h) sed -n '2,4p' "$0"; exit 0 ;;
    *) die "invalid option" ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] || die "no hosts given"
require_cmd openssl

# cert_enddate HOST PORT -> prints notAfter string
cert_enddate() {
  echo | timeout 10 openssl s_client -servername "$1" -connect "$1:$2" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2
}

# classify DAYS -> OK|WARN|CRIT
classify() {
  if (( $1 <= CRIT )); then echo CRIT; elif (( $1 <= WARN )); then echo WARN; else echo OK; fi
}

rc=0 now=$(date +%s)
for target in "$@"; do
  host="${target%%:*}"; port="${target##*:}"; [[ "$port" == "$target" ]] && port=443
  end="$(cert_enddate "$host" "$port" || true)"
  if [[ -z "$end" ]]; then
    err "$host:$port unreachable or no certificate"; notify "🔴 TLS: $host unreachable"; rc=2; continue
  fi
  days=$(days_between "$now" "$(date -d "$end" +%s)")
  case "$(classify "$days")" in
    OK) ok "$host:$port expires in $days days ($end)" ;;
    WARN) warn "$host:$port expires in $days days"; notify "🟡 TLS: $host expires in $days days"; (( rc < 1 )) && rc=1 ;;
    CRIT) err "$host:$port expires in $days days"; notify "🔴 TLS: $host expires in $days days"; rc=2 ;;
  esac
done
exit "$rc"
