# Windows PowerShell 5.1 integration fixture: NO writes to actual MOZA files.
# All installation / restore paths are in a new system TEMP directory.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$setup = Join-Path $repo 'Tools\SetupEngine.ps1'
$recover = Join-Path $repo 'Tools\RecoveryEngine.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $repo 'Tools\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('MediocreAtBest-Upgrade-QA-' + [Guid]::NewGuid().ToString('N'))
$presetDir = Join-Path $fixture 'Presets'
$backupRoot = Join-Path $fixture 'Backups'
$dbFile = Join-Path $fixture 'carModels.db'
New-Item -ItemType Directory -Path $presetDir -Force | Out-Null
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
python (Join-Path $repo 'tests\make_db_fixture.py') $dbFile --complete
if ($LASTEXITCODE -ne 0) { throw 'Synthetic database fixture creation failed' }

function Hash([string]$File) { return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert([bool]$Valid, [string]$Message) { if (-not $Valid) { throw $Message } }
function RestorePoints {
  return @(Get-ChildItem -LiteralPath $backupRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'restore.json') -PathType Leaf } |
    Sort-Object Name)
}

try {
  # Create a representative v1.0.0 P15 profile with user-modified tuning.
  # Same UUID and exact car mapping as the current release, old class name and gains.
  $oldRecord = @($manifest.profiles | Where-Object { $_.profile_id -eq 'P15' })[0]
  $oldP15Path = Join-Path $presetDir ([string]$oldRecord.filename)
  $newP15 = Join-Path (Join-Path $repo 'Profiles') ([string]$oldRecord.filename)
  $oldJson = Get-Content -LiteralPath $newP15 -Raw -Encoding UTF8 | ConvertFrom-Json
  $oldJson.name = 'Automobilista 2 - MediocreAtBest - WEC Hypercar / IMSA GTP'
  $oldJson.deviceParams.platform.maxMotionAngle = 66
  $oldJson.deviceParams.platform.tactileFeedbackValue = 50
  $oldJson.deviceParams.AccToRoll.Flatness = 65
  $oldJson.deviceParams.AccToPitch.Flatness = 55
  $oldJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $oldP15Path -Encoding UTF8
  $oldHash = Hash $oldP15Path
  $dbHash = Hash $dbFile

  # Unrelated user MediocreAtBest profile MUST NOT be deleted because of its name alone.
  $personal = Join-Path $presetDir 'personal-MediocreAtBest.json'
  [pscustomobject]@{
    id='test-unrelated-MediocreAtBest-uuid'; name='AMS2 - MediocreAtBest - Personal Unrelated';
    tags=[pscustomobject]@{gameId=15; deviceType='GMotion'; carModels=@('Fixture Personal Only')};
    deviceParams=[pscustomobject]@{layout='F2B2'}
  } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $personal -Encoding UTF8
  $personalHash = Hash $personal

  # Another user's overlapping preset must block a noninteractive install.
  $thirdParty = Join-Path $presetDir 'third-party-conflict.json'
  [pscustomobject]@{
    id='test-unrelated-third-party'; name='Someone Else - Hypercar';
    tags=[pscustomobject]@{gameId=15; deviceType='GMotion'; carModels=@('Aston Martin Valkyrie Hypercar')};
    deviceParams=[pscustomobject]@{layout='F2B2'}
  } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $thirdParty -Encoding UTF8
  $thirdPartyHash = Hash $thirdParty
  $wasBlocked = $false
  try { & $setup -PresetDir $presetDir -DatabasePath $dbFile -BackupRoot $backupRoot -Apply | Out-Null }
  catch { $wasBlocked = $true }
  Assert $wasBlocked 'Third-party conflicting profile did not block unapproved install.'
  Assert ((Hash $thirdParty) -eq $thirdPartyHash) 'Third-party profile changed in blocked install.'
  Assert ((Hash $oldP15Path) -eq $oldHash) 'Blocked install changed old profile.'
  Assert ((@(RestorePoints)).Count -eq 0) 'Blocked install created a restore point.'
  Remove-Item -LiteralPath $thirdParty
  Write-Host 'PASS: unapproved third-party collision blocks installation.'

  # First upgrade: old P15 to full new 42; independent backup must include edits.
  & $setup -PresetDir $presetDir -DatabasePath $dbFile -BackupRoot $backupRoot -Apply | Out-Null
  $points = @(RestorePoints)
  Assert ($points.Count -eq 1) 'Expected exactly one upgrade backup.'
  $firstBackup = $points[0].FullName
  $savedOld = Join-Path (Join-Path $firstBackup 'Presets') ([string]$oldRecord.filename)
  $state = Get-Content -LiteralPath (Join-Path $firstBackup 'restore.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert ($state.release -eq 'v1.3.0') 'Wrong release recorded in restore manifest.'
  Assert ((Hash $savedOld) -eq $oldHash) 'User-modified old P15 was not safely backed up.'
  Assert ((Hash $oldP15Path) -eq (Hash $newP15)) 'New P15 was not installed.'
  Assert ((@(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File)).Count -eq 43) 'Upgrade created duplicate / missing profiles.'
  Assert ((Hash $personal) -eq $personalHash) 'Unrelated personal MediocreAtBest preset was removed/changed.'
  Assert ((Hash $dbFile) -eq $dbHash) 'Already-patched database should not change.'
  Assert (@($state.installed_hashes).Count -eq 42) 'Restore manifest lacks installed hashes.'
  Write-Host 'PASS: upgrade installs 42 unique profiles and preserves user edits in a separate backup.'

  # Repeat install must stay idempotent, not add duplicate JSON files.
  & $setup -PresetDir $presetDir -DatabasePath $dbFile -BackupRoot $backupRoot -Apply | Out-Null
  $points = @(RestorePoints)
  Assert ($points.Count -eq 2) 'Repeat install did not create independent second backup.'
  $secondBackup = $points[1].FullName
  Assert ((@(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File)).Count -eq 43) 'Repeat install made duplicate JSONs.'
  Assert ((Hash $personal) -eq $personalHash) 'Repeat install changed unrelated preset.'
  Write-Host 'PASS: reinstall remains 42 profiles with a separate backup.'

  # Roll back repeat: should leave v1.3.0 installed and old backup intact.
  & $recover -BackupDir $secondBackup -Apply | Out-Null
  Assert ((Hash $oldP15Path) -eq (Hash $newP15)) 'Restore of repeat did not recover v1.3.0.'
  Assert ((Hash $savedOld) -eq $oldHash) 'Earlier first-upgrade backup was altered.'

  # A user edit after installation must BLOCK rollback without changing files.
  Add-Content -LiteralPath $oldP15Path -Value ' '
  $editedHash=Hash $oldP15Path
  $wasBlocked=$false
  try { & $recover -BackupDir $firstBackup -Apply | Out-Null }
  catch { $wasBlocked=$true }
  Assert $wasBlocked 'Edited profile was silently replaced during restore.'
  Assert ((Hash $oldP15Path) -eq $editedHash) 'Blocked restore did not preserve user''s edit.'
  Copy-Item -LiteralPath $newP15 -Destination $oldP15Path -Force
  Write-Host 'PASS: post-install edits block restore without changing files.'

  # Undo upgrade, restoring the old user-modified profile from independent backup.
  & $recover -BackupDir $firstBackup -Apply | Out-Null
  Assert ((Hash $oldP15Path) -eq $oldHash) 'Restore failed to recover old modified P15.'
  Assert ((Hash $personal) -eq $personalHash) 'Restore changed an unrelated user preset.'
  Assert ((Hash $dbFile) -eq $dbHash) 'Restore touched an already-patched database.'
  Assert ((@(Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File)).Count -eq 2) 'Restore left duplicate profiles.'
  Assert ((Hash $savedOld) -eq $oldHash) 'Restore overwrote the saved original backup.'
  Write-Host 'PASS: rollback restores prior edited P15, retains unrelated profiles and all backups.'
} finally {
  if (Test-Path -LiteralPath $fixture -PathType Container) {
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
