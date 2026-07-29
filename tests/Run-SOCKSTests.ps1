param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $RepoRoot 'socks/SOCKS.psm1'
Import-Module $ModulePath -Force

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if(-not $Condition){ throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if($Expected -ne $Actual){ throw "$Message Expected=[$Expected] Actual=[$Actual]" }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS $Name"
    } catch {
        $script:Failed++
        Write-Host "FAIL $Name - $($_.Exception.Message)"
    }
}

function New-TestConfig {
    param([string]$Root, [string]$WorkspaceRoot, [string]$EvidenceRoot, [bool]$PromoteOptional = $false)
    $ConfigPath = Join-Path $Root 'socks.config.json'
    $Config = [ordered]@{
        schema_version = '1.0'
        socks_version = '0.1.0-alpha.1'
        workspace_root = $WorkspaceRoot
        evidence_root = $EvidenceRoot
        required_runtime = 'PowerShell'
        policy = [ordered]@{ promote_optional_failures = $PromoteOptional }
    }
    Set-Content -LiteralPath $ConfigPath -Value ($Config | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $ConfigPath
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('socks-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
    Invoke-Test 'successful configuration loading' {
        $ConfigPath = New-TestConfig -Root $TempRoot -WorkspaceRoot $RepoRoot -EvidenceRoot (Join-Path $TempRoot 'evidence')
        $Config = Import-SOCKSConfiguration -ConfigPath $ConfigPath
        Assert-Equal '0.1.0-alpha.1' $Config.socks_version 'SOCKS version should load.'
    }

    Invoke-Test 'missing configuration' {
        $Missing = Join-Path $TempRoot 'missing.config.json'
        $Thrown = $false
        try { Import-SOCKSConfiguration -ConfigPath $Missing | Out-Null } catch { $Thrown = $true }
        Assert-True $Thrown 'Missing config should throw.'
    }

    Invoke-Test 'required check passing' {
        $Result = Invoke-SOCKSCheck -Id 'test.required.pass' -Name 'Required pass' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
            @{ status='PASS'; summary='ok'; evidence=@{ ok=$true } }
        }
        Assert-Equal 'PASS' $Result.status 'Required check should pass.'
    }

    Invoke-Test 'required check failing' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'test.required.fail' -Name 'Required fail' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
                @{ status='FAIL'; summary='bad'; evidence=@{ ok=$false }; failure_reason='no'; remediation='fix' }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false }
        Assert-Equal 'FAIL' $Gate.status 'Required failure should fail gate.'
    }

    Invoke-Test 'optional check failing' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'test.optional.fail' -Name 'Optional fail' -Category 'test' -RequirementLevel 'OPTIONAL' -Body {
                @{ status='FAIL'; summary='optional bad'; evidence=@{ ok=$false }; failure_reason='no'; remediation='fix optional' }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false }
        Assert-Equal 'WARN' $Gate.status 'Optional failure should warn gate.'
    }

    Invoke-Test 'check execution error' {
        $Result = Invoke-SOCKSCheck -Id 'test.error' -Name 'Execution error' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
            throw 'boom'
        }
        Assert-Equal 'ERROR' $Result.status 'Thrown checks should normalize to ERROR.'
    }

    Invoke-Test 'overall PASS calculation' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'test.required.pass' -Name 'Required pass' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
                @{ status='PASS'; summary='ok'; evidence=@{ ok=$true } }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false }
        Assert-Equal 'PASS' $Gate.status 'Required pass should pass gate.'
    }

    Invoke-Test 'overall WARN calculation' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'test.required.pass' -Name 'Required pass' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
                @{ status='PASS'; summary='ok'; evidence=@{ ok=$true } }
            }
            Invoke-SOCKSCheck -Id 'test.optional.warn' -Name 'Optional warn' -Category 'test' -RequirementLevel 'OPTIONAL' -Body {
                @{ status='WARN'; summary='watch'; evidence=@{ ok=$false }; remediation='review' }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false }
        Assert-Equal 'WARN' $Gate.status 'Optional warning should warn gate.'
    }

    Invoke-Test 'overall FAIL calculation' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'test.required.error' -Name 'Required error' -Category 'test' -RequirementLevel 'REQUIRED' -Body {
                throw 'required unknown'
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false }
        Assert-Equal 'FAIL' $Gate.status 'Required error should fail gate.'
    }

    Invoke-Test 'evidence report generation' {
        $EvidenceRoot = Join-Path $TempRoot 'report-evidence'
        $Result = Invoke-SOCKSReadiness -ConfigPath (Join-Path $RepoRoot 'socks.config.json') -WorkspacePath $RepoRoot -EvidenceRoot $EvidenceRoot -ReportPrefix 'test-report'
        Assert-True (Test-Path -LiteralPath $Result.reports.json) 'JSON report should exist.'
        Assert-True (Test-Path -LiteralPath $Result.reports.markdown) 'Markdown report should exist.'
        Assert-True (Test-Path -LiteralPath $Result.reports.html) 'HTML report should exist.'
        Assert-True (Test-Path -LiteralPath $Result.reports.summary) 'Summary report should exist.'
    }

    Invoke-Test 'exit-code behavior' {
        Assert-Equal 0 (Get-SOCKSExitCode -GateStatus 'PASS') 'PASS exit code.'
        Assert-Equal 1 (Get-SOCKSExitCode -GateStatus 'FAIL') 'FAIL exit code.'
        Assert-Equal 2 (Get-SOCKSExitCode -GateStatus 'WARN') 'WARN exit code.'
        Assert-Equal 3 (Get-SOCKSExitCode -GateStatus 'ERROR') 'ERROR exit code.'
    }

    Invoke-Test 'secret redaction or exclusion' {
        $Protected = Protect-SOCKSSecret @{ api_key='sk-testshouldberedacted12345'; nested=@{ password='cleartext' }; safe='visible' }
        Assert-Equal '[REDACTED]' $Protected.api_key 'API key should redact.'
        Assert-Equal '[REDACTED]' $Protected.nested.password 'Password should redact.'
        Assert-Equal 'visible' $Protected.safe 'Safe value should remain.'
    }

    Invoke-Test 'SOCKS-002 policy inheritance' {
        $ParentPath = Join-Path $TempRoot 'parent.config.json'
        $ChildPath = Join-Path $TempRoot 'child.config.json'
        Set-Content -LiteralPath $ParentPath -Value (@{
            schema_version='1.0'; socks_version='0.1.0-alpha.1'; workspace_root=$RepoRoot; evidence_root=(Join-Path $TempRoot 'inherit-evidence'); required_runtime='PowerShell';
            policy=@{ promote_optional_failures=$false; disabled_checks=@('git.branch'); check_levels=@{} }
        } | ConvertTo-Json -Depth 8) -Encoding UTF8
        Set-Content -LiteralPath $ChildPath -Value (@{
            extends='parent.config.json'; policy=@{ disabled_checks=@('git.commit'); check_levels=@{ 'workspace.writable'='OPTIONAL' } }
        } | ConvertTo-Json -Depth 8) -Encoding UTF8
        $Config = Import-SOCKSConfiguration -ConfigPath $ChildPath
        Assert-True $Config.config_integrity.inherited 'Inherited config should be recorded.'
        Assert-Equal 'git.commit' $Config.policy.disabled_checks[0] 'Child policy should override arrays.'
        Assert-Equal 'OPTIONAL' $Config.policy.check_levels['workspace.writable'] 'Child policy should merge nested objects.'
    }

    Invoke-Test 'SOCKS-002 schema validation rejects unsupported schema' {
        $Schema = Test-SOCKSConfigurationSchema -Config @{ schema_version='9.9'; socks_version='x'; workspace_root='.'; evidence_root='e'; required_runtime='PowerShell'; policy=@{} }
        Assert-True (-not $Schema.valid) 'Unsupported schema should be invalid.'
    }

    Invoke-Test 'SOCKS-002 promoted optional check blocks gate' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'optional.promoted' -Name 'Promoted optional' -Category 'test' -RequirementLevel 'OPTIONAL' -Body {
                @{ status='FAIL'; summary='promoted bad'; evidence=@{}; remediation='fix promoted' }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ promote_optional_failures=$false; promoted_optional_checks=@('optional.promoted') }
        Assert-Equal 'FAIL' $Gate.status 'Promoted optional failure should fail gate.'
    }

    Invoke-Test 'SOCKS-003 discovery evidence generated safely' {
        $Discovery = Get-SOCKSDiscoveryEvidence -WorkspaceRoot $RepoRoot
        Assert-True ($Discovery.operating_system.version.Length -gt 0) 'OS version should be present.'
        Assert-True ($Discovery.cpu.processor_count -ge 1) 'CPU count should be present.'
        Assert-True ($Discovery.environment_variables.count -ge 1) 'Environment variable names should be counted.'
        $Json = $Discovery | ConvertTo-Json -Depth 12
        Assert-True ($Json -notmatch '(?i)password=|token=|secret=') 'Discovery should not include environment variable values.'
    }

    Invoke-Test 'SOCKS-003 discovery check registered' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Env = Get-SOCKSEnvironment -Config $Config
        $Checks = Get-SOCKSChecks -Config $Config -Environment $Env
        Assert-True (@($Checks | Where-Object id -eq 'discovery.environment').Count -eq 1) 'Discovery check should be registered.'
    }

    Invoke-Test 'SOCKS-004 git evidence generated' {
        $GitEvidence = Get-SOCKSGitEvidence -WorkspaceRoot $RepoRoot
        Assert-True $GitEvidence.git_installed 'Git should be installed for this repository.'
        Assert-True $GitEvidence.inside_work_tree 'Repository should be a work tree.'
        Assert-True ($GitEvidence.commit -match '^[0-9a-f]{40}$') 'Commit should be identified.'
    }

    Invoke-Test 'SOCKS-004 git checks registered' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Env = Get-SOCKSEnvironment -Config $Config
        $Checks = Get-SOCKSChecks -Config $Config -Environment $Env
        foreach($Id in @('git.working_tree_clean','git.remote_status','git.detached_head','git.ignore_validation')){
            Assert-True (@($Checks | Where-Object id -eq $Id).Count -eq 1) "$Id should be registered."
        }
    }

    Invoke-Test 'SOCKS-005 runtime evidence includes PowerShell and Git' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $RuntimeEvidence = Get-SOCKSRuntimeEvidence -Config $Config
        Assert-True (@($RuntimeEvidence | Where-Object { $_.id -eq 'powershell' -and $_.found }).Count -eq 1) 'PowerShell should be found.'
        Assert-True (@($RuntimeEvidence | Where-Object { $_.id -eq 'git' -and $_.found }).Count -eq 1) 'Git should be found.'
    }

    Invoke-Test 'SOCKS-005 missing required runtime fails dependency check' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.dependencies = @{ runtimes = @(@{ id='missing-required'; command='definitely-missing-socks-command'; version_args=@('--version'); requirement='REQUIRED' }) }
        $RuntimeEvidence = Get-SOCKSRuntimeEvidence -Config $Config
        Assert-True (-not $RuntimeEvidence[0].found) 'Missing runtime should not be found.'
    }

    Invoke-Test 'SOCKS-006 missing environment variable detected without value' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.configuration.required_environment = @('SOCKS_TEST_SECRET_TOKEN_SHOULD_NOT_EXIST')
        $Evidence = Get-SOCKSConfigurationSecretEvidence -Config $Config
        Assert-Equal 1 $Evidence.missing_environment_count 'Missing env var should be counted.'
        $Json = $Evidence | ConvertTo-Json -Depth 8
        Assert-True ($Json -notmatch 'SHOULD_NOT_EXIST=.*') 'Env values should not be included.'
    }

    Invoke-Test 'SOCKS-006 placeholder setting detected and secret redacted' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.configuration.required_settings = @('api_key')
        $Config.api_key = 'YOUR_SECRET_VALUE'
        $Evidence = Get-SOCKSConfigurationSecretEvidence -Config $Config
        Assert-Equal 1 $Evidence.placeholder_count 'Placeholder should be detected.'
        Assert-Equal '[REDACTED]' $Evidence.required_settings[0].value 'Secret value should redact.'
    }

    Invoke-Test 'SOCKS-007 connector framework supports known connector types' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.external_connectivity.connectors = @(@{ id='github-readiness'; type='github'; enabled=$false; requirement='OPTIONAL' })
        $Evidence = Get-SOCKSConnectivityEvidence -Config $Config
        Assert-Equal 1 $Evidence.connector_count 'Connector should be discovered.'
        Assert-True $Evidence.connectors[0].supported_type 'GitHub connector type should be supported.'
        Assert-Equal 'SKIPPED' $Evidence.connectors[0].status 'Disabled connector should be skipped.'
    }

    Invoke-Test 'SOCKS-007 unsupported connector type is identified' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.external_connectivity.connectors = @(@{ id='unknown'; type='not-a-real-type'; enabled=$true; requirement='OPTIONAL' })
        $Evidence = Get-SOCKSConnectivityEvidence -Config $Config
        Assert-True (-not $Evidence.connectors[0].supported_type) 'Unsupported connector should be identified.'
    }

    Invoke-Test 'SOCKS-008 plugin manifest validation and ordering' {
        $PluginRoot = Join-Path $TempRoot 'plugins'
        $PluginA = Join-Path $PluginRoot 'a'
        $PluginB = Join-Path $PluginRoot 'b'
        New-Item -ItemType Directory -Path $PluginA,$PluginB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $PluginA 'plugin.json') -Value (@{ id='plugin-a'; name='Plugin A'; version='1.0.0'; socks_min_version='0.1.0'; entry='plugin.ps1'; dependencies=@() } | ConvertTo-Json -Depth 8) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $PluginB 'plugin.json') -Value (@{ id='plugin-b'; name='Plugin B'; version='1.0.0'; socks_min_version='0.1.0'; entry='plugin.ps1'; dependencies=@('plugin-a') } | ConvertTo-Json -Depth 8) -Encoding UTF8
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.plugins.root = $PluginRoot
        $Evidence = Get-SOCKSPluginEvidence -Config $Config -WorkspaceRoot $RepoRoot
        Assert-Equal 2 $Evidence.valid_count 'Two plugin manifests should be valid.'
        Assert-Equal 'plugin-a' $Evidence.dependency_order[0] 'Dependency should come first.'
    }

    Invoke-Test 'SOCKS-008 invalid plugin manifest detected' {
        $PluginRoot = Join-Path $TempRoot 'bad-plugins'
        $BadPlugin = Join-Path $PluginRoot 'bad'
        New-Item -ItemType Directory -Path $BadPlugin -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $BadPlugin 'plugin.json') -Value (@{ id='bad' } | ConvertTo-Json -Depth 8) -Encoding UTF8
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.plugins.root = $PluginRoot
        $Evidence = Get-SOCKSPluginEvidence -Config $Config -WorkspaceRoot $RepoRoot
        Assert-Equal 0 $Evidence.valid_count 'Invalid plugin should not validate.'
    }

    Invoke-Test 'SOCKS-009 report statistics and timeline generated' {
        $EvidenceRoot = Join-Path $TempRoot 'reporting-engine'
        $Result = Invoke-SOCKSReadiness -ConfigPath (Join-Path $RepoRoot 'socks.config.json') -WorkspacePath $RepoRoot -EvidenceRoot $EvidenceRoot -ReportPrefix 'reporting'
        Assert-True ($Result.report.statistics.total -ge 1) 'Statistics should include total checks.'
        Assert-True ($Result.report.timeline.Count -eq $Result.report.statistics.total) 'Timeline should include each check.'
        Assert-True (Test-Path -LiteralPath $Result.reports.html) 'HTML report should be written.'
        Assert-True (Test-Path -LiteralPath $Result.reports.summary) 'Summary report should be written.'
    }

    Invoke-Test 'SOCKS-010 warning threshold promotes warnings' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'optional.warn' -Name 'Optional warn' -Category 'test' -RequirementLevel 'OPTIONAL' -Body {
                @{ status='WARN'; summary='warning'; evidence=@{}; remediation='review' }
            }
        )
        $Gate = Get-SOCKSGateEvaluation -Results $Results -Policy @{ warning_promotion_threshold=1 }
        Assert-Equal 'FAIL' $Gate.status 'Warning threshold should promote warning to fail.'
        Assert-True ($Gate.confidence_score -ge 0) 'Confidence score should be present.'
    }

    Invoke-Test 'SOCKS-010 conditional check filtering' {
        $Config = Import-SOCKSConfiguration -ConfigPath (Join-Path $RepoRoot 'socks.config.json')
        $Config.policy.conditional_checks = @{ 'git.ignore_validation' = $false }
        $Env = Get-SOCKSEnvironment -Config $Config
        $Checks = Get-SOCKSChecks -Config $Config -Environment $Env
        Assert-True (@($Checks | Where-Object id -eq 'git.ignore_validation').Count -eq 0) 'Conditional false check should be filtered.'
    }

    Invoke-Test 'SOCKS-010 dependency graph evidence generated' {
        $Results = @(
            Invoke-SOCKSCheck -Id 'a' -Name 'A' -Category 'test' -RequirementLevel 'REQUIRED' -Body { @{ status='PASS'; summary='a'; evidence=@{} } }
            Invoke-SOCKSCheck -Id 'b' -Name 'B' -Category 'test' -RequirementLevel 'REQUIRED' -Body { @{ status='PASS'; summary='b'; evidence=@{} } }
        )
        $Graph = Get-SOCKSDependencyGraph -Results $Results -Policy @{ check_dependencies=@{ b=@('a') } }
        Assert-Equal 'a' $Graph[1].dependencies[0] 'Dependency graph should record dependency.'
    }
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "SOCKS tests passed=$script:Passed failed=$script:Failed"
if($script:Failed -gt 0){ exit 1 }
exit 0
