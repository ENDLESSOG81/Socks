param(
    [string]$OutputRoot = (Join-Path ([System.IO.Path]::GetTempPath()) ('socks-prod-readiness-' + [guid]::NewGuid().ToString('N'))),
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Results = @()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $script:Results += [ordered]@{ name=$Name; status=$Status; detail=$Detail }
    Write-Host "$Status $Name $Detail"
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    try {
        $Detail = & $Body
        Add-Result -Name $Name -Status 'PASS' -Detail "$Detail"
    } catch {
        Add-Result -Name $Name -Status 'FAIL' -Detail $_.Exception.Message
    }
}

function Write-JsonFile {
    param([string]$Path, $Value)
    Set-Content -LiteralPath $Path -Value ($Value | ConvertTo-Json -Depth 20) -Encoding UTF8
}

function Invoke-SOCKSCli {
    param([string]$Root, [string]$ConfigPath = '')
    $Args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'socks.ps1'))
    if($ConfigPath){ $Args += @('-ConfigPath', $ConfigPath) }
    try {
        $PreviousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $Output = & powershell @Args 2>&1
        return [ordered]@{ exit_code=$LASTEXITCODE; output=(@($Output | ForEach-Object { "$_" }) -join [Environment]::NewLine) }
    } catch {
        return [ordered]@{ exit_code=$LASTEXITCODE; output=$_.Exception.Message }
    } finally {
        $ErrorActionPreference = $PreviousPreference
    }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$PackageInfo = $null
$PackagePath = $null

Invoke-Step 'build fresh release package' {
    $Json = & (Join-Path $RepoRoot 'tools/New-SOCKSReleasePackage.ps1') -OutputRoot (Join-Path $OutputRoot 'release')
    $script:PackageInfo = $Json | ConvertFrom-Json
    $script:PackagePath = $script:PackageInfo.package
    if(-not (Test-Path -LiteralPath $script:PackagePath)){ throw 'Package was not created.' }
    $script:PackageInfo.sha256
}

Invoke-Step 'validate package manifest and exclusions' {
    $Extract = Join-Path $OutputRoot 'manifest-check'
    Expand-Archive -LiteralPath $script:PackagePath -DestinationPath $Extract -Force
    $ManifestPath = Join-Path $Extract 'SOCKS-RELEASE-MANIFEST.json'
    if(-not (Test-Path -LiteralPath $ManifestPath)){ throw 'Missing release manifest.' }
    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $Bad = @($Manifest.files | Where-Object { $_.path -match '(^|/)(\.socks|\.undies|\.git)(/|$)' })
    if($Bad.Count -gt 0){ throw 'Package includes runtime or repository metadata.' }
    "files=$($Manifest.files.Count)"
}

Invoke-Step 'clean-room package installation and PASS run' {
    $Target = Join-Path $OutputRoot 'Clean Room Repo'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'target.txt') -Value 'target repository file' -Encoding UTF8
    & git -C $Target add target.txt | Out-Null
    & git -C $Target commit -m 'initial target commit' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target -BackupExisting | Out-Null
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 0){ throw "Expected PASS exit 0, got $($Run.exit_code): $($Run.output)" }
    'exit=0'
}

Invoke-Step 'path with spaces execution' {
    $Target = Join-Path $OutputRoot 'Path With Spaces Repo'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'space path' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'space path commit' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 0){ throw "Path with spaces failed: $($Run.output)" }
    'exit=0'
}

Invoke-Step 'nested project path execution' {
    $Target = Join-Path $OutputRoot 'nested\inner\repo'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'nested.txt') -Value 'nested' -Encoding UTF8
    & git -C $Target add nested.txt | Out-Null
    & git -C $Target commit -m 'nested commit' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 0){ throw "Nested path failed: $($Run.output)" }
    'exit=0'
}

Invoke-Step 'non-default configuration path' {
    $Target = Join-Path $OutputRoot 'non-default-config'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'config' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'config commit' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Config = Get-Content -LiteralPath (Join-Path $Target 'socks.config.json') -Raw | ConvertFrom-Json
    $Config.evidence_root = '.socks/custom-evidence'
    $Alt = Join-Path $Target 'config.alt.json'
    Write-JsonFile -Path $Alt -Value $Config
    $Run = Invoke-SOCKSCli -Root $Target -ConfigPath $Alt
    if($Run.exit_code -ne 0){ throw "Non-default config failed: $($Run.output)" }
    'exit=0'
}

Invoke-Step 'non-Git workspace forbidden fails closed' {
    $Target = Join-Path $OutputRoot 'non-git-forbidden'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 1){ throw "Expected FAIL exit 1, got $($Run.exit_code)." }
    'exit=1'
}

Invoke-Step 'non-Git workspace permitted by explicit policy' {
    $Target = Join-Path $OutputRoot 'non-git-permitted'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $ConfigPath = Join-Path $Target 'socks.config.json'
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.policy.disabled_checks = @('git.installed','git.repository','git.branch','git.commit','git.working_tree_clean','git.remote_status','git.detached_head','git.ignore_validation')
    Write-JsonFile -Path $ConfigPath -Value $Config
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 0){ throw "Expected policy-permitted PASS, got $($Run.exit_code): $($Run.output)" }
    'exit=0'
}

Invoke-Step 'detached HEAD blocking failure' {
    $Target = Join-Path $OutputRoot 'detached-head'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'detached' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'detached commit' | Out-Null
    $Commit = (& git -C $Target rev-parse HEAD)
    & git -C $Target checkout --detach $Commit | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 1){ throw "Expected detached HEAD FAIL, got $($Run.exit_code)." }
    'exit=1'
}

Invoke-Step 'dirty working tree remains nonblocking advisory' {
    $Target = Join-Path $OutputRoot 'dirty-repo'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'clean' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'dirty base' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'dirty.txt') -Value 'dirty' -Encoding UTF8
    $Run = Invoke-SOCKSCli -Root $Target
    if($Run.exit_code -ne 0){ throw "Dirty advisory should not block by default." }
    'exit=0'
}

Invoke-Step 'failure injection matrix core cases' {
    $Target = Join-Path $OutputRoot 'failure-matrix'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'failure' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'failure base' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null

    $Missing = Invoke-SOCKSCli -Root $Target -ConfigPath (Join-Path $Target 'missing.json')
    if($Missing.exit_code -ne 3){ throw 'Missing config did not exit 3.' }

    $Invalid = Join-Path $Target 'invalid.json'
    Set-Content -LiteralPath $Invalid -Value '{ invalid json' -Encoding UTF8
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $Invalid).exit_code -ne 3){ throw 'Invalid JSON did not exit 3.' }

    $ConfigPath = Join-Path $Target 'socks.config.json'
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.schema_version = '9.9'
    $BadSchema = Join-Path $Target 'bad-schema.json'
    Write-JsonFile -Path $BadSchema -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $BadSchema).exit_code -ne 3){ throw 'Unsupported schema did not exit 3.' }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.workspace_root = (Join-Path $OutputRoot 'missing-workspace')
    $MissingWorkspace = Join-Path $Target 'missing-workspace.json'
    Write-JsonFile -Path $MissingWorkspace -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $MissingWorkspace).exit_code -ne 1){ throw 'Missing workspace did not fail closed.' }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.dependencies.runtimes = @(@{ id='missing-required'; command='definitely-missing-socks-command'; version_args=@('--version'); requirement='REQUIRED' })
    $Runtime = Join-Path $Target 'missing-runtime.json'
    Write-JsonFile -Path $Runtime -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $Runtime).exit_code -ne 1){ throw 'Missing runtime did not fail closed.' }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.configuration.required_environment = @('SOCKS_REQUIRED_ENV_DOES_NOT_EXIST')
    $Env = Join-Path $Target 'missing-env.json'
    Write-JsonFile -Path $Env -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $Env).exit_code -ne 1){ throw 'Missing env did not fail closed.' }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.configuration.required_settings = @('api_key')
    $Config | Add-Member -NotePropertyName api_key -NotePropertyValue 'YOUR_SYNTHETIC_VALUE'
    $Placeholder = Join-Path $Target 'placeholder.json'
    Write-JsonFile -Path $Placeholder -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $Placeholder).exit_code -ne 1){ throw 'Placeholder value did not fail closed.' }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.external_connectivity.connectors = @(@{ id='synthetic-timeout'; type='rest'; enabled=$true; requirement='REQUIRED'; synthetic_failure='timeout' })
    $Connector = Join-Path $Target 'connector-timeout.json'
    Write-JsonFile -Path $Connector -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $Connector).exit_code -ne 1){ throw 'Connector timeout did not fail closed.' }

    'matrix=pass'
}

Invoke-Step 'unwritable report target failure' {
    $Target = Join-Path $OutputRoot 'report-failure'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'report' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'report base' | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target | Out-Null
    $Blocked = Join-Path $Target 'blocked-evidence'
    Set-Content -LiteralPath $Blocked -Value 'file blocks directory' -Encoding UTF8
    $Config = Get-Content -LiteralPath (Join-Path $Target 'socks.config.json') -Raw | ConvertFrom-Json
    $Config.evidence_root = 'blocked-evidence'
    $ConfigPath = Join-Path $Target 'blocked-evidence-config.json'
    Write-JsonFile -Path $ConfigPath -Value $Config
    $Run = Invoke-SOCKSCli -Root $Target -ConfigPath $ConfigPath
    if($Run.exit_code -ne 3){ throw "Expected report-writing system error, got $($Run.exit_code)." }
    'exit=3'
}

Invoke-Step 'upgrade and rollback simulation' {
    $Target = Join-Path $OutputRoot 'upgrade-rollback'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'file.txt') -Value 'upgrade' -Encoding UTF8
    & git -C $Target add file.txt | Out-Null
    & git -C $Target commit -m 'upgrade base' | Out-Null
    $BareRemote = Join-Path $OutputRoot 'upgrade-rollback-remote.git'
    & git init --bare $BareRemote | Out-Null
    & git -C $Target remote add origin $BareRemote | Out-Null
    & git -C $Target push -u origin master | Out-Null
    $BaselinePackage = Join-Path $RepoRoot '.socks/release/SOCKS-1.0.0.zip'
    $FirstPackage = if(Test-Path -LiteralPath $BaselinePackage){ $BaselinePackage } else { $script:PackagePath }
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $FirstPackage -TargetRoot $Target -BackupExisting | Out-Null
    $ConfigPath = Join-Path $Target 'socks.config.json'
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $Config.policy.disabled_checks = @('git.ignore_validation','certification.production_readiness')
    Write-JsonFile -Path $ConfigPath -Value $Config
    if((Invoke-SOCKSCli -Root $Target).exit_code -ne 0){ throw 'Baseline install failed.' }
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target -BackupExisting | Out-Null
    if((Invoke-SOCKSCli -Root $Target).exit_code -ne 0){ throw 'Post-upgrade run failed.' }
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $FirstPackage -TargetRoot $Target -BackupExisting | Out-Null
    if((Invoke-SOCKSCli -Root $Target).exit_code -ne 0){ throw 'Post-rollback run failed.' }
    'upgrade=pass rollback=pass'
}

Invoke-Step 'pilot PASS and blocking FAIL' {
    $Target = Join-Path $OutputRoot 'pilot-repo'
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    & git -C $Target init | Out-Null
    Set-Content -LiteralPath (Join-Path $Target 'pilot.txt') -Value 'pilot' -Encoding UTF8
    & git -C $Target add pilot.txt | Out-Null
    & git -C $Target commit -m 'pilot base' | Out-Null
    & git -C $Target switch -c socks-pilot | Out-Null
    & (Join-Path $RepoRoot 'tools/Install-SOCKS.ps1') -PackagePath $script:PackagePath -TargetRoot $Target -BackupExisting | Out-Null
    if((Invoke-SOCKSCli -Root $Target).exit_code -ne 0){ throw 'Pilot PASS failed.' }
    $Config = Get-Content -LiteralPath (Join-Path $Target 'socks.config.json') -Raw | ConvertFrom-Json
    $Config.workspace_root = (Join-Path $OutputRoot 'pilot-missing-workspace')
    $FailConfig = Join-Path $Target 'pilot-fail.json'
    Write-JsonFile -Path $FailConfig -Value $Config
    if((Invoke-SOCKSCli -Root $Target -ConfigPath $FailConfig).exit_code -ne 1){ throw 'Pilot blocking FAIL failed.' }
    Remove-Item -LiteralPath $FailConfig -Force
    if((Invoke-SOCKSCli -Root $Target).exit_code -ne 0){ throw 'Pilot recovery PASS failed.' }
    'pilot=pass'
}

$Summary = [ordered]@{
    output_root = $OutputRoot
    package = $PackagePath
    package_sha256 = if($PackagePath){ (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash } else { $null }
    total = $Results.Count
    passed = @($Results | Where-Object status -eq 'PASS').Count
    failed = @($Results | Where-Object status -eq 'FAIL').Count
    results = @($Results | ForEach-Object { [ordered]@{ name="$($_.name)"; status="$($_.status)"; detail="$($_.detail)" } })
}
$SummaryPath = Join-Path $OutputRoot 'production-readiness-summary.json'
Write-JsonFile -Path $SummaryPath -Value $Summary
Write-Host "SUMMARY $SummaryPath"

if(-not $Keep -and $Summary.failed -eq 0){
    # Keep summary parent evidence by default; disposable repos remain under OutputRoot for audit during this run.
}
if([int]$Summary.failed -gt 0){ [Environment]::Exit(1) }
[Environment]::Exit(0)
