import SwiftData
import SwiftUI

/// Rewards catalog. Add/remove redeemable prizes; redemption itself
/// happens in `KidDetailView`. `Reward.active` is exposed as a toggle
/// so parents can pause a reward (children no longer see it) without
/// losing the catalog entry.
struct RewardsManageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var households: [Household]
    @Query(sort: [SortDescriptor(\Reward.points), SortDescriptor(\Reward.name)])
    private var rewards: [Reward]

    @State private var showAddReward = false
    @State private var alertMessage: String?

    var body: some View {
        Group {
            if households.first == nil {
                ContentUnavailableView(
                    "Set up your family first",
                    systemImage: "person.3.fill",
                    description: Text("Open Settings to create your family.")
                )
            } else if rewards.isEmpty {
                ContentUnavailableView {
                    Label("No rewards yet", systemImage: "gift")
                } description: {
                    Text("Tap + to add a reward kids can redeem.")
                }
            } else {
                rewardList
            }
        }
        .navigationTitle("Rewards")
        .toolbar {
            if households.first != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddReward = true
                    } label: {
                        Label("Add reward", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addRewardButton")
                }
            }
        }
        .sheet(isPresented: $showAddReward) {
            AddRewardSheet { name, points in
                addReward(name: name, points: points)
            }
        }
        .alert("Rewards", isPresented: $alertMessage.isPresent) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var rewardList: some View {
        List {
            ForEach(rewards) { reward in
                rewardRow(reward)
            }
            .onDelete(perform: deleteRewards)
        }
    }

    @ViewBuilder
    private func rewardRow(_ reward: Reward) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(reward.name)
                if !reward.active {
                    Text("Paused").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            PointPill(points: reward.points)
            Button {
                togglePaused(reward)
            } label: {
                Image(systemName: reward.active ? "pause.circle" : "play.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggleActive_\(reward.name)")
        }
        .accessibilityIdentifier("rewardRow_\(reward.name)")
    }

    // MARK: - Actions

    private func addReward(name: String, points: Int) {
        guard let householdID = households.first?.id else { return }
        do {
            _ = try environment.rewards.create(householdID: householdID,
                                              name: name,
                                              points: points)
            showAddReward = false
        } catch {
            alertMessage = "Could not add reward: \(error.localizedDescription)"
        }
    }

    private func togglePaused(_ reward: Reward) {
        do {
            try environment.rewards.update(reward, active: !reward.active)
        } catch {
            alertMessage = "Could not update reward: \(error.localizedDescription)"
        }
    }

    private func deleteRewards(at offsets: IndexSet) {
        // Snapshot targets — see the note in `HomeView.deleteKids`.
        let targets = offsets.map { rewards[$0] }
        for reward in targets {
            do {
                try environment.rewards.delete(reward)
            } catch {
                alertMessage = "Could not delete reward: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Add sheet

private struct AddRewardSheet: View {
    let onSave: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pointsText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("rewardNameField")
                TextField("Points to redeem", text: $pointsText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("rewardPointsField")
            }
            .navigationTitle("New reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let pts = Int(pointsText), pts >= 0 {
                            onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), pts)
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("confirmAddRewardButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int(pointsText) ?? -1) >= 0
    }
}
