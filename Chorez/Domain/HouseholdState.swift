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

/// Day of the week. Values match `Calendar.Component.weekday` (Sun=1
/// … Sat=7) so a `Calendar` query result drops straight into
/// `Recurrence.includes(weekday:)` without translation.
public enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var id: Int { rawValue }

    /// Bit position used by `Recurrence.daysOfWeekBitmask`. Sun=0 …
    /// Sat=6 keeps the bitmask packed into the low 7 bits.
    public var bitOffset: Int { rawValue - 1 }

    /// Short human label (e.g. "Mon"). Used by `WeekdayPicker`.
    public var shortLabel: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    /// Single-character pill label.
    public var initial: String { String(shortLabel.first!) }
}

/// Days-of-week recurrence pattern for a `ChoreTemplate`.
///
/// Backed by a 7-bit `Int` (bit `weekday.bitOffset` set → that
/// weekday's `ChoreInstance` is spawned by `autoFillTodayIfNeeded`).
/// Bitmask form chosen for storage + sync (native CloudKit `Int`,
/// single SwiftData column) while the struct façade gives call sites
/// a typed API.
///
/// `127` covers every day (the v1 default). `0` is a valid value but
/// effectively disables the template; UI should warn before saving.
public struct Recurrence: Hashable, Sendable, Codable {
    /// Low 7 bits flag the active weekdays.
    public let daysOfWeekBitmask: Int

    public init(daysOfWeekBitmask: Int) {
        // Mask to 7 bits defensively — values outside 0...127 are
        // user-facing nonsense and silently clamp to the valid range.
        self.daysOfWeekBitmask = daysOfWeekBitmask & 0b1111111
    }

    public init(_ days: Set<Weekday>) {
        let mask = days.reduce(0) { $0 | (1 << $1.bitOffset) }
        self.init(daysOfWeekBitmask: mask)
    }

    /// `true` if `weekday`'s bit is set. Convenient for the auto-fill
    /// gate: `template.recurrence.includes(weekday: today)`.
    public func includes(weekday: Weekday) -> Bool {
        (daysOfWeekBitmask & (1 << weekday.bitOffset)) != 0
    }

    public var weekdays: Set<Weekday> {
        Set(Weekday.allCases.filter { includes(weekday: $0) })
    }

    // MARK: - Presets

    /// Every day — matches Phase 1's hard-coded behaviour and the
    /// default for migrated templates.
    public static let daily = Recurrence(daysOfWeekBitmask: 0b1111111)

    /// Monday through Friday. Bits 1-5 set → `0b0111110 = 62`.
    public static let weekdays = Recurrence([.monday, .tuesday, .wednesday, .thursday, .friday])

    /// Saturday and Sunday only. Bits 0 + 6 set → `0b1000001 = 65`.
    public static let weekends = Recurrence([.sunday, .saturday])
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
