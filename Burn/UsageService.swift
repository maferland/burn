import Foundation

private let commandTimeout: TimeInterval = 30

@Observable
@MainActor
final class UsageService {
    var usageData: UsageData = .empty
    var isLoading = false
    var errorMessage: String?

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func startAutoRefresh() {
        refresh()
        scheduleTimer()
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func restartAutoRefresh() {
        stopAutoRefresh()
        scheduleTimer()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let json = try await runCCUsage()
                let response = try JSONDecoder().decode(CCUsageResponse.self, from: json)
                usageData = UsageData.from(response: response)
            } catch is CancellationError {
                // Cancelled
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func scheduleTimer() {
        let interval = TimeInterval(settings.refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private nonisolated func runCCUsage() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let lock = NSLock()
            var resumed = false

            @Sendable func resumeOnce(with result: Result<Data, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", "ccusage daily --json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    resumeOnce(with: .success(data))
                } else {
                    resumeOnce(with: .failure(UsageError.commandFailed(process.terminationStatus)))
                }
            }

            do {
                try process.run()

                DispatchQueue.global().asyncAfter(deadline: .now() + commandTimeout) {
                    guard process.isRunning else { return }
                    process.terminate()
                    resumeOnce(with: .failure(UsageError.timeout))
                }
            } catch {
                resumeOnce(with: .failure(error))
            }
        }
    }
}

enum UsageError: LocalizedError {
    case commandFailed(Int32)
    case timeout

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code):
            code == 127
                ? "ccusage not found. Run: npm i -g ccusage"
                : "ccusage exited with code \(code)"
        case .timeout:
            "ccusage timed out after \(Int(commandTimeout))s"
        }
    }
}
