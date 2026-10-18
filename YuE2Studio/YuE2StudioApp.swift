import SwiftUI

@main
struct YuE2StudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppEnvironmentHolder.shared)
                .environmentObject(AppEnvironmentHolder.shared.settings)
                .environmentObject(AppEnvironmentHolder.shared.history)
                .preferredColorScheme(.dark)
        }
    }
}
