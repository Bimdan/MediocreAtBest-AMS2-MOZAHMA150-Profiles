# Automated restore tests. All writes are confined to a unique TEMP folder.
# This script must never run against a real MOZA profile folder.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$recover = Join-Path $repo 'Tools\RecoveryEngine.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $repo 'Tools\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('MediocreAtBest-QA-' + [Guid]::NewGuid().ToString('N'))
$presetDir = Join-Path $fixture 'Presets'
$backupDir = Join-Path $fixture 'Backups\fixture'
$backupPresets = Join-Path $backupDir 'Presets'
New-Item -ItemType Directory -Path $presetDir -Force | Out-Null
New-Item -ItemType Directory -Path $backupPresets -Force | Out-Null

function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function ExpectBlocked([string]$CaseName) {
  $thrown = $false
  try { & $recover -BackupDir $backupDir -Apply | Out-Null }
  catch { $thrown = $true }
  if (-not $thrown) { throw "A restore should have been blocked but was not: $CaseName" }
  if (-not (Test-Path -LiteralPath $firstInstalled -PathType Leaf)) { throw "Blocked restore modified the installation: $CaseName" }
  if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { throw "Blocked restore removed the backup: $CaseName" }
  Write-Host "PASS (blocked safely): $CaseName"
}

try {
  $installed = @()
  $installedHashes = @()
  foreach ($p in @($manifest.profiles)) {
    $src = Join-Path (Join-Path $repo 'Profiles') ([string]$p.filename)
    $dest = Join-Path $presetDir ([string]$p.filename)
    Copy-Item -LiteralPath $src -Destination $dest
    $installed += $dest
    $installedHashes += [pscustomobject]@{path=$dest; sha256=(Hash $dest)}
  }
  $firstInstalled = $installed[0]
  $oldPath = Join-Path $presetDir 'previous-MediocreAtBest-profile.json'
  $oldData = [pscustomobject]@{
    id='b7ee7792-82b2-41d5-8e03-3b90d8b23175'; name='Automobilista 2 - MediocreAtBest - previous';
    tags=[pscustomobject]@{gameId=15; deviceType='GMotion'; carModels=@('McLaren 720S GT3')}
  }
  $oldSnapshot = Join-Path $backupPresets 'previous-MediocreAtBest-profile.json'
  $oldData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $oldSnapshot -Encoding UTF8
  $archivedHash = Hash $oldSnapshot
  $unrelated = Join-Path $presetDir 'unrelated.json'
  [pscustomobject]@{id='fixture-other'; name='Another game'; tags=[pscustomobject]@{gameId=16; deviceType='GMotion'; carModels=@('Different car')}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $unrelated -Encoding UTF8
  $unrelatedHash=Hash $unrelated
  $state = [pscustomobject]@{
    release='v1.0.0'; date='2026-11-22T00:00:00Z'; preset_dir=$presetDir;
    db_path=''; db_original_sha256=''; db_installed_sha256='';
    archived=@($oldPath); installed=$installed;
    archived_hashes=@([pscustomobject]@{path=$oldPath; sha256=$archivedHash});
    installed_hashes=$installedHashes; installation_complete=$true
  }
  $restoreStateFile=Join-Path $backupDir 'restore.json'
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $restoreStateFile -Encoding UTF8
  $originalManifestHash = Hash $restoreStateFile

  # Dry run must not mutate any files.
  & $recover -BackupDir $backupDir | Out-Null
  if ((Hash $firstInstalled) -ne $installedHashes[0].sha256 -or (Hash $restoreStateFile) -ne $originalManifestHash) {
    throw 'Dry run changed a file.'
  }
  Write-Host 'PASS: dry run is non-destructive'

  # A user-edited installed file must block the entire restore.
  Add-Content -LiteralPath $firstInstalled -Value ' '
  $editedHash=Hash $firstInstalled
  ExpectBlocked 'edited installed profile'
  if ((Hash $firstInstalled) -ne $editedHash) { throw 'Edited profile was unexpectedly overwritten.' }
  Copy-Item -LiteralPath (Join-Path (Join-Path $repo 'Profiles') ([string]$manifest.profiles[0].filename)) -Destination $firstInstalled -Force

  # Altering an archived file must not be silently accepted.
  Add-Content -LiteralPath $oldSnapshot -Value ' '
  ExpectBlocked 'modified saved backup'
  $oldData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $oldSnapshot -Encoding UTF8
  if ((Hash $oldSnapshot) -ne $archivedHash) { throw 'Could not reset the original snapshot fixture.' }

  # A newly added conflicting profile must be preserved and cause a safe stop.
  $extra = Join-Path $presetDir 'unexpected-conflict.json'
  [pscustomobject]@{id='fixture-new'; name='Unrelated addition'; tags=[pscustomobject]@{gameId=15;deviceType='GMotion';carModels=@('McLaren 720S GT3')}} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $extra -Encoding UTF8
  $extraHash=Hash $extra
  ExpectBlocked 'unexpected vehicle-assignment conflict'
  if ((Hash $extra) -ne $extraHash) { throw 'Unexpected profile was altered.' }
  Remove-Item -LiteralPath $extra

  # Successful recovery in the fixture removes only installed files, reinstates
  # the original backup and keeps other JSON files and backup points.
  & $recover -BackupDir $backupDir -Apply | Out-Null
  foreach ($p in $installed) {
    if (Test-Path -LiteralPath $p -PathType Leaf) { throw "An installed profile was not removed: $p" }
  }
  if (-not (Test-Path -LiteralPath $oldPath -PathType Leaf) -or (Hash $oldPath) -ne $archivedHash) {
    throw 'The earlier profile was not correctly recovered.'
  }
  if (-not (Test-Path -LiteralPath $unrelated -PathType Leaf) -or (Hash $unrelated) -ne $unrelatedHash) {
    throw 'Unrelated profile was changed.'
  }
  if ((Hash $oldSnapshot) -ne $archivedHash -or (Hash $restoreStateFile) -ne $originalManifestHash) {
    throw 'Original backup files were changed.'
  }
  $safety = @(Get-ChildItem -LiteralPath (Split-Path -Parent $backupDir) -Directory | Where-Object { $_.Name -like 'RestoreSafety-*' })
  if ($safety.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $safety[0].FullName 'Presets') -PathType Container)) {
    throw 'The independent restore safety snapshot is missing.'
  }
  Write-Host 'PASS: successful fixture restore preserves unrelated data and both backups'
} finally {
  if (Test-Path -LiteralPath $fixture -PathType Container) {
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
