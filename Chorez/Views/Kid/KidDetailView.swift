import SwiftData
import SwiftUI

/// Per-kid screen: today's chores + reward redemption + parent-issued
/// bonus.
///
/// Every state change routes through `AppEnvironment.households` so
/// the DRY invariants in `00-standards.md` hold — no direct mutation
/// of `Kid.currentDailyBalance` from this view.
struct KidDetailView: View {
    let kidID: UUID

    @Environment(AppEnvironment.self) private var environment
    @Query private var kidMatches: [Kid]
    @Query(sort: [SortDescriptor(\ChoreInstance.name)])
    private var allInstances: [ChoreInstance]
    @Query(filter: #Predicate<Reward> { $0.active },
           sort: [SortDescriptor(\Reward.points), SortDescriptor(\Reward.name)])
    private var rewards: [Reward]

    @State private var showBonusSheet = false
    @State private var bonusPoints: String = ""
    @State private var alertMessage: String?

    init(kidID: UUID) {
        self.kidID = kidID
        _kidMatches = Query(filter: #Predicate<Kid> { $0.id == kidID })
    }

    var body: some View {
        Group {
            if let kid = kidMatches.first {
                kidContent(for: kid)
            } else {
                ContentUnavailableView("Kid not found",
                                       systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(kidMatches.first?.name ?? "Kid")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if kidMatches.first != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBonusSheet = true
                    } label: {
                        Label("Give bonus", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("giveBonusButton")
                }
            }
        }
        .sheet(isPresented: $showBonusSheet) { bonusSheet }
        .alert("Kid", isPresented: alertBinding) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func kidContent(for kid: Kid) -> some View {
        let todaysChores = todaysInstances(for: kid.id)
        List {
            Section("Today's balance") {
                HStack {
                    Text("Balance")
                    Spacer()
                    PointPill(points: kid.currentDailyBalance,
                              emphasis: kid.currentDailyBalance > 0 ? .positive : .neutral)
                        .accessibilityIdentifier("dailyBalancePill")
                }
            }

            Section("Today's chores") {
                if todaysChores.isEmpty {
                    Text("No chores today.").foregroundStyle(.secondary)
                } else {
                    ForEach(todaysChores) { instance in
                        ChoreCheckbox(name: instance.name,
                                      points: instance.points,
                                      isDone: instance.status == .done) {
                            complete(instance)
                        }
                        .accessibilityIdentifier("choreCheckbox_\(instance.name)")
                    }
                }
            }

            Section("Rewards") {
                if rewards.isEmpty {
                    Text("No rewards available yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(rewards) { reward in
                        rewardRow(reward, kidBalance: kid.currentDailyBalance)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rewardRow(_ reward: Reward, kidBalance: Int) -> some View {
        let affordable = kidBalance >= reward.points
        HStack {
            VStack(alignment: .leading) {
                Text(reward.name)
                if !affordable {
                    Text("Needs \(reward.points - kidBalance) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            PointPill(points: reward.points, emphasis: .neutral)
            Button("Redeem") { redeem(reward) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!affordable)
                .accessibilityIdentifier("redeemButton_\(reward.name)")
        }
    }

    private var bonusSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Points", text: $bonusPoints)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("bonusPointsField")
                } footer: {
                    Text("Positive points reward, negative points dock. The kid's daily balance cannot go below zero.")
                }
            }
            .navigationTitle("Give bonus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bonusPoints = ""
                        showBonusSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyBonus() }
                        .disabled(parsedBonus == nil || parsedBonus == 0)
                        .accessibilityIdentifier("confirmBonusButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func todaysInstances(for kid: UUID) -> [ChoreInstance] {
        let today = Calendar.current.startOfDay(for: Date.now)
        return allInstances.filter { $0.assignedKidID == kid && $0.date == today }
    }

    private var parsedBonus: Int? {
        Int(bonusPoints.trimmingCharacters(in: .whitespaces))
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } })
    }

    // MARK: - Actions

    private func complete(_ instance: ChoreInstance) {
        do {
            let result = try environment.households.applyChoreCompletion(instanceID: instance.id)
            if case .failure(let error) = result {
                alertMessage = describe(error)
            }
        } catch {
            alertMessage = "Storage error: \(error.localizedDescription)"
        }
    }

    private func redeem(_ reward: Reward) {
        do {
            let result = try environment.households.redeemReward(kidID: kidID, rewardID: reward.id)
            if case .failure(let error) = result {
                alertMessage = describe(error)
            }
        } catch {
            alertMessage = "Storage error: \(error.localizedDescription)"
        }
    }

    private func applyBonus() {
        guard let points = parsedBonus else { return }
        do {
            let result = try environment.households.applyAward(kidID: kidID, points: points)
            if case .failure(let error) = result {
                alertMessage = describe(error)
            } else {
                bonusPoints = ""
                showBonusSheet = false
            }
        } catch {
            alertMessage = "Storage error: \(error.localizedDescription)"
        }
    }

    // MARK: - Error mapping

    private func describe(_ error: ChoreCompletionError) -> String {
        switch error {
        case .instanceNotFound: return "That chore is no longer available."
        case .alreadyCompleted: return "Already completed."
        case .kidNotFound: return "Kid is missing."
        }
    }

    private func describe(_ error: RedemptionError) -> String {
        switch error {
        case .kidNotFound: return "Kid is missing."
        case .rewardNotFound: return "Reward is no longer available."
        case .rewardInactive: return "That reward isn't active."
        case .insufficientBalance: return "Not enough points yet."
        }
    }

    private func describe(_ error: AwardError) -> String {
        switch error {
        case .kidNotFound: return "Kid is missing."
        case .wouldGoNegative: return "Balance cannot go below zero."
        }
    }
}
