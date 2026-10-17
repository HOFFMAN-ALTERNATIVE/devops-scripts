#!/usr/bin/env bash
# Shared helpers for devops-scripts. Source, don't execute.
# shellcheck disable=SC2034

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YLW=$'\e[33m' C_BLU=$'\e[34m' C_RST=$'\e[0m'
else
  C_RED='' C_GRN='' C_YLW='' C_BLU='' C_RST=''
fi

log()  { printf '%s[INFO]%s %s\n'  "$C_BLU" "$C_RST" "$*" >&2; }
ok()   { printf '%s[ OK ]%s %s\n'  "$C_GRN" "$C_RST" "$*" >&2; }
warn() { printf '%s[WARN]%s %s\n'  "$C_YLW" "$C_RST" "$*" >&2; }
err()  { printf '%s[FAIL]%s %s\n'  "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# run_cmd CMD...  — executes, or only prints when DRY_RUN=1
run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

require_root() {
  [[ "${DRY_RUN:-0}" == "1" ]] && return 0
  [[ "$(id -u)" -eq 0 ]] || die "must be run as root (or use DRY_RUN=1)"
}

require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"; done
}

# is_valid_port N -> 0 if 1..65535
is_valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

# is_valid_username NAME -> POSIX-ish user names
is_valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

# days_between EPOCH_FROM EPOCH_TO -> integer days (floor)
days_between() { echo $(( ($2 - $1) / 86400 )); }

# Telegram alert if TG_TOKEN and TG_CHAT are set; silent no-op otherwise.
notify() {
  [[ -n "${TG_TOKEN:-}" && -n "${TG_CHAT:-}" ]] || return 0
  # The URL carrying the token goes through a config on stdin, so it never shows up in `ps`.
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TG_TOKEN" \
    | curl -fsS -m 10 -K - -d chat_id="$TG_CHAT" --data-urlencode text="$1" >/dev/null || warn "notify failed"
}

# install_sshd_dropin PATH CONTENT -> writes an sshd drop-in and validates the full config.
# On a failed `sshd -t` the previous file is restored (or the new one removed), so a bad
# config never stays on disk for the next sshd restart. SSHD_BIN overrides sshd for tests.
install_sshd_dropin() {
  local path="$1" content="$2" sshd_bin="${SSHD_BIN:-sshd}" dir backup="" tmp
  dir="$(dirname "$path")"
  [[ -d "$dir" ]] || die "drop-in directory does not exist: $dir"
  if [[ -e "$path" ]]; then
    backup="$(mktemp "$dir/.sshd-dropin-backup.XXXXXX")"
    cp -p -- "$path" "$backup"
  fi
  tmp="$(mktemp "$dir/.sshd-dropin-new.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  chmod 644 "$tmp"
  mv -f -- "$tmp" "$path"
  if "$sshd_bin" -t; then
    [[ -n "$backup" ]] && rm -f -- "$backup"
    return 0
  fi
  if [[ -n "$backup" ]]; then
    mv -f -- "$backup" "$path"
    err "sshd -t failed; restored previous $path"
  else
    rm -f -- "$path"
    err "sshd -t failed; removed $path"
  fi
  return 1
}
