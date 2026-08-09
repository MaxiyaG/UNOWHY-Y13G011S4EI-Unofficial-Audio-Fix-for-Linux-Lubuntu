#!/bin/bash
#
# audio-fix-all.sh
#
# Manual "big red button": forces the correct ALSA mixer state and
# restarts PipeWire for the currently logged-in user. Useful for cases
# not caught by the watchdogs, such as a single browser tab losing its
# audio stream while other tabs keep working fine.
#
# Intended to be run with root privileges (sudo/pkexec), optionally bound
# to a keyboard shortcut. See README, "Optional: manual shortcut".

amixer -c0 sset Speaker unmute >/dev/null 2>&1
amixer -c0 sset SPKL 80% >/dev/null 2>&1
amixer -c0 sset SPKR 80% >/dev/null 2>&1
amixer -c0 sset 'HPVol SPKVol' 'HPVOL: HPL+HPR, SPKVOL: SPKL+SPKR' >/dev/null 2>&1

TARGET_USER=$(who | awk '{print $1}' | sort -u | head -n1)
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null)
if [ -n "$TARGET_USER" ] && [ -n "$TARGET_UID" ]; then
    runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" systemctl --user restart pipewire pipewire-pulse wireplumber
fi

notify-send "Audio" "Fix applied" 2>/dev/null
logger -t audio-fix-all "Manual fix executed by $(whoami)"
