# 0001. Plain Bash with one shared library

Status: accepted
Date: 2026-10-17

## Context
These scripts run on fresh Debian or Ubuntu servers, often before anything else is
installed, and on small fleets where one person does the ops work. They must be
readable by whoever inherits the server and runnable with nothing but the base system.

## Options
1. Ansible playbooks: idempotent by design, good for many hosts. Needs Python and
   Ansible on a control machine, and a playbook is overkill for a single VPS.
2. A Python or Go CLI: easier to test, but one more runtime or binary to ship.
3. Bash scripts with a shared `lib/common.sh` for logging, validation, dry-run and
   alerts: runs everywhere, but Bash needs discipline to stay safe.

## Decision
Option 3. Zero dependencies on the target host matters more here than the comfort of a
real language. The discipline is enforced by tooling, not by hope.

## Consequences
- Every script starts with `set -euo pipefail` and validates its arguments.
- `run_cmd` in `common.sh` gives every script the same `DRY_RUN=1` preview.
- ShellCheck runs in CI on `bin/` and `lib/`, and 21 bats tests cover argument
  handling, dry-run output and the checkers against local listeners.
- The bats suite cannot test the bootstrap or Docker install against a real VM.
- Revisit, and move to Ansible, once there are more than a handful of hosts to keep in sync.
