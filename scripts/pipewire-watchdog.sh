#!/bin/bash
#
# pipewire-watchdog.sh
#
# Watches the "ERR" counter reported by `pw-top` for the ES8336 output
# node. This counter is CUMULATIVE (it never resets on its own), so this
# script only reacts when it INCREASES compared to the previous check,
# which means a genuinely new stream error just occurred. This avoids
# false positives from a stale non-zero value that no longer reflects a
# real problem.
#
# On a new error, PipeWire/PipeWire-Pulse/WirePlumber are restarted for
# whichever user is currently logged into a graphical session. The user is
# detected dynamically at every run (via `who`), so this script works
# unmodified regardless of which account is logged in.
#
# This covers cases where the ALSA mixer itself looks perfectly correct
# (audio-watchdog.sh finds nothing to fix) but the PipeWire pipeline has
# stalled anyway - for example after some suspend/resume cycles.
#
# It does NOT cover per-browser-tab audio bugs (see README, "Known
# unresolved issues").

INTERVAL=5
COOLDOWN=15
last_restart=0
prev_err=0
NODE_GREP="alsa_output.pci-0000_00_0e.0-platform-sof-essx8336.stereo-fallback"

while true; do
    sleep "$INTERVAL"

    TARGET_USER=$(who | awk '{print $1}' | sort -u | head -n1)
    [ -z "$TARGET_USER" ] && continue
    TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null)
    [ -z "$TARGET_UID" ] && continue

    line=$(runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" timeout 3 pw-top -b -n 2 2>/dev/null | grep "$NODE_GREP" | tail -1)
    err=$(echo "$line" | awk '{print $9}')

    if [[ "$err" =~ ^[0-9]+$ ]]; then
        if [ "$err" -gt "$prev_err" ]; then
            now=$(date +%s)
            if [ $((now - last_restart)) -ge "$COOLDOWN" ]; then
                logger -t pipewire-watchdog "New stream error detected (ERR $prev_err -> $err), restarting PipeWire for user $TARGET_USER"
                runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user restart pipewire pipewire-pulse wireplumber
                last_restart=$now
            fi
        fi
        prev_err=$err
    fi
done
