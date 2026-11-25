# Windows native SQLite + installer/restore tests, using a synthetic database only.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('MediocreAtBest-DB-QA-'+[Guid]::NewGuid().ToString('N'))
$tools=Join-Path $repo 'Tools'
$presets=Join-Path $fixture 'Presets'; $backups=Join-Path $fixture 'Backups'; $db=Join-Path $fixture 'carModels.db'
New-Item -ItemType Directory -Path $presets,$backups -Force | Out-Null
function Assert([bool]$ok,[string]$msg) { if (-not $ok) { throw $msg } }
function Hash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
try {
  python (Join-Path $repo 'tests\make_db_fixture.py') $db
  if ($LASTEXITCODE -ne 0) { throw 'Fixture creation failed' }
  $originalHash=Hash $db
  Add-Type -Path (Join-Path $tools 'Database\SqliteInjector.cs')
  $payload=Get-Content -LiteralPath (Join-Path $tools 'Database\ams2-additions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  [string[]]$triples=@($payload.rows | ForEach-Object { [string]$_.telemetryName; [string]$_.name; [string]$_.category })
  Assert ([MediocreAtBestSqliteInjector]::Run($db,$triples,$false) -eq 420) 'Unexpected preview count'
  Assert ((Hash $db) -eq $originalHash) 'Preview wrote to database'
  & (Join-Path $tools 'SetupEngine.ps1') -PresetDir $presets -DatabasePath $db -BackupRoot $backups -Apply
  Assert ([MediocreAtBestSqliteInjector]::Run($db,$triples,$false) -eq 0) 'Installer missed entries'
  $installedHash=Hash $db
  $points=@(Get-ChildItem -LiteralPath $backups -Directory | Sort-Object Name)
  Assert ($points.Count -eq 1) 'Expected one initial backup'
  $point=$points[0].FullName
  $state=Get-Content -LiteralPath (Join-Path $point 'restore.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert ($state.db_installed_sha256 -eq $installedHash) 'Wrong installed DB hash in restore manifest'
  Assert ((Hash (Join-Path $point 'carModels.original.db')) -eq $originalHash) 'Original DB backup mismatch'
  Assert ([MediocreAtBestSqliteInjector]::Run($db,$triples,$true) -eq 0) 'Repeat insertion not idempotent'
  Assert ((Hash $db) -eq $installedHash) 'Repeat insertion rewrote DB'
  python (Join-Path $repo 'tests\verify_db_fixture.py') $db
  if ($LASTEXITCODE -ne 0) { throw 'Inserted data/other game preservation check failed' }
  & (Join-Path $tools 'RecoveryEngine.ps1') -BackupDir $point -Apply
  Assert ((Hash $db) -eq $originalHash) 'DB restore did not return exact original'
  Assert (@(Get-ChildItem -LiteralPath $presets -Filter '*.json').Count -eq 0) 'Restore left profiles'
  # A partial/custom database has an existing entry with the same telemetry name and a customised display name.
  python (Join-Path $repo 'tests\make_db_fixture.py') $db --partial
  if ($LASTEXITCODE -ne 0) { throw 'Partial fixture creation failed' }
  Assert ([MediocreAtBestSqliteInjector]::Run($db,$triples,$false) -eq 419) 'Existing AMS2 record not recognised'
  Assert ([MediocreAtBestSqliteInjector]::Run($db,$triples,$true) -eq 419) 'Partial injection count wrong'
  python (Join-Path $repo 'tests\verify_db_fixture.py') $db --partial
  if ($LASTEXITCODE -ne 0) { throw 'Existing customised record changed' }
  # Unsupported schema must fail without mutation.
  $bad=Join-Path $fixture 'bad.db'
  python (Join-Path $repo 'tests\make_db_fixture.py') $bad --unsupported
  if ($LASTEXITCODE -ne 0) { throw 'Unsupported fixture creation failed' }
  $before=Hash $bad; $rejected=$false
  try { [void][MediocreAtBestSqliteInjector]::Run($bad,$triples,$true) } catch { $rejected=$true }
  Assert $rejected 'Unsupported schema accepted'
  Assert ((Hash $bad) -eq $before) 'Unsupported DB modified'
  Write-Host 'PASS: native Windows SQLite injection, preview, idempotence, custom entries, exact DB restore and unsupported schema.'
} finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
