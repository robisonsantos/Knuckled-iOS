# iOS Parity + Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the iOS Knuckled app to full Android parity and main-release readiness: app shell polish (icon, settings, top bar, haptics), sound engine, 3D SceneKit die, full connection UX (Host/Join/PIN over fake transport in-simulator), CoreBluetooth BLE transport for real PvP cross-play with Android, the Android-side BLE connector, and App Store release readiness.

**Architecture:** Additive layers on the existing solo app (all solo behavior stays green throughout). New `Knuckled/Connect/` (connector protocol + fake + session state machine + screens), `Knuckled/BLE/` (frozen UUIDs, framing, byte pipe, peripheral host, central client, connector facade), `Knuckled/Audio/` (sound engine), `Knuckled/Die3D/` (orientation map + SceneKit view), `Knuckled/Store/` (settings). `GameSession` becomes link-injected (host/client roles) with the solo path preserved as a convenience. A `tools/sync_project.py` script registers every new file in the `.pbxproj` deterministically (hand-editing project files does not scale past this point).

**Tech Stack:** Swift 5 language mode, SwiftUI, Combine, SceneKit, AVFoundation, CoreBluetooth, XCTest + XCUITest, iOS 17+, `xcodebuild`/`xcrun simctl` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Android side: Kotlin, `BluetoothGatt`/`BluetoothGattServer`, `./gradlew :app:test` + `assembleDebug`.

**Reference:** Android original at `/Users/robison/AndroidStudioProjects/KnuckleGame` (connection flow: `ui/ConnectionViewModel.kt`, `ui/ConnectionScreens.kt`, `ui/components/PinDigits.kt`; transport: `bluetooth/BluetoothConnector.kt`, `bluetooth/AndroidBluetoothConnector.kt`, `bluetooth/GameLink.kt`, `bluetooth/Protocol.kt`, `bluetooth/Handshake.kt`, `bluetooth/LocalConnector.kt`, `bluetooth/FakeBluetoothConnector.kt`, `game/GameMessages.kt`, `game/GameHost.kt`, `game/CpuClient.kt`; audio: `audio/AndroidSoundManager.kt`, `res/raw/*.wav`; die: `ui/dice/DiceCube.kt`, `assets/models/dice.glb`; theme: `ui/theme/Color.kt`, `ui/theme/Type.kt`; settings: `settings/Settings.kt`). Design spec: `docs/superpowers/specs/2026-09-24-crossplay-ios-design.md` (frozen GATT UUIDs in the GATT layout table; foreground-only, no background modes).

**Environment rule (every task):** `xcode-select` points at CommandLineTools and `sudo` is unavailable. Prefix EVERY `xcodebuild`/`xcrun`/`swift` invocation with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Bare `xcodebuild`/`swift test` fail on this machine.

**SwiftUI gotchas (carry-over, apply everywhere):** (1) Never call `.opacity()` on a concrete `Color`/`LinearGradient` — hoist to a View-typed chain or use `Color(red:green:blue:opacity:)`. (2) `KnuckledCore.Grid` collides with `SwiftUI.Grid` — always qualify in views. (3) Font PostScript names must match the variable-font instance (`CinzelRoman-Bold`). (4) XCUITest queries: board identifiers stamp every child — query in-board elements by LABEL; columns that need taps must be real `Button`s; use explicit label predicates + poll loops (KVO `count` on queries is unreliable); `app.terminate()` before `app.launch()` for determinism.

---

### Task 0: Environment preflight

**Files:** none (verification only)

- [ ] **Step 1: Verify toolchain, simulator, repos**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available | grep -i "iphone 17 (" | head -2`
Expected: an `iPhone 17` line (any state).

Run: `git log --oneline -1 && ls Knuckled.xcodeproj Package.swift && ls /Users/robison/AndroidStudioProjects/KnuckleGame/app/src/main/java/com/example/knucklegame/bluetooth/`
Expected: main at/after the solo merge, project + package present, Android `bluetooth/` listing shows `AndroidBluetoothConnector.kt BluetoothConnector.kt FakeBluetoothConnector.kt GameLink.kt Handshake.kt LocalConnector.kt LocalPipe.kt Protocol.kt`.

---

### Task 1: Project sync script + privacy manifest + Bluetooth usage string

**Files:**
- Create: `tools/sync_project.py`
- Create: `Knuckled/PrivacyInfo.xcprivacy`
- Modify: `Knuckled/Info.plist` (add Bluetooth string)
- Modify: `Knuckled.xcodeproj/project.pbxproj` (via the script only)

- [ ] **Step 1: Write `tools/sync_project.py`**

A deterministic, idempotent registrar: scans `Knuckled/**/*.swift`, `Knuckled/**/*.ttf`, `Knuckled/**/*.wav`, `Knuckled/**/*.usdz`, `Knuckled/**/*.xcassets`, `Knuckled/*.xcprivacy`, `Knuckled/*.plist` (excluding `Info.plist`, which is referenced, not copied) and inserts any missing entries into `project.pbxproj` with stable IDs (`uuid5` of the relative path, namespaced per object kind). Swift sources go to their target's Sources phase by directory (`Knuckled/` → app, `KnuckledTests/` → unit, `KnuckledUITests/` → UI tests); resources go to the app Resources phase. Re-running changes nothing.

```python
#!/usr/bin/env python3
"""Sync new source/resource files into Knuckled.xcodeproj/project.pbxproj.

Usage: python3 tools/sync_project.py [--check]
  --check: exit 1 if anything is missing (CI gate), else add it.
Idempotent: stable IDs derived from paths, so re-runs are no-ops.
"""
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "Knuckled.xcodeproj" / "project.pbxproj"

NS = {
    "fileref": uuid.UUID("11111111-1111-4111-8111-111111111111"),
    "buildfile": uuid.UUID("22222222-2222-4222-8222-222222222222"),
    "group": uuid.UUID("33333333-3333-4333-8333-333333333333"),
}


def oid(kind: str, rel: str) -> str:
    return uuid.uuid5(NS[kind], rel).hex[:24].upper()


# target dir -> (sources phase id, group id, group path)
SOURCES = {
    "Knuckled": ("430000000000000000000001", "400000000000000000000002", "Knuckled"),
    "KnuckledTests": ("430000000000000000000004", "400000000000000000000003", "KnuckledTests"),
    "KnuckledUITests": ("430000000000000000000007", "400000000000000000000004", "KnuckledUITests"),
}
RES_PHASE = "430000000000000000000002"
RES_GROUP = "400000000000000000000006"  # Knuckled/Resources

FILETYPE = {
    ".swift": "sourcecode.swift",
    ".ttf": "file",
    ".wav": "audio.wav",
    ".usdz": "file",
    ".xcassets": "folder.assetcatalog",
    ".xcprivacy": "text.plist.xml",
}


def want_files():
    out = []  # (relpath-posix, kind[target-dir or "Resources"], filetype)
    for sub in ("Knuckled", "KnuckledTests", "KnuckledUITests"):
        d = ROOT / sub
        if not d.is_dir():
            continue
        for p in sorted(d.rglob("*")):
            if p.is_dir():
                if p.suffix == ".xcassets":
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[".xcassets"]))
                continue
            if p.suffix in FILETYPE and not (sub == "Knuckled" and p.name == "Info.plist"):
                kind = "Resources" if p.suffix not in (".swift",) and sub == "Knuckled" and p.parent.name == "Resources" else None
                if p.suffix == ".swift":
                    out.append((p.relative_to(ROOT).as_posix(), sub, FILETYPE[".swift"]))
                elif p.suffix in (".ttf", ".wav", ".usdz"):
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[p.suffix]))
                elif p.suffix == ".xcprivacy":
                    out.append((p.relative_to(ROOT).as_posix(), "Resources", FILETYPE[".xcprivacy"]))
    return out


def main() -> int:
    check_only = "--check" in sys.argv
    text = PBX.read_text()
    changed = False

    for rel, target, ftype in want_files():
        if rel in text:
            continue
        if target == "Resources":
            phase, group = RES_PHASE, RES_GROUP
            group_path = "Knuckled/Resources"
        else:
            phase, group, group_path = SOURCES[target]
        fr = oid("fileref", rel)
        bf = oid("buildfile", rel)
        name = Path(rel).name
        if target == "Resources":
            fr_line = f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {name}; sourceTree = \"<group>\"; }};\n"
        else:
            fr_line = f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {name}; sourceTree = \"<group>\"; }};\n"
        bf_comment = "in Resources" if target == "Resources" else "in Sources"
        bf_line = f"\t\t{bf} /* {name} {bf_comment} */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n"
        text = text.replace("/* End PBXFileReference section */", fr_line + "/* End PBXFileReference section */")
        text = text.replace("/* End PBXBuildFile section */", bf_line + "/* End PBXBuildFile section */")
        # append file to phase + group (before closing ");")
        phase_anchor = f"\t\t{phase} /* {'Resources' if target == 'Resources' else 'Sources'} */ = {{\n"
        text = text.replace(
            phase_anchor + "\t\t\tisa = PB",
            phase_anchor + "\t\t\tisa = PB", 1,
        )
        # insert into files list: find phase block, insert before "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing"
        phase_pat = re.compile(
            r"(\t\t" + phase + r" /\*.*?\*/ = \{\n(?:.*?\n)*?\t\t\tfiles = \(\n)(.*?)(\t\t\t\);\n)",
            re.DOTALL,
        )

        def add_file(m):
            return m.group(1) + m.group(2) + f"\t\t\t\t{bf} /* {name} {bf_comment} */,\n" + m.group(3)

        text, n = phase_pat.subn(add_file, text, count=1)
        assert n == 1, f"phase block not found for {phase}"
        # group children: insert before the group's closing "\t\t\t);\n\t\t\tpath = " or name line
        group_pat = re.compile(
            r"(\t\t" + group + r" /\*.*?\*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n)",
            re.DOTALL,
        )

        def add_child(m):
            return m.group(1) + m.group(2) + f"\t\t\t\t{fr} /* {name} */,\n" + m.group(3)

        text, n2 = group_pat.subn(add_child, text, count=1)
        assert n2 == 1, f"group block not found for {group}"
        changed = True
        print(f"registered {rel}")

    if changed and not check_only:
        PBX.write_text(text)
        print("project.pbxproj updated")
    elif changed:
        print("MISSING entries (run without --check to add)")
        return 1
    else:
        print("project in sync (no changes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

(Note: the leftover no-op `phase_anchor` replace is intentional dead code kept minimal — it replaces a string with itself and changes nothing; the real insertions are the `files`/`children` regexes. Do not "clean it up" into behavior change.)

- [ ] **Step 2: Write `Knuckled/PrivacyInfo.xcprivacy`** (required-reason API declaration for UserDefaults; no tracking):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Add the Bluetooth usage string to `Knuckled/Info.plist`** (insert before `</dict>`):

```xml
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Knuckled uses Bluetooth to find and connect to the other player's phone for local multiplayer games.</string>
```

- [ ] **Step 4: Register + verify**

Run: `python3 tools/sync_project.py && python3 tools/sync_project.py --check && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project Knuckled.xcodeproj`
Expected: script reports the new `PrivacyInfo.xcprivacy` registered, second run exits 0 with "in sync", `-list` still shows 3 targets + `Knuckled` scheme. (Full build comes later — Swift task files don't exist yet.)

- [ ] **Step 5: Commit**

```bash
git add tools/sync_project.py Knuckled/PrivacyInfo.xcprivacy Knuckled/Info.plist Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: project sync script, privacy manifest, BT usage string"
```
```bash
git add tools/sync_project.py Knuckled/PrivacyInfo.xcprivacy Knuckled/Info.plist Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: project sync script, privacy manifest, BT usage string"
```

---

### Task 2: SettingsStore + tests

**Files:**
- Create: `Knuckled/SettingsStore.swift`
- Test: `KnuckledTests/SettingsStoreTests.swift`

Mirrors Android `settings/Settings.kt` (SharedPreferences `"knucklegame"` keys `muted`/`auto_roll`/`onboarding_seen`, all default `false`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled

final class SettingsStoreTests: XCTestCase {

    private func freshStore() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "test-\(UUID().uuidString)")
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testDefaultsAreAllFalse() {
        let (store, _) = freshStore()
        XCTAssertFalse(store.muted)
        XCTAssertFalse(store.autoRoll)
        XCTAssertFalse(store.onboardingSeen)
    }

    func testTogglesPersistAndReload() {
        let (_, defaults) = freshStore()
        let store = SettingsStore(defaults: defaults)
        store.muted = true
        store.autoRoll = true
        store.onboardingSeen = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.muted)
        XCTAssertTrue(reloaded.autoRoll)
        XCTAssertTrue(reloaded.onboardingSeen)
    }

    func testSuitesAreIsolated() {
        let (a, _) = freshStore()
        let (b, _) = freshStore()
        a.muted = true
        XCTAssertFalse(b.muted)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KnuckledTests/SettingsStoreTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: FAIL — `SettingsStore` undefined (compile error).

- [ ] **Step 3: Implement `Knuckled/SettingsStore.swift`**

```swift
import Foundation
import Combine

/// Persisted toggles (Android parity: SharedPreferences "knucklegame").
/// All defaults are false, matching Android's Settings + SettingsTest.
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Keys.muted) } }
    @Published var autoRoll: Bool { didSet { defaults.set(autoRoll, forKey: Keys.autoRoll) } }
    @Published var onboardingSeen: Bool { didSet { defaults.set(onboardingSeen, forKey: Keys.onboardingSeen) } }

    private enum Keys {
        static let muted = "knuckled.muted"
        static let autoRoll = "knuckled.autoRoll"
        static let onboardingSeen = "knuckled.onboardingSeen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.muted = defaults.bool(forKey: Keys.muted)
        self.autoRoll = defaults.bool(forKey: Keys.autoRoll)
        self.onboardingSeen = defaults.bool(forKey: Keys.onboardingSeen)
    }
}
```

- [ ] **Step 4: Register + run**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KnuckledTests/SettingsStoreTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4`
Expected: script registers the 2 files; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Knuckled/SettingsStore.swift KnuckledTests/SettingsStoreTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: persisted settings store (muted, auto-roll, onboarding)"
```

---

### Task 3: Sound engine + triggers

**Files:**
- Copy: 5 Android wavs → `Knuckled/Resources/Sounds/` (`tap.wav rattle.wav land.wav win.wav lose.wav`)
- Create: `Knuckled/SoundManager.swift`
- Modify: `Knuckled/GameScreen.swift` (die-tap TAP + phase-driven rattle/land), `Knuckled/ResultOverlays.swift` (WIN/LOSE on appear), `Knuckled/KnuckledApp.swift` (inject manager + seed mute)
- Test: `KnuckledTests/SoundManagerTests.swift`

Trigger map (Android-exact): TAP on die tap only; RATTLE loop while ROLLING; LAND on settle; WIN/LOSE once on WinnerOverlay appear (winner hears WIN, loser LOSE); DrawOverlay silent; placement/destroy/turn-change silent. Mute suppresses everything incl. killing an active rattle loop.

- [ ] **Step 1: Copy sounds + write the failing tests**

Run: `mkdir -p Knuckled/Resources/Sounds && cp /Users/robison/AndroidStudioProjects/KnuckleGame/app/src/main/res/raw/*.wav Knuckled/Resources/Sounds/ && ls Knuckled/Resources/Sounds/`
Expected: 5 wavs listed.

```swift
import XCTest
@testable import Knuckled

final class SoundManagerTests: XCTestCase {

    func testFakeRecordsPlaysAndLoops() {
        let sound = FakeSoundManager()
        sound.play(.tap)
        sound.startLoop(.rattle)
        XCTAssertEqual(sound.played, [.tap])
        XCTAssertEqual(sound.looping, .rattle)
        sound.stopLoop()
        XCTAssertNil(sound.looping)
    }

    func testMutedSuppressesEverythingAndKillsLoop() {
        let sound = FakeSoundManager()
        sound.startLoop(.rattle)
        sound.setMuted(true)
        XCTAssertTrue(sound.isMuted)
        XCTAssertNil(sound.looping)
        sound.play(.win)
        sound.startLoop(.land)
        XCTAssertTrue(sound.played.isEmpty)
        XCTAssertNil(sound.looping)
    }

    func testUnmutingResumesPlayback() {
        let sound = FakeSoundManager()
        sound.setMuted(true)
        sound.setMuted(false)
        sound.play(.lose)
        XCTAssertEqual(sound.played, [.lose])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Same `xcodebuild test -only-testing:KnuckledTests/SoundManagerTests` command shape as Task 2.
Expected: FAIL — `SoundManager`/`FakeSoundManager`/`SoundEvent` undefined.

- [ ] **Step 3: Implement `Knuckled/SoundManager.swift`**

```swift
import Foundation
import SwiftUI
import AVFoundation
import Combine

public enum SoundEvent: Equatable { case tap, rattle, land, win, lose }

public protocol SoundManager: AnyObject {
    var isMuted: Bool { get }
    func setMuted(_ muted: Bool)
    func play(_ event: SoundEvent)
    func startLoop(_ event: SoundEvent)
    func stopLoop()
}

public final class NoopSoundManager: SoundManager {
    public init() {}
    public var isMuted: Bool { true }
    public func setMuted(_ muted: Bool) {}
    public func play(_ event: SoundEvent) {}
    public func startLoop(_ event: SoundEvent) {}
    public func stopLoop() {}
}

/// Test double mirroring Android's FakeSoundManager (records + loop state).
final class FakeSoundManager: SoundManager {
    private(set) var played: [SoundEvent] = []
    private(set) var looping: SoundEvent?
    var isMuted = false

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { looping = nil }
    }

    func play(_ event: SoundEvent) {
        if !isMuted { played.append(event) }
    }

    func startLoop(_ event: SoundEvent) {
        if !isMuted { looping = event }
    }

    func stopLoop() { looping = nil }
}

/// Production engine (Android parity: SoundPool maxStreams 3, USAGE_GAME,
/// volume/rate pinned 1.0, rattle loops infinitely, mute kills the loop).
public final class AVFoundationSoundManager: SoundManager {
    private var players: [SoundEvent: AVAudioPlayer] = [:]
    private var loopEvent: SoundEvent?
    public private(set) var isMuted: Bool
    private let onMutedChanged: (Bool) -> Void

    public init(bundle: Bundle = .main, muted: Bool, onMutedChanged: @escaping (Bool) -> Void = { _ in }) {
        self.isMuted = muted
        self.onMutedChanged = onMutedChanged
        let files: [(SoundEvent, String)] = [
            (.tap, "tap"), (.rattle, "rattle"), (.land, "land"), (.win, "win"), (.lose, "lose"),
        ]
        for (event, name) in files {
            if let url = bundle.url(forResource: name, withExtension: "wav"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = 1
                player.prepareToPlay()
                players[event] = player
            }
        }
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { stopLoop() }
        onMutedChanged(muted)
    }

    public func play(_ event: SoundEvent) {
        guard !isMuted else { return }
        if event == .rattle {
            startLoop(event)
            return
        }
        players[event]?.play()
    }

    public func startLoop(_ event: SoundEvent) {
        guard !isMuted else { return }
        stopLoop()
        if let player = players[event] {
            player.numberOfLoops = -1
            player.play()
            loopEvent = event
        }
    }

    public func stopLoop() {
        if let loopEvent { players[loopEvent]?.stop() }
        loopEvent = nil
    }
}

struct SoundManagerKey: EnvironmentKey {
    static let defaultValue: SoundManager = NoopSoundManager()
}

extension EnvironmentValues {
    var soundManager: SoundManager {
        get { self[SoundManagerKey.self] }
        set { self[SoundManagerKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Wire triggers (edits to existing files)**

In `Knuckled/GameScreen.swift`: add `@Environment(\.soundManager) private var sound` to `GameScreen`. Change the `DieView` `onTap` to `{ sound.play(.tap); session.roll() }`. Add a phase task (place next to the `.task(id: session.state?.status)` block):
```swift
        .task(id: session.state?.phase) {
            guard session.state?.phase == .ROLLING else {
                sound.stopLoop()
                if session.state?.phase == .AWAITING_PLACEMENT { sound.play(.land) }
                return
            }
            sound.startLoop(.rattle)
        }
```
In `Knuckled/ResultOverlays.swift`: add `@Environment(\.soundManager) private var sound` to `WinnerOverlay` + `.task { sound.play(isWinner ? .win : .lose) }` on its root `ZStack` (compute `isWinner` before the stack as today). `DrawOverlay` stays silent.
In `Knuckled/KnuckledApp.swift`: create the store + manager and inject both:
```swift
    @StateObject private var session = GameSession()
    @StateObject private var settings = SettingsStore()
    private var sound: AVFoundationSoundManager {
        AVFoundationSoundManager(muted: settings.muted, onMutedChanged: { settings.muted = $0 })
    }
```
Hmm — computed `sound` rebuilds the manager (reloading wavs) on every body evaluation. Fix: build once with `@StateObject`-style ownership. `AVFoundationSoundManager` is not ObservableObject... simplest correct: `private let sound = AVFoundationSoundManager(muted: SettingsStore().muted, onMutedChanged: { SettingsStore().muted = $0 })`? Two store instances diverge! Correct approach: single shared store instance owned by App, manager owned alongside:
```swift
    @StateObject private var session = GameSession()
    @StateObject private var settings = SettingsStore()
    @State private var sound: AVFoundationSoundManager?

    var body: some Scene {
        WindowGroup {
            ZStack {
                ...
            }
            .environmentObject(settings)
            .environment(\.soundManager, soundManager)
            .onAppear {
                if sound == nil {
                    sound = AVFoundationSoundManager(
                        muted: settings.muted,
                        onMutedChanged: { [settings] in settings.muted = $0 }
                    )
                }
            }
        }
    }

    private var soundManager: SoundManager { sound ?? NoopSoundManager() }
```
Wait — `onMutedChanged: { [settings] in ... }` captures @StateObject wrapper, not the store! Must capture the store value: restructure — create both in `init`:
```swift
    @StateObject private var session = GameSession()
    @StateObject private var settings: SettingsStore
    private let sound: AVFoundationSoundManager

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        sound = AVFoundationSoundManager(muted: settings.muted, onMutedChanged: { settings.muted = $0 })
    }
```
Clean: one store, manager writes back into it, views observe the store. Use EXACTLY this init form. Body applies `.environmentObject(settings)` + `.environment(\.soundManager, sound)`.

- [ ] **Step 5: Register + run**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KnuckledTests/SoundManagerTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4`
Expected: script registers new files; `Executed 3 tests, with 0 failures`. (Audible verification is manual by the user in Phase G — simulator audio routes to the Mac.)

- [ ] **Step 6: Commit**

```bash
git add Knuckled/SoundManager.swift KnuckledTests/SoundManagerTests.swift Knuckled/GameScreen.swift Knuckled/ResultOverlays.swift Knuckled/KnuckledApp.swift Knuckled/Resources/Sounds/ Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: sound engine with Android trigger parity"
```

---

### Task 4: Shell polish (top bar, haptics, keyboard, hint, overlay IDs)

**Files:**
- Create: `Knuckled/Haptics.swift`
- Modify: `Knuckled/GameScreen.swift` (mute/auto-roll buttons, auto-roll task, turn haptics), `Knuckled/StartScreen.swift` (ScrollView + hint card + name-error ID), `Knuckled/ResultOverlays.swift` (button IDs), `Knuckled/KnuckledApp.swift` (already has settings/sound from Task 3 — no change needed unless missing)

- [ ] **Step 1: Create `Knuckled/Haptics.swift`** (Android parity: 150ms one-shot on your turn; iOS has no duration API — medium impact is the documented approximation):

```swift
import UIKit

/// Turn haptics (Android parity: 150ms one-shot vibration on your turn).
enum Haptics {
    static func turn() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
```

- [ ] **Step 2: GameScreen edits** — add `@EnvironmentObject private var settings: SettingsStore` (App already injects it in Task 3). Replace `topBar` with leading Leave + trailing auto-roll + mute:
```swift
    private var topBar: some View {
        HStack {
            Button("Leave") { showLeaveConfirm = true }
                .accessibilityIdentifier("leave")
            Spacer()
            Button(action: { settings.autoRoll.toggle() }) {
                Image(systemName: "dice")
                    .foregroundStyle(settings.autoRoll ? AppColors.gold : AppColors.ivory.opacity(0.5))
            }
            .accessibilityIdentifier("auto-roll")
            .accessibilityLabel(settings.autoRoll ? "Auto-roll on" : "Auto-roll off")
            Button(action: {
                sound.setMuted(!sound.isMuted)
                settings.muted = sound.isMuted
            }) {
                Image(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(AppColors.gold)
            }
            .accessibilityIdentifier("mute")
        }
        .padding(.horizontal, 8)
    }
```
Add auto-roll driver next to the other `.task` blocks (Android-exact, including the non-empty-boards guard that prevents auto-firing the very first turn):
```swift
        .task(id: session.state) {
            guard settings.autoRoll,
                  let s = session.state,
                  s.status == .IN_PROGRESS, s.phase == .IDLE, s.currentTurn == session.myId,
                  s.grid.values.contains(where: { $0.contains(where: { !$0.isEmpty }) })
            else { return }
            session.roll()
        }
```
Add turn haptics:
```swift
        .onChange(of: session.state?.currentTurn) { _, newTurn in
            if session.state?.status == .IN_PROGRESS, newTurn == session.myId {
                Haptics.turn()
            }
        }
```
(`onChange(of:_:_:)` two-parameter form is iOS 17+; target is 17.0 so it compiles.)

- [ ] **Step 3: StartScreen edits** — add `@EnvironmentObject private var settings: SettingsStore`; wrap the content `VStack` in a `ScrollView` + `.scrollDismissesKeyboard(.interactively)` on it; insert the hint card between title and name field:
```swift
                if !settings.onboardingSeen {
                    GlassCard {
                        HStack {
                            Text("Host on one phone, join from the other — when a 3x3 grid fills up, the highest score wins.")
                                .font(.caption)
                            Spacer()
                            Button(action: { settings.onboardingSeen = true }) {
                                Image(systemName: "xmark")
                            }
                            .accessibilityIdentifier("hint-dismiss")
                        }
                        .padding(12)
                    }
                    .accessibilityIdentifier("hint-card")
                }
```
Name error `Text(error)` gains `.accessibilityIdentifier("name-error")`.

- [ ] **Step 4: Overlay button IDs** — in both `WinnerOverlay` and `DrawOverlay`: Play again button += `.accessibilityIdentifier("play-again")`; Disconnect button += `.accessibilityIdentifier("disconnect")`.

- [ ] **Step 5: Register + verify existing suite still green**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: all suites green (unit 7+ + UI 3; counts grow with earlier tasks).

- [ ] **Step 6: Commit**

```bash
git add Knuckled/Haptics.swift Knuckled/GameScreen.swift Knuckled/StartScreen.swift Knuckled/ResultOverlays.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: top-bar controls, haptics, keyboard, hint, overlay IDs"
```

---

### Task 5: App icon

**Files:**
- Create: `tools/make_icon.swift`, `Knuckled/Assets.xcassets/AppIcon.appiconset/Contents.json`, generated `Knuckled/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

Icon concept (mirrors Android `ic_launcher_foreground`: ivory rounded die + 3 gold pips diagonal on felt-dark). Generated headlessly with CoreGraphics — no art tools needed.

- [ ] **Step 1: Write `tools/make_icon.swift`**

```swift
import AppKit
import CoreGraphics

// Generates Knuckled/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Felt-dark background.
ctx.setFillColor(CGColor(red: 0x07/255, green: 0x1A/255, blue: 0x10/255, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: size))

// Ivory die, centered, slightly rotated like a tossed die.
ctx.saveGState()
ctx.translateBy(x: size.width / 2, y: size.height / 2)
ctx.rotate(by: -12 * .pi / 180)
let die = CGRect(x: -280, y: -280, width: 560, height: 560)
let diePath = CGPath(roundedRect: die, cornerWidth: 110, cornerHeight: 110, transform: nil)
ctx.setFillColor(CGColor(red: 0xFF/255, green: 0xFA/255, blue: 0xF0/255, alpha: 1))
ctx.addPath(diePath)
ctx.fillPath()
// 3 gold pips, diagonal.
ctx.setFillColor(CGColor(red: 0xE2/255, green: 0xC2/255, blue: 0x6A/255, alpha: 1))
for (dx, dy) in [(-150, 150), (0, 0), (150, -150)] as [(CGFloat, CGFloat)] {
    ctx.fillEllipse(in: CGRect(x: dx - 62, y: dy - 62, width: 124, height: 124))
}
ctx.restoreGState()
image.unlockFocus()

let out = URL(fileURLWithPath: "Knuckled/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("encode failed")
}
CGImageDestinationAddImage(dest, cg, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out.path)")
```

- [ ] **Step 2: Contents.json + generate**

`Knuckled/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```
Run: `mkdir -p Knuckled/Assets.xcassets/AppIcon.appiconset && swift tools/make_icon.swift && ls -la Knuckled/Assets.xcassets/AppIcon.appiconset/`
Expected: prints the wrote path; PNG exists (~1 MB).

- [ ] **Step 3: Register + build proof**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/KnuckledDD build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **` (asset catalog compiles; no `ASSETCATALOG_COMPILER_APPICON_NAME` setting needed — Xcode derives the icon from the catalog's appiconset automatically).

- [ ] **Step 4: Home-screen evidence**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install booted /tmp/KnuckledDD/Build/Products/Debug-iphonesimulator/Knuckled.app && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io booted screenshot /tmp/knuckled-home.png`
Expected: install succeeds. Inspect `/tmp/knuckled-home.png` yourself (read the image): the Knuckled home-screen icon must show the gold die motif, not the wireframe placeholder.

- [ ] **Step 5: Commit**

```bash
git add tools/make_icon.swift Knuckled/Assets.xcassets/ Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: generated app icon"
```
```bash
git add tools/make_icon.swift Knuckled/Assets.xcassets/ Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: generated app icon"
```

---

### Task 6: Die asset (convert glb → usdz, procedural fallback)

**Files:**
- Create: `Knuckled/Resources/dice.usdz` (converted) OR `Knuckled/Resources/DiceFaces/{1,2,3,4,5,6}.png` (procedural fallback) + `tools/make_dice_faces.swift`

SceneKit cannot load glTF — the asset must become USDZ (preferred, real art) or procedural PNG faces (fallback). Take path A if it works, else path B. Either path unblocks Task 8.

- [ ] **Step 1 (path A): Try headless glb → usdz conversion**

Run: `python3 -c "from pxr import Usd; print('usd-ok')" 2>&1 | head -2`
- If it prints `usd-ok`: run `USDZ_CONVERTER=$(python3 -c "import sysconfig, os; print(os.path.join(sysconfig.get_path('scripts'), 'usdfromgltf'))"); ls "$USDZ_CONVERTER" && "$USDZ_CONVERTER" /Users/robison/AndroidStudioProjects/KnuckleGame/app/src/main/assets/models/dice.glb Knuckled/Resources/dice.usdz && ls -la Knuckled/Resources/dice.usdz`
  Expected: `dice.usdz` exists (~MBs). Go to Step 3 (skip path B).
- Else run: `python3 -m pip install --user usd-core 2>&1 | tail -2` then retry the check above. If STILL no `usdfromgltf`, go to Step 2 (path B).

- [ ] **Step 2 (path B, only if A fails): Procedural pip faces**

Write `tools/make_dice_faces.swift` (CoreGraphics, same standard pip layouts as the temp 2D die):

```swift
import AppKit
import CoreGraphics

// Standard pip cells (3x3 positions 1-9, row-major) per face value.
func pips(for value: Int) -> Set<Int> {
    switch value {
    case 1: return [5]
    case 2: return [1, 9]
    case 3: return [1, 5, 9]
    case 4: return [1, 3, 7, 9]
    case 5: return [1, 3, 5, 7, 9]
    case 6: return [1, 3, 4, 6, 7, 9]
    default: return []
    }
}

let size = CGSize(width: 256, height: 256)
let ivory = CGColor(red: 0xFF/255, green: 0xFA/255, blue: 0xF0/255, alpha: 1)
let brown = CGColor(red: 0x1A/255, green: 0x12/255, blue: 0x07/255, alpha: 1)

for value in 1...6 {
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }
    ctx.setFillColor(ivory)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(brown)
    let cell = size.width / 3
    for pos in pips(for: value) {
        let cx = cell * (CGFloat((pos - 1) % 3) + 0.5)
        let cy = cell * (CGFloat((pos - 1) / 3) + 0.5)
        ctx.fillEllipse(in: CGRect(x: cx - cell * 0.26, y: cy - cell * 0.26, width: cell * 0.52, height: cell * 0.52))
    }
    image.unlockFocus()
    let out = URL(fileURLWithPath: "Knuckled/Resources/DiceFaces/\(value).png")
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("encode failed") }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
    print("wrote \(out.path)")
}
```

Run: `mkdir -p Knuckled/Resources/DiceFaces && swift tools/make_dice_faces.swift && ls Knuckled/Resources/DiceFaces/`
Expected: `1.png … 6.png` listed.

- [ ] **Step 3: Register + commit (whichever path won)**

Run: `python3 tools/sync_project.py`
```bash
git add Knuckled/Resources/dice.usdz tools/make_dice_faces.swift Knuckled/Resources/DiceFaces/ tools/sync_project.py Knuckled.xcodeproj/project.pbxproj 2>/dev/null; git add Knuckled/Resources/ tools/ Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: die asset (usdz conversion or procedural faces)"
```
(First `git add` lists the possibilities; the second sweeps what exists. Report which path won and the file sizes.)

---

### Task 7: Dice orientation table + tests

**Files:**
- Create: `Knuckled/DiceOrientation.swift`
- Test: `KnuckledTests/DiceOrientationTests.swift`

Pure value→Euler map (Android `DiceCube.getRotationForFace`, degrees XYZ, every final orientation puts the rolled face on +Z). Same numbers drive the usdz pivot AND the procedural box (whose faces are laid out [+x,-x,+y,-y,+z,-z] = [3,4,6,1,2,5], so identity shows 2 — verify the arithmetic in review).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled

final class DiceOrientationTests: XCTestCase {

    func testFaceTableMatchesAndroid() {
        XCTAssertEqual(DiceOrientation.eulerForFace(1), SIMD3(-90, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(2), SIMD3(0, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(3), SIMD3(0, -90, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(4), SIMD3(0, 90, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(5), SIMD3(0, 180, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(6), SIMD3(90, 0, 0))
    }

    func testUnknownFaceFallsBackToIdentity() {
        XCTAssertEqual(DiceOrientation.eulerForFace(0), SIMD3(0, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(7), SIMD3(0, 0, 0))
    }

    func testProceduralFaceMapSumsToSeven() {
        // Opposite faces sum to 7 (standard die): materials [+x,-x,+y,-y,+z,-z].
        let faces = DiceOrientation.proceduralFaces
        XCTAssertEqual(faces, [3, 4, 6, 1, 2, 5])
        XCTAssertEqual(faces[0] + faces[1], 7)
        XCTAssertEqual(faces[2] + faces[3], 7)
        XCTAssertEqual(faces[4] + faces[5], 7)
        XCTAssertEqual(faces[4], 2) // identity (+z toward camera) shows 2, per the table
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing:KnuckledTests/DiceOrientationTests` shape.
Expected: FAIL — `DiceOrientation` undefined.

- [ ] **Step 3: Implement `Knuckled/DiceOrientation.swift`**

```swift
import Foundation
import simd

/// Rolled value → XYZ Euler degrees putting that face on +Z.
/// Android parity: `DiceCube.getRotationForFace` verbatim.
enum DiceOrientation {
    static func eulerForFace(_ value: Int) -> SIMD3<Double> {
        switch value {
        case 1: return SIMD3(-90, 0, 0)
        case 3: return SIMD3(0, -90, 0)
        case 4: return SIMD3(0, 90, 0)
        case 5: return SIMD3(0, 180, 0)
        case 6: return SIMD3(90, 0, 0)
        default: return SIMD3(0, 0, 0) // 2 and unknown
        }
    }

    /// Procedural fallback face order for SCNBox materials [+x,-x,+y,-y,+z,-z].
    /// Chosen so the Euler table above holds: identity shows +z = 2, and every
    /// mapped rotation lands its value on +z (opposites sum to 7).
    static let proceduralFaces = [3, 4, 6, 1, 2, 5]
}
```

- [ ] **Step 4: Register + run**

Run: `python3 tools/sync_project.py` + the `-only-testing:KnuckledTests/DiceOrientationTests` command.
Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Knuckled/DiceOrientation.swift KnuckledTests/DiceOrientationTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: dice orientation table with tests"
```

---

### Task 8: SceneKit die view + swap

**Files:**
- Create: `Knuckled/DiceSceneView.swift`
- Modify: `Knuckled/GameScreen.swift` (swap `DieView` → `DiceSceneView` in a `Button`, delete `Knuckled/DieView.swift`)

Keeps the exact XCUITest contract (`buttons["dice"]`, enabled only when tappable, same 3 accessibility labels). Sound stays owned by GameScreen's phase task (Task 3) — this view is visuals only. Respects Reduce Motion (snaps instead of spinning).

- [ ] **Step 1: Implement `Knuckled/DiceSceneView.swift`**

```swift
import SwiftUI
import SceneKit

/// 3D die (120pt). Same contract as the temporary 2D DieView it replaces:
/// fixed size, tap only when enabled && !rolling, spinning cue while rolling.
struct DiceSceneView: View {
    let value: Int?
    let rolling: Bool
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            if enabled && !rolling { onTap() }
        }) {
            DiceSceneRepresentable(value: value, rolling: rolling)
                .frame(width: 120, height: 120)
        }
        .buttonStyle(.plain)
        .disabled(!(enabled && !rolling))
        .accessibilityIdentifier("dice")
        .accessibilityLabel(rolling ? "Dice rolling" : value.map { "Dice showing \($0)" } ?? "Dice tap to roll")
    }
}

private struct DiceSceneRepresentable: UIViewRepresentable {
    let value: Int?
    let rolling: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.scene = makeScene()
        view.autoenablesDefaultLighting = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.sync(scene: view.scene, value: value, rolling: rolling)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(Coordinator.makePivot())
        return scene
    }

    final class Coordinator {
        private var pivot: SCNNode?
        private var displayLink: CADisplayLink?
        private var velocity = SCNVector3Zero
        private var lastTick = CFTimeInterval(0)

        static func makePivot() -> SCNNode {
            let pivot = SCNNode()
            pivot.name = "pivot"
            if let model = loadModel() {
                pivot.addChildNode(model)
            }
            return pivot
        }

        /// dice.usdz when conversion won (Task 6A), else the procedural box.
        static func loadModel() -> SCNNode? {
            if let url = Bundle.main.url(forResource: "dice", withExtension: "usdz"),
               let scene = try? SCNScene(url: url, options: nil),
               let node = scene.rootNode.childNodes.first {
                // Re-center off-center geometry (Android parity: separate pivot
                // node at the origin + centered child, so spin never orbits).
                let (min, max) = node.boundingBox
                node.position = SCNVector3(
                    -(min.x + max.x) / 2,
                    -(min.y + max.y) / 2,
                    -(min.z + max.z) / 2
                )
                let longest = max(max.x - min.x, max(max.y - min.y), max(max.z - min.z))
                if longest > 0 {
                    let s = Float(1.5) / longest
                    node.scale = SCNVector3(s, s, s)
                }
                return node
            }
            return makeProceduralDie()
        }

        /// Fallback box: 6 pip-face materials on [+x,-x,+y,-y,+z,-z].
        static func makeProceduralDie() -> SCNNode? {
            var materials: [SCNMaterial] = []
            for face in DiceOrientation.proceduralFaces {
                let material = SCNMaterial()
                material.diffuse.contents = UIImage(named: "\(face)")
                materials.append(material)
            }
            guard materials.count == 6 else { return nil }
            let box = SCNBox(width: 1.5, height: 1.5, length: 1.5, chamferRadius: 0.12)
            box.materials = materials
            return SCNNode(geometry: box)
        }

        func sync(scene: SCNScene?, value: Int?, rolling: Bool) {
            if pivot == nil { pivot = scene?.rootNode.childNode(withName: "pivot", recursively: false) }
            guard let pivot else { return }
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            if rolling, !reduceMotion {
                if displayLink == nil {
                    velocity = SCNVector3(
                        x: Float(720).degreesToRadians * (Bool.random() ? 1 : -1),
                        y: Float(540).degreesToRadians * (Bool.random() ? 1 : -1),
                        z: 0
                    )
                    lastTick = CACurrentMediaTime()
                    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                    link.add(to: .main, forMode: .common)
                    displayLink = link
                }
            } else {
                displayLink?.invalidate()
                displayLink = nil
                snap(pivot, to: value ?? Int.random(in: 1...6))
            }
        }

        private func snap(_ pivot: SCNNode, to value: Int) {
            let e = DiceOrientation.eulerForFace(value)
            pivot.eulerAngles = SCNVector3(
                Float(e.x).degreesToRadians,
                Float(e.y).degreesToRadians,
                Float(e.z).degreesToRadians
            )
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let pivot else { return }
            let now = link.timestamp
            let dt = min(now - lastTick, 0.05)
            lastTick = now
            pivot.eulerAngles.x += velocity.x * Float(dt)
            pivot.eulerAngles.y += velocity.y * Float(dt)
        }
    }
}

private extension Float {
    var degreesToRadians: Float { self * .pi / 180 }
}
```

Notes the implementer must honor: `UIImage(named:)` looks in the main bundle (procedural PNGs registered as resources) — numbered `"1"`…`"6"`. `SCNScene(url:options:)` is `try?`-safe (missing asset → procedural). Z stays frozen during tumble (Android parity). Hard snap, no tween (Android parity).

- [ ] **Step 2: Swap into GameScreen + delete the temp die**

In `Knuckled/GameScreen.swift`, replace the `DieView(...)` call with:
```swift
                        DiceSceneView(
                            value: s.lastRoll,
                            rolling: s.phase == .ROLLING,
                            enabled: session.canRoll,
                            onTap: { sound.play(.tap); session.roll() }
                        )
```
(`sound` + TAP already exist from Task 3; if the DieView call site differs, keep its exact TAP + roll behavior — only the view type changes.)
Run: `git rm Knuckled/DieView.swift`

- [ ] **Step 3: Register + full gate + screenshots**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: all suites green (unit incl. orientation/model-load + UI smoke/tour/geometry — queries unchanged).
Then capture evidence mid-roll + settled: launch the app, start a game, roll, screenshot twice (rolling spin frame + settled face):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install booted /tmp/KnuckledDD/Build/Products/Debug-iphonesimulator/Knuckled.app
```
(XCUITest already drove rolls in Step 3's run; for screenshots, play manually in DeviceHub: tap Play, tap die, screenshot during the ~2s spin, screenshot after land.) Attach both PNGs in the final report with a verdict (3D model visible? correct face up after land? spin visible mid-roll?).

- [ ] **Step 4: Commit**

```bash
git add Knuckled/DiceSceneView.swift Knuckled/DiceOrientation.swift KnuckledTests/DiceOrientationTests.swift Knuckled/GameScreen.swift Knuckled/DieView.swift Knuckled/Resources/DiceFaces/ Knuckled/Resources/dice.usdz Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: SceneKit 3D die (usdz or procedural fallback)"
```
(Stage what exists — `git add` ignores missing paths only with the trailing fallback form used in Task 6; list precisely per what Task 6 produced.)
```bash
git add Knuckled/DiceSceneView.swift Knuckled/DiceOrientation.swift KnuckledTests/DiceOrientationTests.swift Knuckled/GameScreen.swift Knuckled/DieView.swift Knuckled/Resources/DiceFaces/ Knuckled/Resources/dice.usdz Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: SceneKit 3D die (usdz or procedural fallback)"
```

---

### Task 9: Connector protocol + fake transport + connection state machine

**Files:**
- Create: `Knuckled/Connect/BluetoothConnector.swift` (protocol + `DeviceInfo` + fake)
- Create: `Knuckled/Connect/ConnectionSession.swift`
- Test: `KnuckledTests/ConnectionSessionTests.swift`

Mirrors Android `bluetooth/BluetoothConnector.kt` + `FakeBluetoothConnector.kt` + `ui/ConnectionViewModel.kt` (route states, daemon-thread calls, error mapping). The real BLE connector lands in Task 14 behind the same protocol.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled
@testable import KnuckledCore

final class ConnectionSessionTests: XCTestCase {

    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw TestError.timeout }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func session() -> ConnectionSession {
        ConnectionSession(connector: FakeConnector())
    }

    func testHostFlowConnectsAsHost() throws {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        if case .hosting(let pin) = connection.state {
            XCTAssertEqual(pin, FakeConnector.pin)
        } else {
            XCTFail("expected hosting, got \(connection.state)")
        }
        try waitFor(connection.isConnected, timeout: 10)
        if case .connected(_, let peer, let isHost) = connection.state {
            XCTAssertTrue(isHost)
            XCTAssertNil(peer)
        } else {
            XCTFail("expected connected, got \(connection.state)")
        }
    }

    func testBlankNameShowsErrorAndStays() {
        let connection = session()
        connection.playerName = "   "
        connection.onHostClicked()
        XCTAssertEqual(connection.errorText, "Enter your name")
        if case .start = connection.state {} else {
            XCTFail("expected start, got \(connection.state)")
        }
    }

    func testWrongPinReturnsToStartWithError() throws {
        let connection = session()
        connection.playerName = "Joiner"
        connection.onDiscoverClicked()
        try waitFor(!connection.foundDevices.isEmpty, timeout: 10)
        connection.onDeviceSelected(connection.foundDevices[0])
        connection.onPinEntered("0000")
        try waitFor(connection.isStart, timeout: 10)
        XCTAssertEqual(connection.errorText, "Wrong code. Try again.")
    }

    func testCancelHostingReturnsToStart() {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        connection.cancelCurrent()
        XCTAssertTrue(connection.isStart)
        XCTAssertEqual(connection.hostPin, "")
    }

    func testDisconnectSetsStatus() throws {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        try waitFor(connection.isConnected, timeout: 10)
        connection.disconnect()
        XCTAssertTrue(connection.isStart)
        XCTAssertEqual(connection.statusText, "Disconnected")
    }
}
```

(`TestError.timeout` already exists in `GameSessionTests.swift` (same test target) — reuse it, do NOT redefine. `isConnected`/`isStart`/`hostPin` are tiny read-only helpers you add to `ConnectionSession` in Step 3.)

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing:KnuckledTests/ConnectionSessionTests` shape.
Expected: FAIL — `ConnectionSession`, `FakeConnector`, `DeviceInfo` undefined.

- [ ] **Step 3: Implement `Knuckled/Connect/BluetoothConnector.swift`**

```swift
import Foundation
import KnuckledCore

/// A peer device (Android parity: `DeviceInfo(name, address)`; iOS uses the
/// peripheral identifier string as the address).
struct DeviceInfo: Equatable {
    var name: String?
    var address: String
}

enum FakeConnectorError: Error { case invalidPin }

/// Blocking transport facade (Android parity: all three calls block and run
/// off the main thread; the real BLE connector implements the same shape).
protocol BluetoothConnector {
    func listen(pin: String) throws -> GameLink
    func connect(device: DeviceInfo, pin: String) throws -> GameLink
    func discover() throws -> [DeviceInfo]
}

/// Simulator/DEBUG transport mirroring Android's FakeBluetoothConnector:
/// fixed PIN 1234, one fake peer, loopback pairs with bots.
final class FakeConnector: BluetoothConnector {
    static let pin = "1234"
    static let fakeDevice = DeviceInfo(name: "Fake Peer", address: "00:11:22:33:44:55")

    /// Retained fake hosts (a host bot must stay alive for the session;
    /// mirrors Android holding peer references).
    private var hosts: [GameHost] = []

    func listen(pin: String) throws -> GameLink {
        guard pin == Self.pin else { throw FakeConnectorError.invalidPin }
        let (hostLink, clientLink) = InMemoryLinkPair.make()
        runFakeClient(clientLink)
        return hostLink
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        guard pin == Self.pin else { throw FakeConnectorError.invalidPin }
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        hosts.append(runFakeHost(hostLink))
        return clientLink
    }

    func discover() throws -> [DeviceInfo] { [Self.fakeDevice] }
}
```

- [ ] **Step 4: Implement `Knuckled/Connect/ConnectionSession.swift`**

```swift
import Foundation
import Combine
import KnuckledCore

enum ConnectionState {
    case start
    case hosting(pin: String)
    case discovering
    case enterPin(device: DeviceInfo)
    case connected(link: GameLink, peer: DeviceInfo?, isHost: Bool)
}

/// Connection flow state machine (Android parity: ConnectionViewModel route
/// states, background-thread blocking calls, main-thread publishing).
final class ConnectionSession: ObservableObject {
    @Published private(set) var state: ConnectionState = .start
    @Published var playerName = ""
    @Published private(set) var statusText = ""
    @Published private(set) var foundDevices: [DeviceInfo] = []
    @Published private(set) var errorText: String?
    @Published var useFake = true

    var isStart: Bool { if case .start = state { return true }; return false }
    var isConnected: Bool { if case .connected = state { return true }; return false }
    var hostPin: String { if case .hosting(let pin) = state { return pin }; return "" }

    private let connector: BluetoothConnector
    private var selectedDevice: DeviceInfo?
    private var currentLink: GameLink?
    private(set) var sanitizedName = ""
    private(set) var isHost = true

    init(connector: BluetoothConnector) {
        self.connector = connector
    }

    func onHostClicked() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = true
        let pin = FakeConnector.pin
        state = .hosting(pin: pin)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let link = try self.connector.listen(pin: pin)
                DispatchQueue.main.async { self.onConnected(link: link, peer: nil, isHost: true) }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error.localizedDescription)
                    self.state = .start
                }
            }
        }
    }

    func onDiscoverClicked() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = false
        foundDevices = []
        state = .discovering
        statusText = "Searching for devices..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let devices = try self.connector.discover()
                DispatchQueue.main.async {
                    self.foundDevices = devices
                    self.statusText = devices.isEmpty ? "No devices found — tap Host first" : ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error.localizedDescription)
                    self.state = .start
                }
            }
        }
    }

    func onDeviceSelected(_ device: DeviceInfo) {
        selectedDevice = device
        statusText = ""
        errorText = nil
        state = .enterPin(device: device)
    }

    func onPinEntered(_ pin: String) {
        guard let device = selectedDevice else { return }
        statusText = "Connecting..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let link = try self.connector.connect(device: device, pin: pin)
                DispatchQueue.main.async { self.onConnected(link: link, peer: device, isHost: false) }
            } catch {
                let message = String(describing: error)
                let lower = message.lowercased()
                let friendly = (lower.contains("pin") || lower.contains("handshake"))
                    ? "Wrong code. Try again." : message
                DispatchQueue.main.async {
                    self.showError(friendly)
                    self.state = .start
                }
            }
        }
    }

    func cancelCurrent() {
        try? currentLink?.close()
        statusText = ""
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func disconnect() {
        try? currentLink?.close()
        currentLink = nil
        statusText = "Disconnected"
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func onPeerDisconnected() {
        try? currentLink?.close()
        currentLink = nil
        statusText = "Peer disconnected"
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func dismissError() { errorText = nil }

    private func showError(_ message: String) { errorText = message }

    private func onConnected(link: GameLink, peer: DeviceInfo?, isHost: Bool) {
        try? currentLink?.close()
        currentLink = link
        self.isHost = isHost
        statusText = ""
        errorText = nil
        state = .connected(link: link, peer: peer, isHost: isHost)
    }
}
```

Notes: `try? currentLink?.close()` — `close()` is non-throwing; `try?` on non-throwing is a warning! `GameLink.close()` returns Void, not throws. Write `currentLink?.close()` without `try?`. (Authored correctly above — keep it that way. If the compiler warns on any `try?` without a throwing call, drop it.)

- [ ] **Step 5: Register + run**

Run: `python3 tools/sync_project.py` + the `-only-testing:KnuckledTests/ConnectionSessionTests` command.
Expected: new files registered; `Executed 5 tests, with 0 failures`. (FakeConnector returns instantly, so no timing flakes; wrong-PIN path exercises the error mapping.)

- [ ] **Step 6: Commit**

```bash
git add Knuckled/Connect/BluetoothConnector.swift Knuckled/Connect/ConnectionSession.swift KnuckledTests/ConnectionSessionTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: connection state machine over fake transport"
```

---

### Task 10: GameSession link roles (host/client) + peer lifecycle

**Files:**
- Modify: `Knuckled/GameSession.swift`
- Modify: `KnuckledTests/GameSessionTests.swift` (existing solo tests must pass UNCHANGED; append client-role tests)

Refactors the solo-only session into a link-injected two-role session mirroring Android `GameViewModel` init split (HOST builds `GameHost`; CLIENT sends `NAME` and renders `STATE`). The solo path (`startSinglePlayer`) keeps identical behavior by building its pair + CPU internally, then delegating to the same `connect`.

- [ ] **Step 1: Append the client-role tests** (existing 5 tests untouched)

```swift
    func testClientReceivesHostStates() throws {
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        let host = GameHost(link: hostLink, hostName: "Host", rollValue: { 3 }, rollDelayMs: 0, firstPlayer: { .HOST })
        host.connect()

        let session = GameSession()
        session.connect(link: clientLink, myId: .CLIENT, hostName: "Host", clientName: "Club")
        try waitFor(session.state != nil, timeout: 10)
        let s = session.state!
        XCTAssertEqual(s.hostName, "Host")
        XCTAssertEqual(s.clientName, "Club")
        XCTAssertEqual(s.currentTurn, .HOST)
    }

    func testClientRollAndPlaceRoundTrip() throws {
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        let host = GameHost(link: hostLink, hostName: "Host", rollValue: { 3 }, rollDelayMs: 0, firstPlayer: { .HOST })
        host.connect()

        let session = GameSession()
        session.connect(link: clientLink, myId: .CLIENT, hostName: "Host", clientName: "Club")
        try waitFor(session.state != nil, timeout: 10)
        // Host (test thread) moves first.
        host.hostRoll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT, timeout: 10)
        host.hostPlace(0)
        // Client turn: roll via session, place via session.
        try waitFor(session.state!.currentTurn == .CLIENT, timeout: 10)
        session.roll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT && session.state!.currentTurn == .CLIENT, timeout: 10)
        XCTAssertEqual(session.state!.lastRoll, 3)
        session.place(1)
        try waitFor(session.state!.currentTurn == .HOST, timeout: 10)
        XCTAssertEqual(session.state!.grid[.CLIENT]![1], [3])
    }

    func testClientRestartAndPeerClose() throws {
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        let host = GameHost(link: hostLink, hostName: "Host", rollValue: { 3 }, rollDelayMs: 0, firstPlayer: { .HOST })
        host.connect()
        var peerGone = false
        let session = GameSession()
        session.onPeerDisconnected = { peerGone = true }
        session.connect(link: clientLink, myId: .CLIENT, hostName: "Host", clientName: "Club")
        try waitFor(session.state != nil, timeout: 10)
        host.hostRoll()
        host.hostPlace(0)
        try waitFor(session.state!.currentTurn == .CLIENT, timeout: 10)
        // Client-initiated restart is illegal mid-game (host ignores it).
        session.playAgain()
        XCTAssertEqual(session.state!.status, .IN_PROGRESS)
        // Peer closing the link surfaces peerDisconnected + callback.
        hostLink.close()
        try waitFor(session.peerDisconnected, timeout: 10)
        XCTAssertTrue(peerGone)
    }
```

(`onPeerDisconnected` is a new `var` closure on `GameSession` (default `{}`); `peerDisconnected` a new `@Published private(set) var`. `GameHost` init used positionally as in core tests — verify labels against `Sources/KnuckledCore/Game/GameHost.swift` (`link:hostName:rollValue:rollDelayMs:firstPlayer:onState:`).)

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing` shape for the new tests.
Expected: FAIL — `connect(link:myId:hostName:clientName:)`, `onPeerDisconnected`, `peerDisconnected` undefined.

- [ ] **Step 3: Refactor `Knuckled/GameSession.swift`**

Keep every existing member + behavior; change `myId`/`peerId` to `private(set) var`; add role-aware `connect`, `roll`, `place`, `playAgain`, peer-close handling:

```swift
import Foundation
import Combine
import KnuckledCore

/// Owns one game session over any GameLink (solo loopback, fake, or BLE).
/// HOST runs a GameHost; CLIENT sends NAME and renders STATE broadcasts.
/// All @Published updates happen on the main thread.
final class GameSession: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var playerName: String = "Player"
    @Published private(set) var peerDisconnected = false

    var onPeerDisconnected: () -> Void = {}

    private(set) var myId: PlayerId = .HOST
    private(set) var peerId: PlayerId = .CLIENT

    private var host: GameHost?
    private var link: GameLink?
    private var cpuLink: GameLink?

    var inGame: Bool { state != nil }

    var isMyTurn: Bool {
        guard let s = state else { return false }
        return s.status == .IN_PROGRESS && s.currentTurn == myId
    }

    var canRoll: Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canRoll(s, myId)
    }

    func canPlace(_ column: Int) -> Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canPlace(s, myId, column)
    }

    /// Solo convenience: loopback pair + CPU client, then the host path.
    /// Production defaults mirror Android (2s roll, human pacing).
    func startSinglePlayer(
        name: String,
        rollDelayMs: Int = 2000,
        rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
        firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT },
        preRollDelayMs: Double = CpuPacing.preRollSeconds,
        thinkDelay: @escaping () -> Double = CpuPacing.naturalThink
    ) {
        disconnect()
        let clean = MessageCodec.sanitizeName(name)
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink, preRollDelayMs: preRollDelayMs, thinkDelay: thinkDelay)
        self.cpuLink = cpuLink
        connect(
            link: humanLink, myId: .HOST,
            hostName: clean.isEmpty ? "Player" : clean, clientName: CpuPlayer.name,
            rollValue: rollValue, rollDelayMs: rollDelayMs, firstPlayer: firstPlayer
        )
        playerName = clean.isEmpty ? "Player" : clean
    }

    /// PvP path: attach to an already-connected link in either role.
    func connect(
        link: GameLink,
        myId: PlayerId,
        hostName: String,
        clientName: String,
        rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
        rollDelayMs: Int = 2000,
        firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT }
    ) {
        disconnect()
        self.link = link
        self.myId = myId
        self.peerId = myId == .HOST ? .CLIENT : .HOST
        self.playerName = myId == .HOST ? hostName : clientName
        self.peerDisconnected = false
        if myId == .HOST {
            let host = GameHost(
                link: link,
                hostName: hostName,
                rollValue: rollValue,
                rollDelayMs: rollDelayMs,
                firstPlayer: firstPlayer,
                onState: { [weak self] s in
                    DispatchQueue.main.async { self?.state = s }
                }
            )
            self.host = host
            link.onClosed = { [weak self] in self?.handlePeerClosed() }
            host.connect()
        } else {
            link.onLine = { [weak self] line in
                guard let self, let s = MessageCodec.decodeState(line) else { return }
                let captured = s
                DispatchQueue.main.async { self.state = captured }
            }
            link.onClosed = { [weak self] in self?.handlePeerClosed() }
            try? link.send(MessageCodec.encodeName(clientName))
        }
    }

    /// Async: the host roll blocks ~rollDelayMs mid-roll (same as Android's IO dispatcher).
    /// As client this sends ROLL (host rolls for us).
    func roll() {
        if myId == .HOST {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.host?.hostRoll()
            }
        } else {
            try? link?.send(MessageCodec.encodeRoll())
        }
    }

    func place(_ column: Int) {
        if myId == .HOST {
            host?.hostPlace(column)
        } else {
            try? link?.send(MessageCodec.encodePlace(column))
        }
    }

    func playAgain() {
        if myId == .HOST {
            host?.restart()
        } else {
            try? link?.send(MessageCodec.encodeRestart())
        }
    }

    func disconnect() {
        link?.close()
        link = nil
        cpuLink = nil
        host = nil
        state = nil
    }

    private func handlePeerClosed() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.peerDisconnected = true
            self.onPeerDisconnected()
        }
    }
}
```

Check against the CURRENT file before replacing: keep `cpuLink` retention + `disconnect()`-first guard (blessed fixes) — both preserved above. `try? link?.send` — `link` is optional; `try?` on optional-chained throwing call yields `Result??`... `try? link?.send(...)` is valid Swift (result discarded). `link.onClosed = ...` — non-optional after assignment? `self.link = link` (non-optional param assigned to optional var) then `link.onClosed` uses the PARAM (non-optional) ✓.

- [ ] **Step 4: Register (no new files — skip sync) + run**

Run the full `KnuckledTests` bundle (`-only-testing:KnuckledTests`): all 5 existing solo tests must pass UNCHANGED + 3 new client tests green.
Expected: `Executed 8 tests, with 0 failures` (5 old + 3 new... plus Settings/Sound/Connection suites from earlier tasks — count grows; gate on 0 failures).

- [ ] **Step 5: Commit**

```bash
git add Knuckled/GameSession.swift KnuckledTests/GameSessionTests.swift
git commit -m "feat: link-injected host/client session roles"
```

---

### Task 11: Connection screens + routing + fake-flow UI tests

**Files:**
- Create: `Knuckled/Connect/ConnectionScreens.swift` (Hosting/Discover/EnterPin + PIN digits)
- Modify: `Knuckled/StartScreen.swift` (Host/Join buttons + transport toggle), `Knuckled/KnuckledApp.swift` (state routing + GameContainer), `Knuckled/GameScreen.swift` (peer-disconnect banner)
- Test: `KnuckledUITests/ConnectionFlowTests.swift` (host + join flows over fake)

- [ ] **Step 1: Implement `Knuckled/Connect/ConnectionScreens.swift`**

```swift
import SwiftUI
import KnuckledCore

struct HostingView: View {
    let pin: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("Pairing code")
                    .font(.headline)
                    .foregroundStyle(AppColors.ivory)
                HStack(spacing: 8) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(AppFont.display(size: 32))
                            .foregroundStyle(AppColors.gold)
                            .frame(width: 64, height: 64)
                            .background(AppColors.glassWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppColors.glassBorderGold, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityIdentifier("pin-display")
                Text("Waiting for a device…")
                    .foregroundStyle(AppColors.ivory)
                    .opacity(0.5)
                    .accessibilityIdentifier("hosting-status")
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}
```
(`.headline` is the correct SwiftUI font per the solo plan's font mapping.)

```swift
struct DiscoverView: View {
    let devices: [DeviceInfo]
    let status: String
    let onSelect: (DeviceInfo) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 12) {
                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(AppColors.ivory)
                        .accessibilityIdentifier("scan-status")
                }
                if devices.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        GlassCard { Spacer().frame(height: 56) }
                            .opacity(0.5)
                    }
                }
                List(devices, id: \.address) { device in
                    Button(action: { onSelect(device) }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(AppColors.gold)
                            VStack(alignment: .leading) {
                                Text(device.name ?? device.address)
                                Text(device.address).font(.caption).foregroundStyle(AppColors.ivory.opacity(0.7))
                            }
                        }
                    }
                    .accessibilityIdentifier("device-row")
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}
```
(`AppColors.ivory.opacity(0.7)` — `.opacity` on a `Color` VALUE is the known ambiguity! Write `Color(red: 0xF3/255.0, green: 0xE7/255.0, blue: 0xC3/255.0, opacity: 0.7)` instead. Same anywhere else a concrete color gets `.opacity`.)

```swift
struct EnterPinView: View {
    let deviceName: String
    let status: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var pin = ""
    @State private var shake = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("Enter the code shown on the host phone")
                    .font(.body)
                    .foregroundStyle(AppColors.ivory)
                Text(deviceName)
                    .font(.headline)
                    .foregroundStyle(AppColors.gold)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        let digit: String = {
                            let chars = Array(pin)
                            return i < chars.count ? String(chars[i]) : ""
                        }()
                        Text(digit)
                            .font(AppFont.display(size: 28))
                            .foregroundStyle(AppColors.ivory)
                            .frame(width: 56, height: 56)
                            .background(AppColors.glassWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(!digit.isEmpty ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityIdentifier("pin-input")
                .offset(x: shake ? 8 : 0)
                .background(
                    TextField("", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .opacity(0.01)
                        .onChange(of: pin) { _, new in
                            let digits = new.filter(\.isWholeNumber).prefix(4)
                            pin = String(digits)
                            if pin.count == 4 { onConfirm(pin) }
                        }
                )
                .onTapGesture { focused = true }
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                        .accessibilityIdentifier("pin-status")
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .onAppear { focused = true }
        .onChange(of: status) { _, new in
            if !new.isEmpty {
                pin = ""
                withAnimation(.linear(duration: 0.05).repeatCount(5, autoreverses: true)) {
                    shake.toggle()
                }
            }
        }
    }
}
```
(`TextField` with `.opacity(0.01)` hidden-field-over-tiles pattern mirrors Android's hidden `BasicTextField`; `focused` auto-focus mirrors `FocusRequester`. `.filter(\.isWholeNumber)` keeps key-path syntax valid on `Character`. `onChange(of:_:_:)` two-parameter form is iOS 17+ ✓.)

- [ ] **Step 2: Modify StartScreen (Host/Join + transport toggle)**

Add `@EnvironmentObject private var connection: ConnectionSession` — NO. StartScreen is also used... StartScreen currently takes `session: GameSession` (solo). For connection flows it needs the CONNECTION session instead. Restructure: StartScreen takes both? Cleaner: StartScreen keeps `session` for solo Play, plus optional connection wiring via EnvironmentObject. Write the additions:
```swift
    @EnvironmentObject private var connection: ConnectionSession
```
Buttons row after Play vs CPU:
```swift
                Button("Host a game") { connection.onHostClicked() }
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("host-button")
                Button("Join a game") { connection.onDiscoverClicked() }
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("join-button")
                Picker("Transport", selection: $connection.useFake) {
                    Text("Nearby").tag(false)
                    Text("Fake").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transport-picker")
```
(Transport toggle mirrors Android's planned transport switch; default `true` = Fake on simulator. BLE flips it in Task 14.)
Name validation for Host/Join lives in `ConnectionSession` (shows "Enter your name" via its `errorText` — surface it: StartScreen already shows its own local error for CPU; add `if let error = connection.errorText { Text(error)... .accessibilityIdentifier("connection-error") }` + dismiss on tap? Keep simple: show with a Dismiss button calling `connection.dismissError()`.)

- [ ] **Step 3: Rewrite routing in KnuckledApp + GameContainer**

```swift
import SwiftUI
import KnuckledCore

@main
struct KnuckledApp: App {
    @StateObject private var session = GameSession()   // solo + legacy; kept for StartScreen CPU path
    @StateObject private var connection = ConnectionSession(connector: FakeConnector())
    @StateObject private var settings = SettingsStore()
    private let sound: AVFoundationSoundManager
    ...
```
Hmm — two sessions (solo GameSession + connection) is confusing. SIMPLIFY: single `ConnectionSession` owns routing AND the solo path? Android: ConnectionVM.startSinglePlayer → Connected(link, peer=nil, isHost=true) → SAME GameScreen! Unify: `ConnectionSession.startSinglePlayer()` builds pair+CPU (reuse `LocalConnector`-equivalent inline: InMemoryLinkPair + runCpuClient) and routes to `.connected`. Then StartScreen's CPU button calls `connection.startSinglePlayer()` (drop GameSession from StartScreen), and GameContainer builds ONE GameSession per connection (host/client/solo all flow through `connect`). GameSession.startSinglePlayer stays for TESTS. Rewrite:

```swift
@main
struct KnuckledApp: App {
    @StateObject private var connection: ConnectionSession
    @StateObject private var settings: SettingsStore
    private let sound: AVFoundationSoundManager

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        sound = AVFoundationSoundManager(muted: settings.muted, onMutedChanged: { settings.muted = $0 })
        #if targetEnvironment(simulator)
        _connection = StateObject(wrappedValue: ConnectionSession(connector: FakeConnector()))
        #else
        _connection = StateObject(wrappedValue: ConnectionSession(connector: FakeConnector()))
        #endif
    }
```
(No — don't branch yet; Task 14 swaps the connector + picker. Keep `FakeConnector()` with a `// Task 14: BleConnector` comment.)
```swift
    var body: some Scene {
        WindowGroup {
            ZStack {
                FeltBackground()
                switch connection.state {
                case .start:
                    StartScreen()
                case .hosting(let pin):
                    HostingView(pin: pin, onCancel: { connection.cancelCurrent() })
                case .discovering:
                    DiscoverView(devices: connection.foundDevices, status: connection.statusText, onSelect: { connection.onDeviceSelected($0) }, onCancel: { connection.cancelCurrent() })
                case .enterPin(let device):
                    EnterPinView(deviceName: device.name ?? device.address, status: connection.statusText, onConfirm: { connection.onPinEntered($0) }, onCancel: { connection.cancelCurrent() })
                case .connected(let link, let peer, let isHost):
                    GameContainer(link: link, peer: peer, isHost: isHost)
                }
            }
            .environmentObject(connection)
            .environmentObject(settings)
            .environment(\.soundManager, sound)
        }
    }
}

struct GameContainer: View {
    let link: GameLink
    let peer: DeviceInfo?
    let isHost: Bool
    @EnvironmentObject var connection: ConnectionSession
    @StateObject private var session: GameSession

    init(link: GameLink, peer: DeviceInfo?, isHost: Bool) {
        self.link = link
        self.peer = peer
        self.isHost = isHost
        _session = StateObject(wrappedValue: GameSession())
    }

    var body: some View {
        GameScreen(session: session)
            .id(ObjectIdentifier(link))
            .onAppear {
                let myId: PlayerId = isHost ? .HOST : .CLIENT
                session.onPeerDisconnected = { [weak connection] in connection?.onPeerDisconnected() }
                session.connect(
                    link: link, myId: myId,
                    hostName: isHost ? connection.sanitizedName : (peer?.name ?? "Host"),
                    clientName: isHost ? "Guest" : connection.sanitizedName
                )
            }
    }
}
```
Wait — names: host side needs BOTH names but only knows its own until the client NAME arrives (GameHost learns clientName from NAME ✓; session.playerName updates? GameSession.connect sets playerName from params — for host, clientName param is a placeholder ("Guest") until NAME arrives... then GameHost.state.clientName updates but session.playerName stays "Guest"! Fix: in host onState sink, refresh playerName from state? Android GameViewModel passes hostName/clientName at construction (host passes its own; client name arrives via STATE rendering `s.clientName` — the UI reads STATE names, not VM names!). Our GameScreen ALREADY reads `s.hostName`/`s.clientName` from state ✓ — `playerName` is only used... where? StartScreen doesn't use it; GameScreen doesn't (uses state names). `playerName` is only asserted in old tests. So placeholder is harmless. But `connection.sanitizedName` for hostName ✓ real. For client side: hostName unknown until first STATE — pass `peer?.name ?? "Host"` (fake peer "Fake Peer"; BLE peer name) — UI reads state names anyway ✓. Fine as written. (TurnPill peerName uses `s.clientName` ✓ state-driven.)

`connection` param in GameContainer.init is UNUSED (environment provides it) — drop the param, keep `@EnvironmentObject`. Simplify init to `(link:peer:isHost:)`. (Write it that way.)

`#if targetEnvironment(simulator)` — skip the branch (Task 14 handles selection via the picker + default). One connector line with the Task-14 comment.

StartScreen rewrite: takes NO session now? It needs `connection` (EnvironmentObject) for all three buttons + name field (local @State name → connection.playerName binding? Use `$connection.playerName` directly + validation inside connection methods ✓ simpler — drop local name state, drop local error (connection.errorText shown instead)). Rewrite StartScreen fully:
```swift
struct StartScreen: View {
    @EnvironmentObject private var connection: ConnectionSession
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { ... name field bound to $connection.playerName ... Play vs CPU → connection.startSinglePlayer() ... Host/Join ... picker ... hint card ... error banner ... }
}
```
And `ConnectionSession.startSinglePlayer()`: builds pair + runCpuClient + `onConnected(link:human, peer:nil, isHost:true)` + set sanitizedName (mirror Android VM). ADD it in this task (method on ConnectionSession):
```swift
    func startSinglePlayer() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = true
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink)
        cpuRetain.append(cpuLink)  // hmm — retain!
        onConnected(link: humanLink, peer: nil, isHost: true)
    }
```
RETENTION: cpuLink must live (weak-capture lesson!). Add `private var retainedLinks: [GameLink] = []` cleared on disconnect/cancel. (runFakeHost hosts already retained via `hosts` in FakeConnector — but the FAKE connector is short-lived per call... `FakeConnector` instance lives in ConnectionSession (stored) ✓ its `hosts` array persists ✓. For solo, ConnectionSession retains cpuLink ✓. Document both.)

- [ ] **Step 4: GameScreen peer-disconnect banner** — add near the error area:
```swift
            if session.peerDisconnected {
                GlassCard {
                    Text("Peer disconnected")
                        .foregroundStyle(AppColors.ivory)
                        .padding(12)
                }
                .accessibilityIdentifier("peer-banner")
            }
```
(ConnectionSession flips state to `.start` on peer loss, so the banner is transient by design — same as Android.)

- [ ] **Step 5: Write `KnuckledUITests/ConnectionFlowTests.swift`**

```swift
import XCTest

final class ConnectionFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))
        return app
    }

    private func typeName(_ app: XCUIApplication, _ name: String = "Tester") {
        let field = app.textFields["name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
    }

    func testHostFlowShowsPinThenGame() {
        let app = launch()
        typeName(app)
        app.buttons["host-button"].tap()
        XCTAssertTrue(app.staticTexts["pin-display"].waitForExistence(timeout: 10))
        // Fake client connects immediately: game screen follows.
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 15))
    }

    func testJoinFlowWrongPinShowsError() {
        let app = launch()
        typeName(app)
        app.buttons["join-button"].tap()
        XCTAssertTrue(app.staticTexts["scan-status"].waitForExistence(timeout: 10))
        let row = app.staticTexts["device-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let pin = app.textFields["pin-input"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        pin.typeText("0000")
        // Wrong PIN returns to Start with the error banner.
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 5))
    }

    func testJoinFlowCorrectPinReachesGame() {
        let app = launch()
        typeName(app)
        app.buttons["join-button"].tap()
        let row = app.staticTexts["device-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let pin = app.textFields["pin-input"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        pin.typeText("1234")
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 15))
    }
}
```
Adjustments the implementer is pre-authorized for: device rows are `Button`s containing text — `app.staticTexts["device-row"]` may need to become `app.buttons["device-row"].firstMatch` (same identifier-stamping lesson as columns); PIN field is a near-invisible `TextField` overlay — if `pin.tap()` misses, tap its tile container `pin-input` first. Auto-submit fires `onConfirm` at 4 digits. Scan status text: FakeConnector returns instantly so `"Searching for devices..."` may flash — the test only asserts rows, robust either way. Report any query adjustment.

- [ ] **Step 6: Register + full gate**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: all suites green incl. 3 new connection UI tests.

- [ ] **Step 7: Commit**

```bash
git add Knuckled/Connect/ Knuckled/StartScreen.swift Knuckled/KnuckledApp.swift Knuckled/GameScreen.swift Knuckled/GameSession.swift KnuckledUITests/ConnectionFlowTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: connection screens and routing over fake transport"
```
```bash
git add Knuckled/Connect/ Knuckled/StartScreen.swift Knuckled/KnuckledApp.swift Knuckled/GameScreen.swift Knuckled/GameSession.swift KnuckledUITests/ConnectionFlowTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: connection screens and routing over fake transport"
```

---

### Task 12: BLE UUIDs + framing + tests

**Files:**
- Create: `Knuckled/BLE/BleUUIDs.swift`
- Create: `Knuckled/BLE/BleFraming.swift`
- Test: `KnuckledTests/BleFramingTests.swift`

Frozen layout (spec GATT table — do NOT alter these strings): service `8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A`, write `AAF90241-0F50-42CF-ADFC-2BAADE92ACD1`, notify `3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA`. Line framing on the receiving side stays `Protocol.readLine` inside `GameLinkCore` (byte-wise, 1024 cap, overlong fatal) — this task covers the SENDER chunking only, so there is exactly one framing implementation per direction and no duplication.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled
import CoreBluetooth

final class BleFramingTests: XCTestCase {

    func testFrozenUUIDs() {
        XCTAssertEqual(BleUUIDs.service, CBUUID(string: "8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A"))
        XCTAssertEqual(BleUUIDs.write, CBUUID(string: "AAF90241-0F50-42CF-ADFC-2BAADE92ACD1"))
        XCTAssertEqual(BleUUIDs.notify, CBUUID(string: "3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA"))
        XCTAssertEqual(BleUUIDs.localName, "Knuckled")
    }

    func testChunkSizeDefaults() {
        XCTAssertEqual(BleFraming.chunkSize(mtu: nil), 20)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 23), 20)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 185), 182)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 3), 1)
    }

    func testShortLineIsOneChunk() {
        let chunks = BleFraming.chunk(line: "ROLL", mtu: nil)
        XCTAssertEqual(chunks, [Data("ROLL\n".utf8)])
    }

    func testLongLineSplitsAndRejoinsByteExact() {
        let line = "STATE:" + String(repeating: "héllo 世界", count: 40)
        let chunks = BleFraming.chunk(line: line, mtu: nil)
        XCTAssertTrue(chunks.count > 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(chunks.reduce(Data(), +), Data((line + "\n").utf8))
    }

    func testMultiByteCharacterSurvivesChunkBoundary() {
        // "é" is 2 bytes in UTF-8; 20-byte chunks will split mid-character.
        let line = String(repeating: "é", count: 30)
        let chunks = BleFraming.chunk(line: line, mtu: nil)
        XCTAssertEqual(chunks.reduce(Data(), +), Data((line + "\n").utf8))
    }

    func testChunkDataSplitsRawBytes() {
        let data = Data((0..<55).map { UInt8($0) })
        let chunks = BleFraming.chunkData(data, mtu: 23)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[2].count, 15)
        XCTAssertEqual(chunks.reduce(Data(), +), data)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing:KnuckledTests/BleFramingTests` shape.
Expected: FAIL — `BleUUIDs`, `BleFraming` undefined.

- [ ] **Step 3: Implement both files**

`Knuckled/BLE/BleUUIDs.swift`:
```swift
import Foundation
import CoreBluetooth

/// Frozen GATT layout (spec table — do NOT change after first release).
enum BleUUIDs {
    static let service = CBUUID(string: "8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A")
    static let write = CBUUID(string: "AAF90241-0F50-42CF-ADFC-2BAADE92ACD1")
    static let notify = CBUUID(string: "3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA")
    static let localName = "Knuckled"
    static let clientCharacteristicConfig = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
}
```

`Knuckled/BLE/BleFraming.swift`:
```swift
import Foundation

/// GATT sender chunking (spec framing section): each \n-terminated UTF-8
/// line splits into consecutive chunks of at most (MTU − 3) bytes, 20-byte
/// fallback when the MTU is unknown. No length prefix. The receiver side is
/// `Protocol.readLine` inside `GameLinkCore` (byte-wise split on \n,
/// \r-strip, 1024 cap, overlong fatal) — shared with every transport.
enum BleFraming {
    static func chunkSize(mtu: Int?) -> Int {
        max((mtu ?? 23) - 3, 1)
    }

    static func chunkData(_ data: Data, mtu: Int?) -> [Data] {
        let size = chunkSize(mtu: mtu)
        var out: [Data] = []
        var i = data.startIndex
        while i < data.endIndex {
            let j = data.index(i, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data[i..<j])
            i = j
        }
        return out
    }

    static func chunk(line: String, mtu: Int?) -> [Data] {
        var bytes = Data(line.utf8)
        bytes.append(0x0A)
        return chunkData(bytes, mtu: mtu)
    }
}
```

- [ ] **Step 4: Register + run**

Run: `python3 tools/sync_project.py` + the `-only-testing:KnuckledTests/BleFramingTests` command.
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Knuckled/BLE/BleUUIDs.swift Knuckled/BLE/BleFraming.swift KnuckledTests/BleFramingTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: frozen BLE UUIDs and chunk framing"
```

---

### Task 13: BLE byte pipe + tests

**Files:**
- Create: `Knuckled/BLE/BlePipe.swift`
- Test: `KnuckledTests/BlePipeTests.swift`

One duplex pipe shared by both directions (like `Channel`): inbound = peer chunks (central writes / notify updates), outbound = chunked lines via `onWrite`. `GameLinkCore` provides framing + close semantics on top.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Knuckled
@testable import KnuckledCore
import CoreBluetooth

final class BlePipeTests: XCTestCase {

    func testWriteChunksByMtuAndRoundTripsThroughFeed() {
        let pipe = BlePipe()
        pipe.mtu = 23
        var sent: [Data] = []
        pipe.onWrite = { data, _ in sent.append(data) }
        pipe.write(Data("ROLL\n".utf8))
        XCTAssertEqual(sent, [Data("ROLL\n".utf8)])
        for chunk in sent { pipe.feed(chunk) }
        XCTAssertEqual(Protocol.readLine(from: pipe), "ROLL")
    }

    func testLongWriteSplitsToMtuChunks() {
        let pipe = BlePipe()
        pipe.mtu = 23
        var sent: [Data] = []
        pipe.onWrite = { data, _ in sent.append(data) }
        let line = Data(String(repeating: "x", count: 50).utf8)
        pipe.write(line)
        XCTAssertEqual(sent.count, 3)
        XCTAssertTrue(sent.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(sent.reduce(Data(), +), line)
    }

    func testWriteModePassedThrough() {
        let pipe = BlePipe()
        var modes: [CBCharacteristicWriteType] = []
        pipe.onWrite = { _, mode in modes.append(mode) }
        pipe.writeMode = .withResponse
        pipe.write(Data("PIN:1\n".utf8))
        XCTAssertEqual(modes, [.withResponse])
    }

    func testCloseUnblocksReaderAndDropsWrites() {
        let pipe = BlePipe()
        var writes = 0
        pipe.onWrite = { _, _ in writes += 1 }
        pipe.close()
        pipe.write(Data("x\n".utf8))
        XCTAssertEqual(writes, 0)
        XCTAssertNil(pipe.readByte())
        pipe.close() // idempotent, no crash
    }

    func testOverlongFrameIsFatalLikeProtocol() {
        let pipe = BlePipe()
        pipe.feed(Data(repeating: UInt8(ascii: "x"), count: 1025))
        pipe.feed(Data("\n".utf8))
        XCTAssertNil(Protocol.readLine(from: pipe))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Same `-only-testing:KnuckledTests/BlePipeTests` shape.
Expected: FAIL — `BlePipe` undefined.

- [ ] **Step 3: Implement `Knuckled/BLE/BlePipe.swift`**

```swift
import Foundation
import CoreBluetooth
import KnuckledCore

/// Blocking duplex byte pipe over CoreBluetooth callbacks. Inbound chunks
/// (central writes / notify updates) arrive via `feed` on any thread;
/// outbound lines chunk by MTU through `onWrite`. `GameLinkCore` owns
/// framing (`Protocol.readLine`, 1024 cap) and close semantics on top.
final class BlePipe: ByteSource, ByteSink {
    var mtu: Int?
    var writeMode: CBCharacteristicWriteType = .withoutResponse
    var onWrite: ((Data, CBCharacteristicWriteType) -> Void)?
    var onClose: (() -> Void)?

    private var inbound = Data()
    private var closed = false
    private let cond = NSCondition()
    private var closeFired = false

    func feed(_ chunk: Data) {
        cond.lock()
        if !closed { inbound.append(chunk) }
        cond.signal()
        cond.unlock()
    }

    // MARK: ByteSource

    func readByte() -> Int? {
        cond.lock()
        defer { cond.unlock() }
        while inbound.isEmpty && !closed {
            cond.wait()
        }
        if inbound.isEmpty { return nil }
        return Int(inbound.removeFirst())
    }

    // MARK: ByteSink

    func write(_ data: Data) {
        let chunks = BleFraming.chunkData(data, mtu: mtu)
        let handler = onWrite
        let isClosed: Bool = {
            cond.lock()
            defer { cond.unlock() }
            return closed
        }()
        guard !isClosed else { return }
        for chunk in chunks { handler?(chunk, writeMode) }
    }

    func close() {
        cond.lock()
        let first = !closed
        closed = true
        inboundClosedBroadcast()
        cond.unlock()
        if first { onClose?() }
    }

    private func inboundClosedBroadcast() {
        cond.broadcast()
    }
}
```
(Simplify before writing: `inboundClosedBroadcast` is a one-line wrapper — inline `cond.broadcast()` in `close()` and drop the helper. `close()` holds the lock while calling `onClose` AFTER unlock — as written, `onClose?()` runs outside the lock ✓ re-entrancy safe (same discipline as GameLinkCore).)

- [ ] **Step 4: Register + run**

Run: `python3 tools/sync_project.py` + the `-only-testing:KnuckledTests/BlePipeTests` command.
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Knuckled/BLE/BlePipe.swift KnuckledTests/BlePipeTests.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: BLE duplex byte pipe for GameLinkCore"
```

---

### Task 14: BLE peripheral + central + connector + picker (device validation by user)

**Files:**
- Create: `Knuckled/BLE/BlePeripheralHost.swift`
- Create: `Knuckled/BLE/BleCentralClient.swift`
- Create: `Knuckled/BLE/BleConnector.swift`
- Create: `Knuckled/BLE/BleError.swift`
- Modify: `Knuckled/Connect/ConnectionSession.swift` (real connector selection), `Knuckled/StartScreen.swift` (transport picker labels)

Threading contract (mirrors Android's daemon-thread blocking facade): delegate callbacks run on a private serial queue; `listen`/`connect`/`discover` block the CALLER thread (ConnectionSession already backgrounds them) and never the CB queue. No timeouts/retries (Android parity) — cancel via `close`/session cancel.

- [ ] **Step 1: Implement `Knuckled/BLE/BleError.swift`**

```swift
import Foundation

enum BleError: Error, LocalizedError {
    case bluetoothOff
    case unauthorized
    case unsupported
    case peerLost
    case handshakeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Bluetooth is off. Turn it on and retry."
        case .unauthorized:
            return "Bluetooth permission was denied. Allow it in Settings, then retry."
        case .unsupported:
            return "Bluetooth LE advertising is not supported on this device."
        case .peerLost:
            return "Peer disconnected"
        case .handshakeFailed:
            return "PIN handshake failed."
        case .cancelled:
            return "Cancelled"
        }
    }
}
```
(`"Peer disconnected"` matches the existing banner string; `"PIN handshake failed."` feeds the existing wrong-PIN mapper in `ConnectionSession.onPinEntered` → "Wrong code. Try again.".)

- [ ] **Step 2: Implement `Knuckled/BLE/BlePeripheralHost.swift`** (host = GATT peripheral)

```swift
import Foundation
import CoreBluetooth
import KnuckledCore

/// Host side: advertises the service, waits for one subscriber, runs the PIN
/// handshake over the byte pipe, returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
final class BlePeripheralHost: NSObject {
    private var manager: CBPeripheralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-peripheral")
    private let pipe = BlePipe()
    private var notifyChar: CBMutableCharacteristic!
    private var subscriber: CBCentral?
    private var powered = false
    private var powerError: BleError?
    private let stateSem = DispatchSemaphore(value: 0)
    private let subscribedSem = DispatchSemaphore(value: 0)
    private var cancelled = false

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: queue)
        pipe.onWrite = { [weak self] data, _ in self?.notify(data) }
    }

    func listen(pin: String) throws -> GameLink {
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
        let service = CBMutableService(type: BleUUIDs.service, primary: true)
        let write = CBMutableCharacteristic(
            type: BleUUIDs.write,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        notifyChar = CBMutableCharacteristic(
            type: BleUUIDs.notify,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        service.characteristics = [write, notifyChar]
        manager.removeAllServices()
        manager.add(service)
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BleUUIDs.service],
            CBAdvertisementDataLocalNameKey: BleUUIDs.localName,
        ])
        while true {
            if cancelled { stop(); throw BleError.cancelled }
            if subscribedSem.wait(timeout: .now() + 0.2) == .success { break }
            if !isUsable() { stop(); throw powerError ?? .peerLost }
        }
        manager.stopAdvertising()
        if let sub = subscriber {
            pipe.mtu = sub.maximumUpdateValueLength
        }
        guard Handshake.accept(source: pipe, sink: pipe, expectedPin: pin) else {
            pipe.close()
            stop()
            throw BleError.handshakeFailed
        }
        return GameLinkCore(input: pipe, output: pipe)
    }

    func cancel() {
        cancelled = true
        pipe.close()
        stop()
    }

    private func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
    }

    private func waitPoweredOn() -> Bool {
        while true {
            if cancelled { return false }
            if powered { return true }
            if let err = powerError { return false }
            _ = stateSem.wait(timeout: .now() + 0.5)
        }
    }

    private func isUsable() -> Bool { powered && powerError == nil && !cancelled }

    private func notify(_ data: Data) {
        while true {
            if pipeClosed() || subscriber == nil { return }
            if manager.updateValue(data, for: notifyChar, onSubscribedCentrals: nil) { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func pipeClosed() -> Bool {
        // Best-effort: a closed pipe means teardown is underway.
        // (BlePipe has no public isClosed; the reader thread EOFs and the
        // link layer reports disconnect — this just stops the spin.)
        return cancelled
    }
}

extension BlePeripheralHost: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            powered = true
            powerError = nil
        case .poweredOff:
            powered = false
            powerError = .bluetoothOff
        case .unauthorized:
            powered = false
            powerError = .unauthorized
        case .unsupported:
            powered = false
            powerError = .unsupported
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
        if CBPeripheralManager.authorization == .denied || CBPeripheralManager.authorization == .restricted {
            powered = false
            powerError = .unauthorized
        }
        stateSem.signal()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == BleUUIDs.notify {
            subscriber = central
            subscribedSem.signal()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if central == subscriber as? CBCentral ?? nil { /* identity compare below */ }
        subscriber = nil
        pipe.close()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            pipe.feed(request.value ?? Data())
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        request.value = Data()
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // The notify() spin loop re-attempts; nothing to do here.
    }
}
```
Fix before writing: the `didUnsubscribeFrom` body above is garbled (`central == subscriber as? CBCentral ?? nil` is nonsense). Write it cleanly:
```swift
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if subscriber?.identifier == central.identifier {
            subscriber = nil
        }
        pipe.close()
    }
```
(`CBCentral.identifier: UUID` — compare identifiers, not object identity. Use this form.)

- [ ] **Step 3: Implement `Knuckled/BLE/BleCentralClient.swift`** (client = GATT central)

```swift
import Foundation
import CoreBluetooth
import KnuckledCore

/// Client side: scans for the service, connects, subscribes, runs the PIN
/// handshake (reliable writes), returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
final class BleCentralClient: NSObject {
    private var manager: CBCentralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-central")
    private let pipe = BlePipe()
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var found: [(peripheral: CBPeripheral, name: String?)] = []
    private let foundLock = NSLock()
    private var powered = false
    private var powerError: BleError?
    private let stateSem = DispatchSemaphore(value: 0)
    private let eventSem = DispatchSemaphore(value: 0)
    private var event = false
    private var writeAcked = false
    private let writeSem = DispatchSemaphore(value: 0)
    private var discoveredUUIDs: Set<UUID> = []
    private var cancelled = false

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
        pipe.onWrite = { [weak self] data, mode in self?.send(data, mode: mode) }
    }

    func discover(timeout: TimeInterval = 5) throws -> [DeviceInfo] {
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
        foundLock.lock(); found = []; foundLock.unlock()
        manager.scanForPeripherals(withServices: [BleUUIDs.service], options: nil)
        Thread.sleep(forTimeInterval: timeout)
        manager.stopScan()
        foundLock.lock(); defer { foundLock.unlock() }
        return found.map { DeviceInfo(name: $0.name, address: $0.peripheral.identifier.uuidString) }
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
        guard let uuid = UUID(uuidString: device.address),
              let peripheral = manager.retrievePeripherals(withIdentifiers: [uuid]).first
        else { throw BleError.peerLost }
        target = peripheral
        peripheral.delegate = self
        event = false
        manager.connect(peripheral, options: nil)
        guard waitEvent(timeout: 15) else { cleanup(); throw BleError.peerLost }
        event = false
        peripheral.discoverServices([BleUUIDs.service])
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUUIDs.service }) else {
            cleanup(); throw BleError.peerLost
        }
        event = false
        peripheral.discoverCharacteristics([BleUUIDs.write, BleUUIDs.notify], for: service)
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        guard let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == BleUUIDs.write }),
              let notify = chars.first(where: { $0.uuid == BleUUIDs.notify })
        else { cleanup(); throw BleError.peerLost }
        writeChar = write
        notifyChar = notify
        event = false
        peripheral.setNotifyValue(true, for: notify)
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        pipe.mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        // Reliable handshake writes, then fast path for the game.
        pipe.writeMode = .withResponse
        let ok = Handshake.initiate(source: pipe, sink: pipe, pin: pin)
        pipe.writeMode = .withoutResponse
        guard ok else { cleanup(); throw BleError.handshakeFailed }
        return GameLinkCore(input: pipe, output: pipe)
    }

    func cancel() {
        cancelled = true
        if let target { manager.cancelPeripheralConnection(target) }
        pipe.close()
        eventSem.signal()
        writeSem.signal()
    }

    private func cleanup() {
        if let target { manager.cancelPeripheralConnection(target) }
        pipe.close()
    }

    private func waitPoweredOn() -> Bool {
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            powerError = .unauthorized
            return false
        }
        while true {
            if cancelled { return false }
            if powered { return true }
            if powerError != nil { return false }
            _ = stateSem.wait(timeout: .now() + 0.5)
        }
    }

    private func waitEvent(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !event {
            if cancelled { return false }
            if Date() > deadline { return false }
            _ = eventSem.wait(timeout: .now() + 0.2)
        }
        return true
    }

    private func send(_ data: Data, mode: CBCharacteristicWriteType) {
        guard let target, let writeChar else { return }
        if mode == .withResponse {
            writeAcked = false
            target.writeValue(data, for: writeChar, type: .withResponse)
            _ = writeSem.wait(timeout: .now() + 5)
        } else {
            target.writeValue(data, for: writeChar, type: .withoutResponse)
        }
    }
}

extension BleCentralClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            powered = true
            powerError = nil
        case .poweredOff:
            powered = false
            powerError = .bluetoothOff
        case .unauthorized:
            powered = false
            powerError = .unauthorized
        case .unsupported:
            powered = false
            powerError = .unsupported
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            powered = false
            powerError = .unauthorized
        }
        stateSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        foundLock.lock()
        if !found.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            found.append((peripheral, peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)))
        }
        foundLock.unlock()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        event = true
        eventSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        event = false
        eventSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        pipe.close()
        eventSem.signal()
    }
}

extension BleCentralClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        event = (error == nil)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        event = (error == nil)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        event = (error == nil && characteristic.isNotifying)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BleUUIDs.notify, let value = characteristic.value else { return }
        pipe.feed(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeAcked = (error == nil)
        writeSem.signal()
    }
}
```
Review notes for the implementer (in-code comments already cover the load-bearing ones): `event` is written on the CB queue and read on the caller thread — benign single-flag pattern mirrored from Android latches, but prefer setting it only in delegate callbacks (done). `discover()` blocks the caller with `Thread.sleep` (documented Android parity — no live scan updates, single snapshot). `retrievePeripherals` requires a prior `discover()` in the same session (the UI flow guarantees it; direct API misuse throws `.peerLost` with a clear message).

- [ ] **Step 4: Implement `Knuckled/BLE/BleConnector.swift` + wire selection**

```swift
import Foundation
import KnuckledCore

/// Real radio transport behind the same blocking facade as the fake.
/// Fresh peripheral/central per call (mirrors Android connector usage).
final class BleConnector: BluetoothConnector {
    func listen(pin: String) throws -> GameLink {
        try BlePeripheralHost().listen(pin: pin)
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        try BleCentralClient().connect(device: device, pin: pin)
    }

    func discover() throws -> [DeviceInfo] {
        try BleCentralClient().discover()
    }
}
```
In `ConnectionSession`: replace `private let connector: BluetoothConnector` with both connectors + selection:
```swift
    private let fake = FakeConnector()
    private let ble = BleConnector()
    private var active: BluetoothConnector { useFake ? fake : ble }
```
And replace every `self.connector.` call with `self.active.` (3 sites: listen/discover/connect). Default: `@Published var useFake = true` → change to compile-time default:
```swift
    #if targetEnvironment(simulator)
    @Published var useFake = true
    #else
    @Published var useFake = false
    #endif
```
StartScreen picker already binds `$connection.useFake` (Task 11) with labels Nearby/Fake — no change needed.

- [ ] **Step 5: Register + build (no radio assertions possible headless)**

Run: `python3 tools/sync_project.py && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/KnuckledDD build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **` (CoreBluetooth compiles for simulator; delegates only fire on device).

- [ ] **Step 6: Commit**

```bash
git add Knuckled/BLE/ Knuckled/Connect/ConnectionSession.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: CoreBluetooth BLE transport (peripheral host + central client)"
```

- [ ] **Step 7: Device validation procedure (user-operated, 2 physical iPhones — or 1 iPhone + Android after Task 16; record results, do not change code here)**

1. Install Debug builds on both devices. Enable Bluetooth on both.
2. Device A: name → Host a game → PIN shows. Device B: name → Join → device row appears within ~10s → tap → enter PIN → game screen on both, first STATE renders.
3. Play a full game across the link (each side places ≥3 dice; force a destroy: place a value matching the peer's column). Both boards agree after every move.
4. Play again from the loser side → both reset with names kept.
5. Wrong PIN on join → "Wrong code. Try again." back on Start.
6. Bluetooth off on join → "Bluetooth is off..." error. Permission denied → permission error.
7. Mid-game: enable airplane mode on one side → other shows "Peer disconnected" and returns to Start.
Report pass/fail per step in the final report; failures become new tasks, not drive-by fixes.
```bash
git add Knuckled/BLE/ Knuckled/Connect/ConnectionSession.swift Knuckled.xcodeproj/project.pbxproj
git commit -m "feat: CoreBluetooth BLE transport (peripheral host + central client)"
```

- [ ] **Step 7: Device validation procedure (user-operated, 2 physical iPhones; record results, do not change code here)**

1. Install Debug builds on both devices. Enable Bluetooth on both.
2. Device A: name → Host a game → PIN shows. Device B: name → Join → device row appears within ~10s → tap → enter PIN → game screen on both, first STATE renders.
3. Play a full game across the link (each side places ≥3 dice; force a destroy: place a value matching the peer's column). Both boards agree after every move.
4. Play again from the loser side → both reset with names kept.
5. Wrong PIN on join → "Wrong code. Try again." back on Start.
6. Bluetooth off on join → "Bluetooth is off..." error. Permission denied → permission error.
7. Mid-game: enable airplane mode on one side → other shows "Peer disconnected" and returns to Start.
Report pass/fail per step in the final report; failures become new tasks, not drive-by fixes.

---

### Task 15: Android BLE byte pipe + tests

**Files (Android repo `/Users/robison/AndroidStudioProjects/KnuckleGame`):**
- Modify: `app/src/main/java/com/example/knucklegame/bluetooth/Protocol.kt` (add 3 UUID consts)
- Create: `app/src/main/java/com/example/knucklegame/bluetooth/BleBytePipe.kt`
- Test: `app/src/test/java/com/example/knucklegame/BleBytePipeTest.kt`

- [ ] **Step 1: Add frozen UUIDs to `Protocol.kt`** (append inside `object Protocol`):

```kotlin
    const val BLE_SERVICE_UUID = "8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A"
    const val BLE_WRITE_UUID = "AAF90241-0F50-42CF-ADFC-2BAADE92ACD1"
    const val BLE_NOTIFY_UUID = "3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA"
```

- [ ] **Step 2: Write the failing tests** (`BleBytePipeTest.kt`, JUnit4 like the existing tests):

```kotlin
package com.example.knucklegame

import com.example.knucklegame.bluetooth.BleBytePipe
import com.example.knucklegame.bluetooth.Protocol
import org.junit.Assert.*
import org.junit.Test
import kotlin.concurrent.thread

class BleBytePipeTest {

    @Test
    fun chunkSizeDefaults() {
        val pipe = BleBytePipe(mtu = 23) {}
        assertEquals(20, pipe.chunkSize())
        assertEquals(182, BleBytePipe(mtu = 185) {}.chunkSize())
        assertEquals(20, BleBytePipe(mtu = 0) {}.chunkSize())
    }

    @Test
    fun writeSplitsAndReadLineRejoins() {
        val sent = mutableListOf<ByteArray>()
        val pipe = BleBytePipe(mtu = 23, onChunk = { sent.add(it) })
        pipe.outputStream().use { out ->
            out.write("ROLL\n".toByteArray(Charsets.UTF_8))
            out.flush()
        }
        assertEquals(1, sent.size)
        sent.forEach { pipe.feed(it) }
        assertEquals("ROLL", Protocol.readLine(pipe.inputStream()))
    }

    @Test
    fun longLineSplitsToMtuChunks() {
        val sent = mutableListOf<ByteArray>()
        val pipe = BleBytePipe(mtu = 23, onChunk = { sent.add(it) })
        val line = "x".repeat(50).toByteArray(Charsets.UTF_8)
        pipe.outputStream().use { it.write(line) }
        assertEquals(3, sent.size)
        assertTrue(sent.all { it.size <= 20 })
        assertArrayEquals(line, sent.reduce { a, b -> a + b })
    }

    @Test
    fun closeUnblocksReaderAndDropsWrites() {
        var writes = 0
        val pipe = BleBytePipe(onChunk = { writes++ })
        pipe.close()
        pipe.outputStream().use { it.write("x\n".toByteArray()) }
        assertEquals(0, writes)
        assertEquals(-1, pipe.inputStream().read())
        pipe.close()
    }

    @Test
    fun overlongFrameIsFatalLikeProtocol() {
        val pipe = BleBytePipe(onChunk = {})
        pipe.feed(ByteArray(1025) { 'x'.code.toByte() })
        pipe.feed("\n".toByteArray())
        assertNull(Protocol.readLine(pipe.inputStream()))
    }

    @Test
    fun blockedReadWakesOnFeedFromAnotherThread() {
        val pipe = BleBytePipe(onChunk = {})
        var got: Int? = null
        val t = thread(isDaemon = true) { got = pipe.inputStream().read() }
        Thread.sleep(100)
        pipe.feed(byteArrayOf('A'.code.toByte()))
        t.join(2000)
        assertEquals('A'.code, got)
    }
}
```
(`BleBytePipe(mtu = 185) {}` — trailing-lambda `onChunk`; `mtu` needs a public `var` (it does — mutable for MTU updates). `"x".repeat(50)` is Kotlin stdlib ✓.)

- [ ] **Step 3: Run to verify they fail**

Run: `cd /Users/robison/AndroidStudioProjects/KnuckleGame && ./gradlew :app:testDebugUnitTest --tests "com.example.knucklegame.BleBytePipeTest" 2>&1 | tail -5`
Expected: FAIL — `BleBytePipe` unresolved.

- [ ] **Step 4: Implement `BleBytePipe.kt`**

```kotlin
package com.example.knucklegame.bluetooth

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/** Blocking duplex byte pipe fed by GATT callbacks (both directions share one
 *  pipe, mirroring the iOS BlePipe). Write path chunks by MTU (20-byte
 *  fallback); read path is framed downstream by GameLinkImpl/Protocol
 *  (1024 cap, overlong fatal). Observable behavior matches iOS. */
class BleBytePipe(
    @Volatile var mtu: Int = 23,
    private val onChunk: (ByteArray) -> Unit,
) {
    private val queue = LinkedBlockingQueue<ByteArray>()
    private val closed = AtomicBoolean(false)

    fun chunkSize(): Int = if (mtu <= 0) 20 else maxOf(mtu - 3, 1)

    fun feed(chunk: ByteArray) {
        if (!closed.get()) queue.put(chunk.copyOf())
    }

    fun readByte(): Int {
        var current: ByteArray? = null
        var offset = 0
        while (true) {
            val cur = current
            if (cur != null && offset < cur.size) return cur[offset++].toInt() and 0xFF
            if (closed.get()) return -1
            val next = queue.take()
            if (next.isEmpty()) return -1
            current = next
            offset = 0
        }
    }

    fun close() {
        if (closed.compareAndSet(false, true)) queue.put(ByteArray(0))
    }

    fun inputStream(): InputStream = object : InputStream() {
        override fun read(): Int = this@BleBytePipe.readByte()
    }

    fun outputStream(): OutputStream = object : OutputStream() {
        private val pending = ByteArrayOutputStream()

        override fun write(b: Int) {
            val toSend: ByteArray? = synchronized(this) {
                pending.write(b)
                if (b == '\n'.code) takePending() else null
            }
            if (toSend != null) sendChunks(toSend)
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            val toSend: ByteArray = synchronized(this) {
                pending.write(b, off, len)
                takePending()
            }
            sendChunks(toSend)
        }

        override fun flush() {
            val toSend: ByteArray? = synchronized(this) { takePending() }
            if (toSend != null) sendChunks(toSend)
        }

        private fun takePending(): ByteArray? {
            if (pending.size() == 0) return null
            val bytes = pending.toByteArray()
            pending.reset()
            return bytes
        }

        private fun sendChunks(bytes: ByteArray) {
            if (closed.get()) return
            val size = chunkSize()
            var i = 0
            while (i < bytes.size) {
                val j = minOf(i + size, bytes.size)
                onChunk(bytes.copyOfRange(i, j))
                i = j
            }
        }
    }
}
```
(`sendChunks` runs outside the caller's lock (bytes snapshotted inside) so a slow GATT write never blocks other writers. `read()` unblocks on close via the empty-sentinel + `closed` flag double cover.)

- [ ] **Step 5: Run**

Run: `./gradlew :app:testDebugUnitTest --tests "com.example.knucklegame.BleBytePipeTest" 2>&1 | tail -4`
Expected: `BUILD SUCCESSFUL`, 6 tests pass.

- [ ] **Step 6: Commit (in the Android repo)**

```bash
git add app/src/main/java/com/example/knucklegame/bluetooth/Protocol.kt app/src/main/java/com/example/knucklegame/bluetooth/BleBytePipe.kt app/src/test/java/com/example/knucklegame/BleBytePipeTest.kt
git commit -m "feat: BLE byte pipe with MTU chunking"
```
(Commit in `/Users/robison/AndroidStudioProjects/KnuckleGame`, same `feat:` convention.)

---

### Task 16: Android BLE connector (GATT server host + scanner client)

**Files (Android repo):**
- Create: `app/src/main/java/com/example/knucklegame/bluetooth/AndroidBleConnector.kt`

Implements the existing `BluetoothConnector` blocking facade over GATT (callers already background it; no timeouts/retries except a 30s connect cap and 5s scan window, both documented below). First read `bluetooth/GameLink.kt` lines ~100-121 and use its `GameLinkImpl.create(...)` factory signature EXACTLY (do not guess it).

- [ ] **Step 1: Implement `AndroidBleConnector.kt`**

```kotlin
package com.example.knucklegame.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** BLE transport behind the blocking BluetoothConnector facade (RFCOMM
 *  untouched). Host = GATT server + advertiser; client = scanner + GATT.
 *  Frozen UUIDs match iOS. Cancel mirrors the RFCOMM limitation (state reset;
 *  a blocked listen/connect is not unblocked — documented). */
@SuppressLint("MissingPermission")
class AndroidBleConnector(private val context: Context) : BluetoothConnector {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString(Protocol.BLE_SERVICE_UUID)
        val WRITE_UUID: UUID = UUID.fromString(Protocol.BLE_WRITE_UUID)
        val NOTIFY_UUID: UUID = UUID.fromString(Protocol.BLE_NOTIFY_UUID)
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private fun manager(): BluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: throw IllegalStateException("Bluetooth unavailable.")

    private fun adapter(): BluetoothAdapter =
        manager().adapter ?: throw IllegalStateException("Bluetooth unavailable.")

    override fun listen(pin: String): GameLink {
        val adapter = adapter()
        val advertiser = adapter.bluetoothLeAdvertiser
            ?: throw IllegalStateException("BLE advertising not supported.")
        val serverRef = AtomicReference<BluetoothGattServer?>()
        val peerRef = AtomicReference<BluetoothDevice?>()
        val subscribed = CountDownLatch(1)
        // Route notify chunks once a peer subscribes (set after server exists).
        val pipeWithNotify = BleBytePipe(onChunk = { chunk ->
            val server = serverRef.get()
            val peer = peerRef.get()
            val char = server?.getService(SERVICE_UUID)?.getCharacteristic(NOTIFY_UUID)
            if (server != null && peer != null && char != null) {
                char.value = chunk
                if (Build.VERSION.SDK_INT >= 33) {
                    server.notifyCharacteristicChanged(peer, char, false, chunk)
                } else {
                    @Suppress("DEPRECATION")
                    server.notifyCharacteristicChanged(peer, char, false)
                }
            }
        })
        val callback = object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_DISCONNECTED) pipeWithNotify.close()
            }

            override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
                pipeWithNotify.feed(value)
                serverRef.get()?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }

            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
                serverRef.get()?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, ByteArray(0))
            }

            override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
                if (descriptor.uuid == CCCD_UUID) {
                    peerRef.set(device)
                    subscribed.countDown()
                }
                serverRef.get()?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }
        val server = manager().openGattServer(context, callback)
            ?: throw IllegalStateException("Bluetooth unavailable.")
        serverRef.set(server)
        try {
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val writeChar = BluetoothGattCharacteristic(
                WRITE_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            )
            val notifyChar = BluetoothGattCharacteristic(
                NOTIFY_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ,
            )
            notifyChar.addDescriptor(BluetoothGattDescriptor(CCCD_UUID, BluetoothGattCharacteristic.PERMISSION_WRITE))
            service.addCharacteristic(writeChar)
            service.addCharacteristic(notifyChar)
            server.addService(service)

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setTimeout(0)
                .build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()
            val started = CountDownLatch(1)
            var advOk = false
            val advCallback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    advOk = true
                    started.countDown()
                }

                override fun onStartFailure(errorCode: Int) {
                    started.countDown()
                }
            }
            advertiser.startAdvertising(settings, data, advCallback)
            try {
                started.await()
                if (!advOk) throw IllegalStateException("BLE advertising failed.")
                subscribed.await()
                advertiser.stopAdvertising(advCallback)
                if (!Handshake.accept(pipeWithNotify.inputStream(), pipeWithNotify.outputStream(), pin)) {
                    throw IllegalStateException("PIN handshake failed.")
                }
                val raw = GameLinkImpl.create(pipeWithNotify.inputStream(), pipeWithNotify.outputStream())
                return ManagedBleLink(raw) {
                    try { server.close() } catch (_: Exception) { }
                }
            } finally {
                try {
                    advertiser.stopAdvertising(advCallback)
                } catch (_: Exception) {
                }
            }
        } catch (e: Exception) {
            try {
                server.close()
            } catch (_: Exception) {
            }
            throw e
        }
    }
```
Link wiring (verified against `GameLink.kt:23-26,106-119` — no further reading needed): the `GameLinkImpl` constructor is private; links are built ONLY via `GameLinkImpl.create(input: InputStream, output: OutputStream, onLine: (String) -> Unit = {}, onClosed: () -> Unit = {})`, which attaches handlers and spawns the reader thread. Both call sites below use bare `create(...)` (defaults attach no-ops; `GameHost`/`GameViewModel` assign the real handlers later, exactly like the RFCOMM path). BLE resource lifetime (server/gatt) transfers to the link with a delegating wrapper — wrapping `onClosed` directly would be lost when later code overwrites the vars, so the wrapper delegates the vars and releases resources in an overridden `close()`:

```kotlin
/** GameLink that also releases BLE resources on close. Handler vars delegate
 *  so later assignments keep working. */
private class ManagedBleLink(
    private val delegate: GameLink,
    private val onCloseResources: () -> Unit,
) : GameLink by delegate {
    override fun close() {
        delegate.close()
        try {
            onCloseResources()
        } catch (_: Exception) {
        }
    }
}
```
(Place this class inside `AndroidBleConnector`, immediately before `override fun listen`.)

`Handshake` signatures verified in `Handshake.kt` (24 lines): `accept(input, output, expectedPin)` and `initiate(input, output, pin)`, both positional — the calls below match.

Client + discover (same file, continued):
```kotlin
    override fun discover(): List<DeviceInfo> {
        val adapter = try { adapter() } catch (_: Exception) { return emptyList() }
        if (!adapter.isEnabled) return emptyList()
        val scanner = adapter.bluetoothLeScanner ?: return emptyList()
        val found = ConcurrentHashMap<String, DeviceInfo>()
        for (d in adapter.bondedDevices) {
            if (d.address.isNotBlank()) found[d.address] = DeviceInfo(d.name, d.address)
        }
        val done = CountDownLatch(1)
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                if (device.address.isNotBlank()) {
                    found[device.address] = DeviceInfo(device.name, device.address)
                }
            }
        }
        try {
            scanner.startScan(
                listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
                callback,
            )
            done.await(5, TimeUnit.SECONDS)
        } catch (_: Exception) {
        } finally {
            try { scanner.stopScan(callback) } catch (_: Exception) { }
        }
        return found.values.toList()
    }

    override fun connect(device: DeviceInfo, pin: String): GameLink {
        val adapter = adapter()
        val remote = try {
            adapter.getRemoteDevice(device.address)
        } catch (e: IllegalArgumentException) {
            throw e
        }
        val pipe = BleBytePipe(onChunk = {})
        val connected = CountDownLatch(1)
        val ready = CountDownLatch(1)
        var readyOk = false
        val subscribedAck = CountDownLatch(1)
        var subscribedOk = false
        val mtuLatch = CountDownLatch(1)
        var gattRef: BluetoothGatt? = null
        // write path needs the gatt + characteristic; set after discovery.
        lateinit var writeTarget: Pair<BluetoothGatt, BluetoothGattCharacteristic>
        val chunkPipe = BleBytePipe(onChunk = { chunk ->
            val (gatt, char) = writeTarget
            char.value = chunk
            gatt.writeCharacteristic(char)
        })
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gattRef = gatt
                    connected.countDown()
                    gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    chunkPipe.close()
                    connected.countDown()
                    ready.countDown()
                    subscribedAck.countDown()
                    mtuLatch.countDown()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                readyOk = (status == BluetoothGatt.GATT_SUCCESS)
                ready.countDown()
            }

            override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                chunkPipe.feed(characteristic.value)
            }

            override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
                chunkPipe.feed(value)
            }

            override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                subscribedOk = (status == BluetoothGatt.GATT_SUCCESS)
                subscribedAck.countDown()
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) chunkPipe.mtu = mtu
                mtuLatch.countDown()
            }
        }
        val gatt = remote.connectGatt(context, false, callback)
        try {
            if (!connected.await(30, TimeUnit.SECONDS)) throw IllegalStateException("Could not connect.")
            if (!ready.await(10, TimeUnit.SECONDS) || !readyOk) throw IllegalStateException("BLE service not found.")
            val service = gatt.getService(SERVICE_UUID)
                ?: throw IllegalStateException("BLE service not found.")
            val writeChar = service.getCharacteristic(WRITE_UUID)
                ?: throw IllegalStateException("BLE service not found.")
            val notifyChar = service.getCharacteristic(NOTIFY_UUID)
                ?: throw IllegalStateException("BLE service not found.")
            writeTarget = gatt to writeChar
            gatt.setCharacteristicNotification(notifyChar, true)
            val cccd = notifyChar.getDescriptor(CCCD_UUID)
                ?: throw IllegalStateException("BLE service not found.")
            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            gatt.writeDescriptor(cccd)
            if (!subscribedAck.await(10, TimeUnit.SECONDS) || !subscribedOk) {
                throw IllegalStateException("Could not subscribe.")
            }
            try { gatt.requestMtu(185) } catch (_: Exception) { }
            mtuLatch.await(3, TimeUnit.SECONDS)
            if (!Handshake.initiate(chunkPipe.inputStream(), chunkPipe.outputStream(), pin)) {
                throw IllegalStateException("PIN handshake failed.")
            }
            val raw = GameLinkImpl.create(chunkPipe.inputStream(), chunkPipe.outputStream())
            return ManagedBleLink(raw) {
                try { gatt.disconnect() } catch (_: Exception) { }
                try { gatt.close() } catch (_: Exception) { }
            }
        } catch (e: Exception) {
            try { gatt.disconnect() } catch (_: Exception) { }
            try { gatt.close() } catch (_: Exception) { }
            throw e
        }
    }
```

- [ ] **Step 0 (mandatory first): confirm the link wiring against `GameLink.kt`**

Read `app/src/main/java/com/example/knucklegame/bluetooth/GameLink.kt` lines 106-119 and confirm the factory reads `fun create(input: InputStream, output: OutputStream, onLine: (String) -> Unit = ..., onClosed: () -> Unit = ...)` with a private constructor and reader spawned inside `create()` (verified by the plan author — if your read disagrees, STOP and report NEEDS_CONTEXT instead of guessing). The `listen`/`connect` tails above already use bare `create(...)` + `ManagedBleLink` accordingly; no changes expected from this step.

- [ ] **Step 1: Write the file** (as specified above, `ManagedBleLink` placed before `override fun listen`)

- [ ] **Step 2: Build only (no radio assertions headless)**

Run: `cd /Users/robison/AndroidStudioProjects/KnuckleGame && ./gradlew :app:assembleDebug 2>&1 | tail -3`
Expected: `BUILD SUCCESSFUL`. (Unit tests for the pipe ran in Task 15; GATT paths are device-only.)

- [ ] **Step 3: Commit (in the Android repo)**

```bash
git add app/src/main/java/com/example/knucklegame/bluetooth/AndroidBleConnector.kt
git commit -m "feat: BLE GATT connector (server host + scanner client)"
```

---

### Task 17: Android transport toggle + cross-play validation

**Files (Android repo):**
- Modify: `app/src/main/java/com/example/knucklegame/ui/ConnectionViewModel.kt` (transport field + selection)
- Modify: `app/src/main/java/com/example/knucklegame/ui/ConnectionScreens.kt` (Classic/BLE picker row)
- Modify: `app/src/main/res/values/strings.xml` (2 strings)
- Test: existing suites must stay green

- [ ] **Step 1: ViewModel edits** — add after the `androidConnector`/`fakeConnector` fields (lines ~37-38):

```kotlin
    enum class Transport { RFCOMM, BLE }
    private val bleConnector by lazy { AndroidBleConnector(application) }
    var transport: Transport = Transport.RFCOMM
    fun setTransport(t: Transport) {
        transport = t
        refreshConnector()
    }

    private fun refreshConnector() {
        activeConnector = if (inFakeMode) fakeConnector
            else if (transport == Transport.BLE) bleConnector else androidConnector
    }
```
And in `toggleFakeMode()`: replace its `activeConnector = if ...` assignment line with a call to `refreshConnector()` (read lines ~68-85 first to place it; the assignment is the only statement to replace).

- [ ] **Step 2: StartScreen picker** — insert after the Join button block (lines ~136-141), before the `Spacer(Modifier.height(16.dp))`:

```kotlin
        Spacer(Modifier.height(12.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.testTag("transport-picker"),
        ) {
            Text(
                text = stringResource(R.string.transport_classic),
                color = if (transport == Transport.RFCOMM) Gold else Color.Gray,
                modifier = Modifier.clickable { onTransportChange(Transport.RFCOMM) }.testTag("transport-classic"),
            )
            Spacer(Modifier.width(16.dp))
            Text(
                text = stringResource(R.string.transport_ble),
                color = if (transport == Transport.BLE) Gold else Color.Gray,
                modifier = Modifier.clickable { onTransportChange(Transport.BLE) }.testTag("transport-ble"),
            )
        }
```
Add params to the `StartScreen` signature: `transport: Transport, onTransportChange: (Transport) -> Unit` (beside `onToggleFake`), import `Transport` (same package — no import needed if same file package `ui`; `Transport` is nested in `ConnectionViewModel` → reference as `ConnectionViewModel.Transport` in the composable + call site). Update the `KnuckledApp.kt` call site (line ~108): add `transport = connectionViewModel.transport, onTransportChange = connectionViewModel::setTransport,`.

- [ ] **Step 3: Strings** — append before `</resources>` in `app/src/main/res/values/strings.xml`:

```xml
    <string name="transport_classic">Classic</string>
    <string name="transport_ble">BLE</string>
```

- [ ] **Step 4: Full Android gate**

Run: `cd /Users/robison/AndroidStudioProjects/KnuckleGame && ./gradlew :app:testDebugUnitTest :app:assembleDebug 2>&1 | tail -4`
Expected: `BUILD SUCCESSFUL` (all existing tests pass — default transport is RFCOMM so no behavior change; new pipe tests from Task 15 included).

- [ ] **Step 5: Commit (in the Android repo)**

```bash
git add app/src/main/java/com/example/knucklegame/ui/ConnectionViewModel.kt app/src/main/java/com/example/knucklegame/ui/ConnectionScreens.kt app/src/main/res/values/strings.xml
git commit -m "feat: Classic/BLE transport toggle"
```

- [ ] **Step 6: Cross-play validation (user-operated: 1 Android phone + 1 iPhone, both physical; record results)**

1. Android hosts Classic (RFCOMM): iPhone cannot join (expected — documents the iOS-has-no-RFCOMM boundary; iPhone shows no Classic peer).
2. Android hosts BLE + iPhone joins BLE: full game both place ≥3 dice; destroy visible on both; scores agree every move.
3. iPhone hosts BLE + Android joins BLE: full game; same checks.
4. Play again from the loser side (both directions) → both reset, names kept.
5. Wrong PIN → "Wrong code. Try again." on the joiner.
6. Airplane mode mid-game → "Peer disconnected" + Start on the survivor.
Report pass/fail per step; failures become new tasks.

---

### Task 18: Release readiness gate

**Files:** none (verification + App Store answers; commit only if a fix is needed)

- [ ] **Step 1: Version check**

Run: `grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" Knuckled.xcodeproj/project.pbxproj | sort -u; grep -E "versionCode|versionName" /Users/robison/AndroidStudioProjects/KnuckleGame/app/build.gradle.kts`
Expected: iOS `1.0` / `1`; Android `versionCode 1`-ish / `versionName "1.0"`. (First public release = 1.0; bump only if the values differ — report, don't freelance.)

- [ ] **Step 2: Full gates (all green required)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E "Executed .* tests" | tail -1` (expect 68+, 0 failures)
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Knuckled.xcodeproj -scheme Knuckled -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -2` (expect all suites + `** TEST SUCCEEDED **`)
Run: `cd /Users/robison/AndroidStudioProjects/KnuckleGame && ./gradlew :app:testDebugUnitTest :app:assembleDebug 2>&1 | tail -2` (expect `BUILD SUCCESSFUL`)

- [ ] **Step 3: App Store answers (record in the final report, no code)**

- Tracking: NO (no IDFA, no analytics, no ads).
- Data collected: NONE (player names + scores stay on-device/in-session; UserDefaults local-only under declared CA92.1; Bluetooth peers ephemeral).
- Encryption: standard OS encryption only (`ITSAppUsesNonExemptEncryption = false` set in Info.plist).
- Content: Games, 4+ (dice game, no objectionable content, no user accounts, no chat — opponent names are player-typed session labels).
- Review notes: local multiplayer needs two physical devices; no demo account exists by design.

- [ ] **Step 4: Screenshot set (user-operated in DeviceHub)**

Capture: Start, mid-game with dice, destroy ghost visible, result overlay, iPad layout. Attach in the final report.

- [ ] **Step 5: Commit only if Step 1-2 required fixes**

Otherwise no commit (verification only).





