import SwiftData
import SwiftUI

/// Edit-in-place form for an existing `ChoreTemplate`.
///
/// Reachable by tapping a row in `ChoresManageView`. Pre-fills every
/// field from the template; saving routes through
/// `ChoreRepository.updateTemplate`, which also cascades changes to
/// today's still-pending `ChoreInstance` (or tombstones it when
/// `active` flips off). Completed history rows are never touched.
struct EditChoreSheet: View {
    /// Payload returned to the caller when the user taps Save.
    /// Bundled into a struct so `ChoresManageView`'s save handler
    /// stays under SwiftLint's five-parameter cap.
    public struct Result {
        public let name: String
        public let points: Int
        public let kidID: UUID
        public let recurrence: Recurrence
        public let active: Bool
    }

    let template: ChoreTemplate
    let kids: [Kid]
    let onSave: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pointsText: String
    @State private var assignedKidID: UUID
    @State private var recurrence: Recurrence
    @State private var active: Bool

    init(template: ChoreTemplate,
         kids: [Kid],
         onSave: @escaping (Result) -> Void) {
        self.template = template
        self.kids = kids
        self.onSave = onSave
        // Pre-fill from the template so the form opens reflecting
        // current state. `@State` initialisers stick to the first
        // value the view receives, which is exactly what we want
        // here — re-renders don't clobber in-progress edits.
        _name = State(initialValue: template.name)
        _pointsText = State(initialValue: String(template.points))
        _assignedKidID = State(initialValue: template.assignedKidID)
        _recurrence = State(initialValue: template.recurrence)
        _active = State(initialValue: template.active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    Picker("For", selection: $assignedKidID) {
                        ForEach(kids) { kid in
                            Text(kid.name).tag(kid.id)
                        }
                    }
                    .accessibilityIdentifier("editKidPicker")
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("editChoreNameField")
                    TextField("Points", text: $pointsText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("editChorePointsField")
                }
                Section("Repeats") {
                    WeekdayPicker(recurrence: $recurrence)
                }
                Section {
                    Toggle("Active", isOn: $active)
                        .accessibilityIdentifier("editActiveToggle")
                } footer: {
                    Text("""
                        Pausing a chore stops it from appearing on new \
                        days. Today's pending instance will be removed \
                        if you pause it now.
                        """)
                }
            }
            .navigationTitle("Edit chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let pts = parsedPoints {
                            onSave(Result(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                points: pts,
                                kidID: assignedKidID,
                                recurrence: recurrence,
                                active: active
                            ))
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("confirmEditChoreButton")
                }
            }
        }
    }

    private var parsedPoints: Int? {
        guard let value = Int(pointsText), (0...10_000).contains(value) else { return nil }
        return value
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedPoints != nil
            && recurrence.daysOfWeekBitmask != 0
    }
}
