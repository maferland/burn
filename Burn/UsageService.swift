import Foundation

private let commandTimeout: TimeInterval = 30

@Observable
final class UsageService: @unchecked Sendable {
    var usageData: UsageData = .empty
    var isLoading = false
    var errorMessage: String?

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private let settings: SettingsStore
    private let lock = NSLock()

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
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let json = try await self.runCCUsage()
                let response = try JSONDecoder().decode(CCUsageResponse.self, from: json)
                let data = UsageData.from(response: response)
                await MainActor.run {
                    self.usageData = data
                    self.isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func scheduleTimer() {
        let interval = TimeInterval(settings.refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func runCCUsage() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let guard_ = ContinuationGuard(continuation: continuation)

            let process = Process()
            let pipe = Pipe()

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", "ccusage daily --json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    guard_.resume(with: .success(data))
                } else {
                    guard_.resume(with: .failure(UsageError.commandFailed(process.terminationStatus)))
                }
            }

            do {
                try process.run()

                DispatchQueue.global().asyncAfter(deadline: .now() + commandTimeout) {
                    guard process.isRunning else { return }
                    process.terminate()
                    guard_.resume(with: .failure(UsageError.timeout))
                }
            } catch {
                guard_.resume(with: .failure(error))
            }
        }
    }
}

private final class ContinuationGuard<T: Sendable>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Error>
    private let lock = NSLock()
    private var resumed = false

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
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
