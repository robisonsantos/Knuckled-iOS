# iOS App Design — Cross-Play BLE Contract + Native Swift App

Date: 2026-09-24

Native iOS app (iPhone + iPad) for Knuckled, cross-playing against the Android app over Bluetooth. iOS third-party apps cannot use Bluetooth Classic RFCOMM (the transport the Android app uses for Android↔Android), so cross-play rides on **BLE**, preserving the existing PIN handshake and newline-framed line protocol unchanged.

Mirror note: this spec is the iOS repo's copy of the cross-play contract. The Android repo (`~/AndroidStudioProjects/KnuckleGame`, `docs/superpowers/specs/2026-09-24-crossplay-ios-design.md`) carries the Android-side implementation of the same contract. The wire/JSON format is frozen; either repo may extend it only with a coordinated change.

## Goals

- iPhone/iPad ↔ Android cross-play over Bluetooth using the same PIN + line-protocol idea as the Android app.
- A native iOS app matching Android UX parity: two-player PvP, single-player vs CPU, name/PIN flow, rolling 3D die, sound, settings toggles (mute, animations, auto-roll), leave confirmation, win/lose/draw overlays, play-again keeps names.
- Vertically-stacked boards on every device (column-vs-column comparison is core to play).

## Non-goals (YAGNI)

- No RFCOMM on iOS (Android-only transport; Android↔Android keeps using it in the Android repo).
- No background-mode support: the app is played in the foreground on both devices.
- No OS-level BLE bonding beyond the app's own 4-digit PIN auth.
- No server/relay, no internet, no Game Center/iCloud.
- No change to the wire format, JSON schema, or game rules — frozen.

## Context

The Android link layer is byte-stream based: `Protocol` frames `\n`-terminated UTF-8 lines, `Handshake` does PIN accept/initiate over that stream, `GameLinkImpl` runs a reader dispatching lines to `onLine` and firing `onClosed`. The iOS app reproduces the same seam: a `GameLink` that hands complete lines to a handler, wrapped in a BLE transport.

## Part 1 — The BLE transport contract

### Roles

- **Host** = GATT *peripheral*: advertises the Knuckled service, accepts the connection, hosts the authoritative `GameHost`.
- **Client** = GATT *central*: scans for the service, connects, runs PIN handshake, renders `STATE` broadcasts.
- Android↔Android over BLE uses the same mapping (in the Android repo).

### GATT layout

One custom 128-bit service (frozen 2026-10-04 — do NOT change after first release):

| Element | UUID | Role |
|---|---|---|
| Service | `8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A` | Advertised by host; scan filter for client |
| Write Char | `AAF90241-0F50-42CF-ADFC-2BAADE92ACD1` | Write (+ WriteWithoutResponse post-handshake) — client → host message bytes |
| Notify Char | `3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA` | Read + Notify (subscribe via CCCD) — host → client message bytes |

### Framing over GATT

The `Protocol` line framing *is* the wire format (`\n`-terminated UTF-8, `MAX_FRAME_BYTES = 1024`). BLE only swaps the byte pipe:

- **Sender** chunks each line into consecutive GATT writes/notifications of at most (negotiated MTU − 3) bytes; falls back to 20-byte chunks when the peer MTU is unknown. No length prefix.
- **Receiver** appends chunks to a bounded buffer and splits on `\n` (immune to chunk boundaries cutting a line or a multi-byte UTF-8 character; byte-wise reassembly).
- BLE preserves ordering and reliability on a connected link, so the stream model holds exactly.
- Buffer capped at `MAX_FRAME_BYTES`; overflow is a fatal read error, matching Android behavior.
- MTU negotiation best-effort: iOS client `setMaximumWriteValueLength`/`maximumWriteValueLength`, iOS peripheral `maximumUpdateValueLength`. Framing must work even at 20-byte chunks.

### Discovery & auth

- Host advertises the service UUID (`CBPeripheralManager`; iOS may advertise UUID without a name).
- Client scans filtered on the service UUID (`CBCentralManager`); shows results by `CBPeripheral.name` + scan status.
- PIN (4 digits) gates the link exactly as Android: `Handshake.initiate`/`accept` ride the same byte-pipe. Wrong PIN → "Wrong code. Try again."

### Wire/JSON freeze

`STATE:` carries a JSON serialization of `GameState` with these exact property names and enum string values:

- `hostName: String`, `clientName: String`, `status` (`IN_PROGRESS|FINISHED|DRAW`), `currentTurn` (`HOST|CLIENT`), `phase` (`IDLE|ROLLING|AWAITING_PLACEMENT`), `grid: Map<HOST|CLIENT, List<[Int]>>` (3 columns, bottom-most die first), `winner: PlayerId|null`, `lastRoll: Int|null`, `destroyed: [{player, column, value}]`.
- Swift `Codable` must decode strictly (unknown field ⇒ invalid state, like Android's `decodeState` returning null). All fields present (Android encodes defaults).

Command lines: `NAME:<sanitized>`, `ROLL`, `PLACE:<0..2>`, `RESTART`, `STATE:<json>`.

## Part 2 — iOS app

Native Swift 6 / SwiftUI. iOS 17+ minimum, iPhone + iPad, both orientations. Xcode project at repo root. XCTest unit tests + XCUITest; physical devices required for real BLE validation (GATT signaling doesn't work between simulator instances).

### Code layout

| Path | Responsibility |
|---|---|
| `Knuckled/Models/` | `GameState`, `PlayerId`, `Status`, `Phase`, `Grid`, `DieRef` with strict `Codable` matching the frozen schema. |
| `Knuckled/Rules/` | `KnucklebonesRules` port: total/column score, roll/place validity, `canRoll`, status transitions. Fixtures mirrored from Android tests. |
| `Knuckled/Game/` | `GameHost`, `CpuPlayer`/`CpuClient` + human-feel pacing ports (single-player parity). |
| `Knuckled/Networking/` | `GameLink` (line semantics like `GameLinkImpl`), `MessageCodec` (NAME/ROLL/PLACE/RESTART/STATE), `Handshake`, `PinGenerator`. |
| `Knuckled/BLE/` | `BleConnector`: `CBPeripheralManager` (host) + `CBCentralManager` (client), MTU-aware chunking; `BleGameLink` on the byte-pipe contract. `NSBluetoothAlwaysUsageDescription` in Info.plist. |
| `Knuckled/Audio/` | `SoundManager` over AVFoundation; same `SoundEvent` set (TAP/RATTLE/LAND/WIN/LOSE), mute + loop semantics; ships the same `.wav` files as Android. |
| `Knuckled/Settings/` | `@AppStorage`: player name, mute, animations, auto-roll (3-dot), mirroring Android. |
| `Knuckled/Views/` | `StartView`, `HostingView` (PIN display), `DiscoverView` (device list + scan status), `GameView`, `RollArea`, `TurnPill`, `GameBoard`, `DestroyGhosts`, `Confetti`, `WinnerOverlay`, `DrawOverlay`, `LeaveConfirm`, `FeltBackground`, `GlassCard`, `GoldButton`, `PinDigits`; theme (gold/ivory/glass colors, `cinzel_bold.ttf`). |

### 3D die

`DiceRoller3D` hosts **SceneKit** `SceneView` loading a SceneKit-compatible conversion of `models/dice.glb` (ModelIO / Reality Converter → check in a `.usdz`), replicating `getRotationForFace`, the ~2 s X/Y spin with randomized velocity, camera on +Z, tap gesture, and LAND/RATTLE sound hooks.

**Asset spike (first task of the polish phase):** validate `dice.glb` → loadable model before UI work. Fallback if conversion fails: SceneKit-built die geometry (same behavior and orientation table, no asset dependency).

### iPad

Vertically-stacked boards on every device. Regular width: content constrained to ~560 pt and centered. No side-by-side layout.

## Part 3 — Errors, edge cases, testing

### Edge cases

- Bluetooth off / permission denied / advertising unsupported / empty scan → clear error banner.
- Wrong PIN → "Wrong code. Try again."
- Mid-game drop (`didDisconnectPeripheral` → `onClosed`) → peer-disconnected banner + leave, same as Android.
- Oversized line / buffer overflow → fatal read, disconnect, banner.
- Foreground-only; no `UIBackgroundModes`. Screen lock / backgrounding during a game degrades to a disconnect handled by the banner.

### Testing

- **XCTest unit:** rules port (Android-mirrored fixtures), codec strict decoding, chunk reassembly, handshake.
- **XCUITest (simulator):** connection→game→overlay choreography over an in-memory/fake link (no radio).
- **Fakes:** `LocalPipe`/`FakeGamePeer`/`FakeSoundManager` equivalents in Swift so simulator and test flows exercise the full loop without radios.
- **Cross-play conformance (physical hardware, scripted choreography doc in the Android repo):** Android↔iOS both host directions; each pairing — happy path, wrong PIN, mid-game leave, play-again restart.
- Simulators cannot run real GATT between each other; BLE integration testing is device-only by design.

## Part 4 — Phasing

The iOS implementation plans follow, each independently testable:

1. **iOS core** — Xcode project scaffold; `Models`/`Rules`/`Networking`/`Game` ports with unit tests; fake-link game loop runnable on simulator (no radio).
2. **iOS BLE + cross-play** — CoreBluetooth host/client, Info.plist keys, `BleGameLink`; cross-play validation with the Android app on hardware (both host directions).
3. **iOS parity polish** — SceneKit die (asset spike first), audio, settings toggles, iPad sizing, CPU mode, XCUITest, release config.

The Android BLE transport phase is tracked in the Android repo (its plan: Android BLE connector + transport toggle UI).

## Assets shared unchanged (sourced from the Android repo)

- `app/src/main/assets/models/dice.glb` (plus a checked-in `.usdz` conversion for iOS).
- `app/src/main/res/raw/tap.wav`, `rattle.wav`, `land.wav`, `win.wav`, `lose.wav`.
- `app/src/main/res/font/cinzel_bold.ttf`.
- Theme colors — exact values in Android `ui/theme/Color.kt` (Gold, Ivory, GlassWhite, GlassBorderGold, DieIvoryLight, …).