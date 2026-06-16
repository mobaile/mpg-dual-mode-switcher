# MPG Dual Mode Switcher

A small native macOS utility for switching the MSI MPG 274U E16M / MPG 274URDFW E16M monitor between its two Dual Mode profiles.

- **UHD / 4K**: writes `002E0=000`
- **FHD / 1080P / 320Hz**: writes `002E0=001`
- Reads both `002E0` and `00190` to confirm the current state
- Uses the monitor's USB HID control interface directly

## Supported Device

This utility targets:

```text
USB HID: VID_1462 PID_3FA4 MI_00
Product: MSI Monitor MPG 274URDFW E16M
Report ID: 0x01
Report length: 64 bytes
```

The Dual Mode command is:

```text
Read:
0x01 + "58002E0\r"

Write UHD / 4K:
0x01 + "5b002E0000\r"

Write FHD / 1080P / 320Hz:
0x01 + "5b002E0001\r"
```

Writes do not return an ACK. The app waits and re-reads the monitor status after switching.

## Build

Requirements:

- macOS
- Xcode Command Line Tools
- Swift toolchain

Build the app:

```sh
./scripts/build.sh
```

The built app and zip archive are written to `dist/`.

## Notes

- The app is intentionally not sandboxed because it needs direct USB HID access.
- The app is ad-hoc signed by the build script for local use.
- This is a hardware-specific utility and is not expected to work with unrelated MSI monitor models.
