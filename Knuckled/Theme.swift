import SwiftUI

enum AppColors {
    static let feltLight = Color(red: 0x1F / 255.0, green: 0x6B / 255.0, blue: 0x3E / 255.0)
    static let feltMid = Color(red: 0x0E / 255.0, green: 0x3A / 255.0, blue: 0x22 / 255.0)
    static let feltDark = Color(red: 0x07 / 255.0, green: 0x1A / 255.0, blue: 0x10 / 255.0)
    static let gold = Color(red: 0xE2 / 255.0, green: 0xC2 / 255.0, blue: 0x6A / 255.0)
    static let goldDark = Color(red: 0xB8 / 255.0, green: 0x90 / 255.0, blue: 0x2E / 255.0)
    static let ivory = Color(red: 0xF3 / 255.0, green: 0xE7 / 255.0, blue: 0xC3 / 255.0)
    static let dieIvoryLight = Color(red: 0xFF / 255.0, green: 0xFA / 255.0, blue: 0xF0 / 255.0)
    static let pipBrown = Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x07 / 255.0)
    static let glassWhite = Color.white.opacity(0.07)
    static let glassBorderGold = AppColors.gold.opacity(0.45)
    static let error = Color(red: 0xE5 / 255.0, green: 0x73 / 255.0, blue: 0x73 / 255.0)
}

enum AppFont {
    /// Cinzel Bold for display text (title, PIN, scores). Falls back to system bold if the font is missing.
    static func display(size: CGFloat) -> Font {
        .custom("Cinzel-Bold", size: size, relativeTo: .largeTitle)
    }
}

struct FeltBackground: View {
    var body: some View {
        RadialGradient(
            colors: [AppColors.feltLight, AppColors.feltMid, AppColors.feltDark],
            center: .center,
            startRadius: 20,
            endRadius: 700
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .background(AppColors.glassWhite)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.glassBorderGold, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark],
                    startPoint: .leading, endPoint: .trailing
                )
                .opacity(isEnabled ? 1 : 0.4)
            )
            .foregroundStyle(AppColors.pipBrown)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct GoldSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.gold.opacity(0.25))
            .foregroundStyle(AppColors.gold)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}
