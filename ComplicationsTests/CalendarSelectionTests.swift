import Foundation
import Testing

struct CalendarSelectionTests {
    private typealias Key = CalendarSelection.Key

    private let work = Key(identifier: "phone-work", title: "Work", source: "iCloud")
    private let home = Key(identifier: "phone-home", title: "Home", source: "iCloud")
    private let gmail = Key(identifier: "phone-gmail", title: "Calendar", source: "dan@example.com")

    private var selection: CalendarSelection {
        CalendarSelection(date: Date(timeIntervalSince1970: 1_800_000_000), hidden: [work, gmail])
    }

    @Test func travelsInAMessage() throws {
        let decoded = try #require(CalendarSelection(message: selection.message))
        #expect(decoded == selection)
        #expect(CalendarSelection(message: AccentColor.standard.message) == nil)
    }

    @Test func keepsTheNewest() throws {
        let defaults = try #require(UserDefaults(suiteName: "CalendarSelectionTests"))
        defaults.removePersistentDomain(forName: "CalendarSelectionTests")
        #expect(CalendarSelection.saved(in: defaults) == nil)

        #expect(selection.save(in: defaults))
        var older = selection
        older.date = selection.date.addingTimeInterval(-60)
        older.hidden = []
        #expect(!older.save(in: defaults))
        #expect(CalendarSelection.saved(in: defaults) == selection)
        #expect(!CalendarSelection.all.save(in: defaults))
    }

    @Test func matchesTheSameCalendarsOnThePhone() {
        let phone = [work, home, gmail]
        #expect(selection.hides(work, among: phone))
        #expect(!selection.hides(home, among: phone))
        #expect(selection.hides(gmail, among: phone))
        #expect(!CalendarSelection.all.hides(work, among: phone))
    }

    /// The watch's copies may have other identifiers; the title within the same account still finds them.
    @Test func matchesByTitleAndAccountOnTheWatch() {
        let watchWork = Key(identifier: "watch-1", title: "Work", source: "iCloud")
        let watchHome = Key(identifier: "watch-2", title: "Home", source: "iCloud")
        let watchCalendar = Key(identifier: "watch-3", title: "Calendar", source: "iCloud")
        let watchGmail = Key(identifier: "watch-4", title: "Calendar", source: "dan@example.com")
        let watch = [watchWork, watchHome, watchCalendar, watchGmail]
        #expect(selection.hides(watchWork, among: watch))
        #expect(!selection.hides(watchHome, among: watch))
        // Same title in another account the watch has too: only the one in the hidden account.
        #expect(!selection.hides(watchCalendar, among: watch))
        #expect(selection.hides(watchGmail, among: watch))
    }

    /// When the watch names an account differently, the title alone has to do.
    @Test func fallsBackToTheTitleWhenTheAccountIsUnknown() {
        let watchGmail = Key(identifier: "watch-4", title: "Calendar", source: "Gmail")
        let watchHome = Key(identifier: "watch-2", title: "Home", source: "iCloud")
        #expect(selection.hides(watchGmail, among: [watchGmail, watchHome]))
        #expect(!selection.hides(watchHome, among: [watchGmail, watchHome]))
    }
}
