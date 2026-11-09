# BenchLog

A native Mac app for a one-person electronics repair bench: customers, their devices, and every repair from check-in to pickup, with parts, repair guides, photos, notes, and invoices in Québec French.

**Download:** [BenchLog.dmg](https://github.com/matguitarist/BenchLog/releases/latest/download/BenchLog.dmg) (macOS 26 or later)

## Build

```zsh
./build.sh --open                                                        # builds, installs ~/Applications/BenchLog.app, opens it
swift test --scratch-path ~/Library/Developer/BenchLog/test-build        # unit tests
tools/selftest.sh                                                        # the app's self-test on a /tmp library
```

A Swift package, no Xcode project. The plan is in `docs/BRIEF.md` and `docs/STORIES.md`.

## License

MIT
