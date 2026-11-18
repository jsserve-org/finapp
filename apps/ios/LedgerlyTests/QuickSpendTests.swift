import XCTest
@testable import Ledgerly

final class QuickSpendTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Nov 18 2026 is a Wednesday; Nov 14–15 are that weekend.
    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testNoonGuessesLunch() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 18, hour: 12), calendar: calendar), "Lunch")
    }

    func testMorningGuessesBreakfast() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 18, hour: 8), calendar: calendar), "Breakfast")
    }

    func testEveningGuessesDinner() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 18, hour: 18), calendar: calendar), "Dinner")
    }

    func testWeekendLateMorningGuessesBrunch() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 14, hour: 11), calendar: calendar), "Brunch")
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 15, hour: 12), calendar: calendar), "Brunch")
    }

    func testWeekdayLateMorningStaysLunch() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 18, hour: 11), calendar: calendar), "Lunch")
    }

    func testMidAfternoonHasNoConfidentGuess() {
        XCTAssertNil(QuickSpendMeal.guess(for: date(day: 18, hour: 15), calendar: calendar))
        XCTAssertNil(QuickSpendMeal.guess(for: date(day: 18, hour: 16), calendar: calendar))
    }

    func testLateNightGuessesSnack() {
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 18, hour: 23), calendar: calendar), "Late-night snack")
        XCTAssertEqual(QuickSpendMeal.guess(for: date(day: 19, hour: 2), calendar: calendar), "Late-night snack")
    }
}
