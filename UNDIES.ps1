param(
    [Parameter(Position=0)]
    [string]$Command = 'help',
    [string]$SessionId,
    [switch]$DependencyValidated,
    [switch]$Preview,
    [Alias('dry-run')][switch]$DryRun,
    [switch]$Confirm,
    [Alias('project-name')][string]$ProjectName,
    [Alias('project-code')][string]$ProjectCode,
    [switch]$Show,
    [switch]$Validate,
    [string]$ProjectPurpose,
    [string]$ProjectVersion,
    [switch]$Check,
    [switch]$Apply,
    [switch]$Detailed
)
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ActivePath = Join-Path $Root '.undies/active-version.json'
if(-not(Test-Path -LiteralPath $ActivePath)){ throw 'UNDIES active version is not installed. Restore a validated UNDIES release artifact and run initialize.' }
$Active = Get-Content -LiteralPath $ActivePath -Raw | ConvertFrom-Json
$Core = Join-Path $Root ($Active.active_core_path + '\UNDIES.core.ps1')
if(-not(Test-Path -LiteralPath $Core)){ throw "Active UNDIES core not found: $Core" }
$CoreManifestPath = Join-Path $Root ($Active.active_core_path + '\CORE-MANIFEST.json')
if(Test-Path -LiteralPath $CoreManifestPath){
    $CoreManifest = Get-Content -LiteralPath $CoreManifestPath -Raw | ConvertFrom-Json
    foreach($File in @($CoreManifest.files)){
        $ManagedPath = Join-Path $Root $File.path
        if(Test-Path -LiteralPath $ManagedPath){
            $ActualHash = (Get-FileHash -LiteralPath $ManagedPath -Algorithm SHA256).Hash
            if($ActualHash -ne $File.sha256){
                if($Command -eq 'repair'){
                    $BackupPath = Join-Path $Root ('.undies/backups/core/' + $Active.active_core_version + '/UNDIES.core.ps1')
                    if((Test-Path -LiteralPath $BackupPath) -and ((Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash -eq $File.sha256)){
                        Set-ItemProperty -LiteralPath $ManagedPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                        Copy-Item -LiteralPath $BackupPath -Destination $ManagedPath -Force
                        Set-ItemProperty -LiteralPath $ManagedPath -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
                        continue
                    }
                }
                $Result = @{status='RED';issues=@("Core hash mismatch $($File.path)");active_core_version=$Active.active_core_version;reverse_synchronization='DISABLED';source_repository_dependency='NONE'} | ConvertTo-Json -Depth 10
                if($Command -in @('doctor','integrity','core-status','ownership')){ $Result; exit 0 }
                throw "UNDIES immutable core integrity failed: $($File.path)"
            }
        }
    }
}
$Forward = @{ Command = $Command }
if($SessionId){$Forward.SessionId = $SessionId}
if($DependencyValidated){$Forward.DependencyValidated = $true}
if($Preview){$Forward.Preview = $true}
if($DryRun){$Forward.DryRun = $true}
if($Confirm){$Forward.Confirm = $true}
if($ProjectName){$Forward.ProjectName = $ProjectName}
if($ProjectCode){$Forward.ProjectCode = $ProjectCode}
if($Show){$Forward.Show = $true}
if($Validate){$Forward.Validate = $true}
if($ProjectPurpose){$Forward.ProjectPurpose = $ProjectPurpose}
if($ProjectVersion){$Forward.ProjectVersion = $ProjectVersion}
if($Check){$Forward.Check = $true}
if($Apply){$Forward.Apply = $true}
if($Detailed){$Forward.Detailed = $true}
& $Core @Forward
