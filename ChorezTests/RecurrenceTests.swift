import Foundation
import Testing
@testable import Chorez

// Pure-value tests for the Phase 1.6 `Recurrence` struct and the
// `Weekday` enum. No SwiftData or CloudKit involved.

@Suite("Recurrence presets")
struct RecurrencePresetTests {
    @Test(".daily covers every weekday")
    func dailyCoversEveryWeekday() {
        let recurrence = Recurrence.daily
        for day in Weekday.allCases {
            #expect(recurrence.includes(weekday: day))
        }
        #expect(recurrence.daysOfWeekBitmask == 0b1111111)
        #expect(recurrence.daysOfWeekBitmask == 127)
    }

    @Test(".weekdays = Mon-Fri only")
    func weekdaysOnly() {
        let recurrence = Recurrence.weekdays
        #expect(!recurrence.includes(weekday: .sunday))
        #expect(recurrence.includes(weekday: .monday))
        #expect(recurrence.includes(weekday: .tuesday))
        #expect(recurrence.includes(weekday: .wednesday))
        #expect(recurrence.includes(weekday: .thursday))
        #expect(recurrence.includes(weekday: .friday))
        #expect(!recurrence.includes(weekday: .saturday))
        // Bits 1-5 set → 0b0111110 = 62
        #expect(recurrence.daysOfWeekBitmask == 62)
    }

    @Test(".weekends = Sat + Sun")
    func weekendsOnly() {
        let recurrence = Recurrence.weekends
        #expect(recurrence.includes(weekday: .sunday))
        #expect(!recurrence.includes(weekday: .monday))
        #expect(!recurrence.includes(weekday: .friday))
        #expect(recurrence.includes(weekday: .saturday))
        // Bits 0 + 6 set → 0b1000001 = 65
        #expect(recurrence.daysOfWeekBitmask == 65)
    }
}

@Suite("Recurrence init forms")
struct RecurrenceInitTests {
    @Test("Set-based init round-trips through weekdays accessor")
    func setRoundTrip() {
        let recurrence = Recurrence([.tuesday, .thursday])
        #expect(recurrence.weekdays == [.tuesday, .thursday])
        #expect(recurrence.includes(weekday: .tuesday))
        #expect(recurrence.includes(weekday: .thursday))
        #expect(!recurrence.includes(weekday: .wednesday))
    }

    @Test("Bitmask init defensively clamps out-of-range bits to the low 7")
    func bitmaskClamps() {
        // 0xFF = bits 0-7. Bit 7 (= 128) should be stripped to 0
        // because it doesn't correspond to any weekday — defensive
        // against corrupt CloudKit data or future schema drift.
        let recurrence = Recurrence(daysOfWeekBitmask: 0xFF)
        #expect(recurrence.daysOfWeekBitmask == 0b1111111)
    }

    @Test("Empty set produces zero bitmask")
    func emptySet() {
        let recurrence = Recurrence([])
        #expect(recurrence.daysOfWeekBitmask == 0)
        for day in Weekday.allCases {
            #expect(!recurrence.includes(weekday: day))
        }
    }
}

@Suite("Weekday helpers")
struct WeekdayTests {
    @Test("rawValue matches Calendar.Component.weekday (Sun=1 … Sat=7)")
    func calendarConvention() {
        #expect(Weekday.sunday.rawValue == 1)
        #expect(Weekday.saturday.rawValue == 7)
    }

    @Test("bitOffset packs into low 7 bits (Sun=0 … Sat=6)")
    func bitOffsets() {
        #expect(Weekday.sunday.bitOffset == 0)
        #expect(Weekday.monday.bitOffset == 1)
        #expect(Weekday.saturday.bitOffset == 6)
    }

    @Test("allCases lists every weekday once, in calendar order")
    func allCasesShape() {
        #expect(Weekday.allCases.count == 7)
        #expect(Weekday.allCases.first == .sunday)
        #expect(Weekday.allCases.last == .saturday)
    }
}

@Suite("Recurrence Codable round-trip")
struct RecurrenceCodableTests {
    @Test("JSON encode + decode preserves the bitmask")
    func jsonRoundTrip() throws {
        let original = Recurrence.weekdays
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        #expect(decoded == original)
    }
}
