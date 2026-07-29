# SOCKS-007 External Connectivity Framework

SOCKS defines a reusable connector framework for future external readiness checks:

- GitHub
- Discord
- Supabase
- PostgreSQL
- REST APIs
- AI providers
- Future connectors

Connectors are configuration-driven and disabled unless explicitly configured. SOCKS-007 does not hard-code project integrations and does not perform external network checks by default.

Each connector declares:

- `id`
- `type`
- `enabled`
- `requirement`
- optional metadata such as endpoint names

Evidence records connector readiness metadata and execution status without credentials.
