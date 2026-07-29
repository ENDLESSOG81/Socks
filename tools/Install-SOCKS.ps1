param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [Parameter(Mandatory=$true)][string]$TargetRoot,
    [switch]$BackupExisting
)

$ErrorActionPreference = 'Stop'
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
if(-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)){ throw "Package not found: $PackagePath" }
if(-not (Test-Path -LiteralPath $TargetRoot -PathType Container)){ throw "Target root not found: $TargetRoot" }

$BackupPath = $null
if($BackupExisting){
    $BackupPath = Join-Path $TargetRoot ('.socks/backups/socks-install-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    foreach($Path in @('README.md','socks.config.json','socks.ps1','socks','docs','tests','tools','SOCKS-RELEASE-MANIFEST.json')){
        $Existing = Join-Path $TargetRoot $Path
        if(Test-Path -LiteralPath $Existing){ Copy-Item -LiteralPath $Existing -Destination $BackupPath -Recurse -Force }
    }
}

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('socks-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $Temp -Force
    foreach($Path in @('README.md','socks.config.json','socks.ps1','socks','docs','tests','tools','SOCKS-RELEASE-MANIFEST.json')){
        $Source = Join-Path $Temp $Path
        if(Test-Path -LiteralPath $Source){
            if($Path -eq 'socks.config.json'){
                $ExistingConfig = Join-Path $TargetRoot 'socks.config.json'
                if(Test-Path -LiteralPath $ExistingConfig){
                    Copy-Item -LiteralPath $Source -Destination (Join-Path $TargetRoot 'socks.config.example.json') -Force
                } else {
                    Copy-Item -LiteralPath $Source -Destination $TargetRoot -Force
                }
            } else {
                Copy-Item -LiteralPath $Source -Destination $TargetRoot -Recurse -Force
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{ installed=$true; target=$TargetRoot; backup=$BackupPath } | ConvertTo-Json -Depth 6
