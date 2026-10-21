# Security Policy

Orbit moves files to the Trash, terminates processes, controls input devices, captures the screen and can install an optional privileged fan-control helper, so safety bugs matter. Thank you for helping keep it safe.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

**Please do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/Sero3105/Orbit/security/advisories/new)
with steps to reproduce, the affected version and macOS version.

You can expect an acknowledgement within 7 days. Once a fix is released, the advisory is published and you're credited unless you prefer otherwise.

## In scope

- Trashing or modifying anything the user did not confirm, or anything outside the allowed roots
- Bypassing path revalidation (symlinks, inode swaps / TOCTOU, protected paths)
- Uninstall matching files that do not belong to the app being removed
- Data leaving the Mac other than through the connections listed in [docs/PRIVACY.md](docs/PRIVACY.md)
- Privilege escalation through the fan-control helper or its XPC interface
- Command injection into any command Orbit runs

## Design guarantees

- **Maintenance window** (Dashboard, Energy, Cleanup, Disk Analyzer, Applications, Maintenance, Processes, History): scans are read-only; removal is Trash-only after explicit confirmation and revalidation; no `sudo`, no network. See [docs/security-model.md](docs/security-model.md).
- **Fan control** is opt-in. Its helper only accepts clients signed with Orbit's Apple Developer Team ID; until releases are signed with one, the helper refuses every client and the in-app updater opens the release page instead of installing.
- **Network**: every connection is listed in [docs/PRIVACY.md](docs/PRIVACY.md). Orbit runs no server of its own.
