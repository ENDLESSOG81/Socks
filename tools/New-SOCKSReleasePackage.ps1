param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '.socks/release')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Version = '1.0.0'
$Commit = (& git -C $RepoRoot rev-parse HEAD 2>$null)
$BuiltAt = (Get-Date).ToUniversalTime().ToString('o')
$PackageRoot = Join-Path $OutputRoot "SOCKS-$Version"
$ZipPath = Join-Path $OutputRoot "SOCKS-$Version.zip"

if(Test-Path -LiteralPath $PackageRoot){ Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

foreach($Path in @('README.md','socks.config.json','socks.ps1','socks','docs','tests','tools')){
    $Source = Join-Path $RepoRoot $Path
    if(Test-Path -LiteralPath $Source){
        Copy-Item -LiteralPath $Source -Destination $PackageRoot -Recurse -Force
    }
}

Get-ChildItem -LiteralPath $PackageRoot -Recurse -Force -Directory |
    Where-Object { $_.Name -in @('.git','.undies','.socks') } |
    Remove-Item -Recurse -Force

$Files = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | ForEach-Object {
    $Relative = $_.FullName.Substring($PackageRoot.Length + 1)
    [ordered]@{
        path = $Relative.Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        bytes = $_.Length
    }
} | Sort-Object path

$Manifest = [ordered]@{
    product = 'SOCKS'
    version = $Version
    source_commit = "$Commit"
    built_at_utc = $BuiltAt
    schema_version = '1.0'
    includes_tests = $true
    excludes_runtime_evidence = $true
    files = @($Files)
}
Set-Content -LiteralPath (Join-Path $PackageRoot 'SOCKS-RELEASE-MANIFEST.json') -Value ($Manifest | ConvertTo-Json -Depth 10) -Encoding UTF8

if(Test-Path -LiteralPath $ZipPath){ Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -Path (Join-Path $PackageRoot '*') -DestinationPath $ZipPath -Force
[ordered]@{
    version = $Version
    source_commit = "$Commit"
    built_at_utc = $BuiltAt
    package = $ZipPath
    sha256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
} | ConvertTo-Json -Depth 6
