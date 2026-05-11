import Foundation
import SwiftData

/// CRUD wrapper over `ChoreTemplate` and `ChoreInstance` rows, plus the
/// `autoFillTodayIfNeeded` bottleneck.
///
/// Per `00-standards.md`, "auto-fill today's chores lives in one
/// repository method, called from a single app-launch hook" — that hook
/// is `autoFillTodayIfNeeded(now:)`. Same-day re-launch short-circuits
/// via `Household.lastAutoFillDate`, so closing out the day then
/// re-opening the app does not re-create the instances `closeOutDay`
/// just deleted.
///
/// `ChoreInstance.completedAt` and `.status` are read here for display
/// but only mutated via `HouseholdRepository.applyChoreCompletion` so
/// the rules engine stays the sole authority on point math.
@MainActor
public final class ChoreRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Templates

    public func templates(householdID: UUID) throws -> [ChoreTemplate] {
        let descriptor = FetchDescriptor<ChoreTemplate>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func activeTemplates(householdID: UUID) throws -> [ChoreTemplate] {
        let descriptor = FetchDescriptor<ChoreTemplate>(
            predicate: #Predicate { $0.householdID == householdID && $0.active },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// Create a new template. If today's auto-fill has already run, also
    /// inserts today's `ChoreInstance` so the new chore appears
    /// immediately instead of "the chore I just added isn't here" until
    /// tomorrow's launch.
    @discardableResult
    public func createTemplate(householdID: UUID,
                               name: String,
                               points: Int,
                               assignedKidID: UUID,
                               now: Date = .now) throws -> ChoreTemplate {
        // `ChoreTemplate.init` and `ChoreInstance.init` default
        // `updatedAt = .now`, so fresh inserts are sync-ready.
        let template = ChoreTemplate(householdID: householdID,
                                     name: name,
                                     points: points,
                                     assignedKidID: assignedKidID,
                                     updatedAt: now)
        context.insert(template)

        let today = Calendar.current.startOfDay(for: now)
        var hhFetch = FetchDescriptor<Household>(
            predicate: #Predicate { $0.id == householdID }
        )
        hhFetch.fetchLimit = 1
        if let household = try context.fetch(hhFetch).first,
           household.lastAutoFillDate == today {
            context.insert(ChoreInstance(templateID: template.id,
                                         householdID: householdID,
                                         name: name,
                                         points: points,
                                         assignedKidID: assignedKidID,
                                         date: today,
                                         updatedAt: now))
        }

        try context.save()
        return template
    }

    public func updateTemplate(_ template: ChoreTemplate,
                               name: String? = nil,
                               points: Int? = nil,
                               assignedKidID: UUID? = nil,
                               active: Bool? = nil) throws {
        if let name { template.name = name }
        if let points { template.points = points }
        if let assignedKidID { template.assignedKidID = assignedKidID }
        if let active { template.active = active }
        // Stamp on every mutation so the sync engine's LWW resolver
        // promotes this edit over any concurrent device's stale copy.
        template.updatedAt = .now
        try context.save()
    }

    /// Delete a template. Future (`status == .pending`) instances spawned
    /// from it are also removed; completed instances stay so the audit
    /// log remains consistent.
    public func deleteTemplate(_ template: ChoreTemplate) throws {
        let templateID = template.id
        try context.delete(model: ChoreInstance.self,
                           where: #Predicate { instance in
                               instance.templateID == templateID
                               && instance.statusRaw == "pending"
                           })
        context.delete(template)
        try context.save()
    }

    // MARK: - Instances

    public func instances(forDate date: Date) throws -> [ChoreInstance] {
        let target = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<ChoreInstance>(
            predicate: #Predicate { $0.date == target },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func instances(forKid kidID: UUID, on date: Date) throws -> [ChoreInstance] {
        let target = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<ChoreInstance>(
            predicate: #Predicate { $0.assignedKidID == kidID && $0.date == target },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// Create a one-off `ChoreInstance` for a kid on a specific day with
    /// no parent template. The date is normalized to `startOfDay` so
    /// queries by day stay timezone-stable.
    @discardableResult
    public func createAdHocInstance(householdID: UUID,
                                    kidID: UUID,
                                    name: String,
                                    points: Int,
                                    on date: Date) throws -> ChoreInstance {
        // `ChoreInstance.init` defaults `updatedAt = .now`, so the freshly
        // inserted row is sync-ready.
        let instance = ChoreInstance(templateID: nil,
                                     householdID: householdID,
                                     name: name,
                                     points: points,
                                     assignedKidID: kidID,
                                     date: Calendar.current.startOfDay(for: date))
        context.insert(instance)
        try context.save()
        return instance
    }

    // MARK: - Auto-fill

    /// Generate today's `ChoreInstance` rows from every active template,
    /// once per day. Updates `Household.lastAutoFillDate` so subsequent
    /// same-day calls are no-ops.
    ///
    /// Returns the count of new instances inserted — `0` when this is a
    /// no-op same-day call. Useful for tests; UI code can ignore.
    @discardableResult
    public func autoFillTodayIfNeeded(now: Date) throws -> Int {
        let today = Calendar.current.startOfDay(for: now)

        var hhFetch = FetchDescriptor<Household>()
        hhFetch.fetchLimit = 1
        guard let household = try context.fetch(hhFetch).first else { return 0 }

        if household.lastAutoFillDate == today { return 0 }

        let householdID = household.id
        let templatesDescriptor = FetchDescriptor<ChoreTemplate>(
            predicate: #Predicate { $0.householdID == householdID && $0.active },
            sortBy: [SortDescriptor(\.name)]
        )
        let templates = try context.fetch(templatesDescriptor)

        for template in templates {
            // `ChoreInstance.init` defaults `updatedAt = .now` so the
            // freshly inserted rows are sync-ready.
            context.insert(ChoreInstance(templateID: template.id,
                                         householdID: householdID,
                                         name: template.name,
                                         points: template.points,
                                         assignedKidID: template.assignedKidID,
                                         date: today))
        }

        household.lastAutoFillDate = today
        // The Household row's `lastAutoFillDate` field just changed, so
        // bump its `updatedAt` to keep the sync engine's LWW resolver
        // honest. Without this stamp, a concurrent edit on the other
        // device could clobber `lastAutoFillDate` and re-trigger auto-fill.
        household.updatedAt = .now
        try context.save()
        return templates.count
    }
}
