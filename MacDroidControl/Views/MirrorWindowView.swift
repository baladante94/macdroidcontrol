#if os(macOS)
import SwiftUI

/// Content of the floating mirror window.
/// Shows the live device frame with a translucent auto-hiding toolbar.
struct MirrorWindowView: View {
    let device: Device
    @ObservedObject var session: MirrorSession
    @ObservedObject var sessionVM: SessionViewModel
    @ObservedObject var deviceVM: DeviceManagerViewModel

    @State private var toolbarVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let error = session.lastError {
                errorOverlay(error)
            } else {
                MirrorDisplayView(device: device, session: session)
            }

            // Auto-hiding toolbar
            if toolbarVisible {
                floatingToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toolbarVisible)
        .onContinuousHover { phase in
            switch phase {
            case .active: showToolbar()
            case .ended:  scheduleHide()
            }
        }
        .onAppear { showToolbar() }
        .onChange(of: session.isRunning) { _, running in
            if !running { showToolbar() }
        }
    }

    // MARK: - Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 14) {
            // Live indicator + device name
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isRunning ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                    .shadow(color: session.isRunning ? .green.opacity(0.6) : .clear, radius: 4)
                Text(device.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer()

            // Record toggle
            ToolbarIconButton(
                symbol: sessionVM.isRecording(for: device.id) ? "stop.circle.fill" : "record.circle",
                tint: sessionVM.isRecording(for: device.id) ? .red : .white.opacity(0.8),
                help: sessionVM.isRecording(for: device.id) ? "Stop recording" : "Start recording"
            ) {
                if sessionVM.isRecording(for: device.id) {
                    sessionVM.stopRecording(device: device)
                } else {
                    sessionVM.startRecording(device: device)
                }
            }

            // Screenshot
            ToolbarIconButton(symbol: "camera", help: "Screenshot to Save Location") {
                sessionVM.takeScreenshot(for: device, deviceVM: deviceVM)
            }

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 14)

            // Stop / close mirror
            ToolbarIconButton(symbol: "xmark.circle.fill", tint: .white.opacity(0.6), help: "Stop mirroring") {
                sessionVM.stopSession(for: device.id)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.96))
    }

    // MARK: - Error

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar auto-hide

    private func showToolbar() {
        hideTask?.cancel()
        withAnimation { toolbarVisible = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { toolbarVisible = false }
        }
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButton: View {
    let symbol: String
    var tint: Color = .white.opacity(0.8)
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.white.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}
#endif
