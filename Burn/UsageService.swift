import Foundation

@Observable
final class UsageService: @unchecked Sendable {
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
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await Task.detached {
                    try SessionReader.readUsage()
                }.value
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
}
