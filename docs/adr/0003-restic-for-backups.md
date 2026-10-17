# 0003. Use restic for off-site backups

Status: accepted
Date: 2026-10-17

## Context
Small servers need encrypted backups to cheap storage outside the host, with a
retention policy and an alert when a run fails. The storage is usually some
S3-compatible bucket, and the operator does not control the bucket provider.

## Options
1. `tar` plus `rclone` or `aws s3 cp`: no new tool, but no deduplication, and
   encryption and retention have to be scripted by hand.
2. BorgBackup: deduplicated and encrypted, but needs SSH access to a Borg server, not
   plain object storage.
3. restic: one static binary, encrypted and deduplicated, talks to S3 directly, and
   has built-in `forget --prune` retention.

## Decision
Option 3. It works against any S3-compatible bucket and covers encryption,
deduplication and retention in one tool.

## Consequences
- Config comes from env vars or an env file, which the README tells you to keep at mode 0600.
- Only snapshots tagged `auto` are pruned, so manual snapshots are kept.
- Defaults keep 7 daily, 4 weekly and 6 monthly snapshots.
- Losing `RESTIC_PASSWORD` means losing the backups. The key has to be stored somewhere
  other than the server being backed up.
- `--check` exists but does not run on its own. Schedule it, or restore tests do not happen.
