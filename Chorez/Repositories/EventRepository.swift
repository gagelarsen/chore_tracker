import Foundation
import SwiftData

/// Read-only access to the append-only `Event` audit log.
///
/// Writes happen exclusively through `HouseholdRepository.applyEngine`:
/// every rules-engine call returns the new events on its `HouseholdState`,
/// and the bottleneck inserts them. Exposing a `write` method here would
/// undermine the DRY invariant.
@MainActor
public final class EventRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func all() throws -> [Event] {
        let descriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func forKid(_ kidID: UUID) throws -> [Event] {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.kidID == kidID },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}
