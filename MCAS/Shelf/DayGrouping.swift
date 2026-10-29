// DayGrouping.swift
//
// What: splits history into "Today", "Yesterday", then one group per date (F4).
// Why:  pure logic with no UI, so it can be tested with a fixed date and calendar.

import Foundation

struct DaySection: Identifiable, Equatable {
    /// Start of that day; also the section's identity.
    let id: Date
    let title: String
    let items: [ClipItem]
}

enum DayGrouping {
    /// `items` must already be newest first; order inside each day is kept.
    static func group(_ items: [ClipItem], now: Date = .now, calendar: Calendar = .current) -> [DaySection] {
        var order: [Date] = []
        var buckets: [Date: [ClipItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order.map { day in
            DaySection(id: day, title: title(for: day, now: now, calendar: calendar), items: buckets[day] ?? [])
        }
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd") // e.g. "Monday, Oct 27"
        return formatter.string(from: day)
    }
}
