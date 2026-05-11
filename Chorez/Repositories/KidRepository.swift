import Foundation
import SwiftData

/// CRUD wrapper over `Kid` rows.
///
/// View models call this repository instead of touching `ModelContext`
/// directly (per `00-standards.md` persistence DRY rule). `currentDailyBalance`
/// is read here for display but only mutated via
/// `HouseholdRepository.applyEngine` — repository updates limited to
/// `name` and `displayOrder` to keep the engine the sole authority on
/// point math.
@MainActor
public final class KidRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func all() throws -> [Kid] {
        let descriptor = FetchDescriptor<Kid>(
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func find(id: UUID) throws -> Kid? {
        let predicate = #Predicate<Kid> { $0.id == id }
        var descriptor = FetchDescriptor<Kid>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func create(householdID: UUID, name: String, displayOrder: Int? = nil) throws -> Kid {
        let order = try displayOrder ?? all().count
        let kid = Kid(householdID: householdID, name: name, displayOrder: order)
        context.insert(kid)
        try context.save()
        return kid
    }

    public func rename(_ kid: Kid, to newName: String) throws {
        kid.name = newName
        try context.save()
    }

    public func reorder(_ kid: Kid, to displayOrder: Int) throws {
        kid.displayOrder = displayOrder
        try context.save()
    }

    /// Hard delete with cascade to children the kid owns directly.
    ///
    /// Deletes the `Kid`, every `ChoreTemplate` assigned to them
    /// (templates are personalized in v1), every pending `ChoreInstance`
    /// regardless of date, and every future `ChoreInstance` (status
    /// irrelevant). **Completed instances on today or earlier stay** so
    /// the audit query against `Event` records is still
    /// self-consistent — every `choreCompleted` event still has its
    /// referenced `ChoreInstance` row. Append-only `Event` and
    /// `RewardRedemption` rows are never touched.
    public func delete(_ kid: Kid) throws {
        let kidID = kid.id
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)

        try context.delete(model: ChoreTemplate.self,
                           where: #Predicate { $0.assignedKidID == kidID })
        // `instance.date > today` (strictly greater): future instances
        // are wiped regardless of status, but completed-today instances
        // stay so the audit log isn't orphaned. Pending instances
        // (any date, past or today) are also wiped — nothing left for
        // the kid to do.
        try context.delete(model: ChoreInstance.self,
                           where: #Predicate { instance in
                               instance.assignedKidID == kidID
                               && (instance.statusRaw == "pending" || instance.date > today)
                           })
        context.delete(kid)
        try context.save()
    }
}
