#!/bin/bash
#
# audio-watchdog.sh
#
# Continuously monitors the ALSA mixer state of the sof-essx8336 (ES8336)
# codec and re-applies the correct speaker routing whenever it drifts.
# On the UNOWHY Y13G011S4EI (and likely similar boards), the codec resets
# 'Speaker' to muted and/or 'HPVol SPKVol' to the headphone routing after:
#   - system suspend/resume
#   - PCI runtime autosuspend of the audio controller
#   - repeated pause/play cycles in a browser tab
#
# This script does not diagnose WHY it drifts; it just keeps correcting it,
# which in practice covers all three triggers above.
#
# Tune INTERVAL below to trade CPU usage for reaction time. 0.3-0.5s gives
# near-instant recovery at a small, measured CPU cost (roughly 2-10% of one
# core on an Intel Celeron N4120, depending on the interval). 2s is much
# lighter on CPU/battery but leaves a longer silent gap after each drift.
#
# NOTE: assumes the ES8336 card is ALSA card index 0 on this hardware
# (verify with: cat /proc/asound/cards). Adjust "-c0" below if different.

INTERVAL=0.5

while true; do
    changed=0

    if amixer -c0 sget Speaker 2>/dev/null | grep -q '\[off\]'; then
        amixer -c0 sset Speaker unmute >/dev/null 2>&1
        changed=1
    fi

    if amixer -c0 sget SPKL 2>/dev/null | grep -q '\[0%\]'; then
        amixer -c0 sset SPKL 80% >/dev/null 2>&1
        changed=1
    fi

    if amixer -c0 sget SPKR 2>/dev/null | grep -q '\[0%\]'; then
        amixer -c0 sset SPKR 80% >/dev/null 2>&1
        changed=1
    fi

    # Only the active "Item0:" line matters here, not the "Items:" list of
    # all possible values (which always contains the target string).
    current_route=$(amixer -c0 sget 'HPVol SPKVol' 2>/dev/null | grep '^  Item0:')
    if ! echo "$current_route" | grep -q 'SPKVOL: SPKL+SPKR'; then
        amixer -c0 sset 'HPVol SPKVol' 'HPVOL: HPL+HPR, SPKVOL: SPKL+SPKR' >/dev/null 2>&1
        changed=1
    fi

    [ "$changed" -eq 1 ] && logger -t audio-watchdog "Mixer drift detected and corrected"

    sleep "$INTERVAL"
done
