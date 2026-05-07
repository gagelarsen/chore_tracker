import SwiftUI

/// Root screen placeholder.
///
/// Exists so the initial CI run has something real to build and the UI test
/// suite has something real to assert against. Replace with the chore list
/// when that feature lands.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, Chorez")
                .font(.title2)
                .accessibilityIdentifier("welcomeLabel")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
