# SOCKS-003 Environment Discovery Engine

SOCKS discovery gathers local, non-destructive environment evidence:

- Operating system
- Runtime versions
- CPU
- Memory
- Disk
- Network interfaces
- Environment variable names
- Workspace metadata

Environment variable values are not recorded. SOCKS stores names and counts only, with secret-like names redacted. Discovery evidence is included in readiness reports and used by discovery checks.
