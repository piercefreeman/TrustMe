#!/bin/sh
# Full-screen storm of macOS permission popups over your current wallpaper.
# Esc quits, R replays. Extra arguments pass through (see README.md).
cd "$(dirname "$0")" && swift build -q --product PopupStorm && exec .build/debug/PopupStorm "$@"
