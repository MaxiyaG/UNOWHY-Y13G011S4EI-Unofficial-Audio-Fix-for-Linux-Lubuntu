#!/bin/bash
#
# uninstall.sh — removes the UNOWHY Y13G011S4EI audio fix entirely and
# restores the stock configuration.
# Run with: sudo ./uninstall.sh

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo ./uninstall.sh"
    exit 1
fi

echo "== UNOWHY Y13G011S4EI audio fix — uninstall =="

for svc in audio-watchdog.service audio-no-runtime-pm.service pipewire-watchdog.service; do
    systemctl disable --now "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/$svc"
done
systemctl daemon-reload

rm -f /usr/local/bin/audio-watchdog.sh
rm -f /usr/local/bin/pipewire-watchdog.sh
rm -f /usr/local/bin/audio-fix-all.sh

rm -f /etc/modprobe.d/es8336-quirk.conf

cat <<'EOF'

Done. Everything has been removed.

A reboot is required to fully restore the stock kernel audio behavior:
  sudo reboot
EOF
