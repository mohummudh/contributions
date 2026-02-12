# GitHub Contributions Desktop Widget (WidgetKit)

This is a native macOS widget implementation using:

- SwiftUI app (for settings)
- WidgetKit extension (actual desktop widget)
- Shared GitHub contributions fetcher/parser

## What you get

- A true macOS widget you can add to desktop/widget gallery
- GitHub-style contribution heatmap colors
- Username stored in shared app group (`UserDefaults`)
- Automatic timeline refresh every 30 minutes

## 1. Create the project in Xcode

1. Open Xcode, create a new `App` project:
   - Name: `GitHubDesktopContributions`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Platform: `macOS`
2. Add a new target:
   - `Widget Extension`
   - Name: `GitHubDesktopContributionsWidgetExtension`
3. Close Xcode.

## 2. Replace generated files with this template

Copy these folders from this repo into your Xcode project directory:

- `App/`
- `WidgetExtension/`
- `Shared/`

Then reopen the project and add any missing files to the appropriate targets:

- App target:
  - `App/*`
  - `Shared/*`
- Widget extension target:
  - `WidgetExtension/*`
  - `Shared/*`

## 3. Configure bundle IDs and app group

In Xcode:

1. Set unique bundle identifiers for:
   - App target
   - Widget extension target
2. Enable `Signing & Capabilities` for both targets:
   - `App Sandbox` (if not already enabled)
   - Outgoing network connections (client)
   - `App Groups`
3. Create and add one shared group to both targets, for example:
   - `group.com.yourname.GitHubDesktopContributions`

Then update this constant in `Shared/WidgetSharedConfig.swift`:

- `appGroupIdentifier`

Also update both entitlements files to match the same group string:

- `App/GitHubDesktopContributions.entitlements`
- `WidgetExtension/GitHubDesktopContributionsWidgetExtension.entitlements`

## 4. Run and add the widget

1. Build and run the macOS app target once.
2. In the app window, set your GitHub username.
3. Add the widget from the macOS widget gallery to desktop.

## Notes

- Data source: `https://github.com/<username>?tab=contributions` (XHR), with fallback to `https://github.com/users/<username>/contributions`
- No external dependencies — parsing uses Foundation regex
- This only displays what GitHub exposes publicly for that profile.
