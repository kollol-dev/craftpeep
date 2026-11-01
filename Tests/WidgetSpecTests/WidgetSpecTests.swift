import XCTest
@testable import WidgetSpec

final class WidgetSpecTests: XCTestCase {
    func testSpecVersion() {
        XCTAssertEqual(WidgetSpecInfo.version, "0.1")
    }
}
