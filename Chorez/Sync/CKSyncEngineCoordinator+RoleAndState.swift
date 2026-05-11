import CloudKit
import Foundation

/// Role + persisted-state helpers for `CKSyncEngineCoordinator`.
///
/// Split into its own file so the main coordinator stays under the
/// 400-line `.swiftlint.yml` cap and so the "which CloudKit database
/// am I" and "where do I keep my engine state on disk" concerns are
/// findable together.
///
/// All members here would normally sit on the main type — keeping
/// them in an extension is purely a file-size accommodation, not a
/// logical separation. Internal access keeps them reachable from the
/// rest of the coordinator and `@testable` tests.

/// Which CloudKit database the coordinator pushes / pulls through.
///
/// Owners (the parent who created the household) hold the share root
/// in their own private database. Participants (the spouse who
/// accepted the invite) see the shared zone in their shared database.
/// Both roles run the same coordinator type — only the database
/// changes — so the receive / queue / serialise paths are identical.
@available(iOS 17.5, *)
public enum CKSyncEngineRole: Sendable {
    case owner
    case participant
}

@available(iOS 17.5, *)
extension CKSyncEngineCoordinator {
    /// Reads the persisted participant flag set by
    /// `acceptShareInvitation(_:)`. Defaults to `.owner` for fresh
    /// installs — that's the right answer for the parent who creates
    /// the household first.
    public nonisolated static func persistedRole() -> CKSyncEngineRole {
        UserDefaults.standard.bool(forKey: participantDefaultsKey) ? .participant : .owner
    }

    /// Persist that this device is now a share participant. Called
    /// from the app delegate's `userDidAcceptCloudKitShareWith`
    /// handler. Sticks across launches so the coordinator picks the
    /// shared database on the next start.
    public nonisolated static func markAsParticipant() {
        UserDefaults.standard.set(true, forKey: participantDefaultsKey)
    }

    /// Returns the `CKRecordZone.ID` to use for outbound writes given
    /// the current role and any owner name observed from inbound
    /// records. Owner mode: always `CKCurrentUserDefaultName`.
    /// Participant mode: the stored owner record name if known, else
    /// `CKCurrentUserDefaultName` as a best-effort fallback (the
    /// engine will reject the write if the fallback is wrong and
    /// `fetchChanges` will give us the right owner before retry).
    internal func sharedZoneIDForCurrentRole() -> CKRecordZone.ID {
        let owner: String
        switch role {
        case .owner:
            owner = CKCurrentUserDefaultName
        case .participant:
            owner = sharedZoneOwnerName ?? CKCurrentUserDefaultName
        }
        return CKRecordZone.ID(zoneName: Self.sharedZoneName, ownerName: owner)
    }

    /// Called by the delegate when an inbound record arrives so the
    /// coordinator can remember the participant-side owner name for
    /// future outbound writes. No-op in owner mode.
    internal func captureOwnerName(from recordID: CKRecord.ID) {
        guard role == .participant else { return }
        let observed = recordID.zoneID.ownerName
        guard observed != CKCurrentUserDefaultName, observed != sharedZoneOwnerName else { return }
        sharedZoneOwnerName = observed
        let ownerKey = Self.participantOwnerKeyPrefix + containerIdentifier
        UserDefaults.standard.set(observed, forKey: ownerKey)
    }

    /// `UserDefaults` key for the persisted CKSyncEngine state blob.
    /// Namespaced by container id so a switch between staging /
    /// production containers doesn't cross-contaminate state.
    internal var stateKey: String {
        "chorez.cksyncengine.state.\(containerIdentifier)"
    }

    /// Load the engine's previously persisted state. Falls back to
    /// `nil` on decode failure so a corrupted blob doesn't wedge the
    /// app — the engine treats nil as "fresh install" and re-fetches
    /// the world.
    internal func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            log.error("Failed to decode state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Persist the engine's latest state. Encoded as JSON so it's
    /// inspectable in `defaults read` during debugging; the blob is
    /// small (a few KB) so the choice has no perf cost.
    internal func saveState(_ state: CKSyncEngine.State.Serialization) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            log.error("Failed to encode state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wipe persisted state. Called on `.accountChange` so a
    /// sign-out / sign-in cycle starts from a clean slate rather
    /// than re-applying the previous account's tokens.
    internal func resetState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
        clearPendingChanges()
    }
}
