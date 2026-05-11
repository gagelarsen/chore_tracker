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
}

/// SwiftUI bridge that drives `UICloudSharingController`.
///
/// `UICloudSharingController` is a UIKit-only system sheet — Apple
/// hasn't shipped a SwiftUI equivalent — so any app that wants the
/// native "share via Messages / Mail / Copy Link" picker has to wrap it
/// in `UIViewControllerRepresentable`. SettingsView presents this
/// inside a `.sheet { … }` once the owner taps "Invite spouse".
///
/// Why we mint the share before constructing the controller:
/// `UICloudSharingController.init(preparationHandler:)` is deprecated
/// from iOS 17. The replacement `init(share:container:)` needs a live
/// `CKShare` in hand, so the representable returns a transparent host
/// `UIViewController` immediately, kicks off an async share-creation
/// task, and presents the real share sheet from that host once the
/// share resolves.
///
/// Why we use a CloudKit-mirror record instead of the SwiftData
/// `Household` row directly: as of iOS 18 SDK, SwiftData does not
/// expose a public API to fetch the `CKRecord` backing a `@Model`
/// instance, and only that record can root a `CKShare`. We mint a
/// dedicated `ChorezHouseholdShare` record keyed by household UUID and
/// root the share on that. SwiftData-managed rows replicate via the
/// shared zone alongside.
@available(iOS 17.5, *)
@MainActor
public struct CloudKitShareSheet: UIViewControllerRepresentable {
    /// The household whose record becomes the share root. The model
    /// instance itself isn't shared directly; we mirror its `id` into
    /// a `CKRecord` that anchors the share zone.
    public let household: Household
    /// CloudKit container identifier (e.g. `iCloud.com.glarsen.chorez`).
    /// Passed in rather than hard-coded so test/staging builds can
    /// target a different container without recompiling this file.
    public let cloudKitContainerIdentifier: String
    /// Invoked on the main actor when the sheet closes. Success carries
    /// the live `CKShare`; failure carries either a CloudKit error or
    /// one of our `CloudKitShareError` cases. SettingsView drives its
    /// alert state from this.
    public let onComplete: @MainActor (Result<CKShare, Error>) -> Void

    public init(household: Household,
                cloudKitContainerIdentifier: String,
                onComplete: @escaping @MainActor (Result<CKShare, Error>) -> Void) {
        self.household = household
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.onComplete = onComplete
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(household: household,
                    cloudKitContainerIdentifier: cloudKitContainerIdentifier,
                    onComplete: onComplete)
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        // Return a transparent host immediately and present the real
        // share sheet from inside it once the async share mint resolves.
        // Doing it this way (rather than blocking `makeUIViewController`
        // on the async call) keeps the SwiftUI lifecycle non-blocking
        // and gives us a stable presenter for the share sheet.
        let host = ShareHostController()
        context.coordinator.host = host
        Task { @MainActor in
            await context.coordinator.startShareFlow()
        }
        return host
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No reactive state — the share lifecycle is one-shot.
    }

    /// UIKit delegate, share-preparation worker, and presenter glue.
    ///
    /// Lives as long as the SwiftUI representable is in the hierarchy.
    /// Holds the in-flight share so the delegate callbacks can resolve
    /// it back to the caller via `onComplete`.
    @MainActor
    public final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        fileprivate weak var host: ShareHostController?
        private let household: Household
        private let cloudKitContainerIdentifier: String
        private let onComplete: @MainActor (Result<CKShare, Error>) -> Void
        private var pendingShare: CKShare?
        private var didReportCompletion = false

        init(household: Household,
             cloudKitContainerIdentifier: String,
             onComplete: @escaping @MainActor (Result<CKShare, Error>) -> Void) {
            self.household = household
            self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
            self.onComplete = onComplete
        }

        /// Mint (or fetch) the share root and the `CKShare`, then
        /// present `UICloudSharingController(share:container:)` from
        /// the host VC. Called once when the representable first
        /// materialises.
        fileprivate func startShareFlow() async {
            let container = CKContainer(identifier: cloudKitContainerIdentifier)
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: SharedZone.name,
                                         ownerName: CKCurrentUserDefaultName)
            let rootRecordID = CKRecord.ID(recordName: "Household-\(household.id.uuidString)",
                                           zoneID: zoneID)
            do {
                try await Self.ensureZoneExists(zoneID: zoneID, in: database)
                let rootRecord = try await Self.fetchOrCreateRoot(
                    recordID: rootRecordID,
                    householdID: household.id,
                    householdName: household.name,
                    in: database
                )
                let share = try await Self.fetchOrCreateShare(
                    for: rootRecord,
                    householdName: household.name,
                    in: database
                )
                pendingShare = share
                let controller = UICloudSharingController(share: share, container: container)
                controller.delegate = self
                // `.allowReadWrite` + `.allowPrivate` is the canonical
                // "anyone-with-link, co-edit, no password" combo for a
                // parent-pair share. `.allowPublic` would make the
                // link joinable without any iCloud account, which we
                // don't want.
                controller.availablePermissions = [.allowReadWrite, .allowPrivate]
                host?.present(controller, animated: true)
            } catch {
                reportCompletion(.failure(error))
                host?.dismiss(animated: true)
            }
        }

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

        /// Returns the existing root record for this household if one
        /// has already been created, otherwise creates and saves a
        /// fresh one. Keeping the record name deterministic
        /// (`Household-<uuid>`) guarantees a second invite attempt
        /// reuses the same share rather than forking a duplicate.
        private static func fetchOrCreateRoot(recordID: CKRecord.ID,
                                              householdID: UUID,
                                              householdName: String,
                                              in database: CKDatabase) async throws -> CKRecord {
            do {
                return try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                let record = CKRecord(recordType: Self.householdRecordType, recordID: recordID)
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
            // `modifyRecords` returns one result per saved record; pluck
            // the share back out. A missing share here means CloudKit
            // accepted the save but didn't echo the CKShare we just
            // wrote — treat as an SDK contract violation.
            let savedShare = saved.saveResults.values
                .compactMap { try? $0.get() as? CKShare }
                .first
            guard let savedShare else { throw CloudKitShareError.shareUnavailable }
            return savedShare
        }

        // MARK: - UICloudSharingControllerDelegate

        public func cloudSharingController(_ csc: UICloudSharingController,
                                           failedToSaveShareWithError error: Error) {
            reportCompletion(.failure(error))
        }

        public func itemTitle(for csc: UICloudSharingController) -> String? {
            household.name
        }

        public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share ?? pendingShare else {
                reportCompletion(.failure(CloudKitShareError.shareUnavailable))
                return
            }
            reportCompletion(.success(share))
        }

        public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            reportCompletion(.failure(CloudKitShareError.cancelledByUser))
        }

        private func reportCompletion(_ result: Result<CKShare, Error>) {
            // The system delegate can fire both didSave + didStop in
            // quick succession; guard against a double callback so
            // SettingsView's alert state doesn't flicker.
            guard !didReportCompletion else { return }
            didReportCompletion = true
            onComplete(result)
        }

        /// Record type for the share root. Kept distinct from the
        /// SwiftData-generated record types so the share anchor doesn't
        /// collide with model-mirrored data. The zone name itself
        /// lives in `SharedZone` so the share coordinator and the
        /// `CKSyncEngineCoordinator` (which writes the actual data
        /// into the same zone) agree on it.
        fileprivate static let householdRecordType = "ChorezHouseholdShare"
    }

    /// Transparent presenter that anchors the share sheet inside the
    /// SwiftUI hierarchy.
    ///
    /// `UIViewControllerRepresentable` needs a `UIViewController` to
    /// return synchronously, but the `CKShare` isn't available at that
    /// moment. This host fills the slot and becomes the presenting
    /// view controller once the async mint resolves.
    public final class ShareHostController: UIViewController {
        public override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }
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
