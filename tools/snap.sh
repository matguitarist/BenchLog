#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Applications/BenchLog.app/Contents/MacOS/BenchLog
store=/tmp/BenchLog-test.sqlite
shots=/tmp/BenchLog-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.benchlog.savedState
# Seed data only fills an empty store, so start from nothing.
rm -rf $store $store-wal $store-shm ${store:r}.log ${store:r}-files
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
