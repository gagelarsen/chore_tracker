import SwiftUI

/// Bridges an optional value (typically a `String?` alert message) to
/// the `Bool` binding that SwiftUI `.alert(_:isPresented:…)` requires.
///
/// Without this every screen ended up with the same four-line
/// `Binding(get:set:)` boilerplate. Centralising it here keeps the
/// "shared component" rule in `00-standards.md` honest.
extension Binding where Value == String? {
    /// `true` when the wrapped optional is non-`nil`; assigning `false`
    /// clears the optional. Other assignments are no-ops by design —
    /// SwiftUI only ever sets this back to `false` when an alert
    /// dismisses.
    var isPresent: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
