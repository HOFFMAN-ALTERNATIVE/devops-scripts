# devops-scripts

[![ci](https://github.com/HOFFMAN-ALTERNATIVE/devops-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/HOFFMAN-ALTERNATIVE/devops-scripts/actions/workflows/ci.yml)
![ShellCheck](https://img.shields.io/badge/shellcheck-clean-brightgreen)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

Six Bash scripts for running small Linux fleets: bootstrap a fresh VPS, install Docker, take encrypted off-site backups, reclaim disk space, and watch TLS expiry and uptime. Every script is idempotent, validates its arguments, runs under `set -euo pipefail`, supports a `DRY_RUN=1` preview, and is ShellCheck-clean. 21 [bats](https://github.com/bats-core/bats-core) tests run in CI.

The trade-off: Bash keeps the scripts dependency-free and readable on any server, but they target Debian and Ubuntu only and are not a replacement for Ansible once you manage more than a handful of hosts.

| Script | What it does |
|---|---|
| `bin/bootstrap-server.sh` | Admin user with key-only login, SSH hardening drop-in (validated with `sshd -t`), UFW deny-by-default with rate-limited SSH, fail2ban, unattended-upgrades |
| `bin/install-docker.sh` | Docker Engine + Compose plugin from the official apt repo (Debian/Ubuntu) |
| `bin/restic-backup.sh` | Encrypted, deduplicated backups to any S3-compatible storage with retention policy and failure alerts |
| `bin/log-cleanup.sh` | Vacuum journald, delete old rotated logs, truncate oversized Docker logs |
| `bin/ssl-expiry-check.sh` | TLS expiry for many hosts, warn/critical thresholds, Nagios-style exit codes |
| `bin/uptime-check.sh` | TCP port and HTTP(S) status checks with retries; TLS certificates are verified unless `--insecure` is passed |

All alerting is optional: set `TG_TOKEN` and `TG_CHAT` to receive Telegram notifications.

## Quick start

```bash
git clone https://github.com/HOFFMAN-ALTERNATIVE/devops-scripts.git && cd devops-scripts

# Preview everything first
DRY_RUN=1 ./bin/bootstrap-server.sh --user deploy --pubkey-file ~/.ssh/id_ed25519.pub \
  --ssh-port 2222 --allow 80 --allow 443

# Apply (as root on the server)
sudo ./bin/bootstrap-server.sh --user deploy --pubkey-file /root/deploy.pub --ssh-port 2222 --allow 80 --allow 443
sudo ./bin/install-docker.sh deploy

# Backups
cp examples/restic.env.example /etc/restic.env && chmod 600 /etc/restic.env   # edit values
sudo ./bin/restic-backup.sh --env-file /etc/restic.env --init
sudo ./bin/restic-backup.sh --env-file /etc/restic.env

# Monitoring (run from cron or systemd timers)
./bin/ssl-expiry-check.sh -w 21 -c 7 example.com api.example.com:8443
./bin/uptime-check.sh tcp://127.0.0.1:5432 https://example.com/health 'https://example.com/admin#401'
```

## Architecture

```mermaid
flowchart LR
  subgraph lib
    C[common.sh<br/>logging · run_cmd/DRY_RUN · validators · notify]
  end
  B[bootstrap-server] --> C
  D[install-docker] --> C
  R[restic-backup] --> C
  L[log-cleanup] --> C
  S[ssl-expiry-check] --> C
  U[uptime-check] --> C
  C -- optional --> T[(Telegram Bot API)]
  R --> S3[(S3-compatible storage)]
```

## Scheduling example (systemd)

```ini
# /etc/systemd/system/uptime-check.service
[Service]
Type=oneshot
EnvironmentFile=/etc/devops-alerts.env
ExecStart=/usr/local/lib/devops-scripts/bin/uptime-check.sh https://example.com/health

# /etc/systemd/system/uptime-check.timer
[Timer]
OnCalendar=*:0/5
Persistent=true
[Install]
WantedBy=timers.target
```

## Design decisions

- [ADR 0001](docs/adr/0001-bash-with-shared-lib.md): plain Bash with `lib/common.sh`, so
  the scripts run on a bare server. ShellCheck and bats keep it honest.
- [ADR 0002](docs/adr/0002-sshd-drop-in-validated.md): SSH settings go into a drop-in
  file, checked with `sshd -t` before a reload.
- [ADR 0003](docs/adr/0003-restic-for-backups.md): restic for backups, because it does
  encryption, deduplication and retention against any S3 bucket.

## Limits

- Debian and Ubuntu only (apt, UFW, systemd-journald).
- `bootstrap-server.sh` changes SSH and firewall settings. Keep a second session open until you have logged in through the new port.
- The checks are point-in-time scripts, not a monitoring system. Pair them with a scheduler and alerting, or use a real stack for anything beyond a few hosts.
- The bats suite tests argument handling, dry-run output and the checkers against local listeners. It does not run the bootstrap or Docker install against a real VM.

Security notes: [SECURITY.md](SECURITY.md).

## Development

```bash
make lint   # shellcheck
make test   # bats tests/
```

## License

MIT, see [LICENSE](LICENSE).
