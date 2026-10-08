# Swordfish

> A macOS menu bar utility for iOS and macOS engineers: Xcode and Simulator tools, device and distribution workflows, network debugging, system monitoring, and clipboard productivity.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/License-MIT-green)

Swordfish is a native SwiftUI + AppKit menu bar app. Its popover has **System**, **Dev Kit**, and **Clipboard** tabs. Larger tools open their own windows; the menu bar icon can also show a live system metric. The feature list below follows those entry points and includes the settings and permissions needed to use them.

| Area | What you can do |
|---|---|
| [Dev Kit](#xcode--ios-tooling) | Manage Xcode, Simulators and physical devices; inspect builds, signing, crashes and releases; test push, links and network behavior |
| [JSON and utilities](#json) | View and transform JSON; generate Swift types; convert common developer formats and create app assets |
| [System](#system-popover) | Control displays, sleep, audio and appearance; monitor hardware, network, battery and processes |
| [Clipboard](#clipboard) | Search and paste history, run content-aware actions, and use desktop quick actions |
| [Settings](#app-level) | Configure language, startup, monitoring, clipboard behavior, API keys and permissions |

## Screenshots
<img width="3424" height="1248" alt="App" src="https://github.com/user-attachments/assets/85600897-1ed0-4ce0-b183-220057f7defc" />
## Features

### Xcode & iOS Tooling
- **Delete DerivedData** — One-click wipe of `~/Library/Developer/Xcode/DerivedData` with a live size readout
- **Active Xcode switcher** — Lists every installed Xcode and switches `xcode-select` (admin prompt) when more than one is present
- **Disk Cleanup** — Sizes and selectively deletes DerivedData per project, simulator runtimes (with last-used dates, via `simctl runtime delete`), iOS/watchOS/tvOS DeviceSupport per version, Archives, SPM / Xcode / CoreSimulator caches, plus `simctl delete unavailable`
- **Build Times** — Reads Xcode's build manifests in DerivedData: durations per scheme with a trend sparkline, and a notification when a build finishes (minimum duration and "only while Xcode is in the background" configurable; slower-than-usual builds are flagged)
- **Xcode Releases & Runtimes** — Latest Xcode releases (installed ones marked) with release notes, `.xip` download or one-click install through the `xcodes` CLI, and simulator runtime downloads via `xcodebuild -downloadPlatform`
- **Crash Symbolicator** — Drop a `.ips` or `.crash` report; dSYMs are found by UUID through Spotlight and frames resolved with `atos`. Includes a "find dSYM by UUID" lookup
- **Clean Build** — Sends the clean command to the active Xcode workspace via `osascript`
- **iOS Simulator** — List, boot, shut down (including all at once), delete, create (runtime + device type), clone, rename and erase simulators; open the Simulator app
- **Simulator Toolbox** — Everyday `simctl` helpers for a booted simulator in one place:
  - **Status Bar Override** — App Store screenshot mode (9:41, full battery & signal) with editable time, battery level/state, and network indicator (`simctl status_bar`)
  - **Permission Manager** — Grant / revoke / reset privacy services (Location, Photos, Contacts, Microphone, …) per installed app (`simctl privacy`)
  - **Location Simulation** — City presets or custom lat/lon, plus routes: preset or custom waypoints / GPX import played at walk, run, bike, city or highway speed (`simctl location start`)
  - **Add Media** — Drag & drop images/videos (or a file picker) straight into the simulator's Photos library (`simctl addmedia`)
  - **Apps** — List installed user apps; install a `.app` (drag & drop), launch / terminate, launch in any of the app's languages or with pseudo-localization (double-length, right-to-left, unlocalized-string highlighting), edit UserDefaults in a dedicated editor, open SQLite / Core Data / SwiftData stores, erase app data, uninstall
  - **Device** — Dynamic Type size (XS…AX5), Increase Contrast, Face ID / Touch ID enroll + match / no-match, keychain reset, Mac ↔ Simulator pasteboard sync, and trusting a proxy root CA (Proxyman / Charles / mitmproxy)
  - **Quick actions** — One-click simulator screenshot to Desktop (`simctl io screenshot`) and Light/Dark appearance toggle (`simctl ui appearance`)
- **Simulator Logs** — Dedicated window streaming a booted simulator's unified log (`simctl spawn … log stream`), filtered by process / subsystem / level, with search, errors-only, and auto-scroll
- **Physical Devices** — Paired iPhones/iPads via `devicectl`: copy the UDID, install `.app` / `.ipa` (drag & drop), launch by bundle ID, open a custom-scheme or universal link in the app, and export screenshots or crash logs to the Desktop
- **Signing & Profiles** — Provisioning profiles (type, bundle ID, team, devices, entitlements, expiry) cross-checked against the signing certificates in your keychain; trash expired profiles in one click
- **Push Notification Tester** — Send simple, rich, silent or custom JSON payloads to a booted simulator, or to a real device through APNs (token-based `.p8` auth, sandbox / production, readable error reasons); save named payloads and resend the last one
- **Deep Link Launcher** — Test custom URL schemes and universal links with recent-URL history
- **Universal Link Validator** — Fetches a domain's `apple-app-site-association` from your server and Apple's CDN, checks status / content type / size / redirects / JSON / app IDs, and tells you which app (if any) a given URL opens and by which rule
- **Simulator Recorder** — Records the simulator screen to MP4/HEVC on the Desktop with a live timer; turn any recording into a looping GIF; toggle Simulator touch indicators
- **Design Overlay** — Lays a design export semi-transparently over the Simulator window (click-through), with a layout grid, snap-to-Simulator and 1 pt nudging
- **App Store Connect** — Recent builds and their processing state through the App Store Connect API, with a notification when a build is ready in TestFlight
- **Apple Developer Status** — APNs, App Store Connect, TestFlight, notary service… current incidents from Apple's system status feed
- **Network Lab** — A local proxy that logs HTTP requests, status, timing and byte counts; HTTPS tunnels show host and byte counts, without decrypting content. Point a client at the proxy or route the Mac and Simulators through it. The mock API server has editable method, path patterns, status, delay, headers and body, with a request log
- **Network Link Conditioner** — Throttle the Mac's default route (and therefore the iOS Simulator) via `dnctl` + `pfctl` (dummynet). Presets: Off / Edge / 3G / DSL / LTE / 5% Loss / 100% Loss, each tile shows target bandwidth + delay. First use writes `/etc/sudoers.d/swordfish-throttle` so later toggles run silently.
- **Color Picker** — System eyedropper (`NSColorSampler`), editable HEX field, copyable RGB and HSL values, recent-color history, and one-click copy rows for SwiftUI, UIKit and CSS snippets

### JSON
- **JSON Viewer** — Dedicated window: raw editor on the left, a native tree (`List` + `OutlineGroup` = `NSOutlineView` under the hood) on the right. Paste, Format, Minify, Sort Keys, with parse-error line/column reporting.
- **JSON to Struct** — Generates Swift Codable structs from a JSON sample with toggles for `Codable` conformance and snake_case → camelCase mapping (auto-generated `CodingKeys`).

### Dev Utilities (window)
- JWT decoder (header, payload and `exp` / `iat` readout; **does not verify signatures**), Unix seconds/milliseconds/microseconds ↔ ISO 8601 timestamps, Base64 / base64url, URL encode / decode + component breakdown, cURL → `URLRequest` code (and request → cURL), UUID v4 generator, Plist ↔ JSON, MD5 / SHA hashes — all local
- **SF Symbols** browser (search, rendering modes, copy name / SwiftUI / UIKit), **App Icon** generator (one 1024 px image → `AppIcon.appiconset` for iOS / macOS / watchOS), **Localization Check** (per-language coverage and missing keys of every `.xcstrings` in a project, CSV export)
- **Color Picker** also shows WCAG contrast against white, black or any color, with AA / AAA results

### System (popover)
- **Displays** — DDC/CI brightness slider for external monitors (`IOAVService`) plus built-in brightness (`DisplayServices.framework`)
- **Anti-Sleep** — Caffeine-style sleep prevention with an in-place duration picker (∞ / 15m / 1h / 2h / 5h), live countdown, and absolute end time
- **Lid-Closed Mode** — Keeps the Mac awake even with the lid closed (`pmset -a disablesleep`). One-time admin prompt writes a sudoers entry scoped to exactly the two pmset commands; sleep is restored automatically when Swordfish quits.
- **Quick Toggles** — Dark Mode, show hidden files in Finder, mute/unmute the default microphone when supported, and choose default audio output / input devices (CoreAudio)
- **Hardware monitor** — CPU temperature (Apple Silicon IOHID sensors), fan RPM (SMC), 12-sample sparklines, threshold-colored bars, plus a thermal-pressure badge when macOS starts throttling
- **CPU / GPU load** — Overall and per-core CPU utilisation (`host_processor_info`) and GPU utilisation (IOAccelerator performance statistics)
- **Memory & Storage** — Live stats via `host_statistics64` + `URL.resourceValues`, with app/wired/cache/free memory breakdown and used/free volume capacity
- **Network** — Live download / upload rate with sparklines, active interface, local IP and VPN indicator
- **Battery** — Charge, time remaining, health (full-charge vs. design capacity), cycle count, temperature and adapter wattage; connected AirPods / Magic accessories' battery levels
- **Processes** — Top processes by CPU or memory with quit / force quit for your own processes, a dev-tools memory summary, listening TCP ports for your user (open in browser, copy, quit the owner), and one-click restarts for SourceKit, CoreSimulator and the Xcode build service

### Clipboard
- **History** — Text, links, code, images and files; searchable, pinnable, filterable (All/Text/Links/Code/Media), shows the source app; optional persistence across launches and a configurable 20–500 unpinned item limit
- **Privacy** — Copies marked private by password managers (`org.nspasteboard.ConcealedType` / `TransientType`) are never recorded; per-app exclusion list (1Password, Bitwarden, Keychain Access… by default); tokens and API keys (JWT, `sk-…`, `ghp_…`, `AKIA…`, PEM keys) are masked, kept in memory only, and deleted after 2 minutes
- **Smart actions** — JSON → JSON Viewer, JWT → decoder, Unix timestamp → date, Base64 → decoded text, deep link → open in booted Simulator, HEX → color swatch + SwiftUI / UIColor; plus transforms (trim, case, camelCase / snake_case, sort / dedupe lines, JSON escape / unescape)
- **Quick paste panel** — Global hotkey (⌃⌘V by default, configurable) opens a Spotlight-style history panel over any app: search, ↑↓, ↩ to paste (with Accessibility permission), ⌘1–9 quick pick. Without Accessibility permission, ↩ copies the item so you can paste manually
- **Quick Actions** — Interactive screenshot to the clipboard, Lock Screen (⌃⌘Q via System Events), Flush DNS (admin prompt), and open Terminal

### App-level
- **Settings window** (gear menu → Settings…, ⌘,) —
  - **General**: in-app language picker (System Default / English / Türkçe, with one-click relaunch), Launch at Login (`SMAppService`), version info
  - **Monitoring**: optional live value next to the menu bar icon (CPU temperature / load, memory, network speed) and notifications for CPU temperature, low disk space, critical memory pressure and thermal throttling (30-minute cooldown per alert)
  - **Clipboard**: keep history after quitting, set the unpinned history limit, choose the Quick Paste shortcut, request Accessibility access, and manage apps excluded from capture
  - **Developer Keys**: APNs and App Store Connect API keys (IDs in preferences, `.p8` private keys in the Keychain)
  - **Permissions**: status and setup for Screen Recording, Automation (System Events), the two sudoers helpers (Lid-Closed Mode, Network Link Conditioner), and Xcode Developer Tools (`simctl`), with Request / Open System Settings shortcuts and a copyable `xcode-select` fix when developer tools are missing. Clipboard Accessibility is managed in the Clipboard settings; notification authorization is shown in Monitoring
- **Launch at Login** — Also toggleable directly from the gear menu
- **Localization** — English, Turkish, Spanish, French, Serbian (Cyrillic & Latin), and Japanese via a String Catalog (`Localizable.xcstrings`); follows the system language or the in-app override

## Installation

1. Download the latest `Swordfish.dmg` from [Releases](https://github.com/akkanferhan/Swordfish/releases)
2. Open the DMG and drag `Swordfish.app` to your `Applications` folder
3. First launch: right-click `Swordfish.app` → **Open** (Gatekeeper bypass for new downloads)
4. Grant permissions as features request them (see below)

## Permissions

Swordfish asks for these on first use. Everything is optional — features that require a missing permission will surface an inline error rather than fail silently.

| Permission | Used by |
|---|---|
| Automation → System Events / Xcode | Lock Screen (⌃⌘Q shortcut synthesis) and Clean Build in the active Xcode workspace |
| Accessibility | Direct paste from the Quick Paste panel; without it, selecting an item copies it for manual paste |
| Notifications | Build and TestFlight completion notices, plus enabled monitoring alerts |
| Admin privileges (one-time auth prompt) | Flush DNS (`dscacheutil` + `killall -HUP mDNSResponder`) |
| Admin privileges (one-time, writes a sudoers entry) | Network Link Conditioner — grants `NOPASSWD` for `/usr/sbin/dnctl` and `/sbin/pfctl` so later toggles don't prompt. Removed when the helper is uninstalled from the ••• menu. |
| Admin privileges (one-time, writes a sudoers entry) | Lid-Closed Mode — grants `NOPASSWD` for exactly `pmset -a disablesleep 1/0`. Removed via right-click → "Remove helper & restore sleep". |
| Screen Recording | Color Picker eyedropper, Quick Screenshot |

## Requirements

- **macOS 13.0** (Ventura) or later
- **Apple Silicon** for the full feature set — CPU temperature reading uses the Apple Silicon IOHID sensor surface
- **Intel Macs**: SMC-based temperatures, fan speeds, and all non-hardware features still work; the IOHID temperature path returns nil and the UI falls back accordingly

Xcode command-line tools (`xcrun simctl`) are required for Simulator features, and `xcrun devicectl` is used for paired physical devices. The Xcode Releases panel can install Xcode with the optional [`xcodes` CLI](https://github.com/XcodesOrg/xcodes); release and status feeds, App Store Connect, APNs and Universal Link checks require network access.

## Building from Source

Requirements:
- Xcode 15 or later
- Swift 5.9
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.35 or later: `brew install xcodegen`

```bash
git clone https://github.com/akkanferhan/Swordfish.git
cd Swordfish/Swordfish
xcodegen generate
open Swordfish.xcodeproj
```

Run via `⌘R` in Xcode.

Set `SWORDFISH_MOCK_SENSORS=1` in the scheme environment to use simulated CPU/fan values (useful when working on the hardware tiles without touching real sensors).

## Architecture

```
App/
  SwordfishApp.swift        — @main, NSApplicationDelegateAdaptor
  AppDelegate.swift         — NSStatusItem + NSPopover owner, PopoverController
  AppEnvironment.swift      — dependency wiring

Services/                   — state and operations for each feature domain
  SystemMonitor.swift       — hardware, memory, disk and network polling
  SystemSamplers.swift      — CPU, GPU, battery and network samples
  HardwareSensors.swift     — IOHIDEventSystemClient + SMC wrappers
  DisplayController.swift   — display enumeration and brightness control
  CaffeineService.swift     — IOPMAssertion-based anti-sleep
  LidSleepService.swift     — lid-closed mode and its helper
  QuickTogglesService.swift — appearance, Finder and CoreAudio controls
  ProcessMonitor.swift      — processes, listening ports and dev daemon restarts
  ClipboardService.swift    — pasteboard history and persistence
  ClipboardSupport.swift    — privacy detection and content classification
  SimulatorService.swift    — xcrun simctl wrapper
  SimulatorToolbox.swift    — simulator status, privacy, media, apps and device actions
  SimulatorDefaults.swift   — simulator app UserDefaults access
  SimulatorLogService.swift — unified log streaming
  PhysicalDeviceService.swift — xcrun devicectl wrapper
  DevCleanupService.swift   — developer disk cleanup
  BuildMonitor.swift        — build history and completion notifications
  XcodeVersionsService.swift — installed Xcode discovery and switching
  NetworkThrottleService.swift — dnctl + pfctl dummynet, sudoers helper
  NetworkLab.swift          — traffic proxy and mock server
  AppleAPIKeys.swift        — Keychain storage and APNs token creation
  AppStoreConnect.swift     — App Store Connect build status
  SigningService.swift      — profiles and certificates
  CrashSymbolicator.swift   — crash report and dSYM matching
  UniversalLinkValidator.swift — AASA inspection and URL matching
  DevUtilities.swift       — local encoders, decoders and generators
  DevUtilitiesExtras.swift — cURL, app icon and localization helpers
  AlertService.swift        — monitoring alerts
  LoginItemManager.swift    — SMAppService
  JSONToSwift.swift         — recursive Swift struct generator
  DevToolsState.swift       — shared state across Dev Kit tools

Views/
  Popover/                  — status-item popover shell
  SystemHub/                — displays, sleep, audio, hardware and processes
  DevKit/                   — Xcode, Simulator, devices, network and tooling
  Productivity/             — clipboard history + quick actions
  QuickPaste/               — global search and paste panel
  JSONViewer/               — standalone JSON Viewer window
  JSONToSwift/              — standalone Struct Generator window
  DevUtilities/             — conversion and asset tools window
  SimulatorLogs/            — live log window
  Signing/                  — profiles and certificates window
  Settings/                 — preferences and permission guidance
  Shared/                   — ExpandableSection, LaunchSection, Sparkline, Badge

DesignSystem/               — Theme, Typography, Spacing, Motion, Radius

Utilities/                  — ProcessRunner, AppVersion (Bundle helpers)
```

`AppEnvironment` wires shared services into the popover and standalone windows. Feature-specific views own local presentation state and call their corresponding services or system tools.

## Private APIs

Swordfish uses a handful of private / undocumented Apple APIs because there is no public alternative:

- **`DisplayServices.framework`** — built-in display brightness control (`DisplayServicesSetBrightness` / `DisplayServicesGetBrightness`). Loaded via `dlopen`.
- **`IOAVService`** (+ `IOAVServiceWriteI2C`) — DDC/CI VCP writes to external monitors.
- **`IOHIDEventSystemClient`** — Apple Silicon PMU temperature sensors (matched via `0xFF00` usage page).

These are declared with `@_silgen_name` and called directly. Using them **precludes Mac App Store distribution** — which is a conscious tradeoff. The app targets developers who install tools from GitHub, and the public alternatives would gut the app's value.

Inspired patterns: [MonitorControl](https://github.com/MonitorControl/MonitorControl) for DDC, [Stats](https://github.com/exelban/stats) for IOHID sensor enumeration.

## Development Workflow

Swordfish follows a `master` / `develop` / `feature/*` branching model:

- `master` holds only released builds (tagged `v*`)
- `develop` is the integration branch — every feature lands here via a merge commit (`--no-ff`)
- Feature work branches off `develop` as `feature/<slug>` and merges back via PR

Browse `git log --graph develop` to see how each feature was built and integrated.

## License

[MIT](LICENSE) — do whatever you want, no warranty.
