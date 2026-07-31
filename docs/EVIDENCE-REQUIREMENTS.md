# SOCKS Evidence Requirements

SOCKS decisions are only meaningful when supported by auditable evidence.

## Required Evidence Fields

Each check should record:

- Check identifier.
- Check name.
- Category.
- Requirement level.
- Status.
- Summary.
- Evidence reference or evidence payload.
- Failure reason when applicable.
- Remediation guidance when applicable.
- Start timestamp when available.
- End timestamp when available.
- Duration when available.
- Implementation or policy version when applicable.

## Gate Evidence

Each gate decision should record:

- Repository or project identifier.
- Branch and commit when applicable.
- Governance context.
- Gate start and end timestamps.
- Individual check results.
- Overall gate result.
- Blocking conditions.
- Warnings.
- Recommended remediation.
- Evidence integrity information where practical.

## Evidence Integrity

Evidence should be reproducible where possible. Machine-readable evidence is preferred for automation; human-readable summaries are preferred for operator review. Hashes, manifests, or signed records may be used where the adopting repository requires stronger integrity.

## Evidence Exclusions

Evidence must not contain:

- Secret values.
- API keys.
- Tokens.
- Passwords.
- Private keys.
- Connection strings.
- Personal credentials.
- Unapproved local machine paths.

Evidence may record the presence or absence of required secret names, but not their values.
