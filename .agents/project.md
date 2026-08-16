# Project Context

FlClash is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Version Notes

- Release CI pins Flutter 3.44.4. Local SDK may diverge, so trust the CI
  version as the source of truth for release builds.
- Dart SDK constraint: `>=3.8.0 <4.0.0`.

## Forked Dependencies

Three `pubspec.yaml` dependencies are pinned to a fork by commit SHA. Each entry
records what the fork changes and what has to be true before it can go back to
the published package, so a future upgrade does not have to rediscover it.
Re-verify a fork by diffing its pub cache checkout against the published version
of the same number:

```bash
diff -ru ~/.pub-cache/hosted/pub.dev/<name>-<version> ~/.pub-cache/git/<name>-<sha>
```

`window_manager` — `chen08209/window_manager`, path `packages/window_manager`,
version 0.5.1.

- Changes `windows/window_manager_plugin.cpp` only. With `titleBarStyle: hidden`
  a maximized window uses the monitor work area (`GetMonitorInfo().rcWork`)
  instead of upstream's `adjustNCCALCSIZE` border fudge, so the maximized window
  no longer covers the taskbar.
- Drop the fork once upstream constrains a hidden-title-bar maximized window to
  the work area on Windows. Dart API is untouched, so nothing in `lib/` changes.

`launch_at_startup` — `chen08209/launch_at_startup`, version 0.5.1.

- Migrates `win32_registry` from `^2.0.0` to `^3.0.3`, which is a breaking rename
  across the whole Windows implementation (`Registry.openPath` → `CURRENT_USER.open`,
  `createValue` → `setValue`, `getStringValue` → `getString`).
- This one is not optional while it lasts: FlClash depends on `win32_registry: ^3.0.3`
  directly, and upstream's `^2.0.0` constraint cannot co-resolve with it.
- Drop the fork when upstream publishes a release that accepts `win32_registry` 3.x.

`yaml_writer` — `chen08209/yaml_writer`, version 2.1.0.

- Adds `StringNode.quoteKey()` and applies it to map keys in `lib/src/node.dart`.
  Upstream quotes values but emits keys verbatim, so a profile key needing quotes
  is written as invalid YAML.
- Drop the fork once upstream quotes map keys by the same
  `isValidUnquotedString` rule it already applies to values.

Two published dependencies are deliberately on a pre-release and should move to a
stable release when one exists: `freezed` (pinned exactly to `3.2.6-dev.1`) and
`file_picker` (`^12.0.0-beta.7`).

## Build Dependencies

Linux:

```bash
sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev
```

Windows:

- GCC and Inno Setup.
- `ANDROID_NDK` env var for Android builds.

macOS:

```bash
npm install -g appdmg
```
