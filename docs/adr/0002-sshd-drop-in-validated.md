# 0002. Harden SSH through a validated drop-in file

Status: accepted
Date: 2026-10-17

## Context
`bootstrap-server.sh` changes the SSH port, disables passwords and root login, and
limits logins to one admin user. A broken sshd config on a remote VPS can lock the
operator out, and editing `/etc/ssh/sshd_config` in place conflicts with package
upgrades that ship a new default file.

## Options
1. Edit `sshd_config` with `sed`: works on any version, but fragile against
   formatting changes and leaves a diff that apt asks about on upgrade.
2. Replace `sshd_config` with a full template: predictable, but throws away
   distribution defaults and breaks on the next major release.
3. Write `/etc/ssh/sshd_config.d/10-hardening.conf`, run `sshd -t`, and reload only if
   the test passes.

## Decision
Option 3. The distribution keeps its own file, our settings live in one place, and an
invalid config is never loaded.

## Consequences
- Depends on the `Include sshd_config.d/*.conf` line that current Debian and Ubuntu
  ship. Older releases without it would ignore the drop-in.
- If `sshd -t` fails, the script stops but leaves the drop-in on disk. The next sshd
  restart would then fail too. Removing the file on failure is an open improvement.
- UFW is configured right after the reload and opens the new port with `ufw limit`.
  If UFW was already active with other rules, there is a short window where the new
  port is closed. The README asks to keep a second session open for that reason.
