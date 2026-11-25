# Validation summary

The project includes automated validation for the generated profile library and installer package, Windows PowerShell 5.1 fixture tests and a successful installation reported by the author on the intended gaming PC (25 November 2026). A successful installation is not proof of live restoration or physical motion behaviour across every vehicle.

## File checks

| Check | Verified result |
|---|---|
| Motion profile JSONs | 42 named P01-P42 |
| Vehicle assignments | 565 distinct car names, each in one profile |
| Class mapping | 204 observed AMS2 class codes and 10 documented car-level exceptions |
| Profile identity | 42 unique UUIDs |
| Master-to-profile settings | 840 exact comparisons (20 settings per profile) |
| Platform targets | `maxMotionAngle=35`, `tactileFeedbackValue=35` in all 42 |
| Acceleration filtering | `AccToRoll.Flatness=20`, `AccToPitch.Flatness=20` in all 42 |
| Conservative movement | Body Roll 10–30, Pitch 20–29, Heave 5–10, Acceleration Roll/Pitch 10–14; user-tested Formula V10 is the minimum-motion reference |
| Profile discoverability | AMS2 class names first, familiar aliases and useful years retained |
| Engine vibration | 160 Hz common carrier, not calculated from RPM |
| Database integrity | 420 exact AMS2-only delta records; no MOZA database included; native Windows SQLite insertion and restoration fixture tests passed |
| Installer archive | Packaged files compared against repository sources and hashes |

## Windows validation

| Check | Result |
|---|---|
| Package, manifests, profiles and database delta | PASS |
| Windows PowerShell 5.1 syntax | PASS |
| Non-destructive restore fixtures | PASS |
| Installed-profile replacement and rollback fixtures | PASS |
| Native SQLite insertion and database restore fixtures | PASS |
| Installation on the author's Windows PC | Successful, as reported by the author |

All automated checks passed in the GitHub Actions workflow for the tested installer. The installation report does not independently establish how many database rows were inserted on the gaming PC or verify live restoration.

## Local checks still required

- Verify the profile names, assignments and platform settings in MOZA Motion Manager.
- Verify physical clearances, motion strength and comfort on your own rig.
- Test live backup recovery where needed, and recheck compatibility after MOZA Motion Manager or AMS2 updates.

The fixture tests are included under `tests/` and do not substitute for hardware testing.
