[CmdletBinding()]
param(
  [string]$PresetDir = '',
  [string]$DatabasePath = '',
  [string]$BackupRoot = '',
  [switch]$Apply,
  [switch]$AllowOtherProfileConflicts,
  [switch]$Interactive
)
$ErrorActionPreference = 'Stop'

function Get-MozaPresetCandidates {
  $documentRoots = New-Object 'System.Collections.Generic.List[string]'
  $windowsDocuments = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
  if (-not [string]::IsNullOrWhiteSpace($windowsDocuments)) { $documentRoots.Add($windowsDocuments) }
  if ($env:USERPROFILE) { $documentRoots.Add((Join-Path $env:USERPROFILE 'Documents')) }
  foreach ($oneDriveVar in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
    $oneDriveRoot = [Environment]::GetEnvironmentVariable($oneDriveVar)
    if ($oneDriveRoot) { $documentRoots.Add((Join-Path $oneDriveRoot 'Documents')) }
  }
  $found = New-Object 'System.Collections.Generic.List[string]'
  foreach ($documents in $documentRoots) {
    $candidate = Join-Path $documents 'MOZA\MOZA Motion Manager\Presets'
    if ((Test-Path -LiteralPath $candidate -PathType Container) -and -not $found.Contains($candidate)) {
      $found.Add($candidate)
    }
  }
  return $found.ToArray()
}

function Get-MozaDatabaseCandidates {
  $roots = New-Object 'System.Collections.Generic.List[string]'
  $installKeys = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  # Registered installations take priority over ordinary Program Files locations.
  foreach ($key in $installKeys) {
    foreach ($app in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
      if ($app.DisplayName -match '(?i)MOZA.*Motion Manager') {
        if ($app.InstallLocation) { $roots.Add(([string]$app.InstallLocation).Trim().Trim('"')) }
        if ($app.DisplayIcon) {
          $icon = ([string]$app.DisplayIcon).Split(',')[0].Trim().Trim('"')
          if ($icon) { $roots.Add((Split-Path -Path $icon -Parent)) }
        }
      }
    }
  }
  $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  if ($programFilesX86) { $roots.Add((Join-Path $programFilesX86 'MOZA Motion Manager')) }
  if ($env:ProgramFiles) { $roots.Add((Join-Path $env:ProgramFiles 'MOZA Motion Manager')) }
  if ($env:LOCALAPPDATA) { $roots.Add((Join-Path $env:LOCALAPPDATA 'Programs\MOZA Motion Manager')) }
  if ($env:PROGRAMDATA) { $roots.Add((Join-Path $env:PROGRAMDATA 'MOZA Motion Manager')) }
  $found = New-Object 'System.Collections.Generic.List[string]'
  foreach ($rootPath in $roots) {
    if ([string]::IsNullOrWhiteSpace($rootPath)) { continue }
    foreach ($relative in @('bin\GameConfigs\carModels.db', 'GameConfigs\carModels.db', 'carModels.db')) {
      $candidate = Join-Path $rootPath $relative
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $full = (Get-Item -LiteralPath $candidate).FullName
        if ($found -notcontains $full) { $found.Add($full) }
      }
    }
  }
  return $found.ToArray()
}

function Test-DatabaseWritable([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    return $true
  } catch {
    return $false
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Test-RunningAsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Interactive) {
  Write-Host ''
  Write-Host '=====================================================' -ForegroundColor Cyan
  Write-Host ' MediocreAtBest - AUTOMOBILISTA 2 / MOZA MOTION PROFILES' -ForegroundColor Cyan
  Write-Host '=====================================================' -ForegroundColor Cyan
  Write-Host 'Close MOZA Motion Manager (including its tray icon).'
  Write-Host 'Turn off your motion platform before continuing.'
  Write-Host 'The installer will find the required folders automatically.'
  Write-Host 'Nothing is changed until you approve the installation.'
  Write-Host ''
}

if ([string]::IsNullOrWhiteSpace($PresetDir)) {
  $presetCandidates = @(Get-MozaPresetCandidates)
  if ($presetCandidates.Count -eq 0) {
    throw 'Could not find the MOZA Presets folder automatically. Open MOZA Motion Manager once, close it, then run INSTALL.cmd again. No files have been changed.'
  }
  if ($presetCandidates.Count -eq 1) {
    $PresetDir = $presetCandidates[0]
  } else {
    if (-not $Interactive) { throw 'More than one MOZA Presets folder was found. Use INSTALL.cmd to choose. No files changed.' }
    Write-Host 'Multiple MOZA Presets folders were found:' -ForegroundColor Yellow
    for ($i = 0; $i -lt $presetCandidates.Count; $i++) { Write-Host ('  {0}. {1}' -f ($i + 1), $presetCandidates[$i]) }
    $answer = Read-Host 'Select a folder number [Enter uses 1]'
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = '1' }
    $selection = 0
    if (-not [int]::TryParse($answer, [ref]$selection) -or $selection -lt 1 -or $selection -gt $presetCandidates.Count) { throw 'Invalid folder selection. No files changed.' }
    $PresetDir = $presetCandidates[$selection - 1]
  }
}
if (-not (Test-Path -LiteralPath $PresetDir -PathType Container)) {
  throw 'The MOZA Presets folder was not found. No files have been changed.'
}

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
  $dbCandidates = @(Get-MozaDatabaseCandidates)
  if ($dbCandidates.Count -eq 1) {
    $DatabasePath = $dbCandidates[0]
  } elseif ($dbCandidates.Count -gt 1) {
    if (-not $Interactive) {
      throw 'More than one MOZA database was found. Run INSTALL.cmd to choose your installed copy; nothing has been changed.'
    }
    Write-Host 'More than one MOZA installation was found:' -ForegroundColor Yellow
    for ($i = 0; $i -lt $dbCandidates.Count; $i++) {
      Write-Host ('  {0}. {1}' -f ($i + 1), $dbCandidates[$i])
    }
    $answer = Read-Host 'Select an installation number [Enter uses 1]'
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = '1' }
    $selection = 0
    if (-not [int]::TryParse($answer, [ref]$selection) -or $selection -lt 1 -or $selection -gt $dbCandidates.Count) {
      throw 'Invalid installation choice; nothing has been changed.'
    }
    $DatabasePath = $dbCandidates[$selection - 1]
  }
}
if ($DatabasePath -and -not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
  throw 'The MOZA car database was not found. No files have been changed.'
}

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $toolsRoot
$manifestPath = Join-Path $toolsRoot 'manifest.json'
$sourceDir = Join-Path $root 'Profiles'
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
  $BackupRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'MOZA\MediocreAtBest Profile Backups'
}
$backupRoot = $BackupRoot
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Missing manifest.json' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$installedNames = @{}
$profileUUIDs = @{}
foreach ($p in $manifest.profiles) {
  if ($profileUUIDs.ContainsKey([string]$p.uuid)) { throw "Duplicate profile UUID: $($p.uuid)" }
  $profileUUIDs[[string]$p.uuid] = $true
  foreach ($n in $p.cars) {
    if ($installedNames.ContainsKey([string]$n)) { throw "Duplicate car assignment: $n" }
    $installedNames[[string]$n] = $p.uuid
  }
}
if ($manifest.profile_count -ne 42 -or $installedNames.Count -ne 565) { throw 'Release manifest count mismatch' }
if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { throw 'Missing Profiles directory' }
foreach ($p in $manifest.profiles) {
  if ([string]::IsNullOrWhiteSpace([string]$p.filename) -or
      [IO.Path]::GetFileName([string]$p.filename) -ne [string]$p.filename) { throw 'Invalid profile filename in the manifest. Nothing changed.' }
  if ([string]::IsNullOrWhiteSpace([string]$p.sha256) -or ([string]$p.sha256) -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'Missing or invalid profile SHA-256 in the manifest. Nothing changed.'
  }
  $file = Join-Path $sourceDir $p.filename
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing profile: $file" }
  $j = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($j.id -ne $p.uuid -or $j.tags.gameId -ne 15 -or $j.tags.deviceType -ne 'GMotion' -or $j.deviceParams.layout -ne 'F2B2' -or [string]$j.name -cne [string]$p.name) {
    throw "Profile metadata mismatch: $file"
  }
  if (@($j.tags.carModels).Count -ne $p.car_count) { throw "Car count mismatch: $file" }
  # Validate the saved platform and acceleration-filter baseline before modifying any installed profiles.
  if ($j.deviceParams.platform.maxMotionAngle -ne 35 -or $j.deviceParams.platform.tactileFeedbackValue -ne 35 -or
      $j.deviceParams.AccToRoll.Flatness -ne 20 -or $j.deviceParams.AccToPitch.Flatness -ne 20) {
    throw "Motion baseline mismatch: $file. Nothing has been changed."
  }
  if ($p.sha256 -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$p.sha256).ToLowerInvariant()) {
    throw "Profile integrity check failed: $file"
  }
  foreach ($name in @($j.tags.carModels)) {
    if (-not $installedNames.ContainsKey([string]$name) -or $installedNames[[string]$name] -ne $p.uuid) {
      throw "Profile assignment mismatch: $file ($name)"
    }
  }
}

Write-Host '[1/3] INSTALLATION DETECTED' -ForegroundColor Cyan
Write-Host "  Profiles folder: $PresetDir" -ForegroundColor Green
if ($DatabasePath) {
  Write-Host "  Car database:    $DatabasePath" -ForegroundColor Green
} else {
  Write-Warning 'Car database was not found automatically. Existing database will be left alone; some cars may be missing from the MOZA selector.'
}
Write-Host ''
Write-Host '[2/3] CHECKING EXISTING PROFILES AND DATABASE' -ForegroundColor Cyan
Write-Host '  New profiles: 42 | Assigned cars: 565'

$toArchive = New-Object System.Collections.ArrayList
$blocked = New-Object System.Collections.ArrayList
$allPresets = @(Get-ChildItem -LiteralPath $PresetDir -Filter '*.json' -File)
foreach ($f in $allPresets) {
  try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw "Cannot read an existing MOZA JSON preset: $($f.FullName). No files have been changed." }
  $validGame = ($j.tags.gameId -eq 15 -and $j.tags.deviceType -eq 'GMotion')
  # A known UUID, not the display brand, identifies an installed pack profile.
  $isMediocreAtBest = ($validGame -and $j.id -and $profileUUIDs.ContainsKey([string]$j.id))
  $overlap = @()
  if ($validGame -and $j.deviceParams.layout -eq 'F2B2') {
    foreach ($name in @($j.tags.carModels)) {
      if ($name -and $installedNames.ContainsKey([string]$name)) { $overlap += [string]$name }
    }
  }
  $uuidMatch = ($j.id -and $profileUUIDs.ContainsKey([string]$j.id))
  $filenameCollision = $false
  foreach ($p in $manifest.profiles) {
    if ($f.Name -ieq [string]$p.filename) { $filenameCollision = $true; break }
  }
  # A user-created MediocreAtBest preset for unrelated cars is NOT an upgrade target.
  # Replace only a colliding assignment, a known profile UUID, or an exact filename.
  if ($overlap.Count -gt 0 -or $uuidMatch -or $filenameCollision) {
    $item = [pscustomobject]@{
      Path = $f.FullName; Name = [string]$j.name; MediocreAtBest = $isMediocreAtBest;
      Overlaps = $overlap.Count; UUIDMatch = $uuidMatch; FilenameCollision = $filenameCollision
    }
    [void]$toArchive.Add($item)
    if (-not $isMediocreAtBest -and ($overlap.Count -gt 0 -or $uuidMatch -or $filenameCollision)) { [void]$blocked.Add($item) }
  }
}
Write-Host "  Existing profiles requiring backup/replacement: $($toArchive.Count)"
$previewLimit = [Math]::Min(6, $toArchive.Count)
for ($i = 0; $i -lt $previewLimit; $i++) {
  Write-Host "    $($toArchive[$i].Name)"
}
if ($toArchive.Count -gt $previewLimit) {
  Write-Host "    ...and $($toArchive.Count - $previewLimit) more. All affected profiles are included in the backup."
}
if ($blocked.Count -gt 0 -and -not $AllowOtherProfileConflicts) {
  Write-Warning "$($blocked.Count) non-MediocreAtBest profiles also use these cars. They will not be removed without permission."
  if (-not $Interactive) { throw 'Run INSTALL.cmd to review third-party profile conflicts. No files changed.' }
  foreach ($item in $blocked) { Write-Host "    Conflicting profile: $($item.Name)" -ForegroundColor Yellow }
  $conflictApproval = Read-Host 'Type REPLACE to back up and replace these conflicting profiles [Enter cancels]'
  if ($conflictApproval -cne 'REPLACE') { Write-Host 'Cancelled. No files changed.' -ForegroundColor Yellow; return }
  $AllowOtherProfileConflicts = $true
}

$payloadPath = Join-Path $toolsRoot 'Database\ams2-additions.json'
$injectorPath = Join-Path $toolsRoot 'Database\SqliteInjector.cs'
foreach ($check in @(@{Path=$payloadPath; Hash=$manifest.db_additions_sha256}, @{Path=$injectorPath; Hash=$manifest.db_injector_sha256})) {
  if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf) -or
      (Get-FileHash -LiteralPath $check.Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$check.Hash).ToLowerInvariant()) {
    throw 'Database injection payload failed integrity verification. No files changed.'
  }
}
$payload = Get-Content -LiteralPath $payloadPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($payload.format -ne 1 -or $payload.gameId -cne '15' -or @($payload.rows).Count -ne 420) { throw 'Invalid database additions payload.' }
[string[]]$additionTriples = @($payload.rows | ForEach-Object { [string]$_.telemetryName; [string]$_.name; [string]$_.category })
function Assert-NoDatabaseSidecars([string]$Path) {
  foreach ($suffix in @('-wal','-shm','-journal')) {
    if (Test-Path -LiteralPath ($Path + $suffix)) { throw 'SQLite sidecar present; close MOZA Motion Manager fully. Database left untouched.' }
  }
}
$installDb = $false
$oldDbHash = ''
$missingCount = 0
if ($DatabasePath) {
  try {
    Assert-NoDatabaseSidecars $DatabasePath
    if (-not ('MediocreAtBestSqliteInjector' -as [type])) { Add-Type -Path $injectorPath -ErrorAction Stop }
    $oldDbHash = (Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $missingCount = [MediocreAtBestSqliteInjector]::Run($DatabasePath,$additionTriples,$false)
    Assert-NoDatabaseSidecars $DatabasePath
    if ((Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDbHash) { throw 'Database changed during preview.' }
    $installDb = ($missingCount -gt 0)
    Write-Host "  Database: $missingCount missing AMS2 entries; existing records are preserved." -ForegroundColor Green
  } catch {
    Write-Warning "Database update skipped: $($_.Exception.Message) Profiles can still install; some vehicle names may be unavailable."
    $installDb = $false
  }
}
Write-Host ''
Write-Host '[3/3] BACKUP AND INSTALL PREVIEW' -ForegroundColor Cyan
Write-Host '  A complete copy of your existing JSON presets is saved before anything is removed.'
Write-Host '  Only overlapping AMS2 presets or profiles with matching UUID/filenames are replaced.'
Write-Host '  Modified existing profiles are preserved in the dated backup before replacement.'
if ($installDb) { Write-Host '  A backup of your existing car database will also be saved.' }
else { Write-Host '  The installed car database will NOT be changed.' }

if (-not $Apply) {
  if (-not $Interactive) {
    Write-Host 'CHECK COMPLETE: Nothing changed. Run INSTALL.cmd to install.' -ForegroundColor Yellow
    return
  }
  Write-Host ''
  $confirmation = Read-Host 'Type INSTALL to create a backup and install [Enter cancels]'
  if ($confirmation -cne 'INSTALL') { Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; return }
  $Apply = $true
}

# A protected database may need administrator rights. Windows prompts via UAC only
# when a database write is necessary; explicit paths are passed to the elevated process,
# so a different administrator account cannot silently change the target user's paths.
if ($installDb -and -not (Test-DatabaseWritable $DatabasePath)) {
  if (Test-RunningAsAdmin) { throw 'The car database is locked or inaccessible. Close MOZA Motion Manager fully and run the installer again. No files changed.' }
  Write-Host 'Windows administrator approval is needed to update the MOZA car database.' -ForegroundColor Yellow
  $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $scriptPath = $MyInvocation.MyCommand.Path
  $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -PresetDir "' + $PresetDir + '" -DatabasePath "' + $DatabasePath + '" -BackupRoot "' + $BackupRoot + '" -Apply'
  if ($AllowOtherProfileConflicts) { $arguments += ' -AllowOtherProfileConflicts' }
  try { $elevated = Start-Process -FilePath $powershellExe -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop }
  catch { throw 'Administrator approval was cancelled or failed. Nothing was changed.' }
  if ($elevated.ExitCode -ne 0) { throw 'The elevated installer did not complete. Check the elevated PowerShell window and try again. Do not assume installation succeeded.' }
  Write-Host 'Installation completed in the Windows-approved administrator session.' -ForegroundColor Green
  return
}

$backup = ''
do {
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $backup = Join-Path $backupRoot $stamp
  if (Test-Path -LiteralPath $backup) { Start-Sleep -Milliseconds 25 }
} while (Test-Path -LiteralPath $backup)
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backup 'Presets') -ErrorAction Stop | Out-Null
$copiedNew = New-Object System.Collections.ArrayList
$archived = New-Object System.Collections.ArrayList
$changesStarted = $false
$databaseWritten = $false
$stagedDb = ''
$localCandidate = ''
$patchedHash = ''
try {
  # Full snapshot plus a restore manifest written BEFORE any original files are deleted.
  $originalHashes = @{}
  foreach ($f in $allPresets) {
    $originalHashes[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backup 'Presets')
    $copy = Join-Path (Join-Path $backup 'Presets') $f.Name
    if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHashes[$f.FullName]) {
      throw "The backup could not be verified: $($f.FullName). No files changed."
    }
  }
  foreach ($item in $toArchive) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $backup 'Presets') (Split-Path $item.Path -Leaf)) -PathType Leaf)) {
      throw "A preset was not backed up: $($item.Path)"
    }
  }
  if ($installDb) {
    Copy-Item -LiteralPath $DatabasePath -Destination (Join-Path $backup 'carModels.original.db') -Force
    if ((Get-FileHash -LiteralPath (Join-Path $backup 'carModels.original.db') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDbHash) {
      throw 'Database backup did not match the original. No presets were changed.'
    }
    # Stage only a copy of this user's own database. The payload contains no database file.
    $stagedDb = Join-Path $backup 'carModels.staged.db'
    Copy-Item -LiteralPath (Join-Path $backup 'carModels.original.db') -Destination $stagedDb
    $inserted = [MediocreAtBestSqliteInjector]::Run($stagedDb,$additionTriples,$true)
    if ($inserted -ne $missingCount -or [MediocreAtBestSqliteInjector]::Run($stagedDb,$additionTriples,$false) -ne 0) { throw 'Staged database verification failed.' }
    $patchedHash = (Get-FileHash -LiteralPath $stagedDb -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-NoDatabaseSidecars $DatabasePath
    if ((Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDbHash) { throw 'Database changed during preparation. Nothing installed.' }
    # Copy onto the same volume before atomic replacement; fail before touching presets if not writable.
    $localCandidate = Join-Path (Split-Path -Parent $DatabasePath) ('carModels.inject-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $stagedDb -Destination $localCandidate -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $localCandidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $patchedHash) { throw 'Local staged database copy mismatch.' }
  }
  $archivePaths = @($toArchive | ForEach-Object { $_.Path })
  $newPaths = @($manifest.profiles | ForEach-Object { Join-Path $PresetDir $_.filename })
  $archivedHashes = @($toArchive | ForEach-Object {
    [pscustomobject]@{ path = $_.Path; sha256 = [string]$originalHashes[$_.Path] }
  })
  $installedHashes = @($manifest.profiles | ForEach-Object {
    [pscustomobject]@{ path = (Join-Path $PresetDir $_.filename); sha256 = [string]$_.sha256 }
  })
  $restoreInfo = [pscustomobject]@{
    release = [string]$manifest.release; date = (Get-Date).ToString('o');
    preset_dir = $PresetDir;
    db_path = $(if ($installDb) { $DatabasePath } else { '' });
    db_original_sha256 = $(if ($installDb) { $oldDbHash } else { '' });
    db_installed_sha256 = $(if ($installDb) { $patchedHash } else { '' });
    archived = $archivePaths; installed = $newPaths;
    archived_hashes = $archivedHashes; installed_hashes = $installedHashes;
    installation_complete = $false
  }
  $restoreInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backup 'restore.json') -Encoding UTF8
  foreach ($item in $toArchive) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHashes[$item.Path]) {
      throw "An existing profile changed during backup; stopping without overwriting it: $($item.Path)"
    }
  }
  $changesStarted = $true
  foreach ($item in $toArchive) { Remove-Item -LiteralPath $item.Path; [void]$archived.Add($item.Path) }
  foreach ($p in $manifest.profiles) {
    $dest = Join-Path $PresetDir $p.filename
    if (Test-Path -LiteralPath $dest -PathType Leaf) { throw "A profile appeared during installation: $dest" }
    Copy-Item -LiteralPath (Join-Path $sourceDir $p.filename) -Destination $dest
    [void]$copiedNew.Add([pscustomobject]@{Path=$dest; Hash=[string]$p.sha256})
    if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$p.sha256).ToLowerInvariant()) {
      throw "Installed profile verification failed: $dest"
    }
  }
  if ($installDb) {
    Assert-NoDatabaseSidecars $DatabasePath
    if ((Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDbHash) { throw 'Database changed since backup; stopping.' }
    [IO.File]::Replace($localCandidate,$DatabasePath,[NullString]::Value)
    $databaseWritten = $true
    if ((Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $patchedHash) {
      throw 'Database verification failed after replacement.'
    }
  }
  $restoreInfo.installation_complete = $true
  $restoreInfo | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backup 'restore.json') -Encoding UTF8
  Write-Host ''
  Write-Host 'INSTALLATION COMPLETE' -ForegroundColor Green
  Write-Host "42 profiles installed. Backup saved at: $backup" -ForegroundColor Green
  Write-Host 'Restart MOZA Motion Manager. Verify the profiles with the motion platform off.'
} catch {
  Write-Warning "Installation failed: $($_.Exception.Message)."
  if (-not $changesStarted) { Write-Warning 'No installed profiles or database files were changed.'; throw }
  Write-Warning 'Attempting immediate rollback from the saved backup.'
  foreach ($f in $copiedNew) {
    if (Test-Path -LiteralPath $f.Path -PathType Leaf) {
      if ((Get-FileHash -LiteralPath $f.Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $f.Hash.ToLowerInvariant()) { Remove-Item -LiteralPath $f.Path -Force }
      else { Write-Warning "Profile changed during rollback; retained: $($f.Path)" }
    }
  }
  foreach ($path in $archived) {
    $snapshot = Join-Path (Join-Path $backup 'Presets') (Split-Path -Leaf $path)
    if (Test-Path -LiteralPath $snapshot -PathType Leaf) {
      if (Test-Path -LiteralPath $path) { Write-Warning "Unexpected file at $path; backup retained." }
      else { Copy-Item -LiteralPath $snapshot -Destination $path }
    }
  }
  if ($databaseWritten -and (Test-Path -LiteralPath (Join-Path $backup 'carModels.original.db') -PathType Leaf)) {
    Assert-NoDatabaseSidecars $DatabasePath
    if ((Get-FileHash -LiteralPath $DatabasePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $patchedHash) {
      $rollbackCandidate = Join-Path (Split-Path -Parent $DatabasePath) ('carModels.rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
      Copy-Item -LiteralPath (Join-Path $backup 'carModels.original.db') -Destination $rollbackCandidate
      [IO.File]::Replace($rollbackCandidate,$DatabasePath,[NullString]::Value)
    } else { Write-Warning 'Database changed after update; automatic rollback skipped. Original backup retained.' }
  }
  throw
} finally {
  foreach ($temp in @($localCandidate,$stagedDb)) { if ($temp -and (Test-Path -LiteralPath $temp -PathType Leaf)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}
