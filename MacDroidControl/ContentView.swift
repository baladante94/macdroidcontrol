import SwiftUI

#if os(macOS)
struct ContentView: View {
    @EnvironmentObject private var deviceVM:      DeviceManagerViewModel
    @EnvironmentObject private var sessionVM:     SessionViewModel
    @EnvironmentObject private var nicknameStore: NicknameStore
    @State private var showConnectIP = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: deviceVM, sessionVM: sessionVM)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            MainView(deviceVM: deviceVM, sessionVM: sessionVM)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await deviceVM.refreshDevices() }
                } label: {
                    if deviceVM.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(deviceVM.isRefreshing)
                .help("Refresh device list")

                Button { showConnectIP = true } label: {
                    Image(systemName: "wifi")
                }
                .help("Connect via Wi-Fi")
                .disabled(!deviceVM.adbAvailable)

            }
        }
        .sheet(isPresented: $showConnectIP) {
            ConnectIPView(viewModel: deviceVM)
        }
        .frame(minWidth: 740, minHeight: 480)
    }
}
#else
struct ContentView: View {
    var body: some View { Text("MacDroidControl requires macOS.") }
}
#endif

#Preview {
    ContentView()
        .environmentObject(DeviceManagerViewModel())
        .environmentObject(SessionViewModel())
        .environmentObject(NicknameStore())
}
