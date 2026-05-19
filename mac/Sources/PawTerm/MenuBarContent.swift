import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        // Status line
        Group {
            switch serverManager.status {
            case .running:
                Text("Status: Running on localhost:\(serverManager.port)")
            case .starting:
                Text("Status: Starting…")
            case .stopped:
                Text("Status: Not running")
            case .error(let msg):
                Text("Status: Error — \(msg)")
            }
        }
        .disabled(true)

        Text("Devices: \(serverManager.deviceCount) paired")
            .disabled(true)

        Divider()

        Button("Open Admin…") {
            openAdmin()
        }
        .disabled(!serverManager.isRunning)

        Button("Show QR…") {
            openAdminQR()
        }
        .disabled(!serverManager.isRunning)

        Divider()

        if !serverManager.isRunning {
            Button("Start Server") {
                Task { await serverManager.start() }
            }
        } else {
            Button("Stop Server") {
                Task { await serverManager.stop() }
            }
        }

        Button("Restart Server") {
            Task { await serverManager.restart() }
        }

        Divider()

        Button("About PawTerm…") {
            NSWorkspace.shared.open(URL(string: "https://github.com/Airoucat233/pawterm")!)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openAdmin() {
        guard let url = AdminURL.adminURL() else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAdminQR() {
        guard let base = AdminURL.adminURL() else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.fragment = "qr"
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}
