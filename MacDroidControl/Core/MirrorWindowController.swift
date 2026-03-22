#if os(macOS)
import AppKit
import SwiftUI

/// Opens and manages the floating device-mirror window.
@MainActor
final class MirrorWindowController: NSObject, NSWindowDelegate {

    var onWindowClose: (() -> Void)?

    private weak var window: NSWindow?

    func open(
        device: Device,
        session: MirrorSession,
        sessionVM: SessionViewModel,
        deviceVM: DeviceManagerViewModel
    ) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = MirrorWindowView(
            device: device,
            session: session,
            sessionVM: sessionVM,
            deviceVM: deviceVM
        )
        let hosting = NSHostingController(rootView: content)

        // Match a standard phone aspect ratio at a comfortable desktop size.
        // 393 × 852 = iPhone 15 logical points — good default.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 393, height: 852),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility             = .hidden
        w.titlebarAppearsTransparent  = true
        w.isMovableByWindowBackground = true
        w.backgroundColor             = .black
        w.contentMinSize              = NSSize(width: 260, height: 500)
        w.contentViewController       = hosting
        w.level                       = .floating
        w.setFrameAutosaveName("MirrorFloatingWindow")
        w.delegate                    = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    func bringToFront() {
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
            self.onWindowClose?()
        }
    }
}
#endif
