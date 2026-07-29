param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '.socks/release')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Version = '1.0.0'
$PackageRoot = Join-Path $OutputRoot "SOCKS-$Version"
$ZipPath = Join-Path $OutputRoot "SOCKS-$Version.zip"

if(Test-Path -LiteralPath $PackageRoot){ Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

foreach($Path in @('README.md','socks.config.json','socks.ps1','socks','docs','tests')){
    $Source = Join-Path $RepoRoot $Path
    if(Test-Path -LiteralPath $Source){
        Copy-Item -LiteralPath $Source -Destination $PackageRoot -Recurse -Force
    }
}

if(Test-Path -LiteralPath $ZipPath){ Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -Path (Join-Path $PackageRoot '*') -DestinationPath $ZipPath -Force
[ordered]@{
    version = $Version
    package = $ZipPath
    sha256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
} | ConvertTo-Json -Depth 6
