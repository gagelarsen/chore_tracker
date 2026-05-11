import Foundation

/// Identifiers shared by every component that touches the household's
/// CloudKit zone.
///
/// `CloudKitShareCoordinator` and `CKSyncEngineCoordinator` both need
/// to agree on the zone name (a `CKShare` covers exactly one zone, so
/// the two coordinators must point at the same zone for the data to
/// ride along with the share). Centralising the constants here means
/// neither file owns the name; rename is a one-line change.
public enum SharedZone {
    /// CloudKit zone where every replicated record lives. Both the
    /// share root and the SwiftData-mirrored data records sit here so
    /// a single `CKShare` carries everything.
    public static let name = "ChorezSharedZone"

    /// Subscription identifier for the zone-change push notification
    /// that wakes the app when remote writes arrive. Constant so a
    /// relaunch reuses the server-side subscription rather than
    /// stacking duplicates.
    public static let subscriptionID = "chorez.shared-zone-subscription"
}
