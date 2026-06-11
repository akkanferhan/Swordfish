# What's new in 1.3

The biggest release yet: a Simulator Toolbox that covers the everyday `simctl` chores, a real Settings window with a permissions overview, and full localization into seven languages.

## New

- **Simulator Toolbox** (Dev Kit) — everyday helpers for a booted simulator in one section:
  - **Status Bar Override** — App Store screenshot mode (9:41, full battery & signal) with editable time, battery level/state, and network indicator (`simctl status_bar`)
  - **Permission Manager** — grant / revoke / reset privacy services (Location, Photos, Contacts, Microphone, …) per installed app (`simctl privacy`)
  - **Location Simulation** — city presets (Istanbul, London, New York, San Francisco, Tokyo) or custom lat/lon (`simctl location`)
  - **Add Media** — drag & drop images/videos (or a file picker) straight into the simulator's Photos library (`simctl addmedia`)
  - **App Containers** — list installed user apps, copy bundle IDs, open an app's data container in Finder
  - **Quick actions** — one-click simulator screenshot to Desktop and Light/Dark appearance toggle
- **Settings window** (gear menu → Settings…, ⌘,)
  - **General** — in-app language picker with one-click relaunch, Launch at Login, version info
  - **Permissions** — live status of everything features depend on: Screen Recording, Automation (System Events), both sudoers helpers (install/remove from here), and Xcode Developer Tools — including a one-click admin-prompted `xcode-select` fix when `simctl` is missing
- **Localization** — English, Turkish, Spanish, French, Serbian (Cyrillic & Latin), and Japanese via a String Catalog. Follows the system language, or pick one in Settings.

## Changes

- **Clear RAM removed for now** — it was backed by `purge`, which requires root on modern macOS and silently does nothing without it. A working `memory_pressure`-based implementation is in place behind the scenes; the button returns once the UX is settled.
- **Memory tile** now shows a Free indicator alongside App / Wired / Cache.

## Install

Download `Swordfish-1.3.dmg`, open, drag **Swordfish** into **Applications**. Signed with Developer ID + notarized.
