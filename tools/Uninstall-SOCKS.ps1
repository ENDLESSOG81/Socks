param(
    [Parameter(Mandatory=$true)][string]$TargetRoot,
    [switch]$RemoveConfig
)

$ErrorActionPreference = 'Stop'
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
if(-not (Test-Path -LiteralPath $TargetRoot -PathType Container)){ throw "Target root not found: $TargetRoot" }

$Removed = @()
foreach($Path in @('socks.ps1','socks','docs','tests','tools','SOCKS-RELEASE-MANIFEST.json')){
    $Target = Join-Path $TargetRoot $Path
    if(Test-Path -LiteralPath $Target){
        Remove-Item -LiteralPath $Target -Recurse -Force
        $Removed += $Path
    }
}
if($RemoveConfig){
    $Config = Join-Path $TargetRoot 'socks.config.json'
    if(Test-Path -LiteralPath $Config){ Remove-Item -LiteralPath $Config -Force; $Removed += 'socks.config.json' }
}

[ordered]@{ uninstalled=$true; target=$TargetRoot; removed=$Removed; config_removed=[bool]$RemoveConfig } | ConvertTo-Json -Depth 6
