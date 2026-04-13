import AppKit
import SwiftUI

let modelsBarSettingsWindowIdentifier = NSUserInterfaceItemIdentifier("ModelsBarSettingsWindow")
let modelsBarAboutWindowIdentifier = NSUserInterfaceItemIdentifier("ModelsBarAboutWindow")
let modelsBarAboutWindowID = "ModelsBarAboutWindow"

@main
struct ModelsBarApp: App {
    @StateObject private var state = ModelsBarState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(state)
                .task {
                    state.startDailyQuotaScheduler()
                }
        } label: {
            ModelsBarMenuBarIcon()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(minWidth: 1_080, minHeight: 760)
                .task {
                    state.startDailyQuotaScheduler()
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Window("About ModelsBar", id: modelsBarAboutWindowID) {
            AboutModelsBarView()
                .frame(width: 420, height: 320)
        }
        .windowResizability(.contentSize)
    }
}

private struct ModelsBarMenuBarIcon: View {
    var body: some View {
        Image(nsImage: ModelsBarBrand.menuBarIcon(size: 18))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("ModelsBar")
    }
}
