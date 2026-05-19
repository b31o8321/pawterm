import SwiftUI

@main
struct PawTermApp: App {
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(serverManager)
        } label: {
            MenuBarIcon()
                .environmentObject(serverManager)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarIcon: View {
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        Image(systemName: "pawprint.fill")
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        switch serverManager.status {
        case .running:
            return serverManager.deviceCount > 0 ? .green : .blue
        case .starting:
            return .yellow
        case .stopped, .error:
            return .secondary
        }
    }
}
