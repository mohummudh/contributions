import SwiftUI
import WidgetKit

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub Desktop Contributions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("To set your GitHub username:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Add the widget to your desktop from the widget gallery", systemImage: "1.circle.fill")
                Label("Right-click the widget → Edit \"GitHub Contributions\"", systemImage: "2.circle.fill")
                Label("Enter your GitHub username and tap outside to save", systemImage: "3.circle.fill")
            }
            .font(.body)

            Divider()

            Button("Reload All Widgets") {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 220)
    }
}
