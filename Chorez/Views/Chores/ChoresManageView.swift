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
            AddTemplateSheet(kids: kids) { kidID, name, points in
                addTemplate(kidID: kidID, name: name, points: points)
            }
        }
        .sheet(isPresented: $showAddAdHoc) {
            AddAdHocSheet(kids: kids) { kidID, name, points in
                addAdHoc(kidID: kidID, name: name, points: points)
            }
        }
        .alert("Chores", isPresented: alertBinding) {
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

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } })
    }

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
        for index in offsets {
            do {
                try environment.chores.deleteTemplate(templates[index])
            } catch {
                alertMessage = "Could not delete chore: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Add sheets

/// Shared form shape used by both add-template and add-ad-hoc sheets.
private struct ChoreFormFields: View {
    let kids: [Kid]
    @Binding var assignedKidID: UUID?
    @Binding var name: String
    @Binding var pointsText: String

    var body: some View {
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
}

private struct AddTemplateSheet: View {
    let kids: [Kid]
    let onSave: (UUID, String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignedKidID: UUID?
    @State private var name = ""
    @State private var pointsText = ""

    var body: some View {
        NavigationStack {
            Form {
                ChoreFormFields(kids: kids,
                                assignedKidID: $assignedKidID,
                                name: $name,
                                pointsText: $pointsText)
            }
            .navigationTitle("New recurring chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let id = assignedKidID, let pts = Int(pointsText), pts >= 0 {
                            onSave(id, name.trimmingCharacters(in: .whitespacesAndNewlines), pts)
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("confirmAddTemplateButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        assignedKidID != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int(pointsText) ?? -1) >= 0
    }
}

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
                ChoreFormFields(kids: kids,
                                assignedKidID: $assignedKidID,
                                name: $name,
                                pointsText: $pointsText)
            }
            .navigationTitle("Add ad-hoc chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let id = assignedKidID, let pts = Int(pointsText), pts >= 0 {
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

    private var isValid: Bool {
        assignedKidID != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int(pointsText) ?? -1) >= 0
    }
}
