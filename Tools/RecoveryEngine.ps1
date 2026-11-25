[CmdletBinding()]
param(
  [string]$BackupDir = '',
  [switch]$Apply,
  [switch]$Interactive
)
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Test-DatabaseWritable([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    return $true
  } catch { return $false }
  finally { if ($null -ne $stream) { $stream.Dispose() } }
}
function Test-RunningAsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-VerifiedPresetPath([string]$Path, [string]$PresetDir) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'An empty profile path was found in the backup. Nothing changed.' }
  $full = [IO.Path]::GetFullPath($Path)
  $parent = [IO.Path]::GetDirectoryName($full).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  $base = [IO.Path]::GetFullPath($PresetDir).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  if ($parent -ine $base -or [IO.Path]::GetExtension($full) -ine '.json') {
    throw "Unexpected profile path in backup manifest: $Path. Nothing changed."
  }
  return $full
}

$toolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot = Split-Path -Parent $toolsRoot
$backupRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'MOZA\MediocreAtBest Profile Backups'

if ($Interactive) {
  Write-Host ''
  Write-Host 'MediocreAtBest - AUTOMOBILISTA 2 / MOZA PROFILE RESTORE' -ForegroundColor Cyan
  Write-Host 'Close MOZA Motion Manager completely and switch off your motion platform.'
  Write-Host 'Any profiles edited after installation will be protected.'
  Write-Host ''
  if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $available = @()
    $mozaDocs = Split-Path -Parent $backupRoot
    if (Test-Path -LiteralPath $mozaDocs -PathType Container) {
      $available = @(Get-ChildItem -LiteralPath $mozaDocs -Directory -Filter '* Profile Backups' | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'restore.json') -PathType Leaf } | Sort-Object Name -Descending)
    }
    if ($available.Count -eq 0) { throw 'No saved restore points were found. Nothing changed.' }
    Write-Host 'Saved restore points (newest first):'
    $limit = [Math]::Min($available.Count, 10)
    for ($i = 0; $i -lt $limit; $i++) { Write-Host ('  {0}. {1}' -f ($i + 1), $available[$i].Name) }
    $choiceText = Read-Host 'Choose a backup number [Enter uses 1]'
    if ([string]::IsNullOrWhiteSpace($choiceText)) { $choiceText = '1' }
    $choice = 0
    if (-not [int]::TryParse($choiceText, [ref]$choice) -or $choice -lt 1 -or $choice -gt $limit) {
      throw 'Invalid backup selection. Nothing changed.'
    }
    $BackupDir = $available[$choice - 1].FullName
  }
}
if ([string]::IsNullOrWhiteSpace($BackupDir)) { throw 'No backup selected. Use RESTORE.cmd. Nothing changed.' }
if (-not (Test-Path -LiteralPath $BackupDir -PathType Container)) { throw 'The selected backup folder does not exist. Nothing changed.' }
$BackupDir = (Get-Item -LiteralPath $BackupDir).FullName
$restoreFile = Join-Path $BackupDir 'restore.json'
if (-not (Test-Path -LiteralPath $restoreFile -PathType Leaf)) { throw 'The selected backup has no restore manifest. Nothing changed.' }
$state = Get-Content -LiteralPath $restoreFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$state.preset_dir) -or -not (Test-Path -LiteralPath $state.preset_dir -PathType Container)) {
  throw 'The original MOZA Presets folder is missing. Nothing changed.'
}
$presetDir = (Get-Item -LiteralPath ([string]$state.preset_dir)).FullName
$originalPaths = @($state.archived | ForEach-Object { Get-VerifiedPresetPath ([string]$_) $presetDir })
$installedPaths = @($state.installed | ForEach-Object { Get-VerifiedPresetPath ([string]$_) $presetDir })
if ($installedPaths.Count -eq 0) { throw 'There are no installed profiles recorded in this backup. Nothing changed.' }

$installedSet = @{}
$originalSet = @{}
foreach ($p in $installedPaths) {
  if ($installedSet.ContainsKey($p)) { throw 'Duplicate installed file in restore manifest. Nothing changed.' }
  $installedSet[$p] = $true
}
foreach ($p in $originalPaths) {
  if ($originalSet.ContainsKey($p)) { throw 'Duplicate original file in restore manifest. Nothing changed.' }
  $originalSet[$p] = $true
}

# Hashes created during installation are authoritative. For older backups lacking
# hashes, use the exact bundled profile bytes and fail closed if they differ.
$expectedInstalled = @{}
$records = @()
if ($null -ne $state.installed_hashes) { $records = @($state.installed_hashes) }
if ($records.Count -gt 0) {
  if ($records.Count -ne $installedPaths.Count) { throw 'Incomplete installed profile hash list. Nothing changed.' }
  foreach ($record in $records) {
    $p = Get-VerifiedPresetPath ([string]$record.path) $presetDir
    $hash = ([string]$record.sha256).ToLowerInvariant()
    if (-not $installedSet.ContainsKey($p) -or $expectedInstalled.ContainsKey($p) -or $hash -notmatch '^[a-f0-9]{64}$') {
      throw 'Invalid installed profile hash record. Nothing changed.'
    }
    $expectedInstalled[$p] = $hash
  }
} else {
  # The first installer generation wrote an installed-files list but not hashes.
  # No heuristic guessing: only accept exact byte matches to the packaged JSON.
  $manifestFile = Join-Path $toolsRoot 'manifest.json'
  if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw 'Cannot verify profiles installed by an older package. Nothing changed.'
  }
  $packageManifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $allowed = @{}
  foreach ($p in @($packageManifest.profiles)) { $allowed[[string]$p.filename] = $true }
  foreach ($p in $installedPaths) {
    $filename = Split-Path -Path $p -Leaf
    if (-not $allowed.ContainsKey($filename)) { throw "Cannot verify an older profile: $filename. Nothing changed." }
    $packageFile = Join-Path (Join-Path $packageRoot 'Profiles') $filename
    if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) { throw "Missing verification source: $filename. Nothing changed." }
    $expectedInstalled[$p] = Get-Sha256 $packageFile
  }
}

# Check everything that rollback might remove. Any edited/replaced/missing
# installed file stops the entire operation before the first change.
foreach ($p in $installedPaths) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "A profile was removed after installation: $p. No files changed."
  }
  if ((Get-Sha256 $p) -ne $expectedInstalled[$p]) {
    throw "A profile was edited or replaced since installation: $p. Restore BLOCKED; no files changed."
  }
}

$expectedArchived = @{}
$archiveRecords = @()
if ($null -ne $state.archived_hashes) { $archiveRecords = @($state.archived_hashes) }
if ($archiveRecords.Count -gt 0) {
  if ($archiveRecords.Count -ne $originalPaths.Count) { throw 'Incomplete backup hash list. Nothing changed.' }
  foreach ($record in $archiveRecords) {
    $p = Get-VerifiedPresetPath ([string]$record.path) $presetDir
    $hash = ([string]$record.sha256).ToLowerInvariant()
    if (-not $originalSet.ContainsKey($p) -or $expectedArchived.ContainsKey($p) -or $hash -notmatch '^[a-f0-9]{64}$') {
      throw 'Invalid original profile hash record. Nothing changed.'
    }
    $expectedArchived[$p] = $hash
  }
}

# Verify the required snapshot, and never overwrite an unexpected file in the
# location where an earlier profile would be restored.
$incomingCars = @{}
$incomingIds = @{}
foreach ($p in $originalPaths) {
  $snapshot = Join-Path (Join-Path $BackupDir 'Presets') (Split-Path -Path $p -Leaf)
  if (-not (Test-Path -LiteralPath $snapshot -PathType Leaf)) { throw "Missing original profile backup: $snapshot. Nothing changed." }
  if ($expectedArchived.Count -gt 0 -and (Get-Sha256 $snapshot) -ne $expectedArchived[$p]) {
    throw "Original profile backup was modified: $snapshot. Nothing changed."
  }
  if (-not $installedSet.ContainsKey($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "An unexpected file occupies an original profile location: $p. Nothing changed."
  }
  try { $j = Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw "Original profile backup is not valid JSON: $snapshot. Nothing changed." }
  if ($j.id) { $incomingIds[[string]$j.id] = $true }
  if ($j.tags.gameId -eq 15 -and $j.tags.deviceType -eq 'GMotion') {
    foreach ($name in @($j.tags.carModels)) { if ($name) { $incomingCars[[string]$name] = $true } }
  }
}

# Preserve unrelated/newly added files. But an unexpected profile that uses the
# same cars or UUID would create a MOZA conflict; stop rather than delete it.
foreach ($f in @(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File)) {
  if ($installedSet.ContainsKey($f.FullName)) { continue }
  try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw "Cannot check an unexpected JSON profile: $($f.FullName). Nothing changed." }
  if ($j.id -and $incomingIds.ContainsKey([string]$j.id)) {
    throw "An unrelated profile shares the UUID of an original profile: $($f.Name). Nothing changed."
  }
  if ($j.tags.gameId -eq 15 -and $j.tags.deviceType -eq 'GMotion') {
    foreach ($name in @($j.tags.carModels)) {
      if ($name -and $incomingCars.ContainsKey([string]$name)) {
        throw "An unrelated profile now uses an original car ($name): $($f.Name). Nothing changed."
      }
    }
  }
}

function Test-DatabaseSidecars([string]$Path) {
  foreach ($suffix in @('-wal','-shm','-journal')) { if (Test-Path -LiteralPath ($Path + $suffix)) { return $true } }
  return $false
}
$restoreDb = $false
$dbBackup = ''
$dbOriginalHash = ''
if ($state.db_path) {
  $dbBackup = Join-Path $BackupDir 'carModels.original.db'
  if (-not (Test-Path -LiteralPath $dbBackup -PathType Leaf)) { throw 'Original car database backup missing. Nothing changed.' }
  $dbOriginalHash = Get-Sha256 $dbBackup
  if ($state.db_original_sha256 -and $dbOriginalHash -ne ([string]$state.db_original_sha256).ToLowerInvariant()) {
    throw 'Original car database backup integrity check failed. Nothing changed.'
  }
  if (Test-Path -LiteralPath $state.db_path -PathType Leaf) {
    $dbCurrentHash = Get-Sha256 ([string]$state.db_path)
    if ($state.db_installed_sha256 -and $dbCurrentHash -eq ([string]$state.db_installed_sha256).ToLowerInvariant() -and -not (Test-DatabaseSidecars ([string]$state.db_path))) {
      $restoreDb = $true
    } else {
      Write-Warning 'The MOZA car database has changed since installation. That newer database will be preserved.'
    }
  } else {
    Write-Warning 'The installed MOZA car database is missing. Database restoration will be skipped.'
  }
}

Write-Host ''
Write-Host 'RESTORE PREVIEW' -ForegroundColor Cyan
Write-Host "  Saved backup: $BackupDir"
Write-Host "  Installed profiles to remove: $($installedPaths.Count)"
Write-Host "  Earlier profiles to recover: $($originalPaths.Count)"
Write-Host '  Other profiles: untouched'
Write-Host '  Original backup: retained'
if ($restoreDb) { Write-Host '  Car database: restore original copy' }
else { Write-Host '  Car database: left alone' }

if (-not $Apply) {
  if (-not $Interactive) { Write-Host 'CHECK COMPLETE. Nothing changed.' -ForegroundColor Yellow; return }
  Write-Host ''
  $confirmation = Read-Host 'Type RESTORE to continue [Enter cancels]'
  if ($confirmation -cne 'RESTORE') { Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; return }
  $Apply = $true
}

if ($restoreDb -and -not (Test-DatabaseWritable ([string]$state.db_path))) {
  if (Test-RunningAsAdmin) { throw 'The database is locked. Close MOZA Motion Manager completely. Nothing changed.' }
  Write-Host 'Windows administrator approval is needed to restore the MOZA database.' -ForegroundColor Yellow
  $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $scriptPath = $MyInvocation.MyCommand.Path
  $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -BackupDir "' + $BackupDir + '" -Apply'
  try { $elevated = Start-Process -FilePath $powershellExe -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop }
  catch { throw 'Administrator approval was cancelled or failed. Nothing changed.' }
  if ($elevated.ExitCode -ne 0) { throw 'Elevated restore was not completed. No success has been assumed.' }
  Write-Host 'Restore finished in the administrator window.' -ForegroundColor Green
  return
}

# Backup the current state again before making any changes. This safety point is
# independent of the selected original backup: neither backup is ever deleted.
$localBackupRoot = Split-Path -Parent $BackupDir
$safety = ''
do {
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $safety = Join-Path $localBackupRoot ('RestoreSafety-' + $stamp)
  if (Test-Path -LiteralPath $safety) { Start-Sleep -Milliseconds 25 }
} while (Test-Path -LiteralPath $safety)
New-Item -ItemType Directory -Path $safety -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path (Join-Path $safety 'Presets') -ErrorAction Stop | Out-Null
$beforeRestore = @{}
$restoredNames = New-Object System.Collections.ArrayList
$databaseWritten = $false
$changesStarted = $false
try {
  foreach ($f in @(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File)) {
    $hash = Get-Sha256 $f.FullName
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $safety 'Presets')
    $snapshot = Join-Path (Join-Path $safety 'Presets') $f.Name
    if ((Get-Sha256 $snapshot) -ne $hash) { throw "Could not verify restore safety backup: $($f.Name)" }
    $beforeRestore[$f.FullName] = $hash
  }
  if ($restoreDb) {
    Copy-Item -LiteralPath $state.db_path -Destination (Join-Path $safety 'carModels.before-restore.db')
    if ((Get-Sha256 (Join-Path $safety 'carModels.before-restore.db')) -ne $dbCurrentHash) {
      throw 'Could not verify the pre-restore database backup.'
    }
  }
  # Recheck after creating the safety copy; don't delete files altered in the meantime.
  foreach ($p in $installedPaths) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Sha256 $p) -ne $expectedInstalled[$p]) {
      throw "A profile changed while the restore was being prepared: $p"
    }
  }
  if ($restoreDb -and ((Get-Sha256 ([string]$state.db_path)) -ne $dbCurrentHash -or (Test-DatabaseSidecars ([string]$state.db_path)))) {
    throw 'The database changed during the restore preparation.'
  }

  $changesStarted = $true
  foreach ($p in $installedPaths) { Remove-Item -LiteralPath $p -ErrorAction Stop }
  foreach ($p in $originalPaths) {
    $source = Join-Path (Join-Path $BackupDir 'Presets') (Split-Path -Path $p -Leaf)
    if (Test-Path -LiteralPath $p -PathType Leaf) { throw "Unexpected profile appeared while restoring: $p" }
    Copy-Item -LiteralPath $source -Destination $p -ErrorAction Stop
    [void]$restoredNames.Add($p)
    if ((Get-Sha256 $p) -ne (Get-Sha256 $source)) { throw "Profile restore verification failed: $p" }
  }
  if ($restoreDb) {
    if ((Test-DatabaseSidecars ([string]$state.db_path)) -or (Get-Sha256 ([string]$state.db_path)) -ne $dbCurrentHash) { throw 'Database changed during restore; original backup retained.' }
    $candidate = Join-Path (Split-Path -Parent ([string]$state.db_path)) ('carModels.restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
      Copy-Item -LiteralPath $dbBackup -Destination $candidate -ErrorAction Stop
      if ((Get-Sha256 $candidate) -ne $dbOriginalHash) { throw 'Staged restoration hash mismatch.' }
      [IO.File]::Replace($candidate,([string]$state.db_path),[NullString]::Value)
      $databaseWritten = $true
    } finally { if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue } }
    if ((Get-Sha256 ([string]$state.db_path)) -ne $dbOriginalHash) { throw 'Database restore verification failed.' }
  }
  Write-Host ''
  Write-Host 'RESTORE COMPLETE' -ForegroundColor Green
  Write-Host "  Earlier profiles restored: $($originalPaths.Count)"
  Write-Host "  Safety backup retained: $safety"
  Write-Host 'Restart MOZA Motion Manager.'
} catch {
  Write-Warning "Restore stopped: $($_.Exception.Message)."
  if (-not $changesStarted) { Write-Warning 'No installed files were changed. Existing backups are untouched.'; throw }
  Write-Warning 'Trying to recover the immediately preceding state.'
  foreach ($p in $restoredNames) {
    if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
  }
  foreach ($p in $beforeRestore.Keys) {
    $snapshot = Join-Path (Join-Path $safety 'Presets') (Split-Path -Path $p -Leaf)
    if (Test-Path -LiteralPath $snapshot -PathType Leaf) {
      Copy-Item -LiteralPath $snapshot -Destination $p -Force -ErrorAction Stop
    }
  }
  if ($databaseWritten -and (Test-Path -LiteralPath (Join-Path $safety 'carModels.before-restore.db') -PathType Leaf)) {
    if (-not (Test-DatabaseSidecars ([string]$state.db_path)) -and (Get-Sha256 ([string]$state.db_path)) -eq $dbOriginalHash) {
      $candidate = Join-Path (Split-Path -Parent ([string]$state.db_path)) ('carModels.rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
      try { Copy-Item -LiteralPath (Join-Path $safety 'carModels.before-restore.db') -Destination $candidate; [IO.File]::Replace($candidate,([string]$state.db_path),[NullString]::Value) }
      finally { if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue } }
    } else { Write-Warning 'Database changed during recovery; safety backup retained.' }
  }
  Write-Warning "The selected backup and the safety copy remain available: $safety"
  throw
}
