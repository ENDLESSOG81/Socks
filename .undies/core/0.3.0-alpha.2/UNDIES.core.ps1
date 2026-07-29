param(
    [Parameter(Position=0)]
    [ValidateSet('initialize','doctor','status','session-start','session-close','blue-report','resume','adopt','configure','version','upgrade','integrity','repair','rollback','disable','remove','import','ownership','core-status','help')]
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
$script:UndiesVersion = '0.3.0-alpha.2'
$script:ConfigurationVersion = '0.2.0'
$script:SourceRepositoryPath = 'D:\GITHUB\undies'
$script:SourceRepositoryUrl = 'https://github.com/ENDLESSOG81/UNDIES.git'

function Get-UndiesUtcTime { [DateTime]::UtcNow.ToString('o') }
function Get-UndiesCentralTime { try { $tz=[TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time'); [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow,$tz).ToString('o') } catch { Get-UndiesUtcTime } }
function ConvertTo-UndiesCanonicalStatus([string]$Status){ if($Status -eq 'WAITING_FOR_EXTERNAL_DEPENDENCY'){'BLUE'}else{$Status} }
function Protect-UndiesText([string]$Text){ if($null -eq $Text){return $null}; [Regex]::Replace($Text,'(?i)(Bearer\s+\S+|token\s*[:=]\s*\S+|password\s*[:=]\s*\S+|secret\s*[:=]\s*\S+)','[REDACTED]') }
function Save-Json($Path,$Data){ $dir=Split-Path -Parent $Path; if(-not(Test-Path $dir)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}; $json=$Data|ConvertTo-Json -Depth 50; if(Test-Path -LiteralPath $Path){ $existing=Get-Content -LiteralPath $Path -Raw; if($existing.TrimEnd() -eq $json.TrimEnd()){ return } }; $tmp=Join-Path $dir ('.tmp-'+[guid]::NewGuid().ToString('N')+'.json'); $json|Set-Content $tmp -Encoding UTF8; Move-Item $tmp $Path -Force }
function Read-Json($Path){ Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Get-Root { Split-Path -Parent $MyInvocation.ScriptName }
function Resolve-InsideRoot([string]$Root,[string]$RelativePath){
    if($RelativePath -match '(^|[\\/])\.\.([\\/]|$)'){ throw "Path traversal rejected: $RelativePath" }
    $rootFull=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path).TrimEnd('\')
    $dest=[IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    if(-not($dest.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase) -or $dest.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase))){ throw "Path escapes project root: $RelativePath" }
    $probe=$dest
    while($probe -and $probe.Length -ge $rootFull.Length){
        if(Test-Path -LiteralPath $probe){
            $item=Get-Item -LiteralPath $probe -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw "Reparse point rejected inside UNDIES path: $probe" }
        }
        if($probe.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)){break}
        $probe=Split-Path -Parent $probe
    }
    $dest
}
function Assert-SafeRoot($Root){
    $p=(Resolve-Path -LiteralPath $Root).Path
    if($p -match '(?i)\\OneDrive( - [^\\]+)?\\'){throw "Unsafe OneDrive workspace: $p"}
    if($p.Equals($script:SourceRepositoryPath,[StringComparison]::OrdinalIgnoreCase) -and -not $env:UNDIES_ALLOW_SOURCE_IMPORT_TEST){throw "Refusing to install into authoritative UNDIES source repository: $p"}
    $t=Join-Path $p '.undies-write.tmp'; 'ok'|Set-Content $t -NoNewline; Remove-Item $t -Force; $true
}
function Get-RelativePath($Root,$Path){ [IO.Path]::GetFullPath($Path).Substring([IO.Path]::GetFullPath($Root).TrimEnd('\').Length).TrimStart('\') }
function Get-Hash($Path){ if(Test-Path -LiteralPath $Path -PathType Leaf){ (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { $null } }
function New-Blue($Reason,$RequiredItem,$Checkpoint){ [pscustomobject]@{status='BLUE';canonical_status='BLUE';reason=$Reason;required_item=$RequiredItem;dependency_type='OPERATOR_INPUT';manual_action='Resolve the collision or provide authorization.';powershell_action='Review the reported path and rerun after correction.';validation_command='.\UNDIES.ps1 ownership -validate';success_condition='Ownership validation returns GREEN';failure_condition='Remain BLUE';resume_module='UND-022';resume_checkpoint=$Checkpoint;blocks_next_module=$true;continuation_decision='PAUSE'} }
function Get-ReleaseManifest($Root){
    $p=Join-Path $Root 'UNDIES-RELEASE-MANIFEST.json'
    if(Test-Path -LiteralPath $p){ return Read-Json $p }
    [pscustomobject]@{product_name='UNDIES';version=$script:UndiesVersion;artifact_filename='UNDIES.ps1';sha256_checksum=(Get-Hash (Join-Path $Root 'UNDIES.ps1'));release_status='local-portable'}
}
function New-LauncherContent($Version){
@"
param(
    [Parameter(Position=0)]
    [string]`$Command = 'help',
    [string]`$SessionId,
    [switch]`$DependencyValidated,
    [switch]`$Preview,
    [Alias('dry-run')][switch]`$DryRun,
    [switch]`$Confirm,
    [Alias('project-name')][string]`$ProjectName,
    [Alias('project-code')][string]`$ProjectCode,
    [switch]`$Show,
    [switch]`$Validate,
    [string]`$ProjectPurpose,
    [string]`$ProjectVersion,
    [switch]`$Check,
    [switch]`$Apply,
    [switch]`$Detailed
)
`$Root = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$ActivePath = Join-Path `$Root '.undies/active-version.json'
if(-not(Test-Path -LiteralPath `$ActivePath)){ throw 'UNDIES active version is not installed. Restore a validated UNDIES release artifact and run initialize.' }
`$Active = Get-Content -LiteralPath `$ActivePath -Raw | ConvertFrom-Json
`$Core = Join-Path `$Root (`$Active.active_core_path + '\UNDIES.core.ps1')
if(-not(Test-Path -LiteralPath `$Core)){ throw "Active UNDIES core not found: `$Core" }
`$CoreManifestPath = Join-Path `$Root (`$Active.active_core_path + '\CORE-MANIFEST.json')
if(Test-Path -LiteralPath `$CoreManifestPath){
    `$CoreManifest = Get-Content -LiteralPath `$CoreManifestPath -Raw | ConvertFrom-Json
    foreach(`$File in @(`$CoreManifest.files)){
        `$ManagedPath = Join-Path `$Root `$File.path
        if(Test-Path -LiteralPath `$ManagedPath){
            `$ActualHash = (Get-FileHash -LiteralPath `$ManagedPath -Algorithm SHA256).Hash
            if(`$ActualHash -ne `$File.sha256){
                if(`$Command -eq 'repair'){
                    `$BackupPath = Join-Path `$Root ('.undies/backups/core/' + `$Active.active_core_version + '/UNDIES.core.ps1')
                    if((Test-Path -LiteralPath `$BackupPath) -and ((Get-FileHash -LiteralPath `$BackupPath -Algorithm SHA256).Hash -eq `$File.sha256)){
                        Set-ItemProperty -LiteralPath `$ManagedPath -Name IsReadOnly -Value `$false -ErrorAction SilentlyContinue
                        Copy-Item -LiteralPath `$BackupPath -Destination `$ManagedPath -Force
                        Set-ItemProperty -LiteralPath `$ManagedPath -Name IsReadOnly -Value `$true -ErrorAction SilentlyContinue
                        continue
                    }
                }
                `$Result = @{status='RED';issues=@("Core hash mismatch `$(`$File.path)");active_core_version=`$Active.active_core_version;reverse_synchronization='DISABLED';source_repository_dependency='NONE'} | ConvertTo-Json -Depth 10
                if(`$Command -in @('doctor','integrity','core-status','ownership')){ `$Result; exit 0 }
                throw "UNDIES immutable core integrity failed: `$(`$File.path)"
            }
        }
    }
}
`$Forward = @{ Command = `$Command }
if(`$SessionId){`$Forward.SessionId = `$SessionId}
if(`$DependencyValidated){`$Forward.DependencyValidated = `$true}
if(`$Preview){`$Forward.Preview = `$true}
if(`$DryRun){`$Forward.DryRun = `$true}
if(`$Confirm){`$Forward.Confirm = `$true}
if(`$ProjectName){`$Forward.ProjectName = `$ProjectName}
if(`$ProjectCode){`$Forward.ProjectCode = `$ProjectCode}
if(`$Show){`$Forward.Show = `$true}
if(`$Validate){`$Forward.Validate = `$true}
if(`$ProjectPurpose){`$Forward.ProjectPurpose = `$ProjectPurpose}
if(`$ProjectVersion){`$Forward.ProjectVersion = `$ProjectVersion}
if(`$Check){`$Forward.Check = `$true}
if(`$Apply){`$Forward.Apply = `$true}
if(`$Detailed){`$Forward.Detailed = `$true}
& `$Core @Forward
"@
}
function Test-LauncherChecksum($Root){
    $scriptPath=Join-Path $Root 'UNDIES.ps1'; $sumPath=Join-Path $Root 'UNDIES.ps1.sha256'
    if(Test-Path -LiteralPath $sumPath){ $expected=(Get-Content -LiteralPath $sumPath -Raw).Trim(); $actual=Get-Hash $scriptPath; if($expected -and $actual -ne $expected){ throw 'UNDIES.ps1 checksum does not match UNDIES.ps1.sha256' } }
}
function New-CoreManifest($Root,$Version){
    $coreDir=Resolve-InsideRoot $Root ".undies/core/$Version"
    $coreFile=Join-Path $coreDir 'UNDIES.core.ps1'
    $coreHash=Get-Hash $coreFile
    [ordered]@{version=$Version;created_utc=Get-UndiesUtcTime;files=@([ordered]@{path=".undies/core/$Version/UNDIES.core.ps1";sha256=$coreHash;size=(Get-Item -LiteralPath $coreFile).Length;ownership_class='CORE_IMMUTABLE'});source_artifact='UNDIES.ps1';reverse_synchronization='DISABLED'}
}
function Add-OwnershipRecord($Root,$Records,$Rel,$Class,$Mutable,$Upgradeable,$Removable,$UserModification,$SourceArtifact){
    $path=Resolve-InsideRoot $Root $Rel
    if(Test-Path -LiteralPath $path -PathType Leaf){ $item=Get-Item -LiteralPath $path; $hash=Get-Hash $path; $size=$item.Length } else { $hash=$null; $size=0 }
    $Records.Add([ordered]@{path=$Rel;ownership_class=$Class;sha256=$hash;size=$size;mutable=$Mutable;may_be_upgraded=$Upgradeable;may_be_removed=$Removable;user_modification_permitted=$UserModification;original_source_artifact=$SourceArtifact}) | Out-Null
}
function Save-OwnershipManifest($Root,$Version){
    $manifest=Get-ReleaseManifest $Root
    $records=New-Object System.Collections.ArrayList
    Add-OwnershipRecord $Root $records 'UNDIES.ps1' 'CORE_LAUNCHER' $false $true $false $false 'release artifact'
    Add-OwnershipRecord $Root $records 'UNDIES.ps1.sha256' 'CORE_LAUNCHER' $false $true $false $false 'release artifact'
    Add-OwnershipRecord $Root $records 'UNDIES-RELEASE-MANIFEST.json' 'CORE_LAUNCHER' $false $true $false $false 'release artifact'
    Add-OwnershipRecord $Root $records '.undies/active-version.json' 'CORE_IMMUTABLE' $false $true $false $false 'install'
    Add-OwnershipRecord $Root $records '.undies/ownership-manifest.json' 'CORE_IMMUTABLE' $false $true $false $false 'install'
    Add-OwnershipRecord $Root $records ".undies/core/$Version/UNDIES.core.ps1" 'CORE_IMMUTABLE' $false $true $true $false 'release artifact'
    Add-OwnershipRecord $Root $records ".undies/core/$Version/CORE-MANIFEST.json" 'CORE_IMMUTABLE' $false $true $true $false 'install'
    Add-OwnershipRecord $Root $records ".undies/core/$Version/CORE.sha256" 'CORE_IMMUTABLE' $false $true $true $false 'install'
    Add-OwnershipRecord $Root $records '.undies/project/project.json' 'PROJECT_CONFIGURATION' $true $false $false $true 'project'
    Add-OwnershipRecord $Root $records '.undies/project/policies.json' 'PROJECT_CONFIGURATION' $true $false $false $true 'project'
    $data=[ordered]@{installation_id=('UNDIES-'+[guid]::NewGuid().ToString('N'));project_root=(Resolve-Path -LiteralPath $Root).Path;undies_version=$Version;installation_timestamp_utc=Get-UndiesUtcTime;active_core_version=$Version;managed_files=$records;release_checksum=$manifest.sha256_checksum;reverse_synchronization='DISABLED'}
    Save-Json (Resolve-InsideRoot $Root '.undies/ownership-manifest.json') $data
    $data
}
function Get-OwnershipManifest($Root){ $p=Join-Path $Root '.undies/ownership-manifest.json'; if(Test-Path -LiteralPath $p){Read-Json $p}else{$null} }
function Test-ExpectedCollision($Root,$Rel,$ExpectedHash,$ExistingOwnership){
    $path=Resolve-InsideRoot $Root $Rel
    if(-not(Test-Path -LiteralPath $path)){ return $null }
    $hash=Get-Hash $path
    if($ExpectedHash -and $hash -eq $ExpectedHash){ return $null }
    $owned=$false
    if($ExistingOwnership){ $owned=@($ExistingOwnership.managed_files|Where-Object path -eq $Rel).Count -gt 0 }
    if(-not $owned){ return New-Blue "Unknown file collision at $Rel" $Rel 'collision-resolution' }
    return New-Blue "Managed file has been modified at $Rel" $Rel 'managed-file-approval'
}
function Install-ImmutableCore($Root,[string]$Mode='initialize'){
    Assert-SafeRoot $Root|Out-Null
    Test-LauncherChecksum $Root
    $version=$script:UndiesVersion
    $ownership=Get-OwnershipManifest $Root
    foreach($d in @('.undies','.undies/core','.undies/project','.undies/project/modules','.undies/extensions','.undies/runtime','.undies/sessions','.undies/evidence','.undies/reports','.undies/recovery','.undies/adoption','.undies/backups')){ New-Item -ItemType Directory -Force -Path (Resolve-InsideRoot $Root $d)|Out-Null }
    $coreDir=Resolve-InsideRoot $Root ".undies/core/$version"
    New-Item -ItemType Directory -Force -Path $coreDir|Out-Null
    $launcherPath=Join-Path $Root 'UNDIES.ps1'
    $sourceScriptPath=$PSCommandPath
    if(-not(Test-Path -LiteralPath $sourceScriptPath)){ $sourceScriptPath=$launcherPath }
    $coreTemp=Join-Path $env:TEMP ('undies-core-'+[guid]::NewGuid().ToString('N')+'.ps1')
    Copy-Item -LiteralPath $sourceScriptPath -Destination $coreTemp -Force
    $expectedCoreHash=Get-Hash $coreTemp
    $collision=Test-ExpectedCollision $Root ".undies/core/$version/UNDIES.core.ps1" $expectedCoreHash $ownership
    if($collision){ Remove-Item $coreTemp -Force; return $collision }
    Move-Item -LiteralPath $coreTemp -Destination (Join-Path $coreDir 'UNDIES.core.ps1') -Force
    try { Set-ItemProperty -LiteralPath (Join-Path $coreDir 'UNDIES.core.ps1') -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue } catch {}
    $backupDir=Resolve-InsideRoot $Root ".undies/backups/core/$version"
    New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
    Copy-Item -LiteralPath (Join-Path $coreDir 'UNDIES.core.ps1') -Destination (Join-Path $backupDir 'UNDIES.core.ps1') -Force
    $coreManifest=New-CoreManifest $Root $version
    Save-Json (Join-Path $coreDir 'CORE-MANIFEST.json') $coreManifest
    $coreManifest.files[0].sha256 | Set-Content -LiteralPath (Join-Path $coreDir 'CORE.sha256') -Encoding ASCII
    $active=[ordered]@{active_core_version=$version;active_core_path=".undies/core/$version";updated_utc=Get-UndiesUtcTime;switch_mode='atomic';reverse_synchronization='DISABLED'}
    Save-Json (Resolve-InsideRoot $Root '.undies/active-version.json') $active
    $launcher=New-LauncherContent $version
    $launcherTmp=Join-Path $Root ('.undies/tmp-launcher-'+[guid]::NewGuid().ToString('N')+'.ps1')
    $launcher|Set-Content -LiteralPath $launcherTmp -Encoding UTF8
    Move-Item -LiteralPath $launcherTmp -Destination $launcherPath -Force
    (Get-Hash $launcherPath) | Set-Content -LiteralPath (Join-Path $Root 'UNDIES.ps1.sha256') -Encoding ASCII
    $projectPath=Resolve-InsideRoot $Root '.undies/project/project.json'
    if(-not(Test-Path -LiteralPath $projectPath)){
        $project=[ordered]@{project_name=if($ProjectName){$ProjectName}else{Split-Path -Leaf $Root};project_code=if($ProjectCode){$ProjectCode}else{'UND'};version=$version;workspace_root=(Resolve-Path -LiteralPath $Root).Path;configuration_version=$script:ConfigurationVersion;created_date=Get-UndiesUtcTime;updated_date=Get-UndiesUtcTime;extensions_enabled=$false}
        Save-Json $projectPath $project
    }
    $policyPath=Resolve-InsideRoot $Root '.undies/project/policies.json'
    if(-not(Test-Path -LiteralPath $policyPath)){ Save-Json $policyPath ([ordered]@{reverse_synchronization='DISABLED';git_tracking='manual';external_connections='deny-by-default';extensions_enabled=$false}) }
    Save-OwnershipManifest $Root $version|Out-Null
    [pscustomobject]@{status='GREEN';mode=$Mode;version=$version;active_core_version=$version;active_core_path=".undies/core/$version";reverse_synchronization='DISABLED';source_repository_dependency='NONE'}
}
function Assert-PortableInstalled($Root,[string]$Operation){
    Assert-SafeRoot $Root|Out-Null
    Test-LauncherChecksum $Root
    $health=Test-ImmutableCore $Root
    if($health.status -ne 'GREEN'){ throw "UNDIES installation is not healthy for $Operation. Run doctor, integrity, repair -preview, then repair -apply if authorized." }
    foreach($d in @('.undies/runtime','.undies/sessions','.undies/evidence','.undies/reports','.undies/recovery')){ New-Item -ItemType Directory -Force -Path (Resolve-InsideRoot $Root $d)|Out-Null }
    $health
}
function Test-ImmutableCore($Root){
    $issues=@()
    try { Assert-SafeRoot $Root|Out-Null } catch { $issues += $_.Exception.Message }
    $activePath=Join-Path $Root '.undies/active-version.json'
    $ownPath=Join-Path $Root '.undies/ownership-manifest.json'
    if(-not(Test-Path -LiteralPath $activePath)){$issues+='Missing active-version.json'}
    if(-not(Test-Path -LiteralPath $ownPath)){$issues+='Missing ownership-manifest.json'}
    if(Test-Path -LiteralPath $activePath){
        $active=Read-Json $activePath
        $coreDir=Resolve-InsideRoot $Root $active.active_core_path
        foreach($rel in @('UNDIES.core.ps1','CORE-MANIFEST.json','CORE.sha256')){ if(-not(Test-Path -LiteralPath (Join-Path $coreDir $rel))){$issues+="Missing core file $rel"} }
        $cmPath=Join-Path $coreDir 'CORE-MANIFEST.json'
        if(Test-Path $cmPath){
            $cm=Read-Json $cmPath
            foreach($f in @($cm.files)){ $p=Resolve-InsideRoot $Root $f.path; if((Get-Hash $p) -ne $f.sha256){$issues+="Core hash mismatch $($f.path)"} }
        }
        foreach($bad in @('.undies/core/'+$active.active_core_version+'/project.json','.undies/core/'+$active.active_core_version+'/runtime.json')){ if(Test-Path (Join-Path $Root $bad)){$issues+="Project or runtime data inside core: $bad"} }
    }
    if(Test-Path $ownPath){
        $om=Read-Json $ownPath
        foreach($r in @($om.managed_files)){ if($r.path -match '^\.\.'){ $issues+="Invalid ownership path $($r.path)" } }
    }
    [pscustomobject]@{status=if($issues.Count){'RED'}else{'GREEN'};issues=$issues;active_core_version=if(Test-Path $activePath){(Read-Json $activePath).active_core_version}else{$null};reverse_synchronization='DISABLED';source_repository_dependency='NONE'}
}
function Invoke-CoreStatus($Root){ Test-ImmutableCore $Root }
function Invoke-Ownership($Root){ if($Validate){ Test-ImmutableCore $Root } else { $m=Get-OwnershipManifest $Root; if($m){$m}else{[pscustomobject]@{status='BLUE';reason='No ownership manifest exists';resume_checkpoint='initialize'}} } }
function Get-PortableInventory($Root){ Get-ChildItem -LiteralPath $Root -Force -Recurse -File | Where-Object { $_.FullName -notmatch '\\(.undies|.git)\\' -and $_.Name -notin @('UNDIES.ps1','UNDIES.ps1.sha256','UNDIES-RELEASE-MANIFEST.json') } | ForEach-Object { [pscustomobject]@{ path=Get-RelativePath $Root $_.FullName; length=$_.Length; sha256=(Get-Hash $_.FullName) } } }
function Get-PortableGitInfo($Root){ if(-not(Test-Path (Join-Path $Root '.git'))){ return $null }; [ordered]@{ root=(& git -C $Root rev-parse --show-toplevel 2>$null); branch=(& git -C $Root branch --show-current 2>$null); head=(& git -C $Root rev-parse HEAD 2>$null); remotes=@(& git -C $Root remote -v 2>$null); staged=@(& git -C $Root diff --cached --name-only 2>$null); unstaged=@(& git -C $Root diff --name-only 2>$null); untracked=@(& git -C $Root ls-files --others --exclude-standard 2>$null); operation=if(Test-Path (Join-Path $Root '.git/MERGE_HEAD')){'MERGE'}elseif(Test-Path (Join-Path $Root '.git/rebase-merge')){'REBASE'}elseif(Test-Path (Join-Path $Root '.git/CHERRY_PICK_HEAD')){'CHERRY_PICK'}else{'NONE'}; nested_repositories=@(Get-ChildItem -LiteralPath $Root -Force -Recurse -Directory -Filter '.git' | Where-Object { $_.FullName -ne (Join-Path $Root '.git') } | ForEach-Object { Get-RelativePath $Root $_.FullName }) } }
function Invoke-PortableAdoption($Root){ $inventory=@(Get-PortableInventory $Root); $proposal=[ordered]@{mode=if($DryRun){'DRY_RUN'}elseif($Preview){'PREVIEW'}elseif($Confirm){'APPLY'}else{'PREVIEW'};project_name=if($ProjectName){$ProjectName}else{Split-Path -Leaf $Root};project_code=if($ProjectCode){$ProjectCode}else{'UND'};existing_file_count=$inventory.Count;conflicts=@();files_to_create=@('UNDIES.ps1','UNDIES.ps1.sha256','UNDIES-RELEASE-MANIFEST.json','.undies/active-version.json','.undies/ownership-manifest.json','.undies/core/'+$script:UndiesVersion,' .undies/project/project.json');untouched_files=@($inventory.path);git=(Get-PortableGitInfo $Root);recommended_gitignore=@('.undies/runtime/','.undies/sessions/','.undies/evidence/','.undies/reports/','.undies/recovery/','.undies/adoption/','.undies/backups/','*.log','.env','.env.*');proposed_git_actions=@('No automatic git add, commit, push, pull, merge, reset, checkout, restore, clean, stash, or branch changes');source='Validated UNDIES release artifact';destination=(Resolve-Path -LiteralPath $Root).Path;reverse_synchronization='DISABLED'}
    if($DryRun -or $Preview -or -not $Confirm){ return $proposal }
    $result=Install-ImmutableCore $Root 'adopt'
    if($result.status -eq 'GREEN'){ New-Item -ItemType Directory -Force -Path (Resolve-InsideRoot $Root '.undies/adoption')|Out-Null; Save-Json (Resolve-InsideRoot $Root '.undies/adoption/baseline.json') ([ordered]@{created_utc=Get-UndiesUtcTime;inventory=$inventory;git=$proposal.git}) }
    $result
}
function Invoke-PortableConfigure($Root){
    Install-ImmutableCore $Root 'configure'|Out-Null
    $manifest=Resolve-InsideRoot $Root '.undies/project/project.json'
    if($Show){ return Read-Json $manifest }
    if($Validate){ $m=Read-Json $manifest; if($m.project_code -notmatch '^[A-Z][A-Z0-9]{1,9}$'){throw 'Invalid project code'}; return [pscustomobject]@{status='GREEN';validated=$true;project_code=$m.project_code} }
    if(-not $Confirm){ return [pscustomobject]@{status='PREVIEW';required=@('project-name','project-code');message='Use -confirm to save configuration.'} }
    if([string]::IsNullOrWhiteSpace($ProjectName)){ throw 'Project name is required.' }
    if([string]::IsNullOrWhiteSpace($ProjectCode) -or $ProjectCode -notmatch '^[A-Z][A-Z0-9]{1,9}$'){ throw 'Invalid project code. Use 2-10 uppercase letters or digits, starting with a letter.' }
    $m=Read-Json $manifest
    foreach($name in @('project_name','project_code','project_purpose','project_version','updated_date')){
        if(-not ($m.PSObject.Properties.Name -contains $name)){ $m | Add-Member -NotePropertyName $name -NotePropertyValue $null }
    }
    $m.project_name=$ProjectName; $m.project_code=$ProjectCode; $m.project_purpose=$ProjectPurpose; if($ProjectVersion){$m.project_version=$ProjectVersion}; $m.updated_date=Get-UndiesUtcTime; Save-Json $manifest $m; Read-Json $manifest
}
function Invoke-PortableVersion($Root){ $project=Join-Path $Root '.undies/project/project.json'; [pscustomobject]@{portable_version=$script:UndiesVersion;installed_version=if(Test-Path $project){(Read-Json $project).version}else{'NONE'};schema_version=$script:ConfigurationVersion} }
function Compare-VersionText([string]$A,[string]$B){ $pa=($A -replace '-.*$','').Split('.')|ForEach-Object{[int]$_}; $pb=($B -replace '-.*$','').Split('.')|ForEach-Object{[int]$_}; for($i=0;$i -lt 3;$i++){ if($pa[$i] -lt $pb[$i]){return -1}; if($pa[$i] -gt $pb[$i]){return 1} }; return 0 }
function Invoke-PortableUpgrade($Root){
    $before=if(Test-Path (Join-Path $Root '.undies/active-version.json')){(Read-Json (Join-Path $Root '.undies/active-version.json')).active_core_version}else{'NONE'}
    if($Check -or $Preview -or -not $Apply){ return [pscustomobject]@{status='GREEN';operation='SIDE_BY_SIDE_UPGRADE';from=$before;to=$script:UndiesVersion;overwrite_active_core=$false;reverse_synchronization='DISABLED'} }
    $previous=$before
    $result=Install-ImmutableCore $Root 'upgrade'
    if($result.status -ne 'GREEN'){ if($previous -ne 'NONE'){ Save-Json (Resolve-InsideRoot $Root '.undies/active-version.json') ([ordered]@{active_core_version=$previous;active_core_path=".undies/core/$previous";updated_utc=Get-UndiesUtcTime;switch_mode='rollback'}) }; return $result }
    Save-Json (Resolve-InsideRoot $Root '.undies/reports/upgrade-report.json') ([ordered]@{status='GREEN';from=$previous;to=$script:UndiesVersion;previous_core_preserved=($previous -ne 'NONE');reverse_synchronization='DISABLED'})
    [pscustomobject]@{status='GREEN';operation='SIDE_BY_SIDE_UPGRADE';from=$previous;to=$script:UndiesVersion;previous_core_preserved=($previous -ne 'NONE')}
}
function New-PortableSession($Root){ Assert-PortableInstalled $Root 'session-start'|Out-Null; $dir=Resolve-InsideRoot $Root '.undies/sessions'; $project=Read-Json (Resolve-InsideRoot $Root '.undies/project/project.json'); $code=if($project.project_code){$project.project_code}else{'UND'}; $id='UND-'+$code+'-'+(Get-Date -Format yyyyMMdd)+'-'+('{0:000}' -f ((@(Get-ChildItem $dir -Filter '*.json' -ErrorAction SilentlyContinue).Count)+1)); $s=[ordered]@{session_id=$id;project_name=$project.project_name;project_code=$code;project_version=$project.version;workspace=(Resolve-Path $Root).Path;start_time_local=Get-UndiesCentralTime;start_time_utc=Get-UndiesUtcTime;end_time_local=$null;end_time_utc=$null;current_module=$null;completed_modules=@();pending_modules=@();failed_module=$null;warnings=@();resume_point='session-started';final_status='IN_PROGRESS';status='IN_PROGRESS'}; Save-Json (Join-Path $dir "$id.json") $s; $s }
function Close-PortableSession($Root,$SessionId){ Assert-PortableInstalled $Root 'session-close'|Out-Null; $dir=Resolve-InsideRoot $Root '.undies/sessions'; if(-not $SessionId){$active=Get-ChildItem $dir -Filter '*.json'|ForEach-Object{Read-Json $_.FullName}|Where-Object status -eq 'IN_PROGRESS'|Select-Object -First 1; if($active){$SessionId=$active.session_id}else{throw 'No active session'}}; $p=Join-Path $dir "$SessionId.json"; $s=Read-Json $p; $s.end_time_local=Get-UndiesCentralTime; $s.end_time_utc=Get-UndiesUtcTime; $s.status='COMPLETE'; $s.final_status='COMPLETE'; Save-Json $p $s; Read-Json $p }
function New-BlueReport($Root){ Assert-PortableInstalled $Root 'blue-report'|Out-Null; $text=@('========================================================','BLUE GATE - MANUAL ACTION REQUIRED','========================================================','MODULE:','UND-PORTABLE Portable bootstrap','STATUS:','BLUE','REASON:','Progress is paused for an exact operator input or collision.','REQUIRED ITEM:','Operator input or file collision decision','DEPENDENCY TYPE:','OPERATOR_INPUT','EXPECTED FORMAT:','Non-secret confirmation value','SENSITIVE:','NO','SOURCE OR RESPONSIBLE PARTY:','Human operator','MANUAL ACTION:','Provide the required input or resolve collision.','POWERSHELL ACTION:','$value = Read-Host "Required input"','VALIDATION COMMAND:','.\UNDIES.ps1 ownership -validate','SUCCESS CONDITION:','Validation returns GREEN','FAILURE CONDITION:','Remain BLUE','RESUME MODULE:','UND-PORTABLE','RESUME CHECKPOINT:','portable-blue-checkpoint','SECURITY NOTICE:','NONE','========================================================') -join [Environment]::NewLine; $path=Resolve-InsideRoot $Root '.undies/reports/portable-blue-report.md'; New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)|Out-Null; $text|Set-Content $path -Encoding UTF8; $text }
function Invoke-PortableDisable($Root){ Install-ImmutableCore $Root 'disable'|Out-Null; $state=[ordered]@{disabled=$true;disabled_utc=Get-UndiesUtcTime;reversible=$true}; Save-Json (Resolve-InsideRoot $Root '.undies/project/disabled.json') $state; $state }
function Invoke-PortableRollback($Root){ Install-ImmutableCore $Root 'rollback'|Out-Null; $active=Read-Json (Resolve-InsideRoot $Root '.undies/active-version.json'); $plan=[ordered]@{status='GREEN';operation='ROLLBACK';active_core_version=$active.active_core_version;preview=(!$Apply);actions=@('Switch active-version pointer to validated previous core when available','Preserve host files')}; if($Preview -or -not $Apply){return $plan}; Save-Json (Resolve-InsideRoot $Root '.undies/reports/rollback-report.json') ([ordered]@{status='GREEN';active_core_version=$active.active_core_version;applied_utc=Get-UndiesUtcTime}); return [pscustomobject]@{status='GREEN';operation='ROLLBACK';validated=$true} }
function Invoke-PortableRemove($Root){ $om=Get-OwnershipManifest $Root; $managed=if($om){@($om.managed_files|Where-Object may_be_removed -eq $true|Select-Object -ExpandProperty path)}else{@()}; $plan=[ordered]@{status='GREEN';operation='REMOVE';preview=(!$Apply);managed_files=$managed;preserve=@('host files','unknown files','.git','reports','evidence')}; if($Preview -or -not $Apply){return $plan}; foreach($rel in $managed){$p=Resolve-InsideRoot $Root $rel; if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}}; Save-Json (Resolve-InsideRoot $Root '.undies/reports/removal-manifest.json') ([ordered]@{removed=$managed;preserved=$plan.preserve;removed_utc=Get-UndiesUtcTime}); [pscustomobject]@{status='GREEN';operation='REMOVE';removed=$managed;preserved=$plan.preserve} }
function Invoke-PortableRepair($Root){ $integrity=Test-ImmutableCore $Root; $plan=[ordered]@{status=if($integrity.status -eq 'GREEN'){'GREEN'}else{'BLUE'};issues=$integrity.issues;preview=(!$Apply);allowed_sources=@('checksum-verified local release artifact','checksum-verified release package','validated local UNDIES backup');disallowed_sources=@('host project source code','project extensions','runtime evidence','another unverified project installation','live development repository shared path')}; if($Preview -or -not $Apply){return $plan}; if($integrity.status -eq 'GREEN'){return [pscustomobject]@{status='GREEN';operation='REPAIR';repairs=@()}}; Install-ImmutableCore $Root 'repair' }
$ScriptDirectory=Split-Path -Parent $MyInvocation.MyCommand.Path
if($ScriptDirectory -match '\\\.undies\\core\\[^\\]+$'){
    $Root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptDirectory))
} else {
    $Root=$ScriptDirectory
}
switch($Command){
 'help' { "UNDIES portable bootstrap $script:UndiesVersion. One-way deployment only. Core is immutable; project configuration, extensions, and runtime data are separate. BLUE is a safe pause; collisions fail closed." }
 'initialize' { Install-ImmutableCore $Root 'initialize' | ConvertTo-Json -Depth 30 }
 'import' { if($DryRun -or $Preview){ @{status='PREVIEW';source='Validated UNDIES release artifact';destination=(Resolve-Path $Root).Path;reverse_synchronization='DISABLED'} | ConvertTo-Json -Depth 10 } else { Install-ImmutableCore $Root 'import' | ConvertTo-Json -Depth 30 } }
 'doctor' { if($Detailed){ Test-ImmutableCore $Root | ConvertTo-Json -Depth 30 } else { $r=Test-ImmutableCore $Root; @{status=$r.status;version=$script:UndiesVersion;active_core_version=$r.active_core_version;blue='supported';workspace=(Resolve-Path $Root).Path;portable=$true;reverse_synchronization='DISABLED'} | ConvertTo-Json -Depth 10 } }
 'integrity' { Test-ImmutableCore $Root | ConvertTo-Json -Depth 30 }
 'core-status' { Invoke-CoreStatus $Root | ConvertTo-Json -Depth 30 }
 'ownership' { Invoke-Ownership $Root | ConvertTo-Json -Depth 50 }
 'status' { @{workspace=(Resolve-Path $Root).Path;statuses=@('GREEN','YELLOW','BLUE','RED','BLOCKED');core=(Invoke-CoreStatus $Root);sessions=@(Get-ChildItem (Join-Path $Root '.undies/sessions') -Filter '*.json' -ErrorAction SilentlyContinue|ForEach-Object{Read-Json $_.FullName}|Select-Object session_id,status)} | ConvertTo-Json -Depth 30 }
 'session-start' { New-PortableSession $Root | ConvertTo-Json -Depth 20 }
 'session-close' { Close-PortableSession $Root $SessionId | ConvertTo-Json -Depth 20 }
 'blue-report' { New-BlueReport $Root }
 'resume' { if(-not $DependencyValidated){ throw 'BLUE dependency validation has not succeeded.' } else { @{status='RESUMED';canonical_status='BLUE';resume_checkpoint='portable-blue-checkpoint'} | ConvertTo-Json -Depth 5 } }
 'adopt' { Invoke-PortableAdoption $Root | ConvertTo-Json -Depth 30 }
 'configure' { Invoke-PortableConfigure $Root | ConvertTo-Json -Depth 20 }
 'version' { Invoke-PortableVersion $Root | ConvertTo-Json -Depth 10 }
 'upgrade' { Invoke-PortableUpgrade $Root | ConvertTo-Json -Depth 20 }
 'repair' { Invoke-PortableRepair $Root | ConvertTo-Json -Depth 20 }
 'disable' { Invoke-PortableDisable $Root | ConvertTo-Json -Depth 20 }
 'rollback' { Invoke-PortableRollback $Root | ConvertTo-Json -Depth 20 }
 'remove' { Invoke-PortableRemove $Root | ConvertTo-Json -Depth 20 }
}
