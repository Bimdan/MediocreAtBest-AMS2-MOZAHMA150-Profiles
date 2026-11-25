# MediocreAtBest AMS2 motion profiles for MOZA HMA150

A collection of editable motion profiles for **Automobilista 2** and the **MOZA HMA150**.

These aren't finely tuned, car-by-car motion profiles. I've used the V10-era Formula One cars as the most muted end of the scale, gradually increasing movement for other vehicle groups while keeping things fairly conservative. The idea is to feel what the car is doing, not get thrown out of your seat at every corner.

The real benefit is that I've done the donkey work for you. Some 565 vehicle names have been organised into 42 recognisable groups, so if you fancy a bit more roll in your GT3 cars, you can tweak the group rather than spend half your evening adjusting individual cars.

They're intended as sensible, drivable starting points. Feel free to tweak them to your own liking.

## What's included

- **42 class-based profiles**, covering 565 AMS2 vehicle names. Exact names and assignments are listed in [CAR-ASSIGNMENTS.csv](docs/CAR-ASSIGNMENTS.csv).
- **Search-friendly profile names** that start with AMS2 class terms, followed by familiar motorsport names and relevant generation years. See [profile groups](docs/PROFILES.md).
- **35% maximum usable stroke** and **35% haptic intensity** as common starting values.
- **20% Acceleration Roll smoothness** and **20% Acceleration Pitch smoothness** as common responsiveness settings. The *strengths* of those and other motion effects remain class-specific.
- A common **160 Hz engine-vibration carrier**. It is not calculated from engine RPM, firing frequency or cylinder count.
- A Windows installer with automatic MOZA path detection, existing-profile checks and recoverable backups, plus a separate restore utility.

Motion is intentionally conservative: even the more compliant categories have restrained body movement and acceleration cues. These numbers are starting points for players to adjust, **not calibrated vehicle dynamics or guaranteed safe hardware settings**. Check the available rig clearance and use motion conservatively until you are satisfied with the response.

## Installation

1. Download **[MediocreAtBest-AMS2-MOZA-v1.3.0.zip](dist/MediocreAtBest-AMS2-MOZA-v1.3.0.zip)** and extract the **whole ZIP** to a folder.
2. Close **MOZA Motion Manager** completely, including its system-tray icon. Switch off the motion platform.
3. Double-click **`INSTALL.cmd`** at the top of the extracted folder.
4. Review the detected Presets folder, car database and any existing profiles the installer proposes to replace. Normally you will not need to enter Windows paths.
5. Type **`INSTALL`** to approve, or press Enter to cancel.
6. Restart MOZA Motion Manager, review the profile names and settings with motion switched off, then check physical clearances before driving.

**Already have MediocreAtBest profiles installed?** The same installer can be run again. It checks for matching profile identities, filenames and car assignments, makes a new backup of the existing presets (including your own edits), then replaces affected profiles. It does not replace an unrelated preset merely because its name contains “MediocreAtBest”. Third-party assignment conflicts require separate approval.

## Backups and restore

Each installation creates an independent backup in your Windows Documents folder:

`Documents\MOZA\MediocreAtBest Profile Backups\<date-time>`

Existing backup folders are retained. Run **`RESTORE.cmd`** from the same extracted installer folder to select a backup and recover the previous state.

The restore utility checks whether installed profile files have been changed since installation and **stops rather than silently overwriting those edits**. Unexpected unrelated presets are preserved. If the MOZA car database has changed since installation, its restoration is skipped to protect subsequent changes.

## Compatibility and notes

- Intended for **Automobilista 2** in MOZA Motion Manager with **MOZA HMA150**, `GMotion`, game ID `15` and layout `F2B2`.
- The supplied vehicle list includes some DLC and potentially community-added car names. You will only see cars supported by your AMS2 installation and the MOZA car selector.
- The installer ships **only 420 additional AMS2 entries**, not a MOZA database. On compatible SQLite databases, it adds missing names transactionally to a local copy of your database, preserves all existing records, and verifies the result before replacing the local file. An unsupported schema, journal mode or unavailable database is left alone. Windows 10/11 supplies the SQLite library.
- Run **`INSTALL.cmd`** and **`RESTORE.cmd`** at the package top level. Python and development tools are not required on the gaming PC. Administrator approval is requested only when a protected database must be written.
- **Installation verified on a real Windows PC.** The automated Windows PowerShell 5.1 installer, restore and native SQLite tests also pass. Live restoration, the actual database insertion count on the gaming PC and every vehicle's motion behaviour have not been independently verified. Check your own rig's clearances and settings before driving.

## Technical information

The repository includes the editable profile JSONs, build tools, documented car assignments and validation tests. The frozen [profile build targets](data/master-targets-v2.json) define the settings used for the 42 profiles. The package validator checks all 20 controlled settings per profile and fails if any generated value differs.

See [technical notes](docs/TECHNICAL.md) and the [validation summary](docs/QA-REPORT.md) for implementation details and testing limitations.
