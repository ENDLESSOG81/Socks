# SOCKS

System Operating Connect Control System.

SOCKS verifies local project readiness and produces an operational gate result:

- `PASS`
- `WARN`
- `FAIL`

SOCKS-001 is the initial foundation build for local, non-destructive environment verification.

Current version: `SOCKS v1.0.0`

## Run

```powershell
.\socks.ps1
```

## Test

```powershell
.\tests\Run-SOCKSTests.ps1
```

## Exit Codes

- `0`: PASS
- `1`: FAIL
- `2`: WARN
- `3`: system or configuration error

See `docs/SOCKS-SYSTEM-CONTRACT.md` for the full contract.

Release packaging:

```powershell
.\tools\New-SOCKSReleasePackage.ps1
```
