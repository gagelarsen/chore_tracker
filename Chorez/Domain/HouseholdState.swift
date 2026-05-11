import Foundation

// MARK: - Per-entity snapshots

/// Snapshot of a `Household` row.
///
/// `lastAutoFillDate` is the `startOfDay` of the day for which we most
/// recently generated today's `ChoreInstance` rows. The repository uses it
/// to make auto-fill idempotent — opening the app twice on the same day
/// must not double-create chores.
public struct HouseholdSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var ownerCloudUserID: String?
    public var createdAt: Date
    public var lastAutoFillDate: Date?
    /// LWW arbiter for the CloudKit sync engine. See
    /// `Chorez/Sync/SyncProtocols.swift`. Defaults to `.now` so a freshly
    /// minted snapshot is always sync-ready.
    public var updatedAt: Date

    public init(id: UUID,
                name: String,
                ownerCloudUserID: String? = nil,
                createdAt: Date,
                lastAutoFillDate: Date? = nil,
                updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.ownerCloudUserID = ownerCloudUserID
        self.createdAt = createdAt
        self.lastAutoFillDate = lastAutoFillDate
        self.updatedAt = updatedAt
    }
}

/// Snapshot of a `Kid` row.
///
/// `currentDailyBalance` is the points earned today that have not yet been
/// redeemed or zeroed out by `closeOutDay`. By DRY rule, only
/// `RulesEngine.applyAward` (called via `HouseholdRepository.applyAward`)
/// is permitted to mutate this field.
public struct KidSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var householdID: UUID
    public var name: String
    public var displayOrder: Int
    public var currentDailyBalance: Int
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    public var updatedAt: Date

    public init(id: UUID,
                householdID: UUID,
                name: String,
                displayOrder: Int,
                currentDailyBalance: Int,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.displayOrder = displayOrder
        self.currentDailyBalance = currentDailyBalance
        self.updatedAt = updatedAt
    }
}

/// How often a `ChoreTemplate` regenerates.
///
/// Phase 1 only supports daily recurrence; the enum exists so later phases
/// can extend (weekly, weekdays-only, etc.) without changing call sites.
public enum Recurrence: String, Codable, Hashable, Sendable {
    case daily
}

/// Snapshot of a `ChoreTemplate` row — the parent definition that
/// auto-generates `ChoreInstance` rows on each new day.
public struct ChoreTemplateSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var householdID: UUID
    public var name: String
    public var points: Int
    public var assignedKidID: UUID
    public var recurrence: Recurrence
    public var active: Bool
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    public var updatedAt: Date

    public init(id: UUID,
                householdID: UUID,
                name: String,
                points: Int,
                assignedKidID: UUID,
                recurrence: Recurrence = .daily,
                active: Bool = true,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.assignedKidID = assignedKidID
        self.recurrence = recurrence
        self.active = active
        self.updatedAt = updatedAt
    }
}

/// Today's status for a single chore.
public enum ChoreStatus: String, Codable, Hashable, Sendable {
    case pending
    case done
}

/// Snapshot of a `ChoreInstance` row.
///
/// `templateID` is `nil` for ad-hoc chores added directly to a day.
/// `date` is the `startOfDay` for which this instance was scheduled.
public struct ChoreInstanceSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var templateID: UUID?
    public var householdID: UUID
    public var name: String
    public var points: Int
    public var assignedKidID: UUID
    public var date: Date
    public var status: ChoreStatus
    public var completedAt: Date?
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    public var updatedAt: Date

    public init(id: UUID,
                templateID: UUID?,
                householdID: UUID,
                name: String,
                points: Int,
                assignedKidID: UUID,
                date: Date,
                status: ChoreStatus = .pending,
                completedAt: Date? = nil,
                updatedAt: Date = .now) {
        self.id = id
        self.templateID = templateID
        self.householdID = householdID
        self.name = name
        self.points = points
        self.assignedKidID = assignedKidID
        self.date = date
        self.status = status
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }
}

/// Snapshot of a `Reward` row — a redeemable prize parents define.
public struct RewardSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var householdID: UUID
    public var name: String
    public var points: Int
    public var active: Bool
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    public var updatedAt: Date

    public init(id: UUID,
                householdID: UUID,
                name: String,
                points: Int,
                active: Bool = true,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.active = active
        self.updatedAt = updatedAt
    }
}

/// Snapshot of a `RewardRedemption` row.
///
/// `points` is captured at the moment of redemption so historical reads
/// stay correct even if the reward's current cost is changed afterwards.
public struct RewardRedemptionSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kidID: UUID
    public var rewardID: UUID
    public var points: Int
    public var redeemedAt: Date
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    /// Append-only rows never re-stamp this field after insert.
    public var updatedAt: Date

    public init(id: UUID,
                kidID: UUID,
                rewardID: UUID,
                points: Int,
                redeemedAt: Date,
                updatedAt: Date = .now) {
        self.id = id
        self.kidID = kidID
        self.rewardID = rewardID
        self.points = points
        self.redeemedAt = redeemedAt
        self.updatedAt = updatedAt
    }
}

/// Snapshot of an append-only `Event` row in the audit log.
public struct EventSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kidID: UUID?
    public var payload: EventPayload
    public var occurredAt: Date
    /// LWW arbiter for the CloudKit sync engine — see `HouseholdSnapshot.updatedAt`.
    /// Append-only rows never re-stamp this field after insert.
    public var updatedAt: Date

    public var type: EventType { payload.type }

    public init(id: UUID,
                kidID: UUID?,
                payload: EventPayload,
                occurredAt: Date,
                updatedAt: Date = .now) {
        self.id = id
        self.kidID = kidID
        self.payload = payload
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Aggregate state

/// Pure-Swift snapshot of an entire household. Inputs and outputs of every
/// rules engine function are values of this type.
///
/// Keeping the engine over a pure value type means tests don't need
/// SwiftData and DRY invariants ("only `applyAward` mutates balance") are
/// trivially enforceable: every mutation path runs through the engine,
/// then through the single `HouseholdRepository.applyEngine` adapter.
public struct HouseholdState: Equatable, Hashable, Sendable {
    public var household: HouseholdSnapshot
    public var kids: [KidSnapshot]
    public var templates: [ChoreTemplateSnapshot]
    public var instances: [ChoreInstanceSnapshot]
    public var rewards: [RewardSnapshot]
    public var redemptions: [RewardRedemptionSnapshot]
    public var events: [EventSnapshot]

    public init(household: HouseholdSnapshot,
                kids: [KidSnapshot] = [],
                templates: [ChoreTemplateSnapshot] = [],
                instances: [ChoreInstanceSnapshot] = [],
                rewards: [RewardSnapshot] = [],
                redemptions: [RewardRedemptionSnapshot] = [],
                events: [EventSnapshot] = []) {
        self.household = household
        self.kids = kids
        self.templates = templates
        self.instances = instances
        self.rewards = rewards
        self.redemptions = redemptions
        self.events = events
    }
}
