# BenchLog

A native macOS app in SwiftUI for a one-person electronics repair bench: customers,
their devices, and every repair from check-in to pickup, with parts, repair guides,
photos, notes, and invoices printed in Québec French. Mac first; an iPhone/iPad app
(and later Android, through a sync server) will share the same data model.

## Layout

- `Sources/BenchLog/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/BenchLogKit/` data and rules with no SwiftUI or AppKit: the SQLite library (GRDB), models, pricing, document wording. A future iOS app reuses it as is. Tests in `Tests/BenchLogKitTests/`.
- The library: `~/Library/Application Support/BenchLog/benchlog.sqlite` plus `Files/` for photos and attachments (the database stores paths relative to it). Schema changes are new migrations in `Migrations.swift`, never edits of old ones; keep `docs/SCHEMA.md` in step. A new table either syncs (add it to `Library.syncedTables` with `queueTriggers`) or is listed in `Library.localTables`; SyncTests fails until it is. Every row has a UUID id, `createdAt`, `updatedAt`, and a nullable `deletedAt`, for sync later.
- The app's log: `~/Library/Logs/BenchLog/BenchLog.log` (LogKit `LogStore`), shown on the Log page.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/BenchLog.app`.
- `tools/release.sh <version>` makes a Developer ID, notarized DMG, the Sparkle zip and a signed appcast, and publishes them as a GitHub release (`--local` builds without publishing, `--check` only checks). The script is the same in every app; what's specific to this one is in `release.conf`. Notes come from `release-notes/<version>.md`, or are drafted from the commits since the last tag. The version lives in `Info.plist.in`.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief (`BRIEF.md`), the stories (`STORIES.md`), and the glossary (`GLOSSARY.md`): use the glossary's names in every string.
- Money is integer cents. Printed documents (intake slip, estimate, invoice) are fr-CA first, with TPS and TVQ; the passcode never prints.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/BenchLog/test-build`.
- Self-test (the app's real functions on a /tmp store): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/BenchLog-shots/<page>-light.png` and `-dark.png` for every sidebar page, and `settings-<tab>-light.png` and `-dark.png` for every Settings tab, then quits. `APP_SNAPSHOT_PAGES=all,settings tools/snap.sh` limits the pages. `APP_SNAPSHOT_MIN=1` shoots the window at its smallest size.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- Snapshots, seed data, and the self-test refuse to run without `APP_STORE` in /tmp.
- Never test against the real library in `~/Library/Application Support/BenchLog/`.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/BenchLog-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Use Apple's controls and system styles. Only the accent color is custom: `UI/Theme.swift` (`ThemeStore.defaultID`). People change it, and light or dark mode, in Settings > Appearance.
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form per tab. Add a case to `SettingsTab` for a new tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
