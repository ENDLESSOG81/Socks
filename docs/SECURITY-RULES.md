# SOCKS Security Rules

SOCKS is a readiness standard. It must not become a credential store, orchestration system, connector runtime, or deployment mechanism.

## Required Rules

- Do not store credentials.
- Do not expose secret values in evidence.
- Do not write sensitive environment variable values.
- Do not embed API keys, tokens, private keys, passwords, or connection strings.
- Do not treat advisory evidence as proof of required readiness.
- Do not auto-repair a target repository unless a separate authorized tool explicitly owns that responsibility.
- Do not execute plugin or connector code from this sterile standard.
- Do not modify UNDIES immutable core files.

## Redaction Principles

Evidence systems implementing SOCKS should redact fields whose names resemble:

- `secret`
- `token`
- `password`
- `credential`
- `api_key`
- `private_key`

Redaction is a backup control. The primary control is to avoid collecting secret values at all.

## Path and Configuration Safety

Configuration paths must be local, intentional, and governed by the target repository policy. Path traversal, hidden machine-specific dependencies, and unreviewed absolute paths are not acceptable as authoritative SOCKS requirements.

## Failure Safety

Security-relevant indeterminate states must fail closed. This includes missing configuration, unreadable evidence, unsupported policy versions, invalid schemas, and incomplete required checks.
