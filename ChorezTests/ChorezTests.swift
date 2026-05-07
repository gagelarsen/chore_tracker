import Testing
@testable import Chorez

/// Sanity-check unit test ensuring the test target links the app target and
/// the Swift Testing runtime executes. Replace with real coverage as features
/// land — the policy requires every new public type/function to ship with at
/// least one test.
struct ChorezTests {
    @Test("App module is reachable from the test target")
    func appModuleIsReachable() {
        // Constructing the @main type would start the SwiftUI runtime, so we
        // only assert the type exists. This catches a broken module link
        // (the most common scaffold regression) without booting the app.
        #expect(String(describing: ChorezApp.self) == "ChorezApp")
    }
}
