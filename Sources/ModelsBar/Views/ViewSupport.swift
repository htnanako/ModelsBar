import AppKit
import SwiftUI

enum ModelsBarTheme {
    static let nsSettingsWindowBackground = dynamicNSColor(
        light: NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.975, alpha: 1),
        dark: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    )

    static let nsMenuWindowBackground = dynamicNSColor(
        light: NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.125, alpha: 0.94)
    )

    static let settingsWindowBackground = Color(nsColor: nsSettingsWindowBackground)
    static let menuWindowBackground = Color(nsColor: nsMenuWindowBackground)

    static let settingsGradientStart = dynamicColor(
        light: NSColor(calibratedRed: 0.74, green: 0.86, blue: 0.98, alpha: 0.64),
        dark: NSColor(calibratedRed: 0.50, green: 0.21, blue: 0.24, alpha: 0.74)
    )
    static let settingsGradientMiddle = dynamicColor(
        light: NSColor(calibratedRed: 0.76, green: 0.94, blue: 0.88, alpha: 0.48),
        dark: NSColor(calibratedRed: 0.54, green: 0.38, blue: 0.14, alpha: 0.58)
    )
    static let settingsGradientEnd = dynamicColor(
        light: NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.975, alpha: 0.98),
        dark: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.98)
    )
    static let settingsGlow = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.54),
        dark: NSColor(calibratedWhite: 1, alpha: 0.14)
    )

    static let settingsSidebarBackground = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.54),
        dark: NSColor(calibratedWhite: 0, alpha: 0.16)
    )
    static let separator = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.48),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )

    static let menuSeparator = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.42),
        dark: NSColor(calibratedWhite: 1, alpha: 0.06)
    )
    static let menuSurface = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.70),
        dark: NSColor(calibratedWhite: 1, alpha: 0.06)
    )
    static let menuSurfaceStrong = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.84),
        dark: NSColor(calibratedWhite: 1, alpha: 0.13)
    )
    static let menuBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.40),
        dark: NSColor(calibratedWhite: 1, alpha: 0.14)
    )
    static let menuBorderSoft = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.28),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let menuHover = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )

    static let surfaceHeroStart = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.86),
        dark: NSColor(calibratedWhite: 1, alpha: 0.16)
    )
    static let surfaceHeroEnd = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.58),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let surfaceSubtleStart = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.78),
        dark: NSColor(calibratedWhite: 1, alpha: 0.09)
    )
    static let surfaceSubtleEnd = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.46),
        dark: NSColor(calibratedWhite: 1, alpha: 0.04)
    )
    static let surfaceSoftStart = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.68),
        dark: NSColor(calibratedWhite: 1, alpha: 0.07)
    )
    static let surfaceSoftEnd = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.36),
        dark: NSColor(calibratedWhite: 1, alpha: 0.03)
    )
    static let surfaceHeroBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.44),
        dark: NSColor(calibratedWhite: 1, alpha: 0.18)
    )
    static let surfaceSubtleBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.34),
        dark: NSColor(calibratedWhite: 1, alpha: 0.11)
    )
    static let surfaceSoftBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.28),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let surfaceHeroShadow = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 0, alpha: 0.20)
    )
    static let surfaceSubtleShadow = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.075),
        dark: NSColor(calibratedWhite: 0, alpha: 0.14)
    )
    static let surfaceSoftShadow = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 0, alpha: 0.10)
    )

    static let inputBackground = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.72),
        dark: NSColor(calibratedWhite: 0, alpha: 0.18)
    )
    static let inputBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.42),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let controlBackground = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.68),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let controlBorder = dynamicColor(
        light: NSColor.separatorColor.withAlphaComponent(0.34),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )
    static let pillBackground = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let progressTrack = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )
    static let inactiveSwitchTrack = dynamicColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1, alpha: 0.14)
    )
    static let switchThumb = dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 0.98),
        dark: NSColor(calibratedWhite: 1, alpha: 0.96)
    )

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }

    private static func dynamicNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

extension KeyStatus {
    var tint: Color {
        switch self {
        case .unknown: .secondary
        case .healthy: .green
        case .warning: .yellow
        case .exhausted: .red
        case .failed: .red
        case .disabled: .gray
        }
    }
}

struct StatusBadge: View {
    var status: KeyStatus
    var title: String?

    var body: some View {
        Label(title ?? status.title, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyHintView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

extension Date {
    var shortDisplay: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
