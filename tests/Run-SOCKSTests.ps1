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
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "SOCKS tests passed=$script:Passed failed=$script:Failed"
if($script:Failed -gt 0){ exit 1 }
exit 0
