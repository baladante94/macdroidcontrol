#if os(macOS)
import SwiftUI
import AppKit

struct AppManagerView: View {
    let device: Device
    let adb: ADBService
    @Environment(\.dismiss) private var dismiss

    @State private var apps: [AppInfo] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var filteredApps: [AppInfo] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.readableName.localizedCaseInsensitiveContains(searchText) ||
            $0.packageName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            appList
            if let msg = statusMessage {
                Divider()
                statusBar(msg)
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .task { await loadApps() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("App Manager")
                    .font(.title3.weight(.semibold))
                Text("Third-party apps on device")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small).padding(.trailing, 6)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - App List

    @ViewBuilder
    private var appList: some View {
        if isLoading && apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("No third-party apps found")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredApps) { app in
                appRow(app)
            }
            .listStyle(.plain)
        }
    }

    private func appRow(_ app: AppInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 0.5)
                    )
                Image(systemName: "app.badge")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.readableName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(app.packageName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Launch") { launch(app) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Uninstall") { confirmUninstall(app) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(Color.red)
        }
        .padding(.vertical, 2)
    }

    private func statusBar(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(statusIsError ? Color.red : Color.green)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func loadApps() async {
        isLoading = true
        statusMessage = nil
        do {
            apps = try await adb.listInstalledApps(deviceId: device.id)
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        isLoading = false
    }

    private func launch(_ app: AppInfo) {
        Task {
            do {
                try await adb.launchApp(package: app.packageName, deviceId: device.id)
                statusMessage = "Launched \(app.readableName)"
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func confirmUninstall(_ app: AppInfo) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \"\(app.readableName)\"?"
        alert.informativeText = "\(app.packageName) will be removed for the current user."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await adb.uninstallApp(package: app.packageName, deviceId: device.id)
                apps.removeAll { $0.packageName == app.packageName }
                statusMessage = "\(app.readableName) uninstalled"
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }
}
#endif
