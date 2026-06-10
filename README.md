# ResourceBar

ResourceBar is a small native macOS menu bar app that shows CPU usage, CPU temperature, memory pressure, battery estimate, network throughput, and SSD throughput in one compact fixed-width menu bar item. Fan speed and extra sensor detail are available in the click menu.

This repository also includes DisplayBar, a native menu bar display-control app for brightness, RGB/YCbCr-style output modes, bit depth, HiDPI/scaled modes, and XDR/EDR brightness boosting on built-in HDR-capable displays.

## Build

```sh
swift build
```

## Run for development

```sh
swift run ResourceBar
```

The app is menu-bar-only, so it does not show a Dock icon or main window. Use the ResourceBar menu item to see detailed readings or quit it.

## Package as a macOS app and installer

```sh
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh
open Build/ResourceBar.app
```

The package script creates:

- `Build/ResourceBar.app`: local app bundle.
- `Build/ResourceBar.zip`: single-file drag-install copy of the app.
- `Build/ResourceBar.pkg`: installer package that installs `ResourceBar.app` into `/Applications`.

Because the app is not notarized with an Apple Developer ID, another Mac may require right-clicking the app or installer and choosing `Open` the first time.

## DisplayBar

Build and run during development:

```sh
swift run DisplayBar
```

Package as a menu-bar-only macOS app:

```sh
chmod +x Scripts/package-displaybar.sh
./Scripts/package-displaybar.sh
open Build/DisplayBar.app
```

DisplayBar shows a single menu bar display icon. Its per-display menus include:

- Hardware brightness through IOKit, DisplayServices/CoreDisplay fallback paths, and DDC/CI VCP code `0x10` for external monitors that expose it.
- `Color Mode / Bit Depth` selection from CoreGraphics display modes, including duplicate low-resolution modes so HiDPI/scaled modes are visible.
- Color output labels parsed from the display mode pixel encoding, including RGB/YCbCr-style model, chroma sampling when exposed, and bit depth when exposed.
- Built-in display brightness-range boosting on EDR-capable screens. The menu still shows a 0-100% brightness slider, but when boost is enabled 100% maps to a brighter CoreDisplay/EDR linear brightness target.

Notes:

- DDC/CI brightness support depends on the monitor, cable path, GPU driver, and macOS exposing an I2C bus for that display.
- RGB vs YCbCr and bit-depth switching depends on macOS exposing those variants as selectable display modes for the monitor.
- The brightness boost uses private CoreDisplay symbols when available. macOS may change those symbols, so DisplayBar keeps this path best-effort and falls back to public EDR/CoreGraphics behavior.
- The HDR boost is intentionally disabled during app termination so the internal display is not left in an overdriven state.

## Display

The strip uses a fixed width for the selected display mode, so values update without moving neighboring menu bar icons:

Full:

```text
CPU  12%   MP  43%   D 0.0MB/s   R 1.4MB/s
     48C   BAT 5:00  U 0.0MB/s   W 16.6MB/s
```

Reduced:

```text
CPU  12%   MP  43%
     48C   BAT 5:00
```

Tiny:

```text
CPU  12%
MP   43%
```

`MP` is memory pressure derived from macOS's memorystatus free-level signal, not raw RAM-used percentage. `D` and `U` are download and upload. `R` and `W` are SSD read and write. The unlabeled temperature under the CPU usage is the CPU or processor-cluster temperature. Throughput values are fixed to MB/s in stable slots so neighboring values do not move around.

CPU temperature text uses Mac-oriented thresholds: normal below 80C, orange from 80C, and red from 95C.

Click the menu bar item to see detailed readings, choose a display mode, and choose a refresh speed:

- `Efficient`: live metrics every 5 seconds; slower sensors every 20 seconds.
- `Balanced`: live metrics every 2 seconds; slower sensors every 10 seconds.
- `Fast`: live metrics every 1 second; slower sensors every 5 seconds.

## Notes

- CPU, network, and SSD counters use the selected live refresh speed.
- Memory pressure, battery, temperature, and fan RPM use the selected slower refresh speed.
- Timer tolerance is enabled so macOS can coalesce wakeups.
- Metrics use native Mach, BSD, and IOKit calls. The app does not shell out to `powermetrics`, `pmset`, `memory_pressure`, or `ioreg` during normal operation.
- The menu bar temperature is read from SMC processor sensors when available. The click menu also shows battery temperature, battery virtual temperature, and system thermal state.
- The click menu shows signed battery power: watts into the battery while charging or watts out of the battery when the Mac is supplementing a weak adapter.
- The click menu also shows adapter capacity from power telemetry, plus the connected adapter's negotiated maximum wattage. This is an available input/limit reading, not a wall-meter measurement of the Mac's current consumption.
- When the Mac is plugged in but net battery power is flowing out, the menu bar battery slot shows `OUT` instead of `CHG`.
- Fan RPM is read through AppleSMC when available and shown only in the click menu.
