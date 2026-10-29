// DayGroupingTests.swift — Today / Yesterday / older dates (F4).

import XCTest
@testable import MCAS

final class DayGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func item(_ text: String, at date: Date) -> ClipItem {
        ClipItem(id: Int64(text.hashValue), createdAt: date, kind: .text, previewText: text,
                 sourceAppBundleID: nil, sourceAppName: nil, contentHash: text, byteSize: 0, thumbnail: nil)
    }

    func testGroupsTodayYesterdayAndOlder() {
        let now = date(2026, 10, 29, 14)
        let items = [
            item("this afternoon", at: date(2026, 10, 29, 13)),
            item("this morning", at: date(2026, 10, 29, 9)),
            item("yesterday", at: date(2026, 10, 28, 20)),
            item("last week", at: date(2026, 10, 22, 10)),
        ]

        let sections = DayGrouping.group(items, now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Thursday, Oct 22"])
        XCTAssertEqual(sections[0].items.map(\.previewText), ["this afternoon", "this morning"])
    }

    func testJustAfterMidnightIsToday() {
        let now = date(2026, 10, 29, 0).addingTimeInterval(60)
        let sections = DayGrouping.group([item("late", at: date(2026, 10, 28, 23))], now: now, calendar: calendar)
        XCTAssertEqual(sections.first?.title, "Yesterday")
    }

    func testEmptyHistoryHasNoSections() {
        XCTAssertTrue(DayGrouping.group([], calendar: calendar).isEmpty)
    }
}
