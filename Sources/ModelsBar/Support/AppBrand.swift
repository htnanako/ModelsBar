import AppKit
import SwiftUI

enum ModelsBarBrand {
    static func menuBarIcon(size: CGFloat) -> NSImage {
        let image = makeLogoImage(size: size, colorful: false)
        image.isTemplate = true
        return image
    }

    static func aboutLogo(size: CGFloat) -> NSImage {
        makeLogoImage(size: size, colorful: true)
    }

    private static func makeLogoImage(size: CGFloat, colorful: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        defer {
            image.unlockFocus()
        }

        let rect = NSRect(origin: .zero, size: image.size)
        let inset = size * 0.1
        let content = rect.insetBy(dx: inset, dy: inset)
        let cornerRadius = size * 0.24

        if colorful {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.15, green: 0.44, blue: 0.93, alpha: 1),
                NSColor(calibratedRed: 0.08, green: 0.74, blue: 0.72, alpha: 1)
            ])!
            let background = NSBezierPath(roundedRect: content, xRadius: cornerRadius, yRadius: cornerRadius)
            gradient.draw(in: background, angle: 45)

            NSColor.white.withAlphaComponent(0.16).setStroke()
            background.lineWidth = max(1.6, size * 0.02)
            background.stroke()
        } else {
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: content, xRadius: cornerRadius, yRadius: cornerRadius)
            outline.lineWidth = max(1.5, size * 0.09)
            outline.stroke()
        }

        let barWidth = content.width * 0.14
        let gap = content.width * 0.09
        let leftX = content.minX + content.width * 0.2
        let baseY = content.minY + content.height * 0.18
        let heights = [content.height * 0.28, content.height * 0.46, content.height * 0.62]
        let barColor = colorful ? NSColor.white.withAlphaComponent(0.94) : NSColor.black

        barColor.setFill()
        for (index, height) in heights.enumerated() {
            let x = leftX + CGFloat(index) * (barWidth + gap)
            let barRect = NSRect(x: x, y: baseY, width: barWidth, height: height)
            let radius = min(barWidth / 2, size * 0.08)
            NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
        }

        let checkColor = colorful ? NSColor(calibratedRed: 0.93, green: 1, blue: 0.98, alpha: 1) : NSColor.black
        checkColor.setStroke()
        let check = NSBezierPath()
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.lineWidth = max(1.8, size * 0.085)
        check.move(to: NSPoint(x: content.minX + content.width * 0.26, y: content.minY + content.height * 0.51))
        check.line(to: NSPoint(x: content.minX + content.width * 0.41, y: content.minY + content.height * 0.36))
        check.line(to: NSPoint(x: content.minX + content.width * 0.74, y: content.minY + content.height * 0.72))
        check.stroke()

        if colorful {
            NSColor.white.withAlphaComponent(0.24).setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: content.minX + content.width * 0.68,
                    y: content.minY + content.height * 0.14,
                    width: content.width * 0.14,
                    height: content.width * 0.14
                )
            ).fill()
        }

        return image
    }
}

enum AppMetadata {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "ModelsBar"
    }

    static var marketingVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    static var buildVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    static var versionDescription: String {
        "Version \(marketingVersion) (\(buildVersion))"
    }
}

struct AboutModelsBarView: View {
    private let repositoryURL = URL(string: "https://github.com/htnanako/ModelsBar")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: ModelsBarBrand.aboutLogo(size: 72))
                    .interpolation(.high)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppMetadata.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(AppMetadata.versionDescription)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("A lightweight macOS menu bar app for checking model lists, quotas, and connectivity across NewAPI and OpenAI-compatible endpoints.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                aboutRow(title: "Author", value: "htnanako")
                aboutRow(title: "Copyright", value: "© 2026 htnanako")
                aboutRow(title: "License", value: "MIT License")
                repoRow(title: "Repo", url: repositoryURL)
            }

            Spacer()

            Text("ModelsBar helps you keep a quick eye on provider health, key availability, quota usage, and model test results directly from the status bar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AboutWindowConfigurator())
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor.windowBackgroundColor),
                    Color(nsColor: NSColor.controlBackgroundColor).opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.callout)
        }
    }

    private func repoRow(title: String, url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Link(destination: url) {
                Text("Github")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help(url.absoluteString)
        }
    }
}

private struct AboutWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.identifier = modelsBarAboutWindowIdentifier
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.isReleasedWhenClosed = false
    }
}
