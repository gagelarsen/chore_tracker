import Foundation
import SwiftData

/// `ChoreRepository.updateTemplate` and its private cascade helpers.
///
/// Split out of `ChoreRepository.swift` so the main class stays under
/// SwiftLint's 250-line type-body cap. Logical group is the same as
/// the rest of the repo — only the file boundary moved.

extension ChoreRepository {
    /// Pile of optional field changes for `updateTemplate`. Bundled
    /// because the function's parameter list grew past SwiftLint's
    /// five-parameter cap once recurrence joined the existing
    /// name/points/kid/active fields.
    public struct TemplateEdits {
        public var name: String?
        public var points: Int?
        public var assignedKidID: UUID?
        public var recurrence: Recurrence?
        public var active: Bool?

        public init(name: String? = nil,
                    points: Int? = nil,
                    assignedKidID: UUID? = nil,
                    recurrence: Recurrence? = nil,
                    active: Bool? = nil) {
            self.name = name
            self.points = points
            self.assignedKidID = assignedKidID
            self.recurrence = recurrence
            self.active = active
        }
    }

    /// Update an existing template. Each parameter is optional — only
    /// the named fields change.
    ///
    /// Cascade rules (Phase 1.6):
    /// - If `active` flips from `true` to `false`, today's still-
    ///   pending instance is **deleted** (tombstone via sync push).
    /// - Otherwise (name / points / kid / recurrence change), today's
    ///   still-pending instance is **updated in place** so the kid
    ///   sees the corrected fields immediately.
    /// - Completed instances are never touched —
    ///   `Event.choreCompleted` rows still match their referenced
    ///   instance.
    public func updateTemplate(_ template: ChoreTemplate,
                               name: String? = nil,
                               points: Int? = nil,
                               assignedKidID: UUID? = nil,
                               recurrence: Recurrence? = nil,
                               active: Bool? = nil,
                               now: Date = .now) throws {
        let edits = TemplateEdits(name: name,
                                  points: points,
                                  assignedKidID: assignedKidID,
                                  recurrence: recurrence,
                                  active: active)
        try updateTemplate(template, edits: edits, now: now)
    }

    /// Struct-input flavour used by `ChoresManageView`'s edit sheet.
    public func updateTemplate(_ template: ChoreTemplate,
                               edits: TemplateEdits,
                               now: Date = .now) throws {
        let wasActive = template.active
        applyTemplateEdits(template, edits: edits, now: now)

        let pendingInstances = try fetchTodaysPendingInstances(forTemplate: template.id, now: now)
        let deactivating = wasActive && (edits.active == false)
        let deletedIDs: [UUID] = deactivating
            ? deleteInstances(pendingInstances)
            : updateInstances(pendingInstances, edits: edits, now: now)

        try context.save()
        push(.upsert(template.snapshot))
        if deactivating {
            for id in deletedIDs {
                push(.delete(.init(id: id,
                                   ckRecordType: ChoreInstanceSnapshot.ckRecordType)))
            }
        } else {
            for instance in pendingInstances {
                push(.upsert(instance.snapshot))
            }
        }
    }

    /// In-place mutation of the SwiftData row.
    fileprivate func applyTemplateEdits(_ template: ChoreTemplate,
                                        edits: TemplateEdits,
                                        now: Date) {
        if let name = edits.name { template.name = name }
        if let points = edits.points { template.points = points }
        if let assignedKidID = edits.assignedKidID { template.assignedKidID = assignedKidID }
        if let recurrence = edits.recurrence { template.recurrence = recurrence }
        if let active = edits.active { template.active = active }
        // Stamp on every mutation so the sync engine's LWW resolver
        // promotes this edit over any concurrent device's stale copy.
        template.updatedAt = now
    }

    /// At most one row in practice (auto-fill spawns one per template
    /// per day) but we fetch the set defensively.
    fileprivate func fetchTodaysPendingInstances(forTemplate templateID: UUID,
                                                 now: Date) throws -> [ChoreInstance] {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<ChoreInstance>(
            predicate: #Predicate { instance in
                instance.templateID == templateID
                && instance.date == today
                && instance.statusRaw == "pending"
            }
        )
        return try context.fetch(descriptor)
    }

    /// Delete every passed-in instance and return their IDs (so
    /// `updateTemplate` can issue tombstones in the sync push).
    fileprivate func deleteInstances(_ instances: [ChoreInstance]) -> [UUID] {
        var ids: [UUID] = []
        for instance in instances {
            ids.append(instance.id)
            context.delete(instance)
        }
        return ids
    }

    /// Mirror the field edits onto each pending instance. `recurrence`
    /// is intentionally absent from the per-instance copy — instances
    /// are single-day rows, the recurrence concept doesn't apply.
    @discardableResult
    fileprivate func updateInstances(_ instances: [ChoreInstance],
                                     edits: TemplateEdits,
                                     now: Date) -> [UUID] {
        for instance in instances {
            if let name = edits.name { instance.name = name }
            if let points = edits.points { instance.points = points }
            if let kidID = edits.assignedKidID { instance.assignedKidID = kidID }
            instance.updatedAt = now
        }
        return []
    }
}
