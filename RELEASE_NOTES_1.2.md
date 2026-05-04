## What's new in 1.2

A round of fixes to features that didn't actually work on macOS Tahoe (and weren't great UX before).

### Fixes

- **Displays — external monitor brightness**: The DDC/CI slider did nothing on Apple Silicon Macs because the EDID-based service matching never resolved on macOS Tahoe. Rewrote it to mirror the m1ddc algorithm (path-based via `IODisplayLocation`), and DDC writes now warm up + send each packet twice — monitors silently dropped the first packet otherwise.
- **Anti-Sleep**: Toggle was on but the Mac still drifted to sleep, because the `IOPMAssertion` only prevented system idle sleep — display kept timing out. Switched to `PreventUserIdleDisplaySleep` (Caffeine parity).
- **iOS Simulator — boot doesn't show**: Pressing play started the simulator in the background but never opened a window. Boot now launches `Simulator.app` first, then issues `simctl boot`. Shutdown also surfaces real errors instead of swallowing them.
- **DevKit expand/collapse animation**: Sections were sliding in from the top edge (`.move(edge: .top)`), which drew over neighboring sections because the popover doesn't clip. Now plain fade — the VStack reflow handles the layout animation.

### UX

- Simulator state is now polled every 2.5 s while the section is open. Booting/shutdown transitions and changes made from Xcode or Simulator.app show up automatically.
- Play/stop buttons show a per-simulator spinner while the transition is in flight (with a 60 s safety timeout if the expected state never arrives).

### Internal

- Header/footer version label is now read from `Bundle.main` instead of being hardcoded — was stuck on `v1.0` through both the 1.0 and 1.1 releases.
- New `Utilities/AppVersion.swift` helper for `CFBundleShortVersionString` / `CFBundleVersion`.

## Install

Download `Swordfish-1.2.dmg`, open, drag **Swordfish** into **Applications**. Signed with Developer ID + notarized.
