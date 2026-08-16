# AGENTS.md

## Cursor Cloud specific instructions

TrackPinch is a **native macOS-only application** built with Swift Package Manager
(`Package.swift` declares `platforms: [.macOS(.v14)]`). It cannot be built, tested,
or run on the Linux Cursor Cloud VM.

Key constraints for future agents working in this Linux environment:

- Every target depends on macOS-only system frameworks. Even the `TrackPinchCore`
  "pure logic" library imports `AppKit` (`ModifierNormalizer.swift`,
  `TrackPinchSettingsStore.swift`) and `CoreGraphics` (`ScrollDeltaNormalizer.swift`,
  `ResizeGestureInterpreter.swift`, `PopoverSizePolicy.swift`). These frameworks are
  part of the macOS SDK and have no Linux equivalent, so a Linux Swift toolchain
  fails with `error: no such module 'AppKit'`.
- `swift build` and `swift test` both fail on Linux for the reason above. The
  executable app additionally uses the Accessibility (`AXUIElement`) API and a
  `CGEvent` tap, which require a real macOS host.
- The app itself needs macOS 14+, a physical trackpad, and granted Accessibility +
  Input Monitoring permissions to exercise the two-finger resize gesture. This is
  interactive and cannot be automated on a headless VM.

Where the standard commands live (run these on a macOS 14+ host with Xcode, not on
this VM):

- Lint / typecheck (strict concurrency) + build + test: see `.github/workflows/ci.yml`
  (`swift test`, then a `-strict-concurrency=complete -warnings-as-errors` build, then
  a release build). CI runs on `macos-15`.
- Build & run the app locally: `TRACKPINCH_LOCAL_DEVELOPMENT=1 ./script/build_and_run.sh`
  (documented in `README.md` and `.codex/environments/environment.toml`). The script
  requires Xcode (`xcodebuild`/`xcrun`) and codesigning identities.
- Package an experimental DMG: `./script/build_release.sh` (see `README.md`).

Bottom line: do not attempt to build/test/run TrackPinch on the Linux cloud VM.
Reserve verification for a macOS host or the `macos-15` GitHub Actions CI.
