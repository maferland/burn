import Foundation

/// Reads ChatGPT plan windows for Codex. When there's no usable token it falls back to the quota
/// snapshot Codex already writes into its rollout logs, which `CodexSessionReader` parses.
struct CodexLimitsClient {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    var transport: LimitsTransport = LimitsHTTP.live

    struct Credentials {
        let accessToken: String
        let accountId: String?
        let email: String?
    }

    func snapshot(
        for account: LimitsAccount,
        rolloutLimits: CodexRateLimits? = nil,
        now: Date = Date()
    ) async -> AccountSnapshot {
        let fallback = account.isDefaultHome ? rolloutLimits : nil

        guard let credentials = Self.credentials(home: account.home) else {
            let missing = LimitsFailure(
                kind: .noCredentials, detail: LimitsAccountStore.codexAuthFile(home: account.home).path
            )
            return Self.snapshot(account, from: fallback) ?? .failed(account, missing)
        }

        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = credentials.accountId {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }

        do {
            let (data, response) = try await transport(request)
            if let failure = LimitsHTTP.failure(for: response.statusCode) {
                return Self.snapshot(account, from: fallback, failure: failure)
                    ?? .failed(account, failure)
            }
            guard let body = try? JSONDecoder().decode(UsageBody.self, from: data) else {
                let failure = LimitsFailure(kind: .malformedResponse, detail: nil)
                return Self.snapshot(account, from: fallback, failure: failure)
                    ?? .failed(account, failure)
            }
            return AccountSnapshot(
                account: account,
                planLabel: body.plan_type.map(Self.planLabel),
                windows: body.windows(now: now),
                spend: nil,
                capturedAt: now,
                source: .api,
                failure: nil
            )
        } catch {
            let failure = LimitsFailure(kind: .network, detail: error.localizedDescription)
            return Self.snapshot(account, from: fallback, failure: failure) ?? .failed(account, failure)
        }
    }

    // MARK: - Rollout-log fallback

    static func snapshot(
        _ account: LimitsAccount,
        from limits: CodexRateLimits?,
        failure: LimitsFailure? = nil
    ) -> AccountSnapshot? {
        guard let limits else { return nil }
        let windows = [
            limits.primary.map { LimitWindow(kind: .fiveHour, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) },
            limits.secondary.map { LimitWindow(kind: .week, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) },
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }

        return AccountSnapshot(
            account: account,
            planLabel: limits.planType.map(planLabel),
            windows: windows,
            spend: nil,
            capturedAt: limits.capturedAt,
            source: .rolloutLogs,
            failure: failure
        )
    }

    static func planLabel(_ raw: String) -> String {
        switch raw {
        case "plus": return "Plus"
        case "pro":  return "Pro"
        case "team": return "Team"
        default:     return raw.split(separator: "_").map(\.capitalized).joined(separator: " ")
        }
    }

    // MARK: - Credentials

    static func credentials(home: URL) -> Credentials? {
        guard let data = try? Data(contentsOf: LimitsAccountStore.codexAuthFile(home: home)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tokens = root["tokens"] as? [String: Any] ?? root
        guard let token = tokens["access_token"] as? String, !token.isEmpty else { return nil }

        let claims = (tokens["id_token"] as? String).flatMap(jwtClaims) ?? [:]
        return Credentials(
            accessToken: token,
            accountId: (tokens["account_id"] as? String) ?? (root["account_id"] as? String),
            email: claims["email"] as? String
        )
    }

    /// The email only exists inside the id_token, and only the payload segment is needed.
    static func jwtClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Response

    struct UsageBody: Decodable {
        struct Window: Decodable {
            let used_percent: Double?
            let reset_at: APITimestamp?
            let reset_after_seconds: Double?

            func resetsAt(now: Date) -> Date? {
                if let date = reset_at?.date { return date }
                return reset_after_seconds.map { now.addingTimeInterval($0) }
            }
        }

        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }

        let plan_type: String?
        let rate_limit: RateLimit?

        func windows(now: Date) -> [LimitWindow] {
            let pairs: [(LimitWindowKind, Window?)] = [
                (.fiveHour, rate_limit?.primary_window),
                (.week, rate_limit?.secondary_window),
            ]
            return pairs.compactMap { kind, window in
                guard let used = window?.used_percent else { return nil }
                return LimitWindow(kind: kind, usedPercent: used, resetsAt: window?.resetsAt(now: now))
            }
        }
    }
}
