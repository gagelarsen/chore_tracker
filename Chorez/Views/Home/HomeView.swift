import SwiftData
import SwiftUI

/// Top-level kids roster — the parent's at-a-glance view of who has
/// what daily balance. Tapping a kid pushes `KidDetailView` for that
/// kid's chores and reward redemption.
///
/// Kid CRUD lives here (toolbar `+` to add, swipe to delete) so the
/// roster is the natural home for "who lives in this household."
/// Settings remains for day-management actions only.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var households: [Household]
    @Query(sort: [SortDescriptor(\Kid.displayOrder), SortDescriptor(\Kid.name)])
    private var kids: [Kid]

    @State private var showAddKid = false
    @State private var newKidName: String = ""
    @State private var alertMessage: String?

    var body: some View {
        Group {
            if households.first == nil {
                ContentUnavailableView(
                    "Set up your family",
                    systemImage: "person.3.fill",
                    description: Text("Open Settings to create your family.")
                )
            } else if kids.isEmpty {
                ContentUnavailableView {
                    Label("No kids yet", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Tap + to add your first kid.")
                }
            } else {
                kidList
            }
        }
        .navigationTitle("Home")
        .toolbar {
            if households.first != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddKid = true
                    } label: {
                        Label("Add kid", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addKidButton")
                }
            }
        }
        .sheet(isPresented: $showAddKid) {
            addKidSheet
        }
        .alert("Home", isPresented: $alertMessage.isPresent) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var kidList: some View {
        List {
            ForEach(kids) { kid in
                NavigationLink(value: kid.id) {
                    KidRow(name: kid.name, dailyBalance: kid.currentDailyBalance)
                }
                .accessibilityIdentifier("kidRow_\(kid.name)")
            }
            .onDelete(perform: deleteKids)
        }
        .navigationDestination(for: UUID.self) { kidID in
            KidDetailView(kidID: kidID)
        }
    }

    private var addKidSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newKidName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("newKidNameField")
            }
            .navigationTitle("Add kid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newKidName = ""
                        showAddKid = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addKid() }
                        .disabled(trimmedNewName.isEmpty)
                        .accessibilityIdentifier("confirmAddKidButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private var trimmedNewName: String {
        newKidName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addKid() {
        guard let householdID = households.first?.id else { return }
        do {
            _ = try environment.kids.create(householdID: householdID, name: trimmedNewName)
            newKidName = ""
            showAddKid = false
        } catch {
            alertMessage = "Could not add kid: \(error.localizedDescription)"
        }
    }

    private func deleteKids(at offsets: IndexSet) {
        // Snapshot the targets before mutating — `kids` is a live
        // `@Query` array and each successful delete can shift indices
        // out from under a subsequent lookup.
        let targets = offsets.map { kids[$0] }
        for kid in targets {
            do {
                try environment.kids.delete(kid)
            } catch {
                alertMessage = "Could not delete kid: \(error.localizedDescription)"
            }
        }
    }
}
