# Release Follow-ups (post-parity-merge)

> **For agentic workers:** Phase A is user-operated (physical hardware) — record
> pass/fail per step, do not change code. Phase B is agent-executable
> (TDD, small diffs, full gate per fix). Phase C is release ops.

**Baseline:** `main` at `55bdcee` (16 parity commits merged) + Android repo
`main` at `b5c1d39` (4 BLE commits). iOS version `1.0` / build `1`;
Android `versionCode 1` / `versionName "1.0"` — match, no bump needed.
Full gates green at merge (iOS unit + UI `TEST SUCCEEDED`, Android `BUILD
SUCCESSFUL`, `swift test` 68/68).

**Reference:** spec `docs/superpowers/specs/2026-09-24-crossplay-ios-design.md`
(frozen GATT UUIDs — do NOT change); parent plan
`docs/superpowers/plans/2026-10-04-ios-parity-release.md` (Tasks 14/17/18
deferred its device steps here).

---

### Phase A: Hardware validation (user-operated, both physical — record only)

- [ ] **Step 1: iOS↔iOS BLE (2 iPhones, Debug builds, Bluetooth on)**
  1. A hosts (name → Host a game → PIN shows); B joins (name → Join → row ≤10s → PIN → game on both, first STATE renders).
  2. Full game, each side places ≥3 dice; force a destroy (match peer's column); boards agree every move.
  3. Play again from the loser side → both reset, names kept.
  4. Wrong PIN → "Wrong code. Try again." back on Start.
  5. Bluetooth off on join → "Bluetooth is off..." error; denied permission → permission error.
  6. Airplane mode mid-game → survivor shows "Peer disconnected", returns to Start.
  Expected: 6/6 pass. Failures become new tasks (do NOT fix inline).

- [ ] **Step 2: Cross-play (1 Android phone + 1 iPhone, Android on BLE transport)**
  1. Android hosts Classic: iPhone sees no peer (expected iOS-has-no-RFCOMM boundary).
  2. Android hosts BLE + iPhone joins BLE: full game, ≥3 dice each, destroy visible both, scores agree.
  3. iPhone hosts BLE + Android joins BLE: full game, same checks.
  4. Play again from loser (both directions) → reset, names kept.
  5. Wrong PIN → joiner sees "Wrong code. Try again."
  6. Airplane mode mid-game → survivor "Peer disconnected" + Start.
  Expected: 6/6 pass (step 1 passes by absence). Also watch the Android
  `transport` picker highlight: `transport` is a plain `var`, not
  `mutableStateOf` — if the highlight sticks after tapping BLE, file a task
  to promote it (do NOT fix inline).

- [ ] **Step 3: Screenshot set (DeviceHub, attach to release notes)**
  Start, mid-game with dice, destroy ghost visible, result overlay, iPad
  layout.
  Expected: 5 PNGs, die faces correct (1–6 per `DiceOrientation`), no
  black-on-dark text.

---

### Phase B: Parked code findings (agent-executable, one fix pass)

- [ ] **Step 1: Cancel generation guard** (`Knuckled/Connect/ConnectionSession.swift`)
  Residual race: `cancelCurrent()` between a blocking `listen`/`connect`
  return and its async `onConnected` dispatch can resurrect a cancelled
  session (no generation token). Add a generation counter: bump on every
  `cancelCurrent`/`disconnect`/`onPinEntered`-new-attempt; capture at op
  start; ignore `onConnected` when stale. Test:
  `testCancelBetweenReturnAndConnectedIsIgnored` (RED: stale completion
  routes to `.connected`; GREEN: stays `.start`). Full gate green.

- [ ] **Step 2: `writeSem` fail-fast** (`Knuckled/BLE/BleCentralClient.swift`)
  `signalFailure` does not signal `writeSem`, so a with-response handshake
  `send()` can block the full 5s before failing. Wire `signalFailure` to
  `writeSem` (keep the 5s timeout as the backstop). Test: failing handshake
  returns in well under 5s. Full gate green.

- [ ] **Step 3: `sync_project.py` basename guard** (`tools/sync_project.py`)
  Presence check keys on basename (`/* {name} */`), so same-name files in
  different dirs collide and the second silently skips registration.
  Scope the check by relative path (e.g. match `path = {fr_path}` lines or
  track registered rels). Test: add same-basename fixture in two dirs,
  `--check` fails before fix, passes after (then remove fixtures). No
  behavior change for existing files (`--check` stays green).

- [ ] **Step 4: Re-add `scan-status` coverage** (`KnuckledUITests/ConnectionFlowTests.swift`)
  The Discover status-path assertion was dropped as racy (fake returns
  instantly). Cover it at unit level instead: assert
  `ConnectionSession.statusText == "Searching for devices..."` synchronously
  after `onDiscoverClicked()` (before the background discover completes).
  Full gate green.

---

### Phase C: App Store submission (release ops)

- [ ] **Step 1: Confirm answers in App Store Connect**
  Tracking: NO (no IDFA/analytics/ads). Data collected: NONE (names/scores
  on-device; UserDefaults under declared `CA92.1`; peers ephemeral).
  Encryption: standard OS only (`ITSAppUsesNonExemptEncryption = false` —
  verify key present in `Knuckled/Info.plist`). Content: Games 4+ (no chat,
  no accounts; opponent names are typed session labels). Review notes:
  local multiplayer needs two physical devices; no demo account by design.
- [ ] **Step 2: Upload 1.0 (1) + Phase A screenshots, submit for review.**

---

### Done when

Phase A 12/12 checks recorded (failures triaged as tasks, not inline fixes);
Phase B merged with green gates; Phase C submitted. This file stays as the
release record — do not delete it after completion.
