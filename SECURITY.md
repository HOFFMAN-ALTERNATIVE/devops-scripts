# Security

## Reporting

Use GitHub's private "Report a vulnerability" button on this repository. I aim to reply within 72 hours.

## Threat model

- **Assets:** root access on the servers these scripts configure, backup repositories and their passwords, the Telegram bot token.
- **Actors:** internet scanners hitting SSH, anyone who can edit the arguments or env files the scripts read.
- **Entry points:** CLI arguments, env files (`restic.env`), hostnames and URLs passed to the checkers.
- **Defaults that matter:** key-only SSH with the config validated by `sshd -t` before reload, UFW deny-by-default with rate-limited SSH, fail2ban, unattended upgrades; all arguments validated before use; hostnames are passed to Bash as arguments, never spliced into command strings (regression-tested); TLS verification on by default in `uptime-check.sh`; the Telegram token is handed to curl on stdin so it does not appear in the process list; env files are expected at mode 600.
- **Verification:** ShellCheck and bats in CI on every commit.

## Not provided

- Secret storage. Backup passwords live in an env file on the host; protect the host.
- Rollback of `bootstrap-server.sh` changes.
