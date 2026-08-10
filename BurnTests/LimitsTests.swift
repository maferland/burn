import XCTest
@testable import Burn

final class LimitsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("limits-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Helpers

    private func account(_ provider: Provider = .claude, label: String = "test") -> LimitsAccount {
        LimitsAccount(provider: provider, label: label, homePath: home.path, isAutoDetected: false)
    }

    private func writeClaudeCredentials(expiresAt: Date? = Date().addingTimeInterval(3_600)) throws {
        let expiry = expiresAt.map { "\"expiresAt\":\($0.timeIntervalSince1970 * 1000)," } ?? ""
        let json = "{\"claudeAiOauth\":{\(expiry)\"accessToken\":\"sk-test\"}}"
        try json.write(to: home.appendingPathComponent(".credentials.json"), atomically: true, encoding: .utf8)
    }

    private func transport(_ status: Int, _ body: String, calls: Counter? = nil) -> LimitsTransport {
        { request in
            calls?.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response)
        }
    }

    private final class Counter: @unchecked Sendable {
        private(set) var count = 0
        private let lock = NSLock()
        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    /// resets_at has to stay in the future: a window whose reset has passed reports as fully
    /// available again (see LimitWindow.hasReset), so a hardcoded past date silently drifted this
    /// fixture's expectations once real time caught up to it.
    private var subscriptionBody: String {
        let iso = ISO8601DateFormatter()
        let fiveHourReset = iso.string(from: Date().addingTimeInterval(3_600))
        let weekReset = iso.string(from: Date().addingTimeInterval(5 * 86_400))
        return """
        {"five_hour":{"utilization":42.5,"resets_at":"\(fiveHourReset)"},
         "seven_day":{"utilization":70.0,"resets_at":"\(weekReset)"},
         "seven_day_opus":{"utilization":12.0,"resets_at":null},
         "seven_day_sonnet":null,
         "spend":null}
        """
    }

    /// Shape returned by an enterprise usage-based seat: every window null, money instead.
    private let creditsBody = """
    {"five_hour":null,"seven_day":null,"seven_day_opus":null,"seven_day_sonnet":null,
     "extra_usage":{"is_enabled":true,"monthly_limit":1000000,"used_credits":7335.0,"utilization":0.7335},
     "spend":{"used":{"amount_minor":7335,"currency":"USD","exponent":2},
              "limit":{"amount_minor":1000000,"currency":"USD","exponent":2},
              "percent":1,"enabled":true},
     "limits":[]}
    """

    // MARK: - Claude

    func testClaudeSubscriptionWindows() async throws {
        try writeClaudeCredentials()
        let client = ClaudeLimitsClient(transport: transport(200, subscriptionBody))
        let snapshot = await client.snapshot(for: account())

        XCTAssertNil(snapshot.failure)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.window(.fiveHour)?.usedPercent, 42.5)
        XCTAssertEqual(snapshot.window(.week)?.remainingPercent, 30)
        XCTAssertEqual(snapshot.tightestWindow?.kind, .week)
        XCTAssertNil(snapshot.window(.weekOpus)?.resetsAt)
        XCTAssertNil(snapshot.spend)
        XCTAssertEqual(snapshot.source, .api)
    }

    func testClaudeCreditsSeatReportsSpendNotWindows() async throws {
        try writeClaudeCredentials()
        let client = ClaudeLimitsClient(transport: transport(200, creditsBody))
        let snapshot = await client.snapshot(for: account())

        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.spend?.usedDollars ?? 0, 73.35, accuracy: 0.001)
        XCTAssertEqual(snapshot.spend?.limitDollars ?? 0, 10_000, accuracy: 0.001)
        XCTAssertEqual(snapshot.spend?.fraction ?? 0, 0.007335, accuracy: 0.000001)
        XCTAssertTrue(snapshot.hasData)
    }

    func testClaudeExpiredTokenSkipsTheRequest() async throws {
        try writeClaudeCredentials(expiresAt: Date().addingTimeInterval(-60))
        let calls = Counter()
        let client = ClaudeLimitsClient(transport: transport(200, subscriptionBody, calls: calls))
        let snapshot = await client.snapshot(for: account())

        XCTAssertEqual(snapshot.failure?.kind, .expiredSession)
        XCTAssertEqual(calls.count, 0)
    }

    func testClaudeMissingCredentialsNamesThePath() async throws {
        let client = ClaudeLimitsClient(transport: transport(200, subscriptionBody))
        let snapshot = await client.snapshot(for: account())

        XCTAssertEqual(snapshot.failure?.kind, .noCredentials)
        XCTAssertEqual(snapshot.failure?.detail, home.appendingPathComponent(".credentials.json").path)
    }

    func testClaudeKeychainRefusalIsNotAMiss() async throws {
        let defaultAccount = LimitsAccount(
            provider: .claude, label: "default", homePath: nil, isAutoDetected: true
        )
        let client = ClaudeLimitsClient(
            transport: transport(200, subscriptionBody),
            readKeychain: { _ in .refused(-25293) }
        )
        let snapshot = await client.snapshot(for: defaultAccount)

        XCTAssertEqual(snapshot.failure?.kind, .keychainRefused)
        XCTAssertEqual(snapshot.failure?.detail, "OSStatus -25293")
    }

    func testClaudeStatusCodesAreClassified() async throws {
        try writeClaudeCredentials()
        let cases: [(Int, LimitsFailure.Kind)] = [
            (429, .rateLimited), (401, .unauthorized), (503, .network),
        ]
        for (status, kind) in cases {
            let client = ClaudeLimitsClient(transport: transport(status, ""))
            let snapshot = await client.snapshot(for: account())
            XCTAssertEqual(snapshot.failure?.kind, kind, "status \(status)")
        }
    }

    func testClaudeMalformedBody() async throws {
        try writeClaudeCredentials()
        let client = ClaudeLimitsClient(transport: transport(200, "not json"))
        let snapshot = await client.snapshot(for: account())

        XCTAssertEqual(snapshot.failure?.kind, .malformedResponse)
    }

    // MARK: - Codex

    func testCodexWindowsFromAPI() async throws {
        let auth = """
        {"tokens":{"access_token":"tok","account_id":"acct-1"},"last_refresh":"2026-08-03T10:00:00Z"}
        """
        try auth.write(to: home.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let now = Date()
        let weeklyReset = (now.timeIntervalSince1970 + 86_400).rounded()
        let body = """
        {"plan_type":"plus","rate_limit":{
          "primary_window":{"used_percent":18.0,"reset_after_seconds":600,"limit_window_seconds":18000},
          "secondary_window":{"used_percent":64.0,"reset_at":\(weeklyReset),"limit_window_seconds":604800}}}
        """
        let client = CodexLimitsClient(transport: transport(200, body))
        let snapshot = await client.snapshot(for: account(.codex), now: now)

        XCTAssertEqual(snapshot.planLabel, "Plus")
        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 82)
        XCTAssertEqual(snapshot.window(.fiveHour)?.resetsAt, now.addingTimeInterval(600))
        XCTAssertEqual(snapshot.window(.week)?.resetsAt, Date(timeIntervalSince1970: weeklyReset))
        XCTAssertEqual(snapshot.window(.week)?.remainingPercent, 36)
        XCTAssertEqual(snapshot.source, .api)
    }

    func testCodexFallsBackToRolloutLogsWhenNotSignedIn() async throws {
        let captured = Date().addingTimeInterval(-900)
        let limits = CodexRateLimits(
            capturedAt: captured,
            planType: "pro",
            primary: CodexRateLimitWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil),
            secondary: CodexRateLimitWindow(usedPercent: 40, windowMinutes: 10_080, resetsAt: nil)
        )
        let defaultAccount = LimitsAccount(
            provider: .codex, label: "codex", homePath: nil, isAutoDetected: true
        )
        let client = CodexLimitsClient(transport: transport(200, ""))
        let snapshot = await client.snapshot(for: defaultAccount, rolloutLimits: limits)

        XCTAssertEqual(snapshot.source, .rolloutLogs)
        XCTAssertEqual(snapshot.capturedAt, captured)
        XCTAssertEqual(snapshot.window(.week)?.remainingPercent, 60)
        XCTAssertEqual(snapshot.planLabel, "Pro")
    }

    /// The rollout fallback only describes the default home, so a second account can't borrow it.
    func testCodexExtraAccountGetsNoRolloutFallback() async throws {
        let limits = CodexRateLimits(
            capturedAt: Date(), planType: "pro",
            primary: CodexRateLimitWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil),
            secondary: nil
        )
        let client = CodexLimitsClient(transport: transport(200, ""))
        let snapshot = await client.snapshot(for: account(.codex), rolloutLimits: limits)

        XCTAssertEqual(snapshot.failure?.kind, .noCredentials)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testCodexEmailComesFromIdTokenClaims() throws {
        let claims = Data(#"{"email":"dev@example.com"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let auth = """
        {"tokens":{"access_token":"tok","account_id":"acct-1","id_token":"header.\(claims).sig"}}
        """
        try auth.write(to: home.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let credentials = CodexLimitsClient.credentials(home: home)
        XCTAssertEqual(credentials?.email, "dev@example.com")
        XCTAssertEqual(credentials?.accountId, "acct-1")
    }

    // MARK: - Windows

    func testWindowPastItsResetIsFullyAvailable() {
        let stale = LimitWindow(
            kind: .week, usedPercent: 95, resetsAt: Date().addingTimeInterval(-60)
        )
        XCTAssertTrue(stale.hasReset)
        XCTAssertEqual(stale.remainingPercent, 100)

        let live = LimitWindow(kind: .week, usedPercent: 95, resetsAt: Date().addingTimeInterval(60))
        XCTAssertEqual(live.remainingPercent, 5)
    }

    func testTightestPicksTheMostUsedWindowAcrossAccounts() {
        let roomy = AccountSnapshot(
            account: account(.claude, label: "work"), planLabel: nil,
            windows: [LimitWindow(kind: .week, usedPercent: 10, resetsAt: nil)],
            spend: nil, capturedAt: Date(), source: .api, failure: nil
        )
        let tight = AccountSnapshot(
            account: LimitsAccount(provider: .codex, label: "personal", homePath: "/tmp/x", isAutoDetected: false),
            planLabel: nil,
            windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 30, resetsAt: nil),
                LimitWindow(kind: .week, usedPercent: 88, resetsAt: nil),
            ],
            spend: nil, capturedAt: Date(), source: .api, failure: nil
        )
        let response = LimitsResponse(accounts: [roomy, tight])

        XCTAssertEqual(response.tightest?.snapshot.account.label, "personal")
        XCTAssertEqual(response.tightest?.window.kind, .week)
        XCTAssertEqual(response.tightest?.window.remainingPercent, 12)
    }

    func testWarningListsOnlyAccountsPastTheThreshold() {
        func snapshot(_ label: String, used: Double) -> AccountSnapshot {
            AccountSnapshot(
                account: LimitsAccount(
                    provider: .claude, label: label, homePath: "/tmp/\(label)", isAutoDetected: false
                ),
                planLabel: nil,
                windows: [LimitWindow(kind: .week, usedPercent: used, resetsAt: nil)],
                spend: nil, capturedAt: Date(), source: .api, failure: nil
            )
        }
        let response = LimitsResponse(accounts: [
            snapshot("roomy", used: 40),
            snapshot("edge", used: LimitsResponse.warningThreshold),
            snapshot("spent", used: 96),
        ])

        XCTAssertEqual(response.accountsNearCap.map(\.account.label), ["edge", "spent"])
    }

    // MARK: - Menu bar

    @MainActor
    private func extensionShowing(_ accounts: [AccountSnapshot]) -> LimitsExtension {
        let service = LimitsService(
            store: LimitsAccountStore(defaults: isolatedDefaults(), detect: { [] }),
            cacheFile: home.appendingPathComponent("menubar-cache.json")
        )
        service.response = LimitsResponse(accounts: accounts)
        let ext = LimitsExtension(service: service)
        ext.showsInMenuBar = true
        return ext
    }

    /// Text has no readable value, so the rendered literal is pulled back out of its description.
    @MainActor
    private func segmentText(_ ext: LimitsExtension) -> String? {
        guard let segment = ext.menuBarSegment() else { return nil }
        let description = String(describing: segment)
        guard let match = description.range(of: #"(?<=: \")[^"]+(?=\")"#, options: .regularExpression) else {
            return description
        }
        return String(description[match])
    }

    private func spending(_ used: Double, of limit: Double?) -> AccountSnapshot {
        AccountSnapshot(
            account: account(), planLabel: "Enterprise", windows: [],
            spend: SpendSnapshot(usedDollars: used, limitDollars: limit),
            capturedAt: Date(), source: .api, failure: nil
        )
    }

    /// A usage-based seat reports no windows at all, which used to make the toggle look broken.
    @MainActor
    func testMenuBarFallsBackToSpendWhenNoWindowsCameBack() {
        XCTAssertEqual(segmentText(extensionShowing([spending(1_098, of: 10_000)])), "◔ 89%")
    }

    @MainActor
    func testMenuBarShowsDollarsWhenTheSeatHasNoCap() {
        XCTAssertEqual(segmentText(extensionShowing([spending(1_098, of: nil)])), "◔ $1,098")
    }

    @MainActor
    func testMenuBarPrefersAWindowOverSpend() {
        let windowed = AccountSnapshot(
            account: account(), planLabel: "Max",
            windows: [LimitWindow(kind: .week, usedPercent: 30, resetsAt: nil)],
            spend: SpendSnapshot(usedDollars: 5, limitDollars: 100),
            capturedAt: Date(), source: .api, failure: nil
        )
        XCTAssertEqual(segmentText(extensionShowing([windowed])), "◔ 70%")
    }

    @MainActor
    func testMenuBarStaysEmptyWhenTheToggleIsOff() {
        let ext = extensionShowing([spending(1_098, of: 10_000)])
        ext.showsInMenuBar = false
        XCTAssertNil(ext.menuBarSegment())
    }

    func testProviderAccentsAreDistinct() {
        XCTAssertNotEqual(Provider.claude.accent, Provider.codex.accent)
        XCTAssertEqual(Provider.claude.accent, Ember.accent)
    }

    // MARK: - Service

    func testMergeKeepsLastGoodNumbersWhenARefreshFails() {
        let good = AccountSnapshot(
            account: account(), planLabel: "Pro",
            windows: [LimitWindow(kind: .week, usedPercent: 50, resetsAt: nil)],
            spend: nil, capturedAt: Date(timeIntervalSince1970: 1_785_000_000),
            source: .api, failure: nil
        )
        let rateLimited = AccountSnapshot.failed(
            account(), LimitsFailure(kind: .rateLimited, detail: nil)
        )
        let merged = LimitsService.merge(fresh: [rateLimited], previous: [good])

        XCTAssertEqual(merged.first?.window(.week)?.usedPercent, 50)
        XCTAssertEqual(merged.first?.capturedAt, good.capturedAt)
        XCTAssertEqual(merged.first?.failure?.kind, .rateLimited)
    }

    @MainActor
    func testRefreshThrottlesBelowTheMinimumInterval() async throws {
        try writeClaudeCredentials()
        let calls = Counter()
        let store = LimitsAccountStore(defaults: isolatedDefaults(), detect: { [] })
        store.add(provider: .claude, label: "work", homePath: home.path)

        let service = LimitsService(
            store: store,
            claude: ClaudeLimitsClient(transport: transport(200, subscriptionBody, calls: calls)),
            cacheFile: home.appendingPathComponent("cache.json")
        )
        service.refresh()
        try await waitUntil { !service.isLoading }
        XCTAssertEqual(calls.count, 1)

        service.refresh()
        try await waitUntil { !service.isLoading }
        XCTAssertEqual(calls.count, 1, "second refresh inside the window should be skipped")

        service.refresh(force: true)
        try await waitUntil { !service.isLoading }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(service.response.accounts.count, 1)
    }

    /// A blocking Keychain prompt used to make a fresh number look 14 minutes old.
    func testCapturedAtMarksArrivalNotCallStart() async throws {
        try writeClaudeCredentials()
        let started = Date()
        let slow: LimitsTransport = { request in
            try await Task.sleep(nanoseconds: 300_000_000)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(self.subscriptionBody.utf8), response)
        }
        let snapshot = await ClaudeLimitsClient(transport: slow).snapshot(for: account())

        let captured = try XCTUnwrap(snapshot.capturedAt)
        XCTAssertGreaterThan(captured.timeIntervalSince(started), 0.25)
    }

    func testRequestsCarryATimeout() async throws {
        try writeClaudeCredentials()
        let seen = RequestBox()
        let client = ClaudeLimitsClient(transport: { request in
            seen.store(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(self.subscriptionBody.utf8), response)
        })
        _ = await client.snapshot(for: account())

        XCTAssertEqual(seen.request?.timeoutInterval, ClaudeLimitsClient.timeout)
        XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    private final class RequestBox: @unchecked Sendable {
        private(set) var request: URLRequest?
        private let lock = NSLock()
        func store(_ request: URLRequest) {
            lock.lock()
            self.request = request
            lock.unlock()
        }
    }

    // MARK: - Account store

    @MainActor
    func testManualAccountsRoundTripAndDedupe() {
        let defaults = isolatedDefaults()
        let detected = LimitsAccount(provider: .claude, label: "detected", homePath: nil, isAutoDetected: true)
        let store = LimitsAccountStore(defaults: defaults, detect: { [detected] })

        store.add(provider: .claude, label: "personal", homePath: home.path)
        store.add(provider: .claude, label: "duplicate", homePath: home.path)
        XCTAssertEqual(store.manualAccounts.count, 1)
        XCTAssertEqual(store.accounts.map(\.label), ["detected", "personal"])

        let reloaded = LimitsAccountStore(defaults: defaults, detect: { [] })
        XCTAssertEqual(reloaded.accounts.map(\.label), ["personal"])

        reloaded.remove(id: reloaded.accounts[0].id)
        XCTAssertTrue(LimitsAccountStore(defaults: defaults, detect: { [] }).accounts.isEmpty)
    }

    @MainActor
    func testManualAccountFallsBackToTheHomeNameWhenUnlabelled() {
        let store = LimitsAccountStore(defaults: isolatedDefaults(), detect: { [] })
        store.add(provider: .codex, label: "  ", homePath: home.path)

        XCTAssertEqual(store.accounts.first?.label, home.lastPathComponent)
    }

    func testClaudeConfigFileResolution() throws {
        let configHome = home.appendingPathComponent(".claude-personal")
        try FileManager.default.createDirectory(at: configHome, withIntermediateDirectories: true)
        let inside = configHome.appendingPathComponent(".claude.json")
        try #"{"oauthAccount":{"emailDress":"x"}}"#.write(to: inside, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            LimitsAccountStore.claudeConfigFile(home: configHome, isDefaultHome: false), inside
        )
        XCTAssertNil(
            LimitsAccountStore.claudeConfigFile(home: home.appendingPathComponent("missing"), isDefaultHome: true)
        )
    }

    func testClaudeIdentityReadsEmailAndSeatTier() throws {
        let configHome = home.appendingPathComponent(".claude-work")
        try FileManager.default.createDirectory(at: configHome, withIntermediateDirectories: true)
        let json = #"{"oauthAccount":{"emailAddress":"dev@example.com","seatTier":"max_20x"}}"#
        try json.write(
            to: configHome.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8
        )

        let identity = LimitsAccountStore.identity(provider: .claude, home: configHome, isDefaultHome: false)
        XCTAssertEqual(identity.email, "dev@example.com")
        XCTAssertEqual(identity.planLabel, "Max 20×")
    }

    func testPlanLabels() {
        XCTAssertEqual(LimitsAccountStore.claudePlanLabel("enterprise_usage_based"), "Enterprise")
        XCTAssertEqual(LimitsAccountStore.claudePlanLabel("max_5x"), "Max 5×")
        XCTAssertEqual(LimitsAccountStore.claudePlanLabel("something_new"), "Something New")
        XCTAssertEqual(CodexLimitsClient.planLabel("team"), "Team")
    }

    // MARK: - Formatters

    func testSpendLine() {
        XCTAssertEqual(
            Formatters.spendLine(SpendSnapshot(usedDollars: 73.35, limitDollars: 10_000)),
            "$73 of $10,000 billed this month"
        )
        XCTAssertEqual(
            Formatters.spendLine(SpendSnapshot(usedDollars: 5, limitDollars: nil)),
            "$5 billed this month"
        )
        XCTAssertEqual(Formatters.percent(29.6), "30%")
    }

    // MARK: - Test utilities

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "limits-tests-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    private func waitUntil(
        timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !MainActor.run(body: condition) {
            if Date() > deadline { XCTFail("timed out waiting for condition"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
