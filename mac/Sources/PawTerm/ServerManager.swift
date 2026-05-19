import Foundation
import Combine

enum ServerStatus: Equatable {
    case stopped
    case starting
    case running
    case error(String)
}

@MainActor
class ServerManager: ObservableObject {
    @Published var status: ServerStatus = .stopped
    @Published var deviceCount: Int = 0

    let port: Int

    private var process: Process?
    private var pollTimer: Timer?
    private let config: PawTermConfig

    init() {
        self.config = PawTermConfig.load()
        self.port = config.port
        startPolling()
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    // MARK: - Control

    func start() async {
        guard case .stopped = status else { return }
        status = .starting

        guard let execURL = findExecutable("pawterm-server") else {
            status = .error("pawterm-server not found — run install.sh first")
            return
        }

        let proc = Process()
        proc.executableURL = execURL
        proc.arguments = []
        proc.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
        } catch {
            status = .error("Failed to start: \(error.localizedDescription)")
            return
        }

        self.process = proc

        // Monitor stdout for "ready" signal
        Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            for try await line in handle.bytes.lines {
                if line.lowercased().contains("ready") || line.lowercased().contains("listening") {
                    await MainActor.run { self?.status = .running }
                    return
                }
            }
        }

        // Fallback: assume running after 3s if process still alive
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if case .starting = status, proc.isRunning {
            status = .running
        }
    }

    func stop() async {
        guard let proc = process, proc.isRunning else {
            status = .stopped
            process = nil
            return
        }
        proc.interrupt() // SIGINT
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if proc.isRunning {
            proc.terminate() // SIGTERM
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        process = nil
        status = .stopped
        deviceCount = 0
    }

    func restart() async {
        await stop()
        await start()
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
        // Poll immediately
        Task { await poll() }
    }

    private func poll() async {
        let baseURL = "http://127.0.0.1:\(port)"
        let token = config.token

        // Health check
        guard let healthURL = URL(string: "\(baseURL)/health"),
              let _ = try? await URLSession.shared.data(from: healthURL) else {
            // Only update to stopped if we didn't spawn it ourselves as starting
            if case .starting = status { return }
            if process == nil {
                status = .stopped
            }
            return
        }

        // If we reach here, server is responding
        if case .stopped = status { status = .running }
        if case .error = status { status = .running }

        // Device count
        guard let token, !token.isEmpty,
              let devURL = URL(string: "\(baseURL)/admin/devices") else { return }

        var req = URLRequest(url: devURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        deviceCount = json.count
    }

    // MARK: - Helpers

    private func findExecutable(_ name: String) -> URL? {
        let searchPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/\(nvmCurrentVersion())/bin",
            "/usr/bin",
            "/bin"
        ]
        for dir in searchPaths {
            let url = URL(fileURLWithPath: "\(dir)/\(name)")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        // Also try PATH from environment
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":").map(String.init) {
                let url = URL(fileURLWithPath: "\(dir)/\(name)")
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    private func nvmCurrentVersion() -> String {
        let nvmDir = "\(NSHomeDirectory())/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvmDir)) ?? []
        return versions.sorted().last ?? "current"
    }
}

// MARK: - Config

struct PawTermConfig {
    let port: Int
    let token: String?

    static func load() -> PawTermConfig {
        let configPath = "\(NSHomeDirectory())/.config/pawterm/config.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PawTermConfig(port: 8765, token: nil)
        }
        let port = json["port"] as? Int ?? 8765
        let token = json["token"] as? String
        return PawTermConfig(port: port, token: token)
    }
}
