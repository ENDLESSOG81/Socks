# SOCKS-006 Secrets & Configuration Validation

SOCKS validates configuration readiness without exposing sensitive values.

Supported validation:

- Required environment variable presence
- Required configuration key presence
- Placeholder detection
- Missing configuration detection
- Secret redaction
- Safe evidence generation

Evidence reports only names, counts, and boolean presence. Values for environment variables and secret-like configuration keys are never written to reports.
