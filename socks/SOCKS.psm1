Set-StrictMode -Version Latest

$script:SOCKSVersion = '0.1.0-alpha.1'
$script:CheckImplementationVersion = '0.1.0'
$script:SupportedSchemaVersions = @('1.0')

function Protect-SOCKSSecret {
    param([AllowNull()]$Value)

    if($null -eq $Value){ return $null }

    if($Value -is [System.Collections.IDictionary]){
        $Output = [ordered]@{}
        foreach($Key in $Value.Keys){
            if("$Key" -match '(?i)(secret|token|password|credential|api[_-]?key|private[_-]?key)'){
                $Output[$Key] = '[REDACTED]'
            } else {
                $Output[$Key] = Protect-SOCKSSecret $Value[$Key]
            }
        }
        return $Output
    }

    if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
        $Items = @()
        foreach($Item in $Value){ $Items += Protect-SOCKSSecret $Item }
        return $Items
    }

    $Text = "$Value"
    $Text = $Text -replace '(?i)(secret|token|password|credential|api[_-]?key|private[_-]?key)\s*[:=]\s*[^;\s,}]+', '$1=[REDACTED]'
    $Text = $Text -replace 'sk-[A-Za-z0-9_\-]{10,}', 'sk-[REDACTED]'
    return $Text
}

function ConvertTo-SOCKSHashtable {
    param([AllowNull()]$Value)

    if($null -eq $Value){ return $null }
    if($Value -is [System.Collections.IDictionary]){
        $Table = [ordered]@{}
        foreach($Key in $Value.Keys){ $Table[$Key] = ConvertTo-SOCKSHashtable $Value[$Key] }
        return $Table
    }
    if($Value -is [pscustomobject]){
        $Table = [ordered]@{}
        foreach($Property in $Value.PSObject.Properties){ $Table[$Property.Name] = ConvertTo-SOCKSHashtable $Property.Value }
        return $Table
    }
    if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
        $Items = @()
        foreach($Item in $Value){ $Items += ConvertTo-SOCKSHashtable $Item }
        return $Items
    }
    return $Value
}

function Get-SOCKSFullPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$BasePath
    )

    if([System.IO.Path]::IsPathRooted($Path)){
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-SOCKSValue {
    param(
        [AllowNull()]$Source,
        [Parameter(Mandatory=$true)][string]$Name,
        $Default = $null
    )

    if($null -eq $Source){ return $Default }
    if($Source -is [System.Collections.IDictionary]){
        if($Source.Contains($Name)){ return $Source[$Name] }
        return $Default
    }
    $Property = $Source.PSObject.Properties[$Name]
    if($null -ne $Property){ return $Property.Value }
    return $Default
}

function Get-SOCKSSha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $HashBytes = $Sha.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($HashBytes) -replace '-', '').ToUpperInvariant()
    } finally {
        $Sha.Dispose()
    }
}

function Merge-SOCKSHashtable {
    param(
        [Parameter(Mandatory=$true)]$Base,
        [Parameter(Mandatory=$true)]$Override
    )

    $Merged = [ordered]@{}
    foreach($Key in $Base.Keys){ $Merged[$Key] = $Base[$Key] }
    foreach($Key in $Override.Keys){
        if($Merged.Contains($Key) -and $Merged[$Key] -is [System.Collections.IDictionary] -and $Override[$Key] -is [System.Collections.IDictionary]){
            $Merged[$Key] = Merge-SOCKSHashtable -Base $Merged[$Key] -Override $Override[$Key]
        } else {
            $Merged[$Key] = $Override[$Key]
        }
    }
    return $Merged
}

function Normalize-SOCKSPolicy {
    param([AllowNull()]$Policy)

    if($null -eq $Policy -or $Policy -isnot [System.Collections.IDictionary]){
        $Policy = [ordered]@{}
    }
    if(-not $Policy.Contains('promote_optional_failures')){ $Policy.promote_optional_failures = $false }
    if(-not $Policy.Contains('promoted_optional_checks') -or $null -eq $Policy.promoted_optional_checks){ $Policy.promoted_optional_checks = @() } else { $Policy.promoted_optional_checks = @($Policy.promoted_optional_checks) }
    if(-not $Policy.Contains('disabled_checks') -or $null -eq $Policy.disabled_checks){ $Policy.disabled_checks = @() } else { $Policy.disabled_checks = @($Policy.disabled_checks) }
    if(-not $Policy.Contains('check_levels') -or $null -eq $Policy.check_levels){ $Policy.check_levels = [ordered]@{} }
    if(-not $Policy.Contains('conditional_checks') -or $null -eq $Policy.conditional_checks){ $Policy.conditional_checks = [ordered]@{} }
    return $Policy
}

function Test-SOCKSConfigurationSchema {
    param([Parameter(Mandatory=$true)]$Config)

    $Errors = @()
    foreach($RequiredKey in @('schema_version','socks_version','workspace_root','evidence_root','required_runtime','policy')){
        if(-not $Config.Contains($RequiredKey) -or [string]::IsNullOrWhiteSpace("$($Config[$RequiredKey])")){
            $Errors += "Required SOCKS configuration key is missing: $RequiredKey"
        }
    }
    if($Config.Contains('schema_version') -and $script:SupportedSchemaVersions -notcontains "$($Config.schema_version)"){
        $Errors += "Unsupported SOCKS configuration schema_version: $($Config.schema_version)"
    }
    if($Config.Contains('policy') -and $Config.policy -isnot [System.Collections.IDictionary]){
        $Errors += 'SOCKS policy must be an object.'
    }
    return [ordered]@{ valid = ($Errors.Count -eq 0); errors = $Errors }
}

function Import-SOCKSConfigurationFile {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [string[]]$Visited = @()
    )

    $FullPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if($Visited -contains $FullPath){ throw "SOCKS configuration inheritance cycle detected at $FullPath" }
    if(-not (Test-Path -LiteralPath $FullPath -PathType Leaf)){ throw "Required SOCKS configuration was not found at $ConfigPath" }

    $Raw = Get-Content -LiteralPath $FullPath -Raw
    if([string]::IsNullOrWhiteSpace($Raw)){ throw "Required SOCKS configuration is empty at $FullPath" }

    $Parsed = ConvertTo-SOCKSHashtable ($Raw | ConvertFrom-Json)
    $Inherited = $false
    if($Parsed.Contains('extends') -and -not [string]::IsNullOrWhiteSpace("$($Parsed.extends)")){
        $ParentPath = Get-SOCKSFullPath -Path $Parsed.extends -BasePath (Split-Path -Parent $FullPath)
        $Parent = Import-SOCKSConfigurationFile -ConfigPath $ParentPath -Visited ($Visited + $FullPath)
        $Parsed.Remove('extends')
        $Parsed = Merge-SOCKSHashtable -Base $Parent.config -Override $Parsed
        $Raw = $Parent.raw + [Environment]::NewLine + $Raw
        $Inherited = $true
    }

    return [ordered]@{ config = $Parsed; raw = $Raw; path = $FullPath; inherited = $Inherited }
}

function Get-SOCKSUndiesSession {
    param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)

    $SessionRoot = Join-Path $WorkspaceRoot '.undies/sessions'
    if(-not (Test-Path -LiteralPath $SessionRoot)){ return $null }

    $Latest = Get-ChildItem -LiteralPath $SessionRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if($null -eq $Latest){ return $null }

    try {
        $Session = Get-Content -LiteralPath $Latest.FullName -Raw | ConvertFrom-Json
        return $Session.session_id
    } catch {
        return $Latest.BaseName
    }
}

function Import-SOCKSConfiguration {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)

    $Loaded = Import-SOCKSConfigurationFile -ConfigPath $ConfigPath
    $Config = $Loaded.config
    $Schema = Test-SOCKSConfigurationSchema -Config $Config
    if(-not $Schema.valid){ throw ($Schema.errors -join '; ') }
    $Config.policy = Normalize-SOCKSPolicy -Policy $Config.policy
    $Config.config_path = $Loaded.path
    $Config.config_directory = Split-Path -Parent $Config.config_path
    $Config.config_integrity = [ordered]@{
        algorithm = 'SHA256'
        raw_sha256 = Get-SOCKSSha256Text -Text $Loaded.raw
        inherited = $Loaded.inherited
        schema_valid = $Schema.valid
    }
    return $Config
}

function Resolve-SOCKSCheckRequirement {
    param(
        [Parameter(Mandatory=$true)][string]$CheckId,
        [Parameter(Mandatory=$true)][ValidateSet('REQUIRED','OPTIONAL','ADVISORY')][string]$DefaultRequirement,
        [Parameter(Mandatory=$true)]$Policy
    )

    if($Policy.check_levels -is [System.Collections.IDictionary] -and $Policy.check_levels.Contains($CheckId)){
        $Level = "$($Policy.check_levels[$CheckId])".ToUpperInvariant()
        if($Level -in @('REQUIRED','OPTIONAL','ADVISORY')){ return $Level }
    }
    return $DefaultRequirement
}

function Test-SOCKSCheckEnabled {
    param(
        [Parameter(Mandatory=$true)][string]$CheckId,
        [Parameter(Mandatory=$true)]$Policy
    )

    return (@($Policy.disabled_checks) -notcontains $CheckId)
}

function Get-SOCKSEnvironment {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [string]$WorkspacePath,
        [string]$EvidenceRoot
    )

    $ResolvedWorkspace = if([string]::IsNullOrWhiteSpace($WorkspacePath)){
        Get-SOCKSFullPath -Path $Config.workspace_root -BasePath $Config.config_directory
    } else {
        Get-SOCKSFullPath -Path $WorkspacePath -BasePath (Get-Location).Path
    }

    $ResolvedEvidenceRoot = if([string]::IsNullOrWhiteSpace($EvidenceRoot)){
        Get-SOCKSFullPath -Path $Config.evidence_root -BasePath $Config.config_directory
    } else {
        Get-SOCKSFullPath -Path $EvidenceRoot -BasePath (Get-Location).Path
    }

    return [ordered]@{
        workspace_root = $ResolvedWorkspace
        evidence_root = $ResolvedEvidenceRoot
        powershell_version = $PSVersionTable.PSVersion.ToString()
        runtime = 'PowerShell'
        platform = [System.Environment]::OSVersion.VersionString
        undies_session_id = Get-SOCKSUndiesSession -WorkspaceRoot $ResolvedWorkspace
        discovery = Get-SOCKSDiscoveryEvidence -WorkspaceRoot $ResolvedWorkspace
    }
}

function Get-SOCKSDiscoveryEvidence {
    param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)

    $DriveRoot = [System.IO.Path]::GetPathRoot($WorkspaceRoot)
    $Drive = $null
    try { $Drive = Get-PSDrive -Name $DriveRoot.Substring(0,1) -ErrorAction Stop } catch { }

    $Network = @()
    try {
        $Network = @(Get-NetIPConfiguration -ErrorAction Stop | ForEach-Object {
            [ordered]@{
                interface_alias = $_.InterfaceAlias
                interface_description = $_.InterfaceDescription
                ipv4_present = ($null -ne $_.IPv4Address)
                ipv6_present = ($null -ne $_.IPv6Address)
            }
        })
    } catch {
        $Network = @([ordered]@{ unavailable = $true; reason = 'Network interface discovery API unavailable.' })
    }

    $EnvNames = [Environment]::GetEnvironmentVariables().Keys | Sort-Object | ForEach-Object {
        if("$_" -match '(?i)(secret|token|password|credential|api[_-]?key|private[_-]?key)'){ '[REDACTED_NAME]' } else { "$_" }
    }

    $WorkspaceItem = Get-Item -LiteralPath $WorkspaceRoot -ErrorAction SilentlyContinue
    return [ordered]@{
        operating_system = [ordered]@{
            platform = [System.Environment]::OSVersion.Platform.ToString()
            version = [System.Environment]::OSVersion.VersionString
            is_64_bit_os = [System.Environment]::Is64BitOperatingSystem
            machine_name = [System.Environment]::MachineName
        }
        runtimes = [ordered]@{
            powershell = $PSVersionTable.PSVersion.ToString()
            dotnet_clr = [System.Environment]::Version.ToString()
        }
        cpu = [ordered]@{
            processor_count = [System.Environment]::ProcessorCount
            is_64_bit_process = [System.Environment]::Is64BitProcess
        }
        memory = [ordered]@{
            working_set_bytes = [System.Environment]::WorkingSet
        }
        disk = [ordered]@{
            root = $DriveRoot
            free_bytes = if($Drive){ $Drive.Free } else { $null }
            used_bytes = if($Drive){ $Drive.Used } else { $null }
        }
        network_interfaces = $Network
        environment_variables = [ordered]@{
            count = @($EnvNames).Count
            names = @($EnvNames)
        }
        workspace = [ordered]@{
            path = $WorkspaceRoot
            exists = ($null -ne $WorkspaceItem)
            created_utc = if($WorkspaceItem){ $WorkspaceItem.CreationTimeUtc.ToString('o') } else { $null }
            modified_utc = if($WorkspaceItem){ $WorkspaceItem.LastWriteTimeUtc.ToString('o') } else { $null }
        }
    }
}

function New-SOCKSCheckResult {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][ValidateSet('REQUIRED','OPTIONAL','ADVISORY')][string]$RequirementLevel,
        [Parameter(Mandatory=$true)][ValidateSet('PASS','WARN','FAIL','SKIPPED','ERROR')][string]$Status,
        [Parameter(Mandatory=$true)][string]$Summary,
        [Parameter(Mandatory=$true)]$Evidence,
        [string]$FailureReason,
        [string]$Remediation,
        [Parameter(Mandatory=$true)][datetime]$StartTime,
        [Parameter(Mandatory=$true)][datetime]$EndTime
    )

    return [ordered]@{
        id = $Id
        name = $Name
        category = $Category
        requirement_level = $RequirementLevel
        status = $Status
        summary = Protect-SOCKSSecret $Summary
        evidence = Protect-SOCKSSecret $Evidence
        failure_reason = Protect-SOCKSSecret $FailureReason
        remediation = Protect-SOCKSSecret $Remediation
        start_timestamp = $StartTime.ToUniversalTime().ToString('o')
        end_timestamp = $EndTime.ToUniversalTime().ToString('o')
        duration_ms = [math]::Round(($EndTime - $StartTime).TotalMilliseconds, 3)
        implementation_version = $script:CheckImplementationVersion
    }
}

function Invoke-SOCKSCheck {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][ValidateSet('REQUIRED','OPTIONAL','ADVISORY')][string]$RequirementLevel,
        [Parameter(Mandatory=$true)][scriptblock]$Body
    )

    $Start = Get-Date
    try {
        $Outcome = & $Body
        $End = Get-Date
        return New-SOCKSCheckResult -Id $Id -Name $Name -Category $Category -RequirementLevel $RequirementLevel -Status (Get-SOCKSValue -Source $Outcome -Name 'status' -Default 'ERROR') -Summary (Get-SOCKSValue -Source $Outcome -Name 'summary' -Default 'Check completed without a summary.') -Evidence (Get-SOCKSValue -Source $Outcome -Name 'evidence' -Default @{}) -FailureReason (Get-SOCKSValue -Source $Outcome -Name 'failure_reason') -Remediation (Get-SOCKSValue -Source $Outcome -Name 'remediation') -StartTime $Start -EndTime $End
    } catch {
        $End = Get-Date
        return New-SOCKSCheckResult -Id $Id -Name $Name -Category $Category -RequirementLevel $RequirementLevel -Status 'ERROR' -Summary 'Check execution error.' -Evidence ([ordered]@{ exception = $_.Exception.GetType().FullName }) -FailureReason $_.Exception.Message -Remediation 'Review the check implementation and retry.' -StartTime $Start -EndTime $End
    }
}

function Get-SOCKSChecks {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)]$Environment
    )

    $Workspace = $Environment.workspace_root
    $EvidenceRoot = $Environment.evidence_root

    return @(
        @{ id='workspace.exists'; name='Workspace path exists'; category='workspace'; requirement='REQUIRED'; body={
            $Exists = Test-Path -LiteralPath $Workspace -PathType Container
            if($Exists){ return @{status='PASS';summary='Workspace path exists.';evidence=@{path=$Workspace;exists=$true}} }
            return @{status='FAIL';summary='Workspace path does not exist.';evidence=@{path=$Workspace;exists=$false};failure_reason='Workspace directory is missing.';remediation='Create the workspace or correct the configured workspace path.'}
        }.GetNewClosure()},
        @{ id='workspace.readable'; name='Workspace path is readable'; category='workspace'; requirement='REQUIRED'; body={
            Get-ChildItem -LiteralPath $Workspace -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
            return @{status='PASS';summary='Workspace path is readable.';evidence=@{path=$Workspace;readable=$true}}
        }.GetNewClosure()},
        @{ id='workspace.writable'; name='Workspace path is writable'; category='workspace'; requirement='REQUIRED'; body={
            $Probe = Join-Path $Workspace ('.socks-write-probe-' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                Set-Content -LiteralPath $Probe -Value 'SOCKS write probe' -NoNewline -ErrorAction Stop
                Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
                return @{status='PASS';summary='Workspace path is writable.';evidence=@{path=$Workspace;writable=$true}}
            } catch {
                Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
                return @{status='FAIL';summary='Workspace path is not writable.';evidence=@{path=$Workspace;writable=$false};failure_reason=$_.Exception.Message;remediation='Grant write access or choose a writable workspace.'}
            }
        }.GetNewClosure()},
        @{ id='git.installed'; name='Git is installed'; category='git'; requirement='REQUIRED'; body={
            $Git = Get-Command git -ErrorAction SilentlyContinue
            if($null -ne $Git){ return @{status='PASS';summary='Git executable was found.';evidence=@{source=$Git.Source}} }
            return @{status='FAIL';summary='Git executable was not found.';evidence=@{found=$false};failure_reason='git was not found on PATH.';remediation='Install Git or add Git to PATH.'}
        }.GetNewClosure()},
        @{ id='git.repository'; name='Current directory is a Git repository'; category='git'; requirement='REQUIRED'; body={
            $Inside = & git -C $Workspace rev-parse --is-inside-work-tree 2>$null
            if($LASTEXITCODE -eq 0 -and "$Inside".Trim() -eq 'true'){ return @{status='PASS';summary='Workspace is inside a Git work tree.';evidence=@{path=$Workspace;inside_work_tree=$true}} }
            return @{status='FAIL';summary='Workspace is not a Git repository.';evidence=@{path=$Workspace;inside_work_tree=$false};failure_reason='git rev-parse could not confirm a work tree.';remediation='Initialize Git or choose a Git repository workspace.'}
        }.GetNewClosure()},
        @{ id='git.branch'; name='Git branch can be identified'; category='git'; requirement='REQUIRED'; body={
            $Branch = (& git -C $Workspace branch --show-current 2>$null).Trim()
            if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($Branch)){ return @{status='PASS';summary='Git branch identified.';evidence=@{branch=$Branch}} }
            return @{status='FAIL';summary='Git branch could not be identified.';evidence=@{branch=$Branch};failure_reason='Current branch is empty or unavailable.';remediation='Checkout a branch or inspect repository state.'}
        }.GetNewClosure()},
        @{ id='git.commit'; name='Git commit can be identified'; category='git'; requirement='REQUIRED'; body={
            $Commit = (& git -C $Workspace rev-parse HEAD 2>$null).Trim()
            if($LASTEXITCODE -eq 0 -and $Commit -match '^[0-9a-f]{40}$'){ return @{status='PASS';summary='Git commit identified.';evidence=@{commit=$Commit}} }
            return @{status='FAIL';summary='Git commit could not be identified.';evidence=@{commit=$Commit};failure_reason='HEAD could not be resolved to a commit.';remediation='Create an initial commit or repair Git metadata.'}
        }.GetNewClosure()},
        @{ id='config.loaded'; name='Required SOCKS configuration can be loaded'; category='configuration'; requirement='REQUIRED'; body={
            return @{status='PASS';summary='Required SOCKS configuration was loaded and validated.';evidence=@{config_path=$Config.config_path;schema_version=$Config.schema_version;socks_version=$Config.socks_version;integrity=$Config.config_integrity;policy=$Config.policy}}
        }.GetNewClosure()},
        @{ id='runtime.identified'; name='Required runtime can be identified'; category='runtime'; requirement='REQUIRED'; body={
            if($Environment.runtime -eq $Config.required_runtime){ return @{status='PASS';summary='Required runtime identified.';evidence=@{required_runtime=$Config.required_runtime;powershell_version=$Environment.powershell_version;platform=$Environment.platform}} }
            return @{status='FAIL';summary='Required runtime was not identified.';evidence=@{required_runtime=$Config.required_runtime;actual_runtime=$Environment.runtime};failure_reason='Runtime mismatch.';remediation='Run SOCKS with the configured runtime.'}
        }.GetNewClosure()},
        @{ id='evidence.directory'; name='Evidence output directory can be created or accessed'; category='evidence'; requirement='REQUIRED'; body={
            if(-not (Test-Path -LiteralPath $EvidenceRoot)){
                New-Item -ItemType Directory -Path $EvidenceRoot -Force -ErrorAction Stop | Out-Null
            }
            $Probe = Join-Path $EvidenceRoot ('.socks-evidence-probe-' + [guid]::NewGuid().ToString('N') + '.tmp')
            Set-Content -LiteralPath $Probe -Value 'SOCKS evidence probe' -NoNewline -ErrorAction Stop
            Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
            return @{status='PASS';summary='Evidence output directory is available.';evidence=@{path=$EvidenceRoot;available=$true}}
        }.GetNewClosure()},
        @{ id='discovery.environment'; name='Environment discovery evidence can be generated'; category='discovery'; requirement='REQUIRED'; body={
            $Discovery = $Environment.discovery
            if($null -ne $Discovery -and $Discovery.operating_system.version -and $Discovery.cpu.processor_count -ge 1){
                return @{status='PASS';summary='Environment discovery evidence was generated.';evidence=$Discovery}
            }
            return @{status='FAIL';summary='Environment discovery evidence is incomplete.';evidence=$Discovery;failure_reason='Required discovery fields were unavailable.';remediation='Run SOCKS in a local PowerShell environment with standard system APIs.'}
        }.GetNewClosure()}
    ) | Where-Object { Test-SOCKSCheckEnabled -CheckId $_.id -Policy $Config.policy } | ForEach-Object {
        $_.requirement = Resolve-SOCKSCheckRequirement -CheckId $_.id -DefaultRequirement $_.requirement -Policy $Config.policy
        $_
    }
}

function Invoke-SOCKSChecks {
    param([Parameter(Mandatory=$true)]$Checks)

    $Results = @()
    foreach($Check in $Checks){
        $Results += Invoke-SOCKSCheck -Id $Check.id -Name $Check.name -Category $Check.category -RequirementLevel $Check.requirement -Body $Check.body
    }
    return $Results
}

function Get-SOCKSGateEvaluation {
    param(
        [Parameter(Mandatory=$true)]$Results,
        [Parameter(Mandatory=$true)]$Policy
    )

    $Policy = Normalize-SOCKSPolicy -Policy $Policy
    $Blocking = @($Results | Where-Object { $_.requirement_level -eq 'REQUIRED' -and $_.status -in @('FAIL','ERROR') })
    $OptionalFailures = @($Results | Where-Object { $_.requirement_level -eq 'OPTIONAL' -and $_.status -in @('FAIL','ERROR','WARN') })
    $AdvisoryFailures = @($Results | Where-Object { $_.requirement_level -eq 'ADVISORY' -and $_.status -in @('FAIL','ERROR','WARN') })
    $PromoteOptional = [bool]$Policy.promote_optional_failures
    $PromotedIds = @($Policy.promoted_optional_checks)
    $PromotedOptionalFailures = @($OptionalFailures | Where-Object { $PromotedIds -contains $_.id })

    if($Blocking.Count -gt 0){
        $Status = 'FAIL'
        $Reason = 'One or more required checks failed or errored.'
    } elseif(($PromoteOptional -or $PromotedOptionalFailures.Count -gt 0) -and $OptionalFailures.Count -gt 0){
        $Status = 'FAIL'
        $Reason = 'Policy promoted optional check failures to blocking failures.'
        if($PromoteOptional){ $Blocking = $OptionalFailures } else { $Blocking = $PromotedOptionalFailures }
    } elseif($OptionalFailures.Count -gt 0){
        $Status = 'WARN'
        $Reason = 'Required checks passed, but optional checks produced warnings or failures.'
    } else {
        $Status = 'PASS'
        $Reason = 'All required checks passed.'
    }

    return [ordered]@{
        status = $Status
        reason = $Reason
        blocking_conditions = @($Blocking | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; summary=$_.summary; remediation=$_.remediation } })
        warnings = @($OptionalFailures | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; summary=$_.summary; remediation=$_.remediation } })
        advisory = @($AdvisoryFailures | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; summary=$_.summary; remediation=$_.remediation } })
        evidence = [ordered]@{
            required_fail_or_error_count = $Blocking.Count
            optional_warning_or_failure_count = $OptionalFailures.Count
            advisory_warning_or_failure_count = $AdvisoryFailures.Count
            promote_optional_failures = $PromoteOptional
            promoted_optional_checks = $PromotedIds
            calculation = $Reason
        }
    }
}

function New-SOCKSReport {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)]$Environment,
        [Parameter(Mandatory=$true)]$Results,
        [Parameter(Mandatory=$true)]$Gate,
        [Parameter(Mandatory=$true)][datetime]$StartTime,
        [Parameter(Mandatory=$true)][datetime]$EndTime
    )

    $BranchResult = $Results | Where-Object { (Get-SOCKSValue -Source $_ -Name 'id') -eq 'git.branch' } | Select-Object -First 1
    $CommitResult = $Results | Where-Object { (Get-SOCKSValue -Source $_ -Name 'id') -eq 'git.commit' } | Select-Object -First 1
    $Branch = Get-SOCKSValue -Source (Get-SOCKSValue -Source $BranchResult -Name 'evidence') -Name 'branch'
    $Commit = Get-SOCKSValue -Source (Get-SOCKSValue -Source $CommitResult -Name 'evidence') -Name 'commit'

    return [ordered]@{
        socks_version = $script:SOCKSVersion
        config_socks_version = $Config.socks_version
        undies_session_id = $Environment.undies_session_id
        repository_path = $Environment.workspace_root
        git_branch = $Branch
        git_commit = $Commit
        start_timestamp = $StartTime.ToUniversalTime().ToString('o')
        end_timestamp = $EndTime.ToUniversalTime().ToString('o')
        duration_ms = [math]::Round(($EndTime - $StartTime).TotalMilliseconds, 3)
        discovery = $Environment.discovery
        check_results = $Results
        gate = $Gate
        blocking_conditions = $Gate.blocking_conditions
        warnings = $Gate.warnings
        recommended_remediation = @($Gate.blocking_conditions + $Gate.warnings | Where-Object { -not [string]::IsNullOrWhiteSpace($_.remediation) } | ForEach-Object { $_.remediation } | Select-Object -Unique)
        integrity = [ordered]@{
            algorithm = 'SHA256'
            payload_sha256_excluding_integrity = $null
        }
    }
}

function Save-SOCKSReports {
    param(
        [Parameter(Mandatory=$true)]$Report,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot,
        [Parameter(Mandatory=$true)][string]$ReportPrefix
    )

    if(-not (Test-Path -LiteralPath $EvidenceRoot)){
        New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    }

    $Stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $Base = "$ReportPrefix-$Stamp"
    $JsonPath = Join-Path $EvidenceRoot ($Base + '.json')
    $MarkdownPath = Join-Path $EvidenceRoot ($Base + '.md')

    $Report.integrity.payload_sha256_excluding_integrity = $null
    $Json = Protect-SOCKSSecret $Report | ConvertTo-Json -Depth 20
    $Hash = Get-SOCKSSha256Text -Text $Json
    $Report.integrity.payload_sha256_excluding_integrity = $Hash
    $Json = Protect-SOCKSSecret $Report | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $JsonPath -Value $Json -Encoding UTF8

    $Lines = @()
    $Lines += "# SOCKS Readiness Report"
    $Lines += ""
    $Lines += "- SOCKS version: $($Report.socks_version)"
    $Lines += "- UNDIES session: $($Report.undies_session_id)"
    $Lines += "- Repository: $($Report.repository_path)"
    $Lines += "- Branch: $($Report.git_branch)"
    $Lines += "- Commit: $($Report.git_commit)"
    $Lines += "- Started: $($Report.start_timestamp)"
    $Lines += "- Ended: $($Report.end_timestamp)"
    $Lines += "- Overall gate result: $($Report.gate.status)"
    $Lines += "- Gate reason: $($Report.gate.reason)"
    $Lines += "- Payload SHA256 excluding integrity field: $($Report.integrity.payload_sha256_excluding_integrity)"
    $Lines += ""
    $Lines += "## Blocking Conditions"
    if($Report.blocking_conditions.Count -eq 0){ $Lines += "None." } else { foreach($Item in $Report.blocking_conditions){ $Lines += "- $($Item.id): $($Item.summary) Remediation: $($Item.remediation)" } }
    $Lines += ""
    $Lines += "## Warnings"
    if($Report.warnings.Count -eq 0){ $Lines += "None." } else { foreach($Item in $Report.warnings){ $Lines += "- $($Item.id): $($Item.summary) Remediation: $($Item.remediation)" } }
    $Lines += ""
    $Lines += "## Check Results"
    foreach($Result in $Report.check_results){
        $Lines += "- [$($Result.status)] $($Result.id) ($($Result.requirement_level)): $($Result.summary)"
    }
    Set-Content -LiteralPath $MarkdownPath -Value (Protect-SOCKSSecret ($Lines -join [Environment]::NewLine)) -Encoding UTF8

    return [ordered]@{ json = $JsonPath; markdown = $MarkdownPath; payload_sha256_excluding_integrity = $Hash }
}

function Invoke-SOCKSReadiness {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [string]$WorkspacePath,
        [string]$EvidenceRoot,
        [string]$ReportPrefix = 'socks-readiness'
    )

    $Start = Get-Date
    $Config = Import-SOCKSConfiguration -ConfigPath $ConfigPath
    $Environment = Get-SOCKSEnvironment -Config $Config -WorkspacePath $WorkspacePath -EvidenceRoot $EvidenceRoot
    $Checks = Get-SOCKSChecks -Config $Config -Environment $Environment
    $Results = Invoke-SOCKSChecks -Checks $Checks
    $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy $Config.policy
    $End = Get-Date
    $Report = New-SOCKSReport -Config $Config -Environment $Environment -Results $Results -Gate $Gate -StartTime $Start -EndTime $End
    $Reports = Save-SOCKSReports -Report $Report -EvidenceRoot $Environment.evidence_root -ReportPrefix $ReportPrefix

    return [ordered]@{
        gate = $Gate
        reports = $Reports
        report = $Report
    }
}

function Get-SOCKSExitCode {
    param([Parameter(Mandatory=$true)][ValidateSet('PASS','WARN','FAIL','ERROR')][string]$GateStatus)

    switch($GateStatus){
        'PASS' { return 0 }
        'FAIL' { return 1 }
        'WARN' { return 2 }
        default { return 3 }
    }
}

Export-ModuleMember -Function Import-SOCKSConfiguration,Test-SOCKSConfigurationSchema,Normalize-SOCKSPolicy,Merge-SOCKSHashtable,Get-SOCKSDiscoveryEvidence,Get-SOCKSEnvironment,Get-SOCKSChecks,Invoke-SOCKSCheck,Invoke-SOCKSChecks,Get-SOCKSGateEvaluation,New-SOCKSReport,Save-SOCKSReports,Invoke-SOCKSReadiness,Get-SOCKSExitCode,Protect-SOCKSSecret
