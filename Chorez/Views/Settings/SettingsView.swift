import CloudKit
import SwiftData
import SwiftUI

/// Household setup, end-of-day, and the PR3 share-flow placeholder.
///
/// SettingsView is the bootstrap surface — first launch shows a "Create
/// your family" form, and creating the household unblocks every other
/// tab. Once a household exists this becomes the day-management hub:
/// rename family, end the day, eventually invite a spouse (PR3).
///
/// Read paths use `@Query` so the screen auto-refreshes when the
/// household is created or renamed. Mutations route through
/// `AppEnvironment.households` so the repository stays the single
/// persistence path (per `00-standards.md`).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var households: [Household]
    @State private var draftHouseholdName: String = ""
    @State private var showEndDayConfirmation = false
    @State private var alertMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        Form {
            if let household = households.first {
                familySection(for: household)
                endDaySection
                syncSection(household: household)
            } else {
                bootstrapSection
                bootstrapSyncPlaceholderSection
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "End the day?",
            isPresented: $showEndDayConfirmation,
            titleVisibility: .visible
        ) {
            Button("End the day", role: .destructive) { endDay() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Zeroes every kid's daily balance and clears today's chores. This cannot be undone.")
        }
        .alert("Settings", isPresented: $alertMessage.isPresent) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var bootstrapSection: some View {
        Section {
            TextField("Family name", text: $draftHouseholdName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("familyNameField")
            Button("Create family") { createHousehold() }
                .disabled(trimmedDraft.isEmpty)
                .accessibilityIdentifier("createFamilyButton")
        } header: {
            Text("Get started")
        } footer: {
            Text("Create your family to unlock the rest of the app.")
        }
    }

    @ViewBuilder
    private func familySection(for household: Household) -> some View {
        Section("Family") {
            LabeledContent("Name", value: household.name)
            LabeledContent("Created",
                           value: household.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    /// Pre-bootstrap variant — there's no Household yet, so the
    /// invite button has nothing to share. Keeps the section visible
    /// (so users see the feature exists) but disabled until setup.
    private var bootstrapSyncPlaceholderSection: some View {
        Section {
            Label("Invite spouse", systemImage: "person.crop.circle.badge.plus")
                .foregroundStyle(.secondary)
        } header: {
            Text("Sync")
        } footer: {
            Text("Create your family first to unlock the invite flow.")
        }
    }

    private var endDaySection: some View {
        Section("End of day") {
            Button(role: .destructive) {
                showEndDayConfirmation = true
            } label: {
                Label("End the day", systemImage: "moon.zzz.fill")
            }
            .accessibilityIdentifier("endDayButton")
        }
    }

    @ViewBuilder
    private func syncSection(household: Household) -> some View {
        Section {
            Button {
                showShareSheet = true
            } label: {
                Label("Invite spouse", systemImage: "person.crop.circle.badge.plus")
            }
            .accessibilityIdentifier("inviteSpouseButton")
        } header: {
            Text("Sync")
        } footer: {
            // Honest framing of the iOS 17.5 SwiftData + CKShare gap:
            // the invite flow works, but the manual data-replication
            // layer needed to surface owner-side data on the spouse's
            // device is a known follow-up. Phase 1 ships plumbing.
            Text("""
                The invite flow is wired up. Two-account data sync \
                will land in a follow-up update — for now, each \
                device shows its own local data.
                """)
        }
        .sheet(isPresented: $showShareSheet) {
            CloudKitShareSheet(
                household: household,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier,
                onComplete: handleShareCompletion
            )
            .ignoresSafeArea()
        }
    }

    /// Hard-coded for Phase 1 PR3; matches the value in `ChorezApp` and
    /// the entitlement. PR3 follow-ups (or a Phase 5 polish pass) can
    /// promote this to a shared constant if a third call site appears.
    private let cloudKitContainerIdentifier = "iCloud.com.glarsen.chorez"

    // MARK: - Actions

    private var trimmedDraft: String {
        draftHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createHousehold() {
        // Clear the draft up front so a thrown error after
        // `createIfMissing` succeeds (e.g. an unlikely SwiftData write
        // failure inside `autoFillTodayIfNeeded`) doesn't leave the
        // bootstrap form looking actionable when the household row
        // already exists.
        let name = trimmedDraft
        draftHouseholdName = ""
        do {
            _ = try environment.households.createIfMissing(name: name)
            // The auto-fill hook ran once at app launch when there was
            // no household to act on. Re-run it now so
            // `Household.lastAutoFillDate` is set to today — that's
            // what tells `createTemplate` it's safe to instantiate
            // today's chore alongside the new template.
            _ = try environment.chores.autoFillTodayIfNeeded(now: .now)
        } catch {
            alertMessage = "Could not create family: \(error.localizedDescription)"
        }
    }

    private func endDay() {
        do {
            _ = try environment.households.closeOutDay()
        } catch HouseholdRepositoryError.householdNotInitialized {
            alertMessage = "Set up your family first."
        } catch {
            alertMessage = "Could not end the day: \(error.localizedDescription)"
        }
    }

    /// Routes share-sheet outcomes back to the screen.
    /// Cancellation is a non-event; everything else surfaces in the
    /// shared alert presenter so the user gets the same UX as the
    /// other Settings flows.
    private func handleShareCompletion(_ result: Result<CKShare, Error>) {
        showShareSheet = false
        switch result {
        case .success:
            // The share controller already informed the user via its
            // own UI; nothing to add here.
            break
        case .failure(let error as CloudKitShareError) where error == .cancelledByUser:
            break
        case .failure(let error):
            alertMessage = "Could not share: \(error.localizedDescription)"
        }
    }
}
