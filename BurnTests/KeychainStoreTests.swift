import XCTest
@testable import Burn

final class KeychainStoreTests: XCTestCase {
    private let service = "burn.tests.keychain-store"

    override func setUp() {
        KeychainStore.delete(service: service)
    }

    override func tearDown() {
        KeychainStore.delete(service: service)
    }

    func testReadReportsMissingWhenNothingStored() {
        guard case .missing = KeychainStore.read(service: service) else {
            return XCTFail("expected missing for an unused service")
        }
    }

    func testWriteThenReadReturnsTheTrimmedToken() {
        KeychainStore.write("  tok-1\n", service: service)

        guard case .value(let token) = KeychainStore.read(service: service) else {
            return XCTFail("expected a stored value")
        }
        XCTAssertEqual(token, "tok-1")
    }

    func testWriteReplacesAnExistingToken() {
        KeychainStore.write("tok-1", service: service)
        KeychainStore.write("tok-2", service: service)

        guard case .value(let token) = KeychainStore.read(service: service) else {
            return XCTFail("expected a stored value")
        }
        XCTAssertEqual(token, "tok-2")
    }

    func testDeleteClearsTheToken() {
        KeychainStore.write("tok-1", service: service)
        KeychainStore.delete(service: service)

        guard case .missing = KeychainStore.read(service: service) else {
            return XCTFail("expected missing after delete")
        }
    }
}
