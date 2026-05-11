import CloudKit
import SwiftUI
import UIKit

/// Errors surfaced by the share flow that don't already come from
/// CloudKit.
///
/// CloudKit throws rich `CKError` values; this enum exists only for the
/// failure modes that originate *inside* the coordinator itself, so
/// SettingsView's alert layer doesn't have to inspect raw CK codes for
/// our own bugs.
public enum CloudKitShareError: Error, Sendable {
    /// CloudKit returned a save result with neither a share nor an
    /// error. Should be impossible per the CloudKit contract; raised
    /// defensively so a future SDK regression can't silently no-op.
    case shareUnavailable
    /// The user dismissed the share sheet without sending. Treated as a
    /// non-fatal cancel by callers — SettingsView swallows it.
    case cancelledByUser
    /// No UIKit view controller could be located to present the share
    /// sheet from. Shouldn't happen in normal app state; raised
    /// defensively in case the call site fires before the scene
    /// activates.
    case noPresenter
}

/// Drives the iCloud share-invitation flow start-to-finish.
///
/// Why this is **not** a `UIViewControllerRepresentable` wrapped in
/// SwiftUI `.sheet`: `UICloudSharingController` is itself a full-screen
/// system modal, and nesting it inside another presented modal (the
/// SwiftUI `.sheet`) makes the system silently dismiss it. Instead this
/// class is created and kicked off imperatively from a button action;
/// it mints (or fetches) the `CKShare` asynchronously, then presents
/// `UICloudSharingController` directly on the topmost view controller
/// of the active window scene.
///
/// **Lifetime**: callers hold a strong reference to the instance (e.g.
/// in `@State`) for the duration of the flow. The `onComplete` closure
/// fires exactly once when the share sheet closes; callers can release
/// the reference at that point.
///
/// Why we use a CloudKit-mirror record instead of the SwiftData
/// `Household` row directly: as of iOS 18 SDK, SwiftData does not
/// expose a public API to fetch the `CKRecord` backing a `@Model`
/// instance, and only that record can root a `CKShare`. We mint a
/// dedicated `ChorezHouseholdShare` record keyed by household UUID and
/// root the share on that. SwiftData-managed rows replicate via the
/// shared zone alongside (Phase 1.5's sync layer).
@available(iOS 17.5, *)
@MainActor
public final class CloudKitShareCoordinator: NSObject, UICloudSharingControllerDelegate {
    private let household: Household
    private let cloudKitContainerIdentifier: String
    private let onComplete: @MainActor (Result<CKShare, Error>) -> Void
    private var pendingShare: CKShare?
    private var didReportCompletion = false

    public init(household: Household,
                cloudKitContainerIdentifier: String,
                onComplete: @escaping @MainActor (Result<CKShare, Error>) -> Void) {
        self.household = household
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.onComplete = onComplete
    }

    /// Kick off the flow. Idempotent — a second invocation is a no-op
    /// so a button held down doesn't fork concurrent share creations.
    public func start() {
        guard !didReportCompletion else { return }
        Task { @MainActor in
            await runFlow()
        }
    }

    // MARK: - Flow

    private func runFlow() async {
        print("[ShareDebug] runFlow begin household=\(household.id) container=\(cloudKitContainerIdentifier)")
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: SharedZone.name,
                                     ownerName: CKCurrentUserDefaultName)
        // Distinct from the real Household record's recordName
        // (`"Household-<uuid>"`) that `CKSyncEngineCoordinator` writes
        // into the same zone. Same recordID across two record types
        // would collide on the CloudKit side and corrupt the sync.
        let rootRecordID = CKRecord.ID(recordName: "ChorezShareRoot-\(household.id.uuidString)",
                                       zoneID: zoneID)
        do {
            print("[ShareDebug] ensureZoneExists zone=\(zoneID.zoneName)")
            try await Self.ensureZoneExists(zoneID: zoneID, in: database)
            print("[ShareDebug] ensureZoneExists ok")
            let rootRecord = try await Self.fetchOrCreateRoot(
                recordID: rootRecordID,
                householdID: household.id,
                householdName: household.name,
                in: database
            )
            print("[ShareDebug] fetchOrCreateRoot ok recordID=\(rootRecord.recordID.recordName)")
            let share = try await Self.fetchOrCreateShare(
                for: rootRecord,
                householdName: household.name,
                in: database
            )
            print("[ShareDebug] share ok url=\(String(describing: share.url)) participants=\(share.participants.count)")
            pendingShare = share

            guard let presenter = Self.topmostViewController() else {
                print("[ShareDebug] no topmost VC found")
                reportCompletion(.failure(CloudKitShareError.noPresenter))
                return
            }
            let controller = UICloudSharingController(share: share, container: container)
            controller.delegate = self
            // `.allowReadWrite` + `.allowPrivate` is the canonical
            // "anyone-with-link, co-edit, no password" combo for a
            // parent-pair share. `.allowPublic` would make the link
            // joinable without any iCloud account, which we don't want.
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            print("[ShareDebug] presenting UICloudSharingController on \(type(of: presenter))")
            presenter.present(controller, animated: true)
        } catch {
            print("[ShareDebug] runFlow FAILED: \(error)")
            if let ckError = error as? CKError {
                print("[ShareDebug] CKError code=\(ckError.code.rawValue) userInfo=\(ckError.userInfo)")
            }
            reportCompletion(.failure(error))
        }
    }

    // MARK: - Topmost VC discovery

    /// Walk the active window scene's root-presented stack to find a
    /// UIViewController capable of `present(_:animated:)`. Stops at
    /// the deepest presented controller so we don't re-present onto a
    /// VC that's already showing a modal.
    private static func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        guard let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        var top = keyWindow.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - CloudKit primitives (unchanged from PR3)

    /// Idempotent zone create. CloudKit returns `.zoneNotFound` if
    /// the zone is missing on first run; any other error propagates.
    private static func ensureZoneExists(zoneID: CKRecordZone.ID,
                                         in database: CKDatabase) async throws {
        do {
            _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }
    }

    /// Returns the existing root record for this household if one has
    /// already been created, otherwise creates and saves a fresh one.
    /// Keeping the record name deterministic (`Household-<uuid>`)
    /// guarantees a second invite attempt reuses the same share rather
    /// than forking a duplicate.
    private static func fetchOrCreateRoot(recordID: CKRecord.ID,
                                          householdID: UUID,
                                          householdName: String,
                                          in database: CKDatabase) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: householdRecordType, recordID: recordID)
            record["id"] = householdID.uuidString as CKRecordValue
            record["name"] = householdName as CKRecordValue
            return try await database.save(record)
        }
    }

    /// Returns the existing `CKShare` for the root record if one
    /// exists (i.e. the owner already invited their spouse on a
    /// previous run), otherwise creates one with the
    /// "anyone-with-link, read-write" permission profile.
    private static func fetchOrCreateShare(for rootRecord: CKRecord,
                                           householdName: String,
                                           in database: CKDatabase) async throws -> CKShare {
        if let existingReference = rootRecord.share {
            let shareID = existingReference.recordID
            if let existing = try? await database.record(for: shareID) as? CKShare {
                return existing
            }
        }
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = householdName as CKRecordValue
        share.publicPermission = .readWrite
        let saved = try await database.modifyRecords(saving: [rootRecord, share],
                                                     deleting: [])
        let savedShare = saved.saveResults.values
            .compactMap { try? $0.get() as? CKShare }
            .first
        guard let savedShare else { throw CloudKitShareError.shareUnavailable }
        return savedShare
    }

    /// Record type for the share root. Kept distinct from the
    /// SwiftData-generated record types so the share anchor doesn't
    /// collide with model-mirrored data. The zone name itself lives
    /// in `SharedZone` so the share coordinator and the
    /// `CKSyncEngineCoordinator` agree on it.
    private static let householdRecordType = "ChorezHouseholdShare"

    // MARK: - UICloudSharingControllerDelegate

    public func cloudSharingController(_ csc: UICloudSharingController,
                                       failedToSaveShareWithError error: Error) {
        print("[ShareDebug] delegate failedToSaveShareWithError: \(error)")
        reportCompletion(.failure(error))
    }

    public func itemTitle(for csc: UICloudSharingController) -> String? {
        household.name
    }

    public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        print("[ShareDebug] delegate didSaveShare")
        guard let share = csc.share ?? pendingShare else {
            reportCompletion(.failure(CloudKitShareError.shareUnavailable))
            return
        }
        reportCompletion(.success(share))
    }

    public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        print("[ShareDebug] delegate didStopSharing (cancel)")
        reportCompletion(.failure(CloudKitShareError.cancelledByUser))
    }

    private func reportCompletion(_ result: Result<CKShare, Error>) {
        guard !didReportCompletion else { return }
        didReportCompletion = true
        onComplete(result)
    }
}

/// Top-level entry point for incoming share acceptance.
///
/// iOS hands the app a `CKShare.Metadata` when the spouse taps the
/// invite link (via `application(_:userDidAcceptCloudKitShareWith:)`
/// in UIKit or the scene-delegate equivalent in SwiftUI). Routing all
/// acceptance through this function keeps the path testable and
/// prevents a future caller from re-implementing the CloudKit
/// hand-off.
///
/// Returns a `Result` rather than throwing so the call site can decide
/// whether to surface failures in UI or log silently — share
/// acceptance can fail transiently (e.g. iCloud not yet reachable) and
/// the app will usually want to swallow the first attempt.
@available(iOS 17.5, *)
@MainActor
public func acceptShareInvitation(_ metadata: CKShare.Metadata,
                                  cloudKitContainerIdentifier: String) async -> Result<Void, Error> {
    let container = CKContainer(identifier: cloudKitContainerIdentifier)
    do {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
        return .success(())
    } catch {
        return .failure(error)
    }
}
