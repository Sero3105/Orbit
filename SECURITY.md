# Security Policy

Orbit moves files to the Trash and terminates processes, so safety bugs matter. Thank you for helping keep it safe.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

**Please do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/Sero3105/OrbitA/security/advisories/new)
with steps to reproduce, the affected version and macOS version.

You can expect an acknowledgement within 7 days. Once a fix is released, the advisory is published and you're credited unless you prefer otherwise.

## In scope

- Orbit trashing or modifying anything the user did not confirm, or anything outside the allowed roots
- Bypassing path revalidation (symlinks, inode swaps / TOCTOU, protected paths)
- Uninstall matching files that do not belong to the app being removed
- Any network access, data leaving the Mac, or privilege escalation
- Command injection into the fixed maintenance commands

## Design guarantees

Scans are read-only; removal is Trash-only after explicit confirmation and revalidation; no `sudo`, privileged helper, SIP/TCC bypass, network or telemetry. See [docs/security-model.md](docs/security-model.md).
