## What's new in 1.1

### Network Link Conditioner
Throttle the Mac's default network — and any running iOS Simulator — with one click. Presets:

| Preset      | Down          | Up            | Delay  | Loss |
|-------------|---------------|---------------|--------|------|
| Edge        | 240 Kbps      | 200 Kbps      | 400 ms | —    |
| 3G          | 3 Mbps        | 1 Mbps        | 100 ms | —    |
| DSL         | 2 Mbps        | 256 Kbps      | 5 ms   | —    |
| LTE         | 50 Mbps       | 10 Mbps       | 50 ms  | —    |
| 5% Loss     | —             | —             | —      | 5%   |
| 100% Loss   | —             | —             | —      | 100% |

Built on macOS's `dnctl` (dummynet) + `pfctl` — same kernel plumbing Apple's Network Link Conditioner uses. First use asks for your password once to install a locked-down sudoers entry (`/etc/sudoers.d/swordfish-throttle`); after that, preset toggles are silent. Removable from the gear menu.

### Fixes
- DMG no longer bundles `DistributionSummary.plist`, `ExportOptions.plist`, or `Packaging.log` alongside the app.

## Install
Download `Swordfish-1.1.dmg`, open, drag **Swordfish** into **Applications**. Signed with Developer ID + notarized.
