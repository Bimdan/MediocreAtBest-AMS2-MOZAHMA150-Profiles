# Technical notes

## Profile generation and validation

The approved V2 profile targets are stored in `data/master-targets-v2.json`, distilled from a read-only Google Sheets `.xlsx` export. Only the 42 generated profile settings and car names needed for the build are included; the underlying research workbook is not part of this repository.

`Tools/import_master_export.py` prepares target data from an approved spreadsheet export (developer-only; requires openpyxl). `Tools/build_profiles.py` generates the MOZA v3 JSONs. Every **20 sheet-controlled settings per profile** are explicitly set, including Acceleration Roll/Pitch strengths and smoothness, 160 Hz vibration carrier, ABS/TC flags and the platform targets. Fields not mapped from the master retain their source-schema values and are not treated as calibrated data.

`tests/check_package.py` checks all 42 outputs against the frozen targets (**840 field comparisons**), the SHA-256 hashes, unique UUIDs, exact 565-car mapping, 204 observed AMS2 class codes, database integrity and installer package consistency. Any mismatch fails validation.

The files contain `platform.maxMotionAngle=35` and `platform.tactileFeedbackValue=35`, matching the approved master targets. Their interpretation should be confirmed in your installed MOZA Motion Manager UI; the JSON schema alone cannot establish every device-side conversion.

## Installation and existing profile handling

`INSTALL.cmd` launches Windows PowerShell 5.1 and `Tools/SetupEngine.ps1`. The installer looks for the user's Windows Documents location (including common OneDrive redirects) and for MOZA's installed car database using registered installation paths and Program Files fallbacks. Multiple matches are offered for selection.

An existing preset is selected for replacement only if it shares a car assignment, matches a supplied profile UUID or occupies an exact destination filename. An unrelated preset is not selected just because its name contains “MediocreAtBest”. Conflicting third-party assignments require explicit additional approval.

Before replacing files, the installer backs up **all current preset files** under `Documents\MOZA\MediocreAtBest Profile Backups`, checks backup SHA-256 values, records installed/archived hashes and paths in `restore.json`, and guards against concurrent file changes. Existing backups remain intact. This supports safe reinstallation or replacement of existing MediocreAtBest profiles, including personally edited files.

## Car database

The installer ships `Tools/Database/ams2-additions.json`, containing 420 additional AMS2 records without database IDs, and `SqliteInjector.cs`, which uses the SQLite library included in Windows 10/11. No original or modified MOZA database is distributed. It previews missing `(gameId, telemetryName)` pairs, validates the schema and integrity, rejects active sidecar files and unsupported journal modes, and saves a verified local database backup. Missing records are inserted into a staged copy in a SQLite transaction using bound parameters and locally allocated IDs. Every original row is checked before commit; a repeat run inserts nothing. The staged copy replaces only the user's unchanged local database using an atomic same-volume file replacement. No whole database from another installation is used. Unsupported databases are left intact. Administrator approval is requested when writing to a protected location.

## Restoration

`RESTORE.cmd` runs `Tools/RecoveryEngine.ps1`. A selected backup is checked against the installed hashes; edited or unexpected conflicting JSON files block restoration before changes begin. Archived originals are also verified. An independent `RestoreSafety-*` snapshot is made before recovery. Database restoration occurs only when the current database still matches the exact post-install database hash.

Choose the restore point that contains the profile state you want to recover. Backups are retained, so previously saved states are not erased by a later installation.

## Repository contents

- `Profiles/`: 42 generated MOZA JSON presets
- `data/master-targets-v2.json`: frozen build targets
- `Tools/`: installer, restore utility, manifest, hashes, database and build tools
- `docs/`: profile groups, exact car assignments and validation information
- `tests/`: generated-value checks and Windows fixture tests
- `dist/`: ready-to-extract installer ZIP and SHA-256 fingerprint (currently `MediocreAtBest-AMS2-MOZA-v1.3.0.zip`)

The on-PC installer and restore utility perform no network operations.
