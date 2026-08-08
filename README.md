# TrackPinch

TrackPinch is a focused macOS menu bar utility for resizing the active window
with a modifier key and a two-finger trackpad gesture.

Hold the configured modifier chord (Control + Option + Command by default),
then move two fingers horizontally, vertically, or diagonally to change the
window width, height, or both.

## Alpha status

`v0.1.0-alpha.2` is an experimental preview intended to validate the core
gesture, Accessibility behavior, and scroll suppression on real Macs. It is
not the finished `v0.1.0` release.

The first DMG is ad hoc signed and not notarized because a Developer ID
certificate is not yet available. Gatekeeper may block it. Do not disable
Gatekeeper globally; if you choose to test the preview, use the per-app
**Open Anyway** control in **System Settings → Privacy & Security** after the
first blocked launch.

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac
- Accessibility permission

## Install the alpha

1. Download the DMG and matching `.sha256` file from the GitHub prerelease.
2. Optionally verify it with `shasum -a 256 -c TrackPinch-0.1.0-alpha.2.dmg.sha256`.
3. Open the DMG and drag `TrackPinch.app` to Applications.
4. Launch TrackPinch and follow the permission setup shown in the menu bar app.

Because this alpha is not notarized, macOS may require the per-app **Open
Anyway** step described above.

## Privacy

TrackPinch runs locally. It has no account, analytics, ads, update service, or
network communication. The event tap observes modifier and precision-scroll
events needed for the gesture; typed key contents are not recorded.

Accessibility permission is used to read and update the active window's size
and to recognize and suppress the configured gesture while TrackPinch owns it.

## Build from source

```bash
swift test
./script/build_and_run.sh --build-only
```

Create an explicitly unnotarized experimental DMG:

```bash
./script/build_release.sh --version 0.1.0-alpha.2 --build-number 2 --allow-adhoc
```

A normal release build requires a Developer ID Application identity and a
`notarytool` keychain profile:

```bash
NOTARY_PROFILE=trackpinch-notary ./script/build_release.sh --version 0.1.0
```

## Known alpha limitations

- Signed-build manual QA across the supported OS/device/app matrix is incomplete.
- Launch at login is not implemented yet.
- There is no automatic update mechanism.
- Fullscreen, tiled, sheet, and panel windows are not guaranteed to resize.

See [docs/spec.md](docs/spec.md) for the product and technical contract.

## License

TrackPinch is available under the [MIT License](LICENSE).
