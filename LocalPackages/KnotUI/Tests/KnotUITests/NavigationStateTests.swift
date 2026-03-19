import XCTest
@testable import KnotUI

final class NavigationStateTests: XCTestCase {

    func testDefaults() {
        let state = NavigationState()
        XCTAssertEqual(state.primaryPage, .dashboard)
        XCTAssertTrue(state.detailPath.isEmpty)
    }

    func testNavigateAppends() {
        let state = NavigationState()
        state.navigate(to: .flowDetail(flowId: "f1", taskId: "1"))
        state.navigate(to: .settingAbout)

        XCTAssertEqual(state.detailPath.count, 2)
        XCTAssertEqual(state.detailPath[0], .flowDetail(flowId: "f1", taskId: "1"))
        XCTAssertEqual(state.detailPath[1], .settingAbout)
    }

    func testSwitchPrimaryClearsPath() {
        let state = NavigationState()
        state.navigate(to: .flowDetail(flowId: "f1", taskId: "1"))
        state.navigate(to: .settingAbout)
        XCTAssertEqual(state.detailPath.count, 2)

        state.switchPrimary(to: .settings)

        XCTAssertEqual(state.primaryPage, .settings)
        XCTAssertTrue(state.detailPath.isEmpty)
    }

    func testSwitchPrimaryUpdatesPage() {
        let state = NavigationState()
        XCTAssertEqual(state.primaryPage, .dashboard)

        state.switchPrimary(to: .ruleList)
        XCTAssertEqual(state.primaryPage, .ruleList)

        state.switchPrimary(to: .certificate)
        XCTAssertEqual(state.primaryPage, .certificate)
    }

    func testNavigateToVariousDestinations() {
        let state = NavigationState()

        state.navigate(to: .ruleDetail(ruleId: "r1"))
        state.navigate(to: .ruleAdd(ruleId: "r2"))
        state.navigate(to: .flowList(taskId: "1"))
        state.navigate(to: .flowDetail(flowId: "f1", taskId: "1"))
        state.navigate(to: .settingCertificate)
        state.navigate(to: .settingWeb(type: .privacy))

        XCTAssertEqual(state.detailPath.count, 6)
    }
}
