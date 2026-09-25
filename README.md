# KnuckleGame-ios

Native iOS app (iPhone + iPad) for **Knuckled**, the Knucklebones dice game, cross-playing against the Android app (`KnuckleGame`) over Bluetooth.

Knucklebones: two 3×3 boards, roll-then-place turns, same-value destruction across opposing columns, highest score when a board fills wins. Full rules in the design spec.

## Cross-play

- iOS ↔ Android over **BLE** (iOS cannot use Bluetooth Classic RFCOMM, so BLE is the shared transport) with the same 4-digit PIN handshake and newline-framed line protocol from the Android app.
- The wire contract and JSON schema are frozen; this repo's `docs/superpowers/specs/` mirrors the contract, and the Android repo (`~/AndroidStudioProjects/KnuckleGame`) carries the Android-side implementation of it.
- Android BLE transport work (host=peripheral/client=central on Android) is tracked in the Android repo; the cross-play pairing is validated with both apps on physical hardware.

## Docs

- `docs/superpowers/specs/` — design specs.
- `docs/superpowers/plans/` — implementation plans.