// NotchGeometryTests.swift — finding the notch and placing the shelf.

import XCTest
@testable import MCAS

final class NotchGeometryTests: XCTestCase {
    /// Roughly a 14" MacBook Pro in its default scaled resolution.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testFindsNotchBetweenTheTwoMenuBarAreas() {
        let g = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 32, leftAreaWidth: 655, rightAreaWidth: 655, menuBarHeight: 24)

        XCTAssertTrue(g.hasNotch)
        XCTAssertEqual(g.notchRect, CGRect(x: 655, y: 950, width: 202, height: 32))
    }

    func testScreenWithoutNotchGetsCenterTab() {
        let g = NotchGeometry.compute(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      safeAreaTop: 0, leftAreaWidth: 0, rightAreaWidth: 0, menuBarHeight: 24)

        XCTAssertFalse(g.hasNotch)
        XCTAssertEqual(g.notchRect.midX, 960)
        XCTAssertEqual(g.notchRect.maxY, 1080, "tab touches the top edge")
        XCTAssertEqual(g.notchRect.width, NotchGeometry.fallbackTabWidth)
    }

    func testSecondScreenToTheRightUsesItsOwnCoordinates() {
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let g = NotchGeometry.compute(screenFrame: external, safeAreaTop: 0, leftAreaWidth: 0, rightAreaWidth: 0, menuBarHeight: 24)
        XCTAssertEqual(g.notchRect.midX, external.midX)
    }

    func testShelfHangsFromTopCenteredOnNotch() {
        let g = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 32, leftAreaWidth: 655, rightAreaWidth: 655, menuBarHeight: 24)
        let frame = g.shelfFrame(width: 480, height: 600)

        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.midX, g.notchRect.midX)
        XCTAssertEqual(frame.width, 480)
    }

    func testShelfStaysOnScreenOnTinyDisplays() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 600)
        let g = NotchGeometry.compute(screenFrame: small, safeAreaTop: 0, leftAreaWidth: 0, rightAreaWidth: 0, menuBarHeight: 24)
        let frame = g.shelfFrame(width: 480, height: 500)

        XCTAssertGreaterThanOrEqual(frame.minX, small.minX)
        XCTAssertLessThanOrEqual(frame.maxX, small.maxX)
    }
}
