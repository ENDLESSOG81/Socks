# SOCKS-002 Configuration & Policy Engine

SOCKS configuration is local JSON and may inherit from one parent file through `extends`. Parent paths must resolve to local files. Child values override parent values, and nested objects are merged recursively.

Required root keys:

- `schema_version`
- `socks_version`
- `workspace_root`
- `evidence_root`
- `required_runtime`
- `policy`

Policy supports:

- `promote_optional_failures`: promotes all optional failures and warnings to blocking failures.
- `promoted_optional_checks`: promotes selected optional check identifiers.
- `disabled_checks`: skips selected checks during registration.
- `check_levels`: overrides a check requirement level with `REQUIRED`, `OPTIONAL`, or `ADVISORY`.
- `conditional_checks`: stores future deterministic execution conditions.

Configuration integrity evidence records the SHA256 of loaded raw configuration content and whether inheritance was used. SOCKS fails closed when required configuration is missing, invalid, or cannot be parsed.
