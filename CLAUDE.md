# BenchLog

A native macOS app in SwiftUI for a one-person electronics repair bench: customers,
their devices, and every repair from check-in to pickup, with parts, repair guides,
photos, notes, and invoices printed in Québec French. Mac first; an iPhone/iPad app
(and later Android, through a sync server) will share the same data model.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

## Layout

- `Sources/BenchLog/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/BenchLogKit/` data and rules with no SwiftUI or AppKit: the SQLite library (GRDB), models, pricing, document wording. A future iOS app reuses it as is. Tests in `Tests/BenchLogKitTests/`.
- The library: `~/Library/Application Support/BenchLog/benchlog.sqlite` plus `Files/` for photos and attachments (the database stores paths relative to it). Schema changes are new migrations in `Migrations.swift`, never edits of old ones; keep `docs/SCHEMA.md` in step. A new table either syncs (add it to `Library.syncedTables` with `queueTriggers`) or is listed in `Library.localTables`; SyncTests fails until it is. The sync server exists twice, `server/` (Node) and `Sources/BenchLogServerKit` (Swift, built into the app): an API change goes into both, and `ServerTests` runs against both. Every row has a UUID id, `createdAt`, `updatedAt`, and a nullable `deletedAt`, for sync later.
- The app's log: `~/Library/Logs/BenchLog/BenchLog.log` (LogKit `LogStore`), shown on the Log page.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/BenchLog.app`.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `Info.plist.in`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief (`BRIEF.md`), the stories (`STORIES.md`), and the glossary (`GLOSSARY.md`): use the glossary's names in every string.
- Money is integer cents. Printed documents (intake slip, estimate, invoice) are fr-CA first, with TPS and TVQ; the passcode never prints.

## Checks specific to this app

- `APP_SNAPSHOT_MIN=1 tools/snap.sh` shoots the window at its smallest size; `APP_SNAPSHOT_SIZE=1600x1000` a wide one (detail pages go to two columns from 880 pt).
- The real library is `~/Library/Application Support/BenchLog/`: never test against it.
