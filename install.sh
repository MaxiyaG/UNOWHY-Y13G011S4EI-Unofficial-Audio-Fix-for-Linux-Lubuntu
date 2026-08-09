#!/bin/bash
#
# install.sh — installs the UNOWHY Y13G011S4EI audio fix.
# Run with: sudo ./install.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== UNOWHY Y13G011S4EI audio fix — install =="

if ! lspci -nnk 2>/dev/null | grep -A3 -i audio | grep -q "sof-audio-pci-intel-apl"; then
    echo "Warning: 'sof-audio-pci-intel-apl' driver not detected on this machine."
    echo "This fix targets that specific driver/codec combo (see README)."
    read -rp "Continue anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

echo "-> Kernel quirk (jack-detect fix)"
cp "$SCRIPT_DIR/scripts/es8336-quirk.conf" /etc/modprobe.d/es8336-quirk.conf

echo "-> Scripts (/usr/local/bin)"
install -m 755 "$SCRIPT_DIR/scripts/audio-watchdog.sh"     /usr/local/bin/audio-watchdog.sh
install -m 755 "$SCRIPT_DIR/scripts/pipewire-watchdog.sh"  /usr/local/bin/pipewire-watchdog.sh
install -m 755 "$SCRIPT_DIR/scripts/audio-fix-all.sh"      /usr/local/bin/audio-fix-all.sh

echo "-> systemd services"
cp "$SCRIPT_DIR/scripts/audio-watchdog.service"       /etc/systemd/system/
cp "$SCRIPT_DIR/scripts/audio-no-runtime-pm.service"  /etc/systemd/system/
cp "$SCRIPT_DIR/scripts/pipewire-watchdog.service"    /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now audio-watchdog.service
systemctl enable --now audio-no-runtime-pm.service
systemctl enable --now pipewire-watchdog.service

cat <<'EOF'

Done.

A reboot is required for the kernel quirk (quirk=64) to take effect:
  sudo reboot

After reboot, verify with:
  cat /sys/module/snd_soc_sof_es8336/parameters/quirk   # -> 64
  systemctl status audio-watchdog.service                # -> active (running)
  speaker-test -c2 -Dhw:0,0 -t wav
EOF
