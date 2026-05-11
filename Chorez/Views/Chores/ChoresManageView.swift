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
            AddChoreSheet(title: "New recurring chore",
                          confirmIdentifier: "confirmAddTemplateButton",
                          kids: kids) { kidID, name, points in
                addTemplate(kidID: kidID, name: name, points: points)
            }
        }
        .sheet(isPresented: $showAddAdHoc) {
            AddChoreSheet(title: "Add ad-hoc chore",
                          confirmIdentifier: "confirmAddAdHocButton",
                          kids: kids) { kidID, name, points in
                addAdHoc(kidID: kidID, name: name, points: points)
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
        HStack {
            VStack(alignment: .leading) {
                Text(template.name)
                if !template.active {
                    Text("Inactive").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            PointPill(points: template.points)
        }
        .accessibilityIdentifier("templateRow_\(template.name)")
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

    private func addTemplate(kidID: UUID, name: String, points: Int) {
        guard let householdID = households.first?.id else { return }
        do {
            _ = try environment.chores.createTemplate(householdID: householdID,
                                                     name: name,
                                                     points: points,
                                                     assignedKidID: kidID)
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
                                                           on: .now)
            showAddAdHoc = false
        } catch {
            alertMessage = "Could not add chore: \(error.localizedDescription)"
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

// MARK: - Add sheet

/// Single sheet for both "new recurring chore" and "today only (ad-hoc)"
/// — the two forms differ only in their `navigationTitle` and the
/// accessibility identifier on the confirm button, so collapsing them
/// keeps `00-standards.md`'s DRY rule honest.
private struct AddChoreSheet: View {
    let title: String
    let confirmIdentifier: String
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
            .navigationTitle(title)
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
                    .accessibilityIdentifier(confirmIdentifier)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Cap points at 10,000 — same defensive bound used by `KidDetailView`'s
    /// bonus parsing to keep engine arithmetic safely inside `Int`.
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
