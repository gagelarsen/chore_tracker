import Foundation
import SwiftData

/// Append-only audit log entry.
///
/// The payload is encoded to JSON `Data` rather than stored as the
/// `EventPayload` enum directly: SwiftData's transparent Codable storage
/// has known sharp edges with associated-value enums (silent corruption,
/// migration friction), and JSON `Data` is also CloudKit-safe. `typeRaw`
/// duplicates the discriminator so the log can be filtered by type
/// without touching the payload.
@Model
public final class Event {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var kidID: UUID?
    public var typeRaw: String = ""
    public var payloadData: Data = Data()
    public var occurredAt: Date = Date()
    /// LWW arbiter for CloudKit sync — see `Household.updatedAt`. Events
    /// are append-only so this is set once at insert and never changes,
    /// but the field still exists so the sync engine handles every record
    /// uniformly.
    public var updatedAt: Date = Date()

    /// Stable encoder/decoder for `EventPayload`.
    ///
    /// Sorted keys keep round-trip output byte-equal — useful in tests and
    /// for any future content-addressed sync logic.
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private static let decoder = JSONDecoder()

    public init(id: UUID = UUID(),
                kidID: UUID? = nil,
                payload: EventPayload,
                occurredAt: Date = .now,
                updatedAt: Date = .now) {
        self.id = id
        self.kidID = kidID
        self.typeRaw = payload.type.rawValue
        // Force-try: `EventPayload` is a finite Codable enum we control,
        // so encoding cannot fail at runtime. Surfacing it as a non-
        // throwing initializer keeps every call site (engine, tests,
        // adapters) free of `try` noise that would never be exercised.
        // swiftlint:disable:next force_try
        self.payloadData = try! Self.encoder.encode(payload)
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: EventSnapshot) {
        self.init(id: snapshot.id,
                  kidID: snapshot.kidID,
                  payload: snapshot.payload,
                  occurredAt: snapshot.occurredAt,
                  updatedAt: snapshot.updatedAt)
    }

    /// Decoded payload. Returns `nil` only if the stored bytes are
    /// corrupt — should never happen in a fresh write but the snapshot
    /// adapter filters such rows out rather than crashing on read.
    public var payload: EventPayload? {
        try? Self.decoder.decode(EventPayload.self, from: payloadData)
    }

    /// Snapshot for the rules engine and tests. Returns `nil` if the
    /// stored payload bytes are unreadable (defensive — fresh writes
    /// always round-trip).
    public var snapshot: EventSnapshot? {
        guard let payload else { return nil }
        return EventSnapshot(id: id,
                             kidID: kidID,
                             payload: payload,
                             occurredAt: occurredAt,
                             updatedAt: updatedAt)
    }
}
