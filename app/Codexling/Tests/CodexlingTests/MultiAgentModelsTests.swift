import XCTest
@testable import Codexling

final class MultiAgentModelsTests: XCTestCase {
    func testPriorityOrderMatchesCommittedRoadmap() {
        XCTAssertEqual(
            BuiltInAgentCatalog.developmentPriority,
            [
                .init(agentID: .codex, surface: nil),
                .init(agentID: .hermes, surface: .hermesCLI),
                .init(agentID: .claudeCode, surface: .claudeCodeCLI),
                .init(agentID: .claudeCode, surface: .claudeCodeDesktop),
                .init(agentID: .reasonix, surface: nil),
            ]
        )
    }

    func testClaudeCodeDesktopIsASurfaceNotASecondIdentityDomain() throws {
        let claude = try XCTUnwrap(
            BuiltInAgentCatalog.prioritized.first(where: { $0.id == .claudeCode })
        )

        XCTAssertTrue(claude.surfaces.contains(.claudeCodeCLI))
        XCTAssertTrue(claude.surfaces.contains(.claudeCodeDesktop))
    }

    func testSameVendorSessionIDDoesNotCollideAcrossCodexAccounts() {
        let personal = ConnectionID(rawValue: UUID())
        let work = ConnectionID(rawValue: UUID())

        let first = AgentSessionID(
            agentID: .codex,
            connectionID: personal,
            vendorSessionID: "thread-1"
        )
        let second = AgentSessionID(
            agentID: .codex,
            connectionID: work,
            vendorSessionID: "thread-1"
        )

        XCTAssertNotEqual(first, second)
    }

    func testCodexAccountsUseSeparateHomes() {
        let personal = AgentConnection(
            id: ConnectionID(rawValue: UUID()),
            agentID: .codex,
            label: "Personal",
            isolation: .codexHome(relativeDirectory: "codex/personal")
        )
        let work = AgentConnection(
            id: ConnectionID(rawValue: UUID()),
            agentID: .codex,
            label: "Work",
            isolation: .codexHome(relativeDirectory: "codex/work")
        )

        XCTAssertNotEqual(personal.isolation, work.isolation)
    }

    func testDeepSeekBalancesRemainConnectionScopedButAccountLevel() {
        let firstConnection = ConnectionID(rawValue: UUID())
        let secondConnection = ConnectionID(rawValue: UUID())
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ProviderBalanceSnapshot(
            connectionID: firstConnection,
            providerID: .deepSeek,
            scope: .account,
            currency: "CNY",
            total: 110,
            granted: 10,
            toppedUp: 100,
            fetchedAt: timestamp
        )
        let second = ProviderBalanceSnapshot(
            connectionID: secondConnection,
            providerID: .deepSeek,
            scope: .account,
            currency: "CNY",
            total: 110,
            granted: 10,
            toppedUp: 100,
            fetchedAt: timestamp
        )

        XCTAssertNotEqual(first.connectionID, second.connectionID)
        XCTAssertEqual(first.scope, .account)
        XCTAssertEqual(second.scope, .account)
    }
}
