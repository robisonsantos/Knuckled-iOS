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
