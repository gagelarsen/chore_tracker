import SwiftUI

/// Top-level tab container.
///
/// Wraps every Phase 1 screen in its own `NavigationStack` so each tab
/// gets independent push/pop state. The Home tab pushes to
/// `KidDetailView`; the rest are flat lists with modal sheets.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .accessibilityIdentifier("homeTab")

            NavigationStack {
                ChoresManageView()
            }
            .tabItem {
                Label("Chores", systemImage: "checklist")
            }
            .accessibilityIdentifier("choresTab")

            NavigationStack {
                RewardsManageView()
            }
            .tabItem {
                Label("Rewards", systemImage: "gift.fill")
            }
            .accessibilityIdentifier("rewardsTab")

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .accessibilityIdentifier("settingsTab")
        }
    }
}
