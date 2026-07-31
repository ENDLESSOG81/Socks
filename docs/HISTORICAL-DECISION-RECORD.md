# Historical Decision Record

## HDR-001: Executable Experiment Preserved As Non-Authoritative

Branch:

`production-hardening-001`

Commit:

`44f2158d5b412d2e59029a96a865d6e13085ad90`

Disposition:

`YELLOW`

Decision:

The branch is preserved as historical evidence only. It is not merged into the sterile authoritative model, not installed into projects, and not authoritative for SOCKS adoption.

Required wording:

> A preserved, non-authoritative implementation experiment from the former executable SOCKS architecture.

Reusable concepts from the experiment may include readiness terminology, gate rules, exit-state definitions, security principles, evidence requirements, operator considerations, and failure-handling principles.

Excluded from the sterile model:

- Runtime code.
- Installation logic.
- Upgrade logic.
- Uninstall logic.
- Release packaging.
- Project deployment behavior.
- Connector execution code.
- Plugin execution code.
- Machine-specific paths.
- Runtime evidence.
- Package manifests.
- Executable dependency assumptions.

## Current Authoritative Model

The authoritative `main` branch is documentation-only and defines the sterile SOCKS standard.
