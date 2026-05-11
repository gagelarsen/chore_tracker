import SwiftUI

/// Seven day-of-week toggles plus three preset shortcuts (Daily,
/// Weekdays, Weekends). Used inside both the add-chore sheet and
/// the edit-chore sheet — wherever a `Recurrence` is being authored.
///
/// Binds to a `Recurrence` directly so callers don't have to
/// shuttle a Set / bitmask through their own state. The picker
/// re-renders from the bound value, so presets and toggles stay in
/// agreement.
struct WeekdayPicker: View {
    @Binding var recurrence: Recurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presetRow
            dayToggleGrid
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekdayPicker")
    }

    // MARK: - Presets

    private var presetRow: some View {
        HStack(spacing: 8) {
            presetButton("Daily", target: .daily)
            presetButton("Weekdays", target: .weekdays)
            presetButton("Weekends", target: .weekends)
            Spacer()
        }
    }

    private func presetButton(_ label: String, target: Recurrence) -> some View {
        Button(label) { recurrence = target }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(recurrence == target ? .accentColor : .secondary)
            .accessibilityIdentifier("weekdayPreset_\(label)")
    }

    // MARK: - Day toggles

    private var dayToggleGrid: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                dayToggle(day)
            }
        }
    }

    private func dayToggle(_ day: Weekday) -> some View {
        let isOn = recurrence.includes(weekday: day)
        return Button(day.initial) {
            toggle(day)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, minHeight: 36)
        .tint(isOn ? .accentColor : .secondary)
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .accessibilityIdentifier("weekdayToggle_\(day.shortLabel)")
        .accessibilityLabel(Text(day.shortLabel))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Flip one weekday's bit. Centralised so the toggle keeps the
    /// existing pattern's other bits intact (vs. naively replacing
    /// the recurrence with a single-day mask).
    private func toggle(_ day: Weekday) {
        var days = recurrence.weekdays
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        recurrence = Recurrence(days)
    }
}

#Preview {
    @Previewable @State var recurrence: Recurrence = .weekdays
    return Form {
        Section("Repeats") {
            WeekdayPicker(recurrence: $recurrence)
        }
    }
}
