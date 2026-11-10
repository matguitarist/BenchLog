#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
# SELFTEST_SERVER=http://127.0.0.1:18420 SELFTEST_TOKEN=… tools/selftest.sh syncs with that server
# (an empty one, such as a new Docker container) instead of starting server/ with Node.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.benchlog.savedState
store=/tmp/BenchLog-self.sqlite
rm -rf $store $store-wal $store-shm ${store:r}.log ${store:r}-files
APP_STORE=$store ~/Applications/BenchLog.app/Contents/MacOS/BenchLog --selftest
