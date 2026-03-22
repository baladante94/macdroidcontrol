#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileBrowserView: View {
    let device: Device
    let adb: ADBService
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath = "/sdcard"
    @State private var files: [DeviceFile] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isUploadTargeted = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTransferring = false
    @State private var selectedFiles: Set<String> = []
    @State private var pullProgress: (done: Int, total: Int) = (0, 0)

    private var selectableFiles: [DeviceFile] { files.filter { !$0.isDirectory } }
    private var allSelected: Bool { !selectableFiles.isEmpty && selectableFiles.allSatisfy { selectedFiles.contains($0.name) } }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            fileArea
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 460)
        .task(id: currentPath) { await loadFiles() }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack(spacing: 8) {
            Button { navigateUp() } label: {
                Image(systemName: "chevron.left").font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(currentPath == "/sdcard" || currentPath == "/")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    breadcrumbButton(label: "Internal Storage", path: "/sdcard")
                    ForEach(subPathComponents, id: \.path) { item in
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                        breadcrumbButton(label: item.label, path: item.path)
                    }
                }
            }

            Spacer()

            if isLoading { ProgressView().controlSize(.mini) }

            // Select All / Deselect All
            if !selectableFiles.isEmpty {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedFiles = []
                    } else {
                        selectedFiles = Set(selectableFiles.map(\.name))
                    }
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.blue)
            }

            Button { Task { await loadFiles() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private struct PathItem: Identifiable {
        var id: String { path }
        let label: String
        let path: String
    }

    private var subPathComponents: [PathItem] {
        guard currentPath.hasPrefix("/sdcard") else { return [] }
        let sub = String(currentPath.dropFirst("/sdcard".count))
        let parts = sub.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return parts.enumerated().map { i, part in
            PathItem(label: part, path: "/sdcard/" + parts[...i].joined(separator: "/"))
        }
    }

    private func breadcrumbButton(label: String, path: String) -> some View {
        Button(label) { currentPath = path }
            .buttonStyle(.plain)
            .foregroundStyle(currentPath == path ? Color.primary : Color.blue)
            .font(.callout)
    }

    // MARK: - File Area

    @ViewBuilder
    private var fileArea: some View {
        if isLoading && files.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28)).foregroundStyle(.orange)
                Text(err).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
                Button("Retry") { Task { await loadFiles() } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty && !isLoading {
            Text("This folder is empty")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(files) { file in
                fileRow(file)
            }
            .listStyle(.plain)
        }
    }

    private func fileRow(_ file: DeviceFile) -> some View {
        HStack(spacing: 10) {
            // Checkbox for files; spacer placeholder for folders to keep alignment
            if file.isDirectory {
                Color.clear.frame(width: 20)
            } else {
                Button {
                    if selectedFiles.contains(file.name) {
                        selectedFiles.remove(file.name)
                    } else {
                        selectedFiles.insert(file.name)
                    }
                } label: {
                    Image(systemName: selectedFiles.contains(file.name)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedFiles.contains(file.name) ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            }

            Image(systemName: file.systemImage)
                .foregroundStyle(file.isDirectory ? Color.blue : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .font(.callout)
                Text(file.isDirectory ? "Folder" : file.sizeFormatted)
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            Text(file.modified)
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .trailing)

            if file.isDirectory {
                Button { navigate(into: file) } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Pull") { pull(file) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTransferring)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if file.isDirectory {
                navigate(into: file)
            } else {
                // Tap anywhere on a file row also toggles selection
                if selectedFiles.contains(file.name) {
                    selectedFiles.remove(file.name)
                } else {
                    selectedFiles.insert(file.name)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            // Batch pull bar — shown when files are selected
            if !selectedFiles.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.to.line.alt")
                        .foregroundStyle(Color.blue)
                    Text("\(selectedFiles.count) file\(selectedFiles.count == 1 ? "" : "s") selected")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if isTransferring && pullProgress.total > 0 {
                        Text("\(pullProgress.done) / \(pullProgress.total)")
                            .font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: Double(pullProgress.done), total: Double(pullProgress.total))
                            .frame(width: 80)
                    }
                    Button("Pull \(selectedFiles.count) File\(selectedFiles.count == 1 ? "" : "s")") {
                        pullSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTransferring)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1))
            }

            // Upload drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isUploadTargeted ? Color.blue : Color(.separatorColor),
                        style: StrokeStyle(lineWidth: isUploadTargeted ? 2 : 1, dash: [5, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isUploadTargeted ? Color.blue.opacity(0.07) : Color.clear)
                    )

                if isTransferring && pullProgress.total == 0 {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Uploading…").font(.callout).foregroundStyle(.secondary)
                    }
                } else if isTransferring {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Pulling \(pullProgress.done) of \(pullProgress.total)…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.to.line.alt")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(isUploadTargeted ? Color.blue : Color(.tertiaryLabelColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drop files here to upload")
                                .font(.callout)
                                .foregroundStyle(isUploadTargeted ? Color.blue : Color.secondary)
                            Text(currentPath + "/")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Choose Files…") { pickAndPush() }
                            .buttonStyle(.bordered)
                            .disabled(isTransferring)
                    }
                    .padding(.horizontal, 14)
                }
            }
            .frame(height: 56)
            .onDrop(of: [UTType.fileURL], isTargeted: $isUploadTargeted) { providers in
                handleDrop(providers: providers)
            }

            if let msg = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !statusIsError {
                        Button("Show in Finder") {
                            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                            NSWorkspace.shared.open(downloads)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.blue)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Navigation

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = (parent.isEmpty || parent == "/") ? "/sdcard" : parent
    }

    private func navigate(into file: DeviceFile) {
        let base = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        currentPath = base + "/" + file.name
    }

    // MARK: - Load

    private func loadFiles() async {
        isLoading = true
        loadError = nil
        selectedFiles = []
        do {
            let raw = try await adb.listFiles(at: currentPath, deviceId: device.id)
            files = raw.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            loadError = error.localizedDescription
            files = []
        }
        isLoading = false
    }

    // MARK: - Transfer

    private func pull(_ file: DeviceFile) {
        let base = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        let remotePath = base + "/" + file.name
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        isTransferring = true
        pullProgress = (0, 0)
        statusMessage = nil
        Task {
            do {
                let url = try await adb.pull(remotePath: remotePath, to: downloads, deviceId: device.id)
                statusMessage = "'\(file.name)' saved to ~/Downloads"
                statusIsError = false
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            isTransferring = false
        }
    }

    private func pullSelected() {
        let base = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        let toPull = files.filter { !$0.isDirectory && selectedFiles.contains($0.name) }
        guard !toPull.isEmpty else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

        isTransferring = true
        pullProgress = (0, toPull.count)
        statusMessage = nil

        Task {
            var succeeded = 0
            var failed = 0

            // Pull files in parallel (up to 4 at a time to avoid overwhelming the connection)
            await withTaskGroup(of: Bool.self) { group in
                var inFlight = 0
                var iterator = toPull.makeIterator()

                func enqueue() {
                    while inFlight < 4, let file = iterator.next() {
                        let remotePath = base + "/" + file.name
                        inFlight += 1
                        group.addTask {
                            do {
                                _ = try await adb.pull(remotePath: remotePath, to: downloads, deviceId: device.id)
                                return true
                            } catch {
                                return false
                            }
                        }
                    }
                }

                enqueue()
                for await success in group {
                    if success { succeeded += 1 } else { failed += 1 }
                    pullProgress.done = succeeded + failed
                    inFlight -= 1
                    enqueue()
                }
            }

            if failed == 0 {
                statusMessage = "\(succeeded) file\(succeeded == 1 ? "" : "s") saved to ~/Downloads"
                statusIsError = false
            } else {
                statusMessage = "\(succeeded) saved, \(failed) failed"
                statusIsError = true
            }

            selectedFiles = []
            isTransferring = false
            pullProgress = (0, 0)
        }
    }

    private func pickAndPush() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        pushURLs(panel.urls)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isTransferring else { return false }
        var droppedURLs: [URL] = []
        let queue = DispatchQueue(label: "filebrowser.drop")
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL else { return }
                queue.sync { droppedURLs.append(url) }
            }
        }
        group.notify(queue: .main) {
            guard !droppedURLs.isEmpty else { return }
            pushURLs(droppedURLs)
        }
        return true
    }

    private func pushURLs(_ urls: [URL]) {
        let dest = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"
        isTransferring = true
        pullProgress = (0, 0)
        statusMessage = nil
        Task {
            do {
                try await adb.push(files: urls, to: dest, deviceId: device.id)
                let count = urls.count
                statusMessage = "\(count) file\(count == 1 ? "" : "s") uploaded to \(currentPath)/"
                statusIsError = false
                await loadFiles()
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            isTransferring = false
        }
    }
}
#endif
