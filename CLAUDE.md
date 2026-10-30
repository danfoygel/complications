# Complications

Personal Apple Watch app (watch-only, no iPhone companion) whose real job is three watch-face complications. Single developer (Dan), personal use only.

| Complication | Family | Shows | Opens |
|---|---|---|---|
| Calendar ("Up Next") | `accessoryRectangular` | next event: time, title, location / "+N more" | `CalendarScreen` (rest of today + tomorrow) |
| Battery ("Battery Outline") | `accessoryCircular` | percent inside a battery outline that fills like a ring | `BatteryScreen` (level, time to empty / full) |
| Weather ("Temperature") | `accessoryCircular` | current temp on a low→high ring, condition symbol | `WeatherScreen` (current, hourly, daily) |

## How taps reach a screen

All three widgets live in one widget extension (`ComplicationsWidgets`, a `WidgetBundle`) embedded in one app. Each widget sets `.widgetURL(Route.x.url)` (`complications://calendar|battery|weather`); `RootView` handles it in `.onOpenURL` by replacing its `NavigationStack` path with that route. To add a complication: add a `Route` case (with `widgetKind`, `title`, `symbol`), a widget in `ComplicationsWidgets/`, list it in `ComplicationsWidgets.swift`, and a screen in `RootView`'s `navigationDestination`.

The scheme is deliberately not registered in Info.plist: `widgetURL` doesn't need it, and `xcrun simctl openurl` on watchOS simulators fails with -10814 even when it is registered. Routes are covered by `RouteTests`; the tap itself can only be checked by adding the complication to a face.

## Project layout

```
project.yml              XcodeGen spec — source of truth for the Xcode project
Complications/           watchOS app target (SwiftUI): RootView + routing, one screen per complication
ComplicationsWidgets/    WidgetKit extension: the widget bundle and the three complications
Shared/                  compiled into the app, the extension and the tests: Route, AppGroup, battery forecast, calendar, weather/location
ComplicationsTests/      hostless Swift Testing unit tests (watchOS); Shared/ is compiled straight into the bundle
.swiftlint.yml           lint rules
.swiftformat             format rules
```

- **`Complications.xcodeproj` is generated and git-ignored.** Never edit it (or change settings in Xcode's UI — they are lost on regeneration). Change `project.yml`, then run `xcodegen generate`.
- Files added or removed on disk are picked up by `xcodegen generate`; run it after adding files.
- Info.plist files are generated from build settings (`INFOPLIST_KEY_*` in `project.yml`). Keys with no `INFOPLIST_KEY_` setting (`NSExtension`, `NSWidgetWantsLocation`) go under the target's `info: properties:`, and entitlements under `entitlements: properties:`; XcodeGen writes those `Info.plist` / `.entitlements` files, which are git-ignored. Never edit them by hand.

## Data and permissions

- **App group** `group.com.danfoygel.complications` (`AppGroup.defaults`) is shared by the app and the extension. It holds the battery history (`batteryHistory`, last hour of readings, used for the forecast and time-remaining estimate), the last weather forecast (`weatherEntries`, shown when a fetch fails), and the last location (`lastLocation`).
- **Calendar**: EventKit full access (`NSCalendarsFullAccessUsageDescription` in both targets). Only the app can prompt; `CalendarScreen` asks and reloads the calendar widget when the answer changes. The extension uses the app's grant.
- **Location**: When In Use. `WeatherScreen` starts a `CLServiceSession` to prompt; the extension has `NSWidgetWantsLocation` and uses `CLLocationUpdate.liveUpdates()` with a 10 s timeout, then the cached location.
- **WeatherKit**: `com.apple.developer.weatherkit` entitlement on both targets. WeatherKit must be enabled for both App IDs (`com.danfoygel.complications`, `com.danfoygel.complications.widgets`) in the developer portal, under both Capabilities and App Services. It usually fails with an auth error in the simulator; test weather on the real watch. `WeatherScreen` shows the Apple Weather attribution (required).
- **Battery**: `WKInterfaceDevice` battery monitoring. The widget gets reloads roughly every 15 min and fills the gaps with one predicted entry per whole percent (`BatteryForecast`). `BatteryScreen` takes a reading every minute while open and reloads the widget.
- Widget reload budgets are limited: calendar reloads every 30 min (entries at every event start/end and at midnight), weather every 30 min (hourly forecast entries for 6 h; 15 min retry with nothing to show), battery every 15 min.

## Identifiers

| | |
|---|---|
| Watch app bundle ID | `com.danfoygel.complications` (`WKWatchOnly`) |
| Widget extension bundle ID | `com.danfoygel.complications.widgets` |
| App group | `group.com.danfoygel.complications` |
| Signing team | `ZVU48K8YCD` (paid Apple Developer Program, individual account; automatic signing) |
| Deployment target | watchOS 26.0 |
| Swift | 6.0 language mode (strict concurrency), toolchain 6.2.4 |
| UI | SwiftUI, WidgetKit |

## Toolchain (this machine)

- Xcode 26.3, SDK watchOS 26.2; simulator runtime watchOS 26.2.
- Homebrew: `xcodegen`, `swiftlint`, `swiftformat`, `xcbeautify`.
- `gh` is signed in as `danfoygel`; remote is `github.com/danfoygel/complications` (private).
- MCP: the `xcode` server (`xcrun mcpbridge`) exposes Xcode tools (build, diagnostics, `RenderPreview`, etc.) for whichever project windows are open in Xcode. Xcode must be running with Settings → Intelligence → "Allow external agents to use Xcode tools" on, and the connection approved in Xcode. If the server shows 0 tools in a session, approve the dialog in Xcode and start a fresh session. Every widget file has a `#Preview(as:)`; `RenderPreview` on it is the quickest way to check a complication's look.
- `xcodebuildmcp` CLI and its skill are also installed.
- Real device: Apple Watch Series 8 (watchOS 26.6), registered to the team, reached through the iPhone 17 ("Big Green Phone"); both must be unlocked and in Developer Mode (`xcrun devicectl list devices`), phone on a cable for reliability. A first device build needs `-allowProvisioningUpdates` so automatic signing can create the App IDs, app group and profiles.
- `~/dev/rootine` is another of Dan's projects using the same setup and the same simulators. It uses Apple Watch Series 11 (46mm), paired with the iPhone 17 Pro; this project uses **Apple Watch Ultra 3 (49mm)** so the two don't collide.

## Commands

```bash
xcodegen generate                      # regenerate Complications.xcodeproj after editing project.yml / adding files

# Build the watch app (also builds and embeds the widget extension)
xcodebuild -project Complications.xcodeproj -scheme Complications \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -derivedDataPath build build | xcbeautify

# Unit tests
xcodebuild -project Complications.xcodeproj -scheme Complications \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -derivedDataPath build test | xcbeautify

swiftformat .                          # format
swiftlint lint                         # lint (should report 0 violations)
```

Build output goes to `build/` (git-ignored). To try the app in the simulator: `xcrun simctl install <sim> build/Build/Products/Debug-watchsimulator/Complications.app`, then `xcrun simctl launch <sim> com.danfoygel.complications`.

## Conventions

- Run `swiftformat .` and `swiftlint lint` before committing; keep lint at 0 violations.
- Prefer SwiftUI and Swift concurrency (`async`/`await`, actors); the project builds in Swift 6 mode, so fix concurrency warnings rather than suppressing them.
- Data that crosses into timeline entries is copied into plain `Sendable` structs (`CalendarEvent`, `WeatherEntry`) rather than holding EventKit/WeatherKit objects.
- Keep forecasting/selection logic pure and in `Shared/` so it can be unit-tested (`BatteryForecast`, `CalendarEvents.upNext`).
- Add capabilities/entitlements via `project.yml` (`entitlements:` / `settings:`) on **both** targets when the extension needs them too, not the Xcode UI.
