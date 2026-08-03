import Foundation

/// Reads Claude's plan windows from the undocumented endpoint `/usage` uses inside Claude Code. Never
/// refreshes the token: rotating it would log the CLI out.
struct ClaudeLimitsClient {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    var transport: LimitsTransport = LimitsHTTP.live
    var readKeychain: (String) -> KeychainStore.ReadResult = { KeychainStore.read(service: $0) }

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?

        func isExpired(now: Date) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }

    func snapshot(for account: LimitsAccount, now: Date = Date()) async -> AccountSnapshot {
        let planLabel = LimitsAccountStore
            .identity(provider: .claude, home: account.home, isDefaultHome: account.isDefaultHome)
            .planLabel

        let credentials: Credentials
        switch lookupCredentials(for: account) {
        case .success(let found):
            credentials = found
        case .failure(let failure):
            return AccountSnapshot.failed(account, failure).withPlan(planLabel)
        }

        if credentials.isExpired(now: now) {
            return AccountSnapshot
                .failed(account, LimitsFailure(kind: .expiredSession, detail: nil))
                .withPlan(planLabel)
        }

        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await transport(request)
            if let failure = LimitsHTTP.failure(for: response.statusCode) {
                return AccountSnapshot.failed(account, failure).withPlan(planLabel)
            }
            guard let body = try? JSONDecoder().decode(UsageBody.self, from: data) else {
                return AccountSnapshot
                    .failed(account, LimitsFailure(kind: .malformedResponse, detail: nil))
                    .withPlan(planLabel)
            }
            return AccountSnapshot(
                account: account,
                planLabel: planLabel,
                windows: body.windows,
                spend: body.spendSnapshot,
                capturedAt: now,
                source: .api,
                failure: nil
            )
        } catch {
            return AccountSnapshot
                .failed(account, LimitsFailure(kind: .network, detail: error.localizedDescription))
                .withPlan(planLabel)
        }
    }

    // MARK: - Credentials

    /// A custom `CLAUDE_CONFIG_DIR` keeps its own `.credentials.json`; the default login lives in the Keychain, whose ACL is bound to Claude Code — so a refusal is a different outcome from a miss.
    func lookupCredentials(for account: LimitsAccount) -> Result<Credentials, LimitsFailure> {
        let file = account.home.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: file) {
            guard let credentials = Self.parse(data) else {
                return .failure(LimitsFailure(kind: .malformedResponse, detail: file.path))
            }
            return .success(credentials)
        }

        guard account.isDefaultHome else {
            return .failure(LimitsFailure(kind: .noCredentials, detail: file.path))
        }

        switch readKeychain(Self.keychainService) {
        case .value(let json):
            guard let credentials = Self.parse(Data(json.utf8)) else {
                return .failure(LimitsFailure(kind: .malformedResponse, detail: "Keychain item"))
            }
            return .success(credentials)
        case .missing:
            return .failure(LimitsFailure(kind: .noCredentials, detail: file.path))
        case .refused(let status):
            return .failure(LimitsFailure(kind: .keychainRefused, detail: "OSStatus \(status)"))
        }
    }

    static func parse(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        // `expiresAt` is epoch milliseconds.
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(accessToken: token, expiresAt: expiresAt)
    }

    // MARK: - Response

    /// Subscription seats fill the window fields; enterprise usage-based seats leave them null and report `spend` instead. Utilization is already a percentage.
    struct UsageBody: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: APITimestamp?
        }

        struct Money: Decodable {
            let amount_minor: Double?
            let exponent: Int?

            var dollars: Double? {
                guard let amount_minor else { return nil }
                return amount_minor / pow(10, Double(exponent ?? 2))
            }
        }

        struct Spend: Decodable {
            let used: Money?
            let limit: Money?
            let enabled: Bool?
        }

        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
        let spend: Spend?

        var windows: [LimitWindow] {
            let pairs: [(LimitWindowKind, Window?)] = [
                (.fiveHour, five_hour),
                (.week, seven_day),
                (.weekOpus, seven_day_opus),
                (.weekSonnet, seven_day_sonnet),
            ]
            return pairs.compactMap { kind, window in
                guard let utilization = window?.utilization else { return nil }
                return LimitWindow(
                    kind: kind, usedPercent: utilization, resetsAt: window?.resets_at?.date
                )
            }
        }

        var spendSnapshot: SpendSnapshot? {
            guard let spend, let used = spend.used?.dollars else { return nil }
            guard spend.enabled == true || used > 0 else { return nil }
            return SpendSnapshot(usedDollars: used, limitDollars: spend.limit?.dollars)
        }
    }
}

extension AccountSnapshot {
    func withPlan(_ label: String?) -> AccountSnapshot {
        var copy = self
        copy.planLabel = label ?? copy.planLabel
        return copy
    }
}
