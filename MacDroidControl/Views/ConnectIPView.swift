#if os(macOS)
import SwiftUI
import AppKit

struct ConnectIPView: View {
    @ObservedObject var viewModel: DeviceManagerViewModel
    @EnvironmentObject var savedDevices: SavedDevicesStore
    @Environment(\.dismiss) private var dismiss

    @State private var ipAddress: String = ""
    @State private var showHowItWorks: Bool = false

    private var willEnableTCPIP: Bool {
        guard let dev = viewModel.selectedDevice else { return false }
        return dev.status == .connected && !dev.id.contains(":")
    }

    var body: some View {
        VStack(spacing: 22) {

            // Header
            VStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                Text("Connect via Wi-Fi")
                    .font(.title2.weight(.semibold))
                Text("Phone and Mac must be on the **same Wi-Fi** network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Quick tip banner
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Already set up wirelessly before?")
                        .font(.callout.weight(.semibold))
                    Text("Just enter the IP and tap Connect — no USB needed. USB is only required the very first time to switch the phone into wireless ADB mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.yellow.opacity(0.2), lineWidth: 1))

            howItWorksSection

            // TCP/IP hint — only show if a USB device is selected
            if willEnableTCPIP {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("USB device selected — will switch **\(viewModel.selectedDevice!.id)** to TCP/IP mode first, then connect.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            // IP Input
            VStack(alignment: .leading, spacing: 6) {
                Text("IP Address")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("192.168.1.100", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isConnecting)
                    .onSubmit { connect() }
            }

            // Error
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isConnecting)

                Spacer()

                Button {
                    connect()
                } label: {
                    if viewModel.isConnecting {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text(willEnableTCPIP ? "Setting up…" : "Connecting…")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ipAddress.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isConnecting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear { viewModel.errorMessage = nil }
        .onChange(of: viewModel.isConnecting) { _, connecting in
            guard !connecting, viewModel.errorMessage == nil else { return }
            let raw = ipAddress.trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty { savedDevices.add(ip: raw) }
            dismiss()
        }
    }

    // MARK: - Connect

    private func connect() {
        let trimmed = ipAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await viewModel.connectViaIP(ip: trimmed) }
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showHowItWorks.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("How does this work?")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showHowItWorks ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: showHowItWorks)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1))

            if showHowItWorks {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.horizontal, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        HowItWorksStep(number: 1, text: "Phone and Mac must be on the **same Wi-Fi network** — this is required")
                        HowItWorksStep(number: 2, text: "**First time only:** On the phone — Settings → Developer Options → enable **USB Debugging** (not Wireless Debugging)")
                        HowItWorksStep(number: 3, text: "**First time only:** Connect via USB cable, select the device in the sidebar, click **\"Enable Wireless ADB\"** in ADB Controls and wait 3 seconds")
                        HowItWorksStep(number: 4, text: "Find phone's IP: **Settings → Wi-Fi → tap your network name → IP Address** (e.g. 192.168.1.x)")
                        HowItWorksStep(number: 5, text: "**Enter the IP here and tap Connect.** The device is saved for next time — find it in the sidebar under Saved")
                        HowItWorksStep(number: 6, text: "After a **phone reboot**, you'll need USB again briefly to re-enable TCP mode (repeat step 3 only)")
                    }
                    .padding(14)
                }
                .background(Color(.controlBackgroundColor).opacity(0.7))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                                                  bottomTrailingRadius: 8, topTrailingRadius: 0))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                                                bottomTrailingRadius: 8, topTrailingRadius: 0)
                    .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - How It Works Step

private struct HowItWorksStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 22, height: 22)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
