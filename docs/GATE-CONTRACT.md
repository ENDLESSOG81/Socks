# SOCKS Gate Contract

The SOCKS gate determines whether a governed repository environment is ready to continue.

## Outcomes

- `PASS`: all required checks pass.
- `WARN`: required checks pass, but optional or advisory checks need attention.
- `FAIL`: at least one required check fails, errors, or cannot be determined.

## Requirement Levels

- `REQUIRED`: blocks progression on `FAIL`, `ERROR`, or indeterminate evidence.
- `OPTIONAL`: does not normally block progression, but may produce `WARN`.
- `ADVISORY`: informational; does not block progression.

## Check Statuses

- `PASS`: evidence supports readiness.
- `WARN`: evidence indicates non-blocking concern.
- `FAIL`: evidence indicates a blocking readiness problem.
- `SKIPPED`: check was intentionally not run by policy.
- `ERROR`: check could not complete.

## Fail-Closed Rule

Every required readiness condition must fail closed. Missing evidence, ambiguous evidence, unavailable inputs, runtime errors, or unsupported states are treated as blocking failures unless the repository policy explicitly reclassifies the condition as non-required.

## Decision Evidence

Every gate decision must include:

- Gate outcome.
- Checks evaluated.
- Requirement level for each check.
- Status for each check.
- Blocking conditions.
- Warnings.
- Evidence references.
- Remediation guidance where available.

## Exit-State Mapping

Executable implementations that choose to expose process exit codes should use:

- `0`: `PASS`
- `1`: `FAIL`
- `2`: `WARN`
- `3`: system, configuration, or execution error

This mapping is a standard, not an implementation shipped by this repository.
