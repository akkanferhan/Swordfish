# What's new in Swordfish 1.4

Swordfish 1.4 expands the Dev Kit into a broader iOS release and debugging toolbox, adds more live system controls, and makes clipboard history easier to use across apps.

## Simulator and device workflows

- **Simulator Toolbox:** Play preset or custom location routes, import GPX waypoints, manage installed apps, launch them in another language or with pseudo-localization, inspect and edit app UserDefaults, open app data stores, and adjust accessibility, biometrics, keychain, pasteboard and proxy certificate settings.
- **Simulator Logs:** Stream and search a booted Simulator's unified log in a separate window, with process, subsystem, level and errors-only filters.
- **Physical Devices:** Use paired iPhones and iPads to install `.app` or `.ipa` builds, launch an app, open deep or universal links, and export screenshots and crash logs.
- **Push testing:** Send saved or preset payloads to Simulators or real devices through APNs using a `.p8` key. Choose sandbox or production and see readable APNs errors.
- **Visual checks:** Record Simulator video and export GIFs; place a transparent design overlay and optional grid over the Simulator window. The Universal Link Validator checks AASA responses from both the site and Apple's CDN.

## Build, distribution and network tools

- **Build Times and cleanup:** Review build durations by scheme with trends and completion notifications. Inspect and selectively remove DerivedData, runtimes, DeviceSupport, archives and caches.
- **Xcode Releases:** See recent Xcode releases, open release notes and downloads, install with the optional `xcodes` CLI, and download Simulator runtimes.
- **Signing and crashes:** Inspect provisioning profiles against installed signing certificates, remove expired profiles, and symbolicate `.ips` or `.crash` reports using matching dSYMs.
- **App Store Connect and Apple status:** Track recent build processing and TestFlight readiness, and check Apple developer service incidents.
- **Network Lab:** Inspect traffic through a local HTTP(S) proxy or run a configurable mock API server. HTTPS traffic is shown by host and byte count; content is not decrypted.
- **Developer Utilities:** Decode JWTs, convert timestamps, Base64, URLs, cURL and property lists, generate UUIDs and hashes, browse SF Symbols, create app icon sets, and check String Catalog translation coverage.

## System and clipboard

- **System:** View CPU and GPU load, memory, storage, network and battery details. Inspect processes and listening ports, restart stuck developer services, switch audio devices, mute the microphone, and toggle Dark Mode or Finder hidden files.
- **Monitoring:** Show a live metric next to the menu bar icon and configure notifications for high CPU temperature, low disk space, critical memory pressure and thermal throttling.
- **Clipboard:** Search and pin text, links, code, images and files; use content-aware actions and text transforms. Private copies are skipped, sensitive tokens stay in memory briefly, and individual apps can be excluded.
- **Quick Paste:** Open clipboard history with a configurable global shortcut. Accessibility access enables direct pasting into the previous app; otherwise selection copies the item for manual paste.

## Settings and installation

The Settings window now includes Monitoring, Clipboard and Developer Keys sections. APNs and App Store Connect `.p8` private keys are stored in the macOS Keychain.

Download `Swordfish-1.4.dmg` from the GitHub release assets, open it, and drag **Swordfish** into **Applications**. Requires macOS 13 or later; Xcode command-line tools are needed for Simulator and device features.
