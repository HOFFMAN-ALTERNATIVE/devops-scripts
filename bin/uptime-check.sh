#!/usr/bin/env bash
# Check TCP ports and HTTP(S) endpoints.
# Usage: uptime-check.sh [--timeout S] [--retries N] [--insecure] TARGET...
#   TARGET = tcp://host:port | http(s)://url[#expected_status]
# Exit 0 if every target is up, 1 otherwise. Telegram alert if TG_TOKEN/TG_CHAT set.
#   --insecure skips TLS certificate verification (off by default).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

TIMEOUT=5 RETRIES=2 INSECURE=0
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --retries) RETRIES="$2"; shift 2 ;;
    --insecure) INSECURE=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) targets+=("$1"); shift ;;
  esac
done
[[ ${#targets[@]} -gt 0 ]] || die "no targets given"
[[ "$TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || die "--timeout must be 1-999 seconds"
[[ "$RETRIES" =~ ^[0-9]{1,2}$ ]] || die "--retries must be 0-99"

# shellcheck disable=SC2317  # invoked indirectly via with_retries
check_tcp() {
  local host="$1" port="$2"
  is_valid_port "$port" || return 1
  [[ "$host" =~ ^[A-Za-z0-9.:_-]+$ ]] || return 1
  # host and port are passed as arguments, never spliced into the command string
  # shellcheck disable=SC2016
  timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null
}

# shellcheck disable=SC2317
check_http() {
  local url="$1" want="$2" code tls=()
  [[ "$INSECURE" == 1 ]] && tls=(--insecure)
  code=$(curl -sS "${tls[@]}" -o /dev/null -m "$TIMEOUT" -w '%{http_code}' -- "$url" 2>/dev/null || true)
  [[ "$code" == "$want" ]]
}

with_retries() {
  local i
  for ((i = 0; i <= RETRIES; i++)); do "$@" && return 0; sleep 1; done
  return 1
}

failed=0
for t in "${targets[@]}"; do
  case "$t" in
    tcp://*)
      hp="${t#tcp://}"; host="${hp%:*}"; port="${hp##*:}"
      if with_retries check_tcp "$host" "$port"; then ok "$t up"; else err "$t DOWN"; failed=1; notify "🔴 DOWN: $t"; fi ;;
    http://*|https://*)
      url="${t%%#*}"; want=200; [[ "$t" == *"#"* ]] && want="${t##*#}"
      if with_retries check_http "$url" "$want"; then ok "$url up ($want)"; else err "$url DOWN (expected $want)"; failed=1; notify "🔴 DOWN: $url"; fi ;;
    *) err "unsupported target: $t"; failed=1 ;;
  esac
done
exit "$failed"
