import XCTest
@testable import Burn

final class ForgejoPRServiceTests: XCTestCase {
    private let payload = """
    [
      {
        "title": "Round distribution amounts",
        "html_url": "https://git.example.com/acme/ledger/issues/50",
        "created_at": "2026-07-27T15:24:16Z",
        "state": "closed",
        "repository": { "full_name": "acme/ledger" },
        "pull_request": {
          "merged": true,
          "merged_at": "2026-07-27T15:29:42Z",
          "html_url": "https://git.example.com/acme/ledger/pulls/50"
        }
      },
      {
        "title": "Draft the API docs",
        "html_url": "https://git.example.com/acme/platform/issues/13845",
        "created_at": "2026-07-27T15:55:27Z",
        "state": "open",
        "repository": { "full_name": "acme/platform" },
        "pull_request": { "merged": false, "merged_at": null, "html_url": null }
      },
      {
        "title": "Abandoned attempt",
        "html_url": "https://git.example.com/other/repo/issues/7",
        "created_at": "2026-07-20T10:00:00Z",
        "state": "closed",
        "repository": { "full_name": "other/repo" },
        "pull_request": { "merged": false, "merged_at": null, "html_url": null }
      },
      {
        "title": "A plain issue",
        "html_url": "https://git.example.com/acme/ledger/issues/9",
        "created_at": "2026-07-20T10:00:00Z",
        "state": "open",
        "repository": { "full_name": "acme/ledger" },
        "pull_request": null
      }
    ]
    """

    private func issues() throws -> [ForgejoIssue] {
        try ForgejoPRService.decode(Data(payload.utf8))
    }

    func testDecodesSnakeCaseAndDates() throws {
        let issues = try issues()
        XCTAssertEqual(issues.count, 4)
        XCTAssertEqual(issues[0].repository.fullName, "acme/ledger")
        XCTAssertEqual(issues[0].pullRequest?.mergedAt, ISO8601DateFormatter().date(from: "2026-07-27T15:29:42Z"))
    }

    func testMapsMergedPRToMergedState() throws {
        let prs = ForgejoPRService.pullRequests(from: try issues(), hostLabel: "git.example.com", owners: [])
        let merged = try XCTUnwrap(prs.first { $0.title == "Round distribution amounts" })

        XCTAssertEqual(merged.state, "MERGED")
        XCTAssertTrue(merged.isMerged)
        XCTAssertNotNil(merged.mergedAt)
        XCTAssertEqual(merged.provider, .forgejo)
        XCTAssertEqual(merged.hostLabel, "git.example.com")
        XCTAssertEqual(merged.url, "https://git.example.com/acme/ledger/pulls/50")
    }

    func testKeepsOpenPRsAndDropsClosedUnmergedAndPlainIssues() throws {
        let prs = ForgejoPRService.pullRequests(from: try issues(), hostLabel: "git.example.com", owners: [])

        XCTAssertEqual(prs.map(\.title).sorted(), ["Draft the API docs", "Round distribution amounts"])
    }

    func testOwnersFilterMatchesRepositoryOwnerCaseInsensitively() throws {
        let all = try issues()

        XCTAssertEqual(ForgejoPRService.pullRequests(from: all, hostLabel: "h", owners: ["ACME"]).count, 2)
        XCTAssertEqual(ForgejoPRService.pullRequests(from: all, hostLabel: "h", owners: ["nobody"]).count, 0)
    }

    func testSearchURLUsesCreatedFlagAndRFC3339Since() throws {
        let config = try XCTUnwrap(ForgejoConfig(host: "git.example.com", token: "t"))
        let since = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
        let url = ForgejoPRService.searchURL(config: config, state: "closed", since: since, page: 2)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(url.host, "git.example.com")
        XCTAssertEqual(url.path, "/api/v1/repos/issues/search")
        XCTAssertEqual(value(of: "created", in: items), "true")
        XCTAssertEqual(value(of: "type", in: items), "pulls")
        XCTAssertEqual(value(of: "state", in: items), "closed")
        XCTAssertEqual(value(of: "page", in: items), "2")
        XCTAssertEqual(value(of: "limit", in: items), "50")
        XCTAssertEqual(value(of: "since", in: items), "2026-07-01T00:00:00Z")
    }

    func testSearchURLOmitsSinceWhenNil() throws {
        let config = try XCTUnwrap(ForgejoConfig(host: "https://git.example.com", token: "t"))
        let url = ForgejoPRService.searchURL(config: config, state: "open", since: nil, page: 1)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertNil(value(of: "since", in: items))
    }

    func testAccessGatewayHTMLIsNotBlamedOnTheToken() {
        let html = Data("<!doctype html><html><head><title>Error ・ Cloudflare Access</title>".utf8)
        let error = ForgejoPRService.error(status: 403, data: html, host: "git.example.com")

        guard case .accessGateway(let host, let status) = error else {
            return XCTFail("expected accessGateway, got \(error)")
        }
        XCTAssertEqual(host, "git.example.com")
        XCTAssertEqual(status, 403)
        let message = try? XCTUnwrap(error.errorDescription)
        XCTAssertEqual(message?.contains("access gateway"), true)
        XCTAssertEqual(message?.lowercased().contains("regenerate"), false)
    }

    func testEmptyBodyCountsAsGateway() {
        guard case .accessGateway = ForgejoPRService.error(status: 502, data: Data(), host: "h") else {
            return XCTFail("expected accessGateway for an empty body")
        }
    }

    func testUnauthorizedOnlyFor401WithJSONBody() throws {
        let body = Data(#"{"message":"token is required"}"#.utf8)
        let error = ForgejoPRService.error(status: 401, data: body, host: "git.example.com")

        guard case .unauthorized(let host) = error else {
            return XCTFail("expected unauthorized, got \(error)")
        }
        XCTAssertEqual(host, "git.example.com")
        XCTAssertTrue(try XCTUnwrap(error.errorDescription).contains("read:issue"))
    }

    func testForbiddenSurfacesTheAPIMessage() throws {
        let body = Data(#"{"message":"token does not have at least one of required scope(s): [read:issue]"}"#.utf8)
        let error = ForgejoPRService.error(status: 403, data: body, host: "git.example.com")

        guard case .forbidden = error else { return XCTFail("expected forbidden, got \(error)") }
        XCTAssertTrue(try XCTUnwrap(error.errorDescription).contains("required scope(s)"))
    }

    func testOtherStatusesTrimTheBody() throws {
        let body = Data(("{\"message\":\"" + String(repeating: "x", count: 400) + "\"}").utf8)
        let error = ForgejoPRService.error(status: 500, data: body, host: "git.example.com")

        guard case .http(_, let status, let reported) = error else {
            return XCTFail("expected http, got \(error)")
        }
        XCTAssertEqual(status, 500)
        XCTAssertLessThanOrEqual(reported.count, 121)
        XCTAssertTrue(reported.hasSuffix("…"))
    }

    func testConfigRequiresHostAndToken() {
        XCTAssertNil(ForgejoConfig(host: "", token: "t"))
        XCTAssertNil(ForgejoConfig(host: "git.example.com", token: ""))
        XCTAssertEqual(ForgejoConfig(host: " git.example.com ", token: "t")?.label, "git.example.com")
    }

    private func value(of name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }
}
