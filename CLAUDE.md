# Complications

Personal Apple Watch app whose real job is three watch-face complications, plus a small iPhone companion that sends the phone's battery level and location to the watch. Single developer (Dan), personal use only.

| Complication | Family | Shows | Opens |
|---|---|---|---|
| Calendar ("Up Next") | `accessoryRectangular` | next two timed events, one per line, never all-day ones or ones over 12 hours (`CalendarEvents.upNext`); one on now or starting within the hour leads, large with its calendar color. Below them, pinned to the bottom of the slot, the weather line (`WeatherLine` / `WeatherLineView`, every symbol in one yellow). With rain or snow in the next 24 h: the total for those 24 h at the left ("0.4″", "12mm", snow as its depth) and when it starts or stops at the right ("in 3h", "for 4h", "for 12h+"). With some only later in the week: the next sunrise or sunset at the left (half a sun over a ▼ for sunset, a ▲ over half a sun for sunrise) and the day at the right ("on Tu"). Otherwise: the sunrise or sunset and the hour's AQI. With no forecast at all, a third event instead | `CalendarScreen` (rest of today + tomorrow) |
| Battery ("Battery Outline") | `accessoryCircular` | a horizontal battery outline split in two halves that both fill from the middle of the left side: watch on top (clockwise) with its percent above, iPhone on the bottom (counter-clockwise) with its percent below (dimmed after an hour) | `BatteryScreen` (level, time to empty / full, iPhone battery) |
| Weather ("Temperature") | `accessoryCircular` | current temp over the next high (▲) or low (▼) on the standard circular background (`TemperatureView`) | `WeatherScreen` (current, hourly, daily) |

## How taps reach a screen

All three widgets live in one widget extension (`ComplicationsWidgets`, a `WidgetBundle`) embedded in the watch app. Each widget sets `.widgetURL(Route.x.url)` (`complications://calendar|battery|weather`); `RootView` handles it in `.onOpenURL` by replacing its `NavigationStack` path with that route. To add a complication: add a `Route` case (with `widgetKind`, `title`, `symbol`), a widget in `ComplicationsWidgets/`, list it in `ComplicationsWidgets.swift`, and a screen in `RootView`'s `navigationDestination`. A complication that also shows another screen's data goes in that route's `widgetKinds` too, so the screens and `PhoneLink` reload it. (Modular's top slot takes only the system date; third-party complications can't go there.)

The scheme is deliberately not registered in Info.plist: `widgetURL` doesn't need it, and `xcrun simctl openurl` on watchOS simulators fails with -10814 even when it is registered. Routes are covered by `RouteTests` (in `BatteryForecastTests.swift`); the tap itself can only be checked by adding the complication to a face.

## Phone battery on the watch

The watch can't read the phone's battery, so the iPhone app (`Complications/`) sends it over WatchConnectivity as a `PhoneBatteryReading` (`Connectivity/PhoneBattery.swift`). The watch's `PhoneLink` saves each newer reading in the app group and reloads the battery widget when it changes the face (`needsReload`: a different percent or charger state, or the timeline's dimming of the reading it was built with, `phoneBatteryInTimeline`, due within half an hour), since background reloads count against the widget's budget. Concurrent asks share one request. The same messages carry the phone's location for the watch's weather (see Location below). Three routes keep it current:

1. **Shortcuts automations** (the main one). The iPhone app provides the App Intent **Send Battery to Watch** (`SendBatteryToWatch`), which runs in the background. Dan sets up personal automations in Shortcuts that run it immediately: Battery Level falls below 90/80/…/10%, rises above 20/40/60/80/95%, and Charger connected / disconnected. The phone app's screen has the same instructions.
2. **Background refresh.** `BGAppRefreshTask` (`com.danfoygel.complications.refresh`) is requested every 15 min, but iOS decides when it runs, and for a rarely opened app that can be hours apart.
3. **Direct asks from the watch.** Whenever the watch app becomes active (and every minute while `BatteryScreen` is open and the app active), `PhoneLink.refresh()` sends `PhoneBatteryReading.request` with `sendMessage`, unless the saved reading is under 5 minutes old (`maxAge`; the phone pushes changes on its own). iOS launches the phone app in the background to answer it (`WatchLink.session(_:didReceiveMessage:replyHandler:)`). The ask times out after 5 s if the phone isn't nearby.

`WatchLink.send()` always updates the application context (the watch picks it up the next time its app runs). It also sends `transferCurrentComplicationUserInfo`, which wakes the watch app at once, but only when the charger state has changed since the last transfer, or the percent has moved by `transferStep` (1% while more than 25 transfers are left that day, then 5%), and a complication is on the active face: iOS allows about 50 a day. A fixed 15-minute schedule isn't possible: iOS has no such timer for third-party apps, and 96 a day would exceed that budget. Both apps call `start()` on their link in `App.init` so a message that launches them in the background finds an activated session.

## Project layout

```
project.yml              XcodeGen spec — source of truth for the Xcode project
Complications/           iOS app target (SwiftUI): battery and location sender (WatchLink), App Intent, background refresh, location prompt, setup screen
ComplicationsWatch/      watchOS app target (SwiftUI), embedded in the iOS app: RootView + routing, PhoneLink, one screen per complication
ComplicationsWidgets/    WidgetKit extension, embedded in the watch app: the widget bundle and the three complications
Shared/                  watch side only (watch app, extension, tests): Route, AppGroup, battery forecast, calendar, weather/location
Connectivity/            compiled into both apps, the extension and the tests: PhoneBatteryReading, PhoneLocation, SessionActivation
ComplicationsTests/      hostless Swift Testing unit tests (watchOS); Shared/ and Connectivity/ are compiled straight into the bundle
.swiftlint.yml           lint rules
.swiftformat             format rules
```

- **`Complications.xcodeproj` is generated and git-ignored.** Never edit it (or change settings in Xcode's UI — they are lost on regeneration). Change `project.yml`, then run `xcodegen generate`.
- Files added or removed on disk are picked up by `xcodegen generate`; run it after adding files.
- Info.plist files are generated from build settings (`INFOPLIST_KEY_*` in `project.yml`). Keys with no `INFOPLIST_KEY_` setting (`NSExtension`) go under the target's `info: properties:`, and entitlements under `entitlements: properties:`; XcodeGen writes those `Info.plist` / `.entitlements` files, which are git-ignored. Never edit them by hand.

## Data and permissions

- **App group** `group.com.danfoygel.complications` (`AppGroup.defaults`) is shared by the watch app and the extension (the iPhone app doesn't use it). It holds the battery history (`batteryHistory`, last hour of readings, or the last one from up to 3 h before when there are none in the hour, used for the forecast and time-remaining estimate; written under `AppGroup.withLock`, a `flock` both processes share), the phone's latest reading (`phoneBattery`), the phone's latest location (`phoneLocation`), and the fetch backoffs (`weatherBackoff`, `airQualityBackoff`). The last WeatherKit fetch (a `WeatherSnapshot` shared by both weather complications and `WeatherScreen`, and shown when a fetch fails) is too big for the defaults, so it's a file in the group's container (`weatherSnapshot.json`); `cachedSummary()` reads just its date and place. The iPhone app keeps what it last sent in its own `UserDefaults.standard` (`Sent`).
- **Calendar**: EventKit full access (`NSCalendarsFullAccessUsageDescription` in both targets). Only the app can prompt; `CalendarScreen` asks and reloads the calendar widget when the answer changes. The extension uses the app's grant. Cancelled events and ones the user declined are left out everywhere (`CalendarEvents.events`). `CalendarScreen` reloads when the app comes back and on `EKEventStoreChanged` (it keeps its own store alive for that); `WeatherScreen` also reloads when the app comes back.
- **Location**: the watch never takes a fix of its own (its GPS costs more battery than the weather is worth) and has no location permission. The iPhone app asks for When In Use (`Locator`, on its screen) and every send and reply carries a `PhoneLocation` (`Connectivity/PhoneLocation.swift`) next to the battery reading: the system's latest fix (`CLLocationManager().location`), which reading never starts the GPS and works in the background. That fix can be hours old, so whenever the phone app comes to the front `Locator` also takes a coarse one (`requestLocation()`, 1 km accuracy, 10 s limit) and sends again; `WeatherScreen` says how old the location is when it's over an hour. A move of 3 km (`significantDistance`) also earns a complication transfer. `PhoneLink` saves each newer one as `phoneLocation` (`PhoneLocation.saved()`), reloading the weather widgets after a 3 km move from both the saved forecast's place and where they were last reloaded for (`weatherReloadLocation`), however many small steps it came in. The weather is only as current as the phone's last send; `WeatherScreen` asks the phone directly when there's none yet.
- **WeatherKit**: `com.apple.developer.weatherkit` entitlement on both watch targets. WeatherKit must be enabled for both watch App IDs (`com.danfoygel.complications.watchkitapp`, `com.danfoygel.complications.watchkitapp.widgets`) in the developer portal, under both Capabilities and App Services. Without App Services the fetch fails with `WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors` code 2 (Apple refused the app's token). `WeatherScreen` shows the full error with its domain and code. It usually fails with an auth error in the simulator; test weather on the real watch. To see the weather and battery complications' faces in the simulator, launch the Debug watch app with `-complicationGallery` (`xcrun simctl launch <sim> com.danfoygel.complications.watchkitapp -complicationGallery`): `ComplicationGallery` shows `TemperatureView`, `BatteryComplicationView` and Up Next's `WeatherLineView` (both in `Shared/` for this) at their 41mm size (45 pt) for sample entries, the top row with a hairline at the complication's bounds. It draws them in full color; tinted faces can only be checked on the watch. `WeatherScreen` shows the Apple Weather attribution (required).
- **Battery**: `WKInterfaceDevice` battery monitoring. The widget gets reloads roughly every 30 min and fills the gaps with one predicted entry per whole percent (`BatteryForecast`). `BatteryScreen` takes a reading every minute while open and the app active, and reloads the widget. Charging means `.charging` or `.full`, on both devices.
- Widget reload budgets are limited: calendar reloads every 30 min (entries for a week ahead at every event start/end, an hour before each start, and at each midnight, so a run of skipped reloads doesn't leave ended events on the face; for the weather line also at each sunrise and sunset, each hour of AQI, and each 5-minute mark in the next 24 h, keeping only those where the line reads differently (`WeatherLine.changes`, by `appearance`); rain is left out once the hourly forecast stops covering the next 24 h, which with 48 hours fetched is a day after the fetch; only shown events (timed, up to 12 h) add entries), weather every 60 min (hourly forecast entries up to 6 h after the fetch, then the no-data icon, with the reload due by then; 15 min retry with nothing to show), battery every 30 min. Both weather complications get their forecast from `WeatherSnapshot.latest`: one `.current` + `.minute` + `.hourly` (48 h from the current hour, `hourlyRange`; the default 25 h stops covering Up Next's 24 h within the hour) + `.daily` fetch, reused while under 50 min old (`maxAge`) and from within 3 km, so between them the watch fetches about once an hour; a fetch already running for about the same place is shared rather than repeated. A fetch gives up after 15 s (`fetchLimit`, via `Deadline`; the AQI request after 10 s) so a poor connection doesn't hold up the calendar. After a failure the widgets don't try again for 15 min, doubling with each further one up to 2 h (`Backoff`, per fetch, reset by a success or a 3 km move); `WeatherScreen` always tries. When one fails, `WeatherSnapshot.fallback` stands in only from within 3 km and under 6 h old for Temperature (`WeatherForecast.horizon`) or a day for Up Next (`fallbackAge`); past that Temperature shows its no-data icon and Up Next a third event.
- **Air quality**: hourly US AQI from Open-Meteo (`AirQuality`, free, no key; WeatherKit has none), sent the location rounded to 2 decimals. Up Next's provider fetches it (`AirQuality.latest`) after the weather, only when the line would show it at some hour of the next day, reusing the saved fetch (`airQuality`) while under 50 min old and from within 3 km, and shows it when it's dry.
- **Rain and snow wording**: `PrecipitationOutlook` turns the forecast into "in 30m" / "in 18h" / "for 4h" / "for 12h+" / "on Tu". Minutes come from WeatherKit's minute forecast, which only some countries have; elsewhere times are whole hours. `PrecipitationTotal` adds up the hourly forecast's amounts for the next 24 h (`WeatherForecast.total`), prorating the current hour, in the locale's rain or snow unit.

## Identifiers

| | |
|---|---|
| iOS app bundle ID | `com.danfoygel.complications` |
| watchOS bundle ID | `com.danfoygel.complications.watchkitapp` (companion = iOS app) |
| Widget extension bundle ID | `com.danfoygel.complications.watchkitapp.widgets` |
| App group | `group.com.danfoygel.complications` |
| Signing team | `ZVU48K8YCD` (paid Apple Developer Program, individual account; automatic signing) |
| Deployment targets | iOS 26.0, watchOS 26.0 |
| Swift | 6.0 language mode (strict concurrency), toolchain 6.2.4 |
| UI | SwiftUI, WidgetKit |

## Toolchain (this machine)

- Xcode 26.3, SDKs iOS 26.2 / watchOS 26.2; simulator runtimes iOS 26.3 / watchOS 26.2.
- Homebrew: `xcodegen`, `swiftlint`, `swiftformat`, `xcbeautify`.
- `gh` is signed in as `danfoygel`; remote is `github.com/danfoygel/complications` (private).
- MCP: the `xcode` server (`xcrun mcpbridge`) exposes Xcode tools (build, diagnostics, `RenderPreview`, etc.) for whichever project windows are open in Xcode. Xcode must be running with Settings → Intelligence → "Allow external agents to use Xcode tools" on, and the connection approved in Xcode. If the server shows 0 tools in a session, approve the dialog in Xcode and start a fresh session. Every widget file has a `#Preview(as:)`; `RenderPreview` on it is the quickest way to check a complication's look, but only while the active scheme in Xcode is `ComplicationsWatch` (with the iOS scheme it fails with AppCannotRunOnTargetDestination). Regenerating the project can close its Xcode window; reopen it with `open Complications.xcodeproj`.
- `xcodebuildmcp` CLI and its skill are also installed.
- Real devices: iPhone 17 ("Big Green Phone", iOS 26.6) and Apple Watch Series 8 (watchOS 26.6), both registered to the team. Each must be unlocked and in Developer Mode (`xcrun devicectl list devices`), phone on a cable for reliability; Xcode reaches the watch through the phone. A first device build needs `-allowProvisioningUpdates` so automatic signing can create the App IDs, app group and profiles. Install each app on its own device with `xcrun devicectl device install app` (the iOS build doesn't reliably push the embedded watch app).
- `~/dev/rootine` is another of Dan's projects using the same setup and the same simulators. It uses Apple Watch Series 11 (46mm), paired with the iPhone 17 Pro; this project uses **Apple Watch Ultra 3 (49mm)** for watch builds and tests so the two don't collide. WatchConnectivity work in the simulator needs a pair of its own (`xcrun simctl pair`), and the simulators have no battery (`PhoneBatteryReading.current()` is `nil` there), so phone-to-watch sending can really only be tested on the devices.

## Commands

```bash
xcodegen generate                      # regenerate Complications.xcodeproj after editing project.yml / adding files

# Build the iPhone app (also builds and embeds the watch app and its widget extension)
xcodebuild -project Complications.xcodeproj -scheme Complications \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build | xcbeautify

# Build the watch app alone
xcodebuild -project Complications.xcodeproj -scheme ComplicationsWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -derivedDataPath build build | xcbeautify

# Unit tests (watchOS)
xcodebuild -project Complications.xcodeproj -scheme ComplicationsWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -derivedDataPath build test | xcbeautify

swiftformat .                          # format
swiftlint lint                         # lint (should report 0 violations)
```

Build output goes to `build/` (git-ignored). To try the watch app in the simulator: `xcrun simctl install <sim> build/Build/Products/Debug-watchsimulator/ComplicationsWatch.app`, then `xcrun simctl launch <sim> com.danfoygel.complications.watchkitapp`.

## Conventions

- Run `swiftformat .` and `swiftlint lint` before committing; keep lint at 0 violations.
- Prefer SwiftUI and Swift concurrency (`async`/`await`, actors); the project builds in Swift 6 mode, so fix concurrency warnings rather than suppressing them.
- Data that crosses into timeline entries is copied into plain `Sendable` structs (`CalendarEvent`, `WeatherEntry`) rather than holding EventKit/WeatherKit objects.
- Keep forecasting/selection logic pure and in `Shared/` so it can be unit-tested (`BatteryForecast`, `CalendarEvents.upNext`, `WeatherForecast.nextExtreme` / `.precipitation` in `WeatherOutlook.swift`, which take `ForecastHour` / `ForecastDay` rather than WeatherKit types).
- Add capabilities/entitlements via `project.yml` (`entitlements:` / `settings:`) on **both** watch targets when the extension needs them too, not the Xcode UI.
- WatchConnectivity delegates (`WatchLink`, `PhoneLink`) are `Sendable` singletons with no mutable state outside a `Mutex`. Delegate callbacks arrive on a background queue, so hop to the main thread for UIKit (`UIDevice`).
- Keep the iPhone and watch targets building at all times; the iOS scheme builds everything.
- Complication text uses fixed point sizes for Dan's 41mm Series 8 (`.system(size:weight:)`) in plain SF Compact (not Rounded), never text styles like `.headline`. They don't follow the watch's Text Size setting.
