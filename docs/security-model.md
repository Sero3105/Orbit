# Security Model
No sudo, no privileged helper, no shell strings from UI (fixed-arg Process only), no SIP/TCC bypass, no telemetry/network. Deletion = Trash only, after confirm + revalidation (inode match, allowlisted root, not symlink, not protected prefix: /, /System, /usr, /bin, other users' homes, mounted volume roots). Scan is read-only.
