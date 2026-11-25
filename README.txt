MediocreAtBest - AMS2 MOTION PROFILES FOR MOZA HMA150
Version 1.3.0
================================================

42 class-based motion profiles for 565 Automobilista 2 vehicle names.

INSTALLATION
------------
1. Extract the entire ZIP to a folder. Do not run scripts inside the ZIP.
2. Quit MOZA Motion Manager completely, including its system-tray icon.
   Switch off your motion platform.
3. Double-click INSTALL.cmd at the top of the extracted folder.
4. Review the automatically detected locations, existing-profile checks
   and backup/replacement summary. Normally no path entry is needed.
5. Type INSTALL to approve; pressing Enter cancels.
6. Restart MOZA Motion Manager. Check the names and values with motion
   switched off. Confirm the platform has adequate physical clearance.

WHAT'S INCLUDED
---------------
- 42 profiles for 565 unique AMS2 vehicle names.
- AMS2 class names first for searching, followed by familiar racing terms
  and meaningful generation years.
- 35% maximum usable stroke and 35% haptic intensity starting values.
- 20% Acceleration Roll and 20% Acceleration Pitch smoothness.
- Conservative class-specific motion strengths, intended for player tuning.
- Common engine-vibration carrier of 160 Hz (not derived from engine RPM).
- Automatic MOZA path detection, existing-profile checks and backups.

EXISTING PROFILES
-----------------
The installer also works when MediocreAtBest profiles are already installed.
Before replacing affected files it makes an independent backup, including
any edits made to those profiles. Unrelated presets are retained, and
third-party assignment conflicts need separate approval.

BACKUP AND RESTORE
------------------
Backups are stored in your Windows Documents folder:
  Documents\MOZA\MediocreAtBest Profile Backups\<date-time>

A new backup is created for each installation; existing backups are kept.
To restore, close MOZA Motion Manager, turn off motion, then run RESTORE.cmd
from the extracted installer folder and choose the appropriate backup.

RESTORE.cmd checks file hashes and stops instead of overwriting profiles
edited since installation. It preserves unrelated presets and does not
revert the car database if that database has subsequently changed.

TUNING AND COMPATIBILITY
------------------------
These settings are practical starting points, not calibrated real-world
vehicle measurements or certified safe limits. Verify rig clearance and
adjust the effects for your comfort and hardware.

The optional database update includes only 420 additional AMS2 records.
It adds missing entries to a verified local copy of your database using
Windows SQLite, preserves existing rows, and installs the local result.
An unsupported or unavailable database is left unchanged. No MOZA database
is included. Windows 10/11 is required for this database feature.

The package is intended for AMS2 with MOZA HMA150 / MOZA Motion Manager.
Some car names may require game DLC or community content.

For the complete car list and technical notes, see the repository README.
