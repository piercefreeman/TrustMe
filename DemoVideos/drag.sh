#!/bin/sh
# TrustMe's window and a simulated System Settings, with the drag-to-allow animated.
# Esc quits, R replays, --once plays a single pass instead of looping.
cd "$(dirname "$0")" && swift build -q --product DragDemo && exec .build/debug/DragDemo "$@"
