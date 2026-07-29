param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'socks.config.json'),
    [string]$WorkspacePath,
    [string]$EvidenceRoot,
    [string]$ReportPrefix = 'socks-readiness',
    [switch]$JsonOnly
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'socks/SOCKS.psm1') -Force
    $Result = Invoke-SOCKSReadiness -ConfigPath $ConfigPath -WorkspacePath $WorkspacePath -EvidenceRoot $EvidenceRoot -ReportPrefix $ReportPrefix

    if($JsonOnly){
        $Result | ConvertTo-Json -Depth 20
    } else {
        Write-Host "SOCKS gate result: $($Result.gate.status)"
        Write-Host "JSON report: $($Result.reports.json)"
        Write-Host "Markdown report: $($Result.reports.markdown)"
        if($Result.reports.html){ Write-Host "HTML report: $($Result.reports.html)" }
        if($Result.reports.summary){ Write-Host "Summary report: $($Result.reports.summary)" }
    }

    exit (Get-SOCKSExitCode -GateStatus $Result.gate.status)
} catch {
    $Message = Protect-SOCKSSecret $_.Exception.Message
    [Console]::Error.WriteLine("SOCKS system/configuration error: $Message")
    exit 3
}
