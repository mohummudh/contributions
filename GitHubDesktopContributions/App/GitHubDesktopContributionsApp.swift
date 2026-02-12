import SwiftUI

@main
struct GitHubDesktopContributionsApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
