import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            if settings.isServerConfigured {
                TabView {
                    CreateSongView(vm: environment.createSongViewModel)
                        .tabItem { Label("创作", systemImage: "music.note") }
                    JobsListView(vm: environment.jobsViewModel)
                        .tabItem { Label("任务", systemImage: "list.bullet.rectangle") }
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                }
            } else {
                ServerSetupView(mode: settings.onboardingDone ? .missing : .onboarding)
            }
        }
        .animation(.easeInOut, value: settings.isServerConfigured)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview-root")!)))
        .environmentObject(AppEnvironment(settings: SettingsStore(defaults: UserDefaults(suiteName: "preview-root")!)).settings)
}
