import Foundation

/// Pacing knobs that make the CPU feel human. All injectable in tests.
public enum CpuPacing {
    public static let preRollSeconds: Double = 0.6
    public static func naturalThink() -> Double { .random(in: 0.7...1.1) }
}
