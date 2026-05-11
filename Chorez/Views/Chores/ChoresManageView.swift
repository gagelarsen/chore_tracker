import SwiftData
import SwiftUI

/// Manage recurring chore templates and add ad-hoc chores for today.
///
/// Templates are the source of the daily auto-fill; ad-hoc instances
/// are one-off today-only chores with no parent template. Both flow
/// through `AppEnvironment.chores` so the auto-fill bottleneck stays
/// the only path that creates `ChoreInstance` rows on a recurring
/// schedule.
struct ChoresManageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var households: [Household]
    @Query(sort: [SortDescriptor(\Kid.displayOrder), SortDescriptor(\Kid.name)])
    private var kids: [Kid]
    @Query(sort: [SortDescriptor(\ChoreTemplate.name)])
    private var templates: [ChoreTemplate]

    @State private var showAddTemplate = false
    @State private var showAddAdHoc = false
    @State private var editingTemplate: ChoreTemplate?
    @State private var alertMessage: String?

    var body: some View {
        Group {
            if households.first == nil {
                ContentUnavailableView(
                    "Set up your family first",
                    systemImage: "person.3.fill",
                    description: Text("Open Settings to create your family.")
                )
            } else if kids.isEmpty {
                ContentUnavailableView(
                    "Add a kid first",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Open Home and tap + to add a kid before adding chores.")
                )
            } else {
                templateList
            }
        }
        .navigationTitle("Chores")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddTemplate) {
            NewTemplateSheet(kids: kids) { kidID, name, points, recurrence in
                addTemplate(kidID: kidID, name: name, points: points, recurrence: recurrence)
            }
        }
        .sheet(isPresented: $showAddAdHoc) {
            AddAdHocSheet(kids: kids) { kidID, name, points in
                addAdHoc(kidID: kidID, name: name, points: points)
            }
        }
        .sheet(item: $editingTemplate) { template in
            EditChoreSheet(template: template, kids: kids) { edit in
                applyEdit(template: template, edit: edit)
            }
        }
        .alert("Chores", isPresented: $alertMessage.isPresent) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var templateList: some View {
        List {
            if templates.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No chores yet", systemImage: "checklist")
                    } description: {
                        Text("Tap + to add a recurring chore or a one-off for today.")
                    }
                }
            } else {
                ForEach(kids) { kid in
                    let kidTemplates = templates.filter { $0.assignedKidID == kid.id }
                    if !kidTemplates.isEmpty {
                        Section(kid.name) {
                            ForEach(kidTemplates) { template in
                                templateRow(template)
                            }
                            .onDelete { offsets in
                                delete(templates: kidTemplates, at: offsets)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: ChoreTemplate) -> some View {
        Button {
            editingTemplate = template
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .foregroundStyle(.primary)
                    Text(recurrenceLabel(for: template.recurrence))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !template.active {
                        Text("Paused").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PointPill(points: template.points)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("templateRow_\(template.name)")
    }

    /// Short human label for the recurrence pattern in the row.
    /// Daily / Weekdays / Weekends get their preset names; anything
    /// else lists the active days (e.g. "Mon Wed Fri").
    private func recurrenceLabel(for recurrence: Recurrence) -> String {
        switch recurrence {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        default:
            let days = Weekday.allCases
                .filter { recurrence.includes(weekday: $0) }
                .map(\.shortLabel)
            return days.isEmpty ? "Never" : days.joined(separator: " ")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if households.first != nil && !kids.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddTemplate = true
                    } label: {
                        Label("New recurring chore", systemImage: "repeat")
                    }
                    .accessibilityIdentifier("addTemplateButton")
                    Button {
                        showAddAdHoc = true
                    } label: {
                        Label("Today only (ad-hoc)", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("addAdHocButton")
                } label: {
                    Label("Add chore", systemImage: "plus")
                }
                .accessibilityIdentifier("addChoreMenu")
            }
        }
    }

    // MARK: - Actions

    private func addTemplate(kidID: UUID, name: String, points: Int, recurrence: Recurrence) {
        guard let householdID = households.first?.id else { return }
        do {
            _ = try environment.chores.createTemplate(householdID: householdID,
                                                     name: name,
                                                     points: points,
                                                     assignedKidID: kidID,
                                                     recurrence: recurrence)
            showAddTemplate = false
        } catch {
            alertMessage = "Could not add chore: \(error.localizedDescription)"
        }
    }

    private func addAdHoc(kidID: UUID, name: String, points: Int) {
        guard let householdID = households.first?.id else { return }
        do {
            _ = try environment.chores.createAdHocInstance(householdID: householdID,
                                                           kidID: kidID,
                                                           name: name,
                                                           points: points,
                                                           on: environment.dateProvider())
            showAddAdHoc = false
        } catch {
            alertMessage = "Could not add chore: \(error.localizedDescription)"
        }
    }

    private func applyEdit(template: ChoreTemplate, edit: EditChoreSheet.Result) {
        do {
            try environment.chores.updateTemplate(template,
                                                  name: edit.name,
                                                  points: edit.points,
                                                  assignedKidID: edit.kidID,
                                                  recurrence: edit.recurrence,
                                                  active: edit.active,
                                                  now: environment.dateProvider())
            editingTemplate = nil
        } catch {
            alertMessage = "Could not update chore: \(error.localizedDescription)"
        }
    }

    private func delete(templates: [ChoreTemplate], at offsets: IndexSet) {
        // Snapshot targets — see the note in `HomeView.deleteKids`.
        let targets = offsets.map { templates[$0] }
        for template in targets {
            do {
                try environment.chores.deleteTemplate(template)
            } catch {
                alertMessage = "Could not delete chore: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - New recurring chore sheet

/// Form for creating a new recurring chore template. Includes the
/// `WeekdayPicker` for selecting which days the chore appears on.
/// Separate from `AddAdHocSheet` because ad-hoc chores are one-off
/// for a single day — no recurrence to pick.
private struct NewTemplateSheet: View {
    let kids: [Kid]
    let onSave: (UUID, String, Int, Recurrence) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignedKidID: UUID?
    @State private var name = ""
    @State private var pointsText = ""
    @State private var recurrence: Recurrence = .daily

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    Picker("For", selection: $assignedKidID) {
                        Text("Choose a kid").tag(UUID?.none)
                        ForEach(kids) { kid in
                            Text(kid.name).tag(UUID?.some(kid.id))
                        }
                    }
                    .accessibilityIdentifier("kidPicker")
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("choreNameField")
                    TextField("Points", text: $pointsText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("chorePointsField")
                }
                Section("Repeats") {
                    WeekdayPicker(recurrence: $recurrence)
                }
            }
            .navigationTitle("New recurring chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let id = assignedKidID, let pts = parsedPoints {
                            onSave(id,
                                   name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   pts,
                                   recurrence)
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("confirmAddTemplateButton")
                }
            }
        }
    }

    private var parsedPoints: Int? {
        guard let value = Int(pointsText), (0...10_000).contains(value) else { return nil }
        return value
    }

    private var isValid: Bool {
        assignedKidID != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedPoints != nil
            && recurrence.daysOfWeekBitmask != 0
    }
}

// MARK: - Ad-hoc chore sheet

/// Form for creating a one-off chore for today (no parent template,
/// no recurrence). Kept separate from `NewTemplateSheet` because the
/// two forms have meaningfully different field sets and merging them
/// behind a mode-flag adds branching without much win.
private struct AddAdHocSheet: View {
    let kids: [Kid]
    let onSave: (UUID, String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignedKidID: UUID?
    @State private var name = ""
    @State private var pointsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("For", selection: $assignedKidID) {
                        Text("Choose a kid").tag(UUID?.none)
                        ForEach(kids) { kid in
                            Text(kid.name).tag(UUID?.some(kid.id))
                        }
                    }
                    .accessibilityIdentifier("kidPicker")
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("choreNameField")
                    TextField("Points", text: $pointsText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("chorePointsField")
                }
            }
            .navigationTitle("Add ad-hoc chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let id = assignedKidID, let pts = parsedPoints {
                            onSave(id, name.trimmingCharacters(in: .whitespacesAndNewlines), pts)
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("confirmAddAdHocButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var parsedPoints: Int? {
        guard let value = Int(pointsText), (0...10_000).contains(value) else { return nil }
        return value
    }

    private var isValid: Bool {
        assignedKidID != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedPoints != nil
    }
}
