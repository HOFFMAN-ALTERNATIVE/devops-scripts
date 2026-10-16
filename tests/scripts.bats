#!/usr/bin/env bats

BIN="$BATS_TEST_DIRNAME/../bin"

setup_file() {
  export NO_COLOR=1
  PORT=$((20000 + RANDOM % 20000))
  export PORT
  python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
  echo $! > "$BATS_FILE_TMPDIR/pid"
  for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break; sleep 0.1; done
}

teardown_file() {
  kill "$(cat "$BATS_FILE_TMPDIR/pid")" 2>/dev/null || true
}

@test "every script has --help / usage" {
  for s in bootstrap-server log-cleanup restic-backup uptime-check; do
    run "$BIN/$s.sh" --help
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}

@test "bootstrap: rejects missing user" {
  run "$BIN/bootstrap-server.sh" --pubkey "ssh-ed25519 AAAA test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid or missing --user"* ]]
}

@test "bootstrap: rejects bad port" {
  run "$BIN/bootstrap-server.sh" --user deploy --pubkey "ssh-ed25519 AAAA" --ssh-port 99999
  [ "$status" -ne 0 ]
}

@test "bootstrap: dry-run renders hardened sshd config" {
  DRY_RUN=1 run "$BIN/bootstrap-server.sh" --user deploy --pubkey "ssh-ed25519 AAAA x" --ssh-port 2222 --allow 443
  [ "$status" -eq 0 ]
  [[ "$output" == *"PermitRootLogin no"* ]]
  [[ "$output" == *"PasswordAuthentication no"* ]]
  [[ "$output" == *"Port 2222"* ]]
  [[ "$output" == *"ufw limit 2222/tcp"* ]]
  [[ "$output" == *"ufw allow 443/tcp"* ]]
}

@test "restic: requires repository" {
  unset RESTIC_REPOSITORY
  run "$BIN/restic-backup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"RESTIC_REPOSITORY"* ]]
}

@test "restic: dry-run backup + retention from env file" {
  f="$BATS_TEST_TMPDIR/env"
  printf 'RESTIC_REPOSITORY=s3:https://s3.example.com/b\nRESTIC_PASSWORD=x\nBACKUP_PATHS="/etc /srv"\nKEEP_DAILY=3\n' > "$f"
  DRY_RUN=1 run "$BIN/restic-backup.sh" --env-file "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restic backup"*"/etc /srv"* ]]
  [[ "$output" == *"--keep-daily 3"* ]]
}

@test "log-cleanup: removes only old rotated logs" {
  d="$BATS_TEST_TMPDIR/logs"; mkdir -p "$d"
  touch "$d/app.log" "$d/new.log.1"
  touch -d '30 days ago' "$d/old.log.1" "$d/old.log.2.gz" "$d/keep.log"
  run "$BIN/log-cleanup.sh" --dir "$d" --days 14 --docker-max 0
  [ "$status" -eq 0 ]
  [ -e "$d/app.log" ]; [ -e "$d/new.log.1" ]; [ -e "$d/keep.log" ]
  [ ! -e "$d/old.log.1" ]; [ ! -e "$d/old.log.2.gz" ]
}

@test "log-cleanup: rejects non-integer days" {
  run "$BIN/log-cleanup.sh" --dir /tmp --days abc
  [ "$status" -ne 0 ]
}

@test "uptime: tcp and http up" {
  run "$BIN/uptime-check.sh" --retries 0 "tcp://127.0.0.1:$PORT" "http://127.0.0.1:$PORT/"
  [ "$status" -eq 0 ]
}

@test "uptime: expected status mismatch is reported down" {
  run "$BIN/uptime-check.sh" --retries 0 "http://127.0.0.1:$PORT/nope#200"
  [ "$status" -eq 1 ]
  run "$BIN/uptime-check.sh" --retries 0 "http://127.0.0.1:$PORT/nope#404"
  [ "$status" -eq 0 ]
}

@test "uptime: closed port is down" {
  run "$BIN/uptime-check.sh" --retries 0 --timeout 2 "tcp://127.0.0.1:1"
  [ "$status" -eq 1 ]
}

@test "ssl: unreachable host is critical" {
  run "$BIN/ssl-expiry-check.sh" 127.0.0.1:1
  [ "$status" -eq 2 ]
}
