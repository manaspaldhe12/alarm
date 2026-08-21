import XCTest
@testable import MorningAlarm

final class RecurrenceTests: XCTestCase {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    func testLocalTimeNextFireDateSameDayIfInFuture() {
        let reference = date(2026, 8, 21, 6, 0) // Friday 6:00
        let time = LocalTime(hour: 7, minute: 0)
        let next = time.nextFireDate(from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 21, 7, 0), "same-day 7am should fire today when it's before 7am")
    }

    func testLocalTimeNextFireDateRollsToTomorrowIfPast() {
        let reference = date(2026, 8, 21, 8, 0) // Friday 8:00, after 7am
        let time = LocalTime(hour: 7, minute: 0)
        let next = time.nextFireDate(from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 22, 7, 0), "should roll to the next day once 7am has passed")
    }

    func testLocalTimeNextFireDateRollsWhenExactlyEqual() {
        let reference = date(2026, 8, 21, 7, 0)
        let time = LocalTime(hour: 7, minute: 0)
        let next = time.nextFireDate(from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 22, 7, 0), "candidate <= reference should roll forward, not fire immediately")
    }

    func testRecurrenceNoneMatchesOneTimeBehavior() {
        let reference = date(2026, 8, 21, 6, 0)
        let time = LocalTime(hour: 7, minute: 0)
        let next = Recurrence.never.nextFireDate(for: time, from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 21, 7, 0))
    }

    func testRecurrenceWeekdaysOnlySkipsWeekend() {
        // 2026-08-21 is a Friday. Weekdays-only alarm at 7am, checked from Friday 8am
        // (past today's 7am) should land on Monday 2026-08-24, not Saturday/Sunday.
        let reference = date(2026, 8, 21, 8, 0)
        let time = LocalTime(hour: 7, minute: 0)
        let next = Recurrence.weekdaysOnly.nextFireDate(for: time, from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 24, 7, 0), "should skip Sat/Sun to land on Monday")
    }

    func testRecurrenceWeekendsOnlySkipsWeekdays() {
        let reference = date(2026, 8, 21, 8, 0) // Friday
        let time = LocalTime(hour: 7, minute: 0)
        let next = Recurrence.weekendsOnly.nextFireDate(for: time, from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 22, 7, 0), "should land on the next Saturday")
    }

    func testRecurrenceSingleWeekdayWrapsToNextWeek() {
        // Only Fridays, checked from Saturday — should wrap forward ~6 days to next Friday.
        let reference = date(2026, 8, 22, 8, 0) // Saturday
        let time = LocalTime(hour: 7, minute: 0)
        let recurrence = Recurrence(weekdays: [.friday])
        let next = recurrence.nextFireDate(for: time, from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 28, 7, 0), "should wrap to the following Friday")
    }

    func testRecurrenceTodayStillMatchesIfBeforeTime() {
        // Today is Friday, alarm is Fri/Sat/Sun at 7am, checked at 6am (before today's fire time).
        let reference = date(2026, 8, 21, 6, 0) // Friday 6am
        let time = LocalTime(hour: 7, minute: 0)
        let recurrence = Recurrence(weekdays: [.friday, .saturday, .sunday])
        let next = recurrence.nextFireDate(for: time, from: reference, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 21, 7, 0), "today should still count if its fire time hasn't passed yet")
    }

    func testRecurrenceSummaries() {
        XCTAssertEqual(Recurrence.never.summary, "Once")
        XCTAssertEqual(Recurrence.everyDay.summary, "Every day")
        XCTAssertEqual(Recurrence.weekdaysOnly.summary, "Weekdays")
        XCTAssertEqual(Recurrence.weekendsOnly.summary, "Weekends")
        XCTAssertEqual(Recurrence(weekdays: [.monday, .wednesday]).summary, "Mon Wed")
    }

    func testWeekdayFromDateMatchesCalendar() {
        // 2026-08-21 is a Friday.
        let friday = date(2026, 8, 21, 12, 0)
        XCTAssertEqual(Weekday.from(date: friday, calendar: calendar), .friday)
    }
}
