# SOCKS Adoption Instructions

SOCKS adoption means applying the readiness-gate standard to a governed repository. Adoption does not mean installing executable SOCKS code from this repository.

## Preconditions

- The target repository is governed by its own repository rules.
- Operators understand which readiness checks are required for that repository.
- No credentials, tokens, private keys, or secret values are placed in SOCKS documentation or evidence.
- Any executable implementation used by a project is separate from this sterile standard and must be independently reviewed.

## Adoption Steps

1. Record the target repository name, branch, commit, and governance context.
2. Define the repository-specific readiness checks.
3. Classify each check as `REQUIRED`, `OPTIONAL`, or `ADVISORY`.
4. Define the evidence required for each check.
5. Define how `PASS`, `WARN`, and `FAIL` decisions are reported.
6. Confirm required failures block progression.
7. Confirm indeterminate required checks fail closed.
8. Store evidence in the target repository's approved evidence location.
9. Record adoption decisions in the target repository's own decision log.

## Non-Adoption

A repository has not adopted SOCKS if it only copies terminology without defining required checks, evidence, failure behavior, and operator responsibilities.

## Operator Notes

SOCKS is intentionally conservative. If readiness cannot be proven for a required condition, the correct result is `FAIL`.
