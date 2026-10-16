#!/usr/bin/env bats

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "is_valid_port accepts 1..65535" {
  is_valid_port 1
  is_valid_port 443
  is_valid_port 65535
}

@test "is_valid_port rejects junk" {
  ! is_valid_port 0
  ! is_valid_port 65536
  ! is_valid_port abc
  ! is_valid_port ""
}

@test "is_valid_username" {
  is_valid_username deploy
  is_valid_username _svc-1
  ! is_valid_username Root
  ! is_valid_username "1bad"
  ! is_valid_username "a b"
}

@test "days_between floors to whole days" {
  [ "$(days_between 0 86400)" -eq 1 ]
  [ "$(days_between 0 172799)" -eq 1 ]
  [ "$(days_between 100 100)" -eq 0 ]
}

@test "run prints instead of executing in DRY_RUN" {
  DRY_RUN=1 run run_cmd touch "$BATS_TEST_TMPDIR/x"
  [ "$status" -eq 0 ]
  [[ "$output" == "[dry-run] touch "* ]]
  [ ! -e "$BATS_TEST_TMPDIR/x" ]
}

@test "notify is a no-op without credentials" {
  unset TG_TOKEN TG_CHAT
  run notify "hello"
  [ "$status" -eq 0 ]
}
