import SwiftUI
import AppKit

@main
struct MacDroidControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var deviceVM          = DeviceManagerViewModel()
    @StateObject private var sessionVM         = SessionViewModel()
    @StateObject private var nicknameStore     = NicknameStore()
    @StateObject private var savedDevicesStore = SavedDevicesStore()
    @StateObject private var appSettings       = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceVM)
                .environmentObject(sessionVM)
                .environmentObject(nicknameStore)
                .environmentObject(savedDevicesStore)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.theme.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MacDroidControl", systemImage: "candybarphone") {
            MenuBarContent()
                .environmentObject(deviceVM)
                .environmentObject(sessionVM)
                .environmentObject(nicknameStore)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Attach window delegate to show one-time close hint
        DispatchQueue.main.async {
            NSApplication.shared.windows.first?.delegate = self
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let shown = UserDefaults.standard.bool(forKey: "hasShownMenuBarHint")
        guard !shown else { return true }
        UserDefaults.standard.set(true, forKey: "hasShownMenuBarHint")

        let alert = NSAlert()
        alert.messageText = "MacDroidControl stays in the menu bar"
        alert.informativeText = "The app keeps running in the background so your devices stay connected. Click the \u{2706} icon in the menu bar to reopen this window, or choose Quit to exit completely."
        alert.addButton(withTitle: "Got it")
        alert.alertStyle = .informational
        if let icon = NSImage(systemSymbolName: "menubar.arrow.up.rectangle", accessibilityDescription: nil) {
            alert.icon = icon
        }
        alert.runModal()
        return true
    }
}
