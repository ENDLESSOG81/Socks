# SOCKS System Contract

## Mission

SOCKS, the System Operating Connect Control System, verifies whether a project environment is ready and safe enough for work to continue.

SOCKS answers one question:

Is everything required to safely continue actually ready?

## Scope

SOCKS provides local environment readiness checks, standardized evidence, gate evaluation, machine-readable reports, human-readable reports, and stable process exit behavior.

The first module, SOCKS-001, covers only local, non-destructive checks for workspace, Git, configuration, runtime, and evidence output readiness.

## Non-Goals

SOCKS-001 does not integrate AIRDS, external databases, Discord, Supabase, OpenAI, AI services, or external network services. It does not request, store, repair, or expose credentials. It does not modify UNDIES immutable-core files and does not automatically repair the environment.

## Core Responsibilities

SOCKS separates configuration loading, environment discovery, check registration, check execution, result normalization, gate evaluation, evidence collection, report generation, and command-line entry.

SOCKS must remain independently usable and testable from the repository where it is installed.

## Readiness States

The readiness gate has three authoritative outcomes:

- `PASS`: all required checks passed and no promoted optional condition blocks progression.
- `WARN`: all required checks passed, but optional checks produced warnings or failures.
- `FAIL`: at least one required check failed, errored, or could not be determined.

## Check Severity Levels

Each check declares a requirement level:

- `REQUIRED`: failure or error blocks progression.
- `OPTIONAL`: failure or error produces warning unless policy promotes it.
- `ADVISORY`: failure or error is reported but does not block progression.

## Check Statuses

Each check returns one normalized status:

- `PASS`
- `WARN`
- `FAIL`
- `SKIPPED`
- `ERROR`

## Gate Behavior

SOCKS fails closed. Any required readiness condition that cannot be determined is treated as blocking.

Gate rules:

- Any `REQUIRED` check returning `FAIL` or `ERROR` produces overall `FAIL`.
- Optional failures produce overall `WARN` unless policy explicitly promotes them.
- Advisory failures do not block progression.
- All required checks passing produces overall `PASS`.
- Every gate decision includes evidence describing how it was calculated.

## Evidence Requirements

Every check result includes:

- Check identifier
- Check name
- Category
- Requirement level
- Status
- Summary
- Evidence
- Failure reason, when applicable
- Remediation guidance, when applicable
- Start timestamp
- End timestamp
- Duration
- Check implementation version

Each run creates both a JSON report and a Markdown report containing the SOCKS version, UNDIES session reference when available, repository path, Git branch, Git commit, timestamps, check results, gate result, blocking conditions, warnings, remediation, and report integrity information where practical.

Secrets must not be written to reports.

## Exit-Code Behavior

SOCKS uses a stable exit-code contract:

- `0`: `PASS`
- `1`: `FAIL`
- `2`: `WARN`
- `3`: system or configuration error

On Windows PowerShell and PowerShell 7, these values are returned by the CLI process exit code.

## Configuration Principles

Configuration is explicit, local, file-based, and portable. Missing required configuration is a system/configuration error. Configuration may define workspace path, evidence output location, policy, and check registration settings.

## Security Principles

SOCKS is deny-by-default for external connections in SOCKS-001. It does not collect credentials, does not inspect secret stores, and redacts secret-like values before reports are written.

## Standalone Operation

SOCKS must run locally from the repository without external services, package downloads, or network access.
