# SOCKS Operator Guide

## Supported Platforms

Validated for Windows PowerShell 5.1 on Windows. PowerShell 7 on Windows is expected to work where standard APIs are available, but is not claimed as validated unless tested in the operator environment.

## System Requirements

- Windows with PowerShell 5.1
- Git 2.0 or newer for Git repository checks
- Local filesystem access to the target repository

## Installation

Build or obtain the release package, then install into a target repository:

```powershell
.\tools\New-SOCKSReleasePackage.ps1
.\tools\Install-SOCKS.ps1 -PackagePath .\.socks\release\SOCKS-1.0.0.zip -TargetRoot D:\path\to\target -BackupExisting
```

## First Run

```powershell
cd D:\path\to\target
.\socks.ps1
```

## Configuration

Edit `socks.config.json`. Keep `workspace_root` local to the target repository and write runtime evidence under `.socks/evidence`.

## Policy Profiles

Use `policy.check_levels` to promote advisory or optional checks to `REQUIRED`. Use `policy.disabled_checks` only when the repository has an explicit reason to permit a missing condition.

## Exit Codes

- `0`: PASS
- `1`: FAIL
- `2`: WARN
- `3`: system or configuration error

## Evidence Locations

Default reports are written to `.socks/evidence` as JSON, Markdown, HTML, and summary JSON.

## Common Failures

- Missing configuration: restore or create `socks.config.json`.
- Unsupported schema: use schema `1.0`.
- Missing Git: install Git or disable Git checks only by explicit policy.
- Detached HEAD: checkout a branch.
- Missing required environment variable: set the variable outside source control.
- Plugin manifest failure: correct `plugin.json` required fields.

## Upgrade

Install the new package with backup enabled:

```powershell
.\tools\Install-SOCKS.ps1 -PackagePath .\SOCKS-1.0.0.zip -TargetRoot D:\path\to\target -BackupExisting
```

Schema `1.0` is backward compatible within SOCKS `1.0.x`.

## Rollback

Restore files from the generated `.socks/backups/socks-install-*` directory or reinstall the previous package with `-BackupExisting`.

## Uninstall

```powershell
.\tools\Uninstall-SOCKS.ps1 -TargetRoot D:\path\to\target
```

Use `-RemoveConfig` only when the operator intentionally wants to remove `socks.config.json`.

## Connectors

External network checks are disabled by default. Synthetic connector failure modes may be used for validation without credentials. Do not store credentials in connector configuration.

## Plugins

Plugins are manifest-only in SOCKS `1.0.0`; arbitrary plugin code is not executed. Plugin manifests must define `id`, `name`, `version`, `socks_min_version`, and `entry`.

## Security

SOCKS redacts secret-like fields, does not record environment variable values, and does not require credentials by default.

## Troubleshooting Evidence Checklist

Provide the summary JSON, full JSON report, command line used, exit code, SOCKS version, UNDIES doctor output, Git branch, and Git commit.
