#!/usr/bin/env bash
# ===========================================================================
#  Hermes Agent - macOS double-click launcher
#  Double-click di Finder (atau klik kanan -> Open) untuk jalankan di Terminal.
#  Semua konfigurasi ada di install-hermes-macos.sh (blok CFG_).
# ===========================================================================
cd "$(dirname "$0")" || exit 1
chmod +x ./install-hermes-macos.sh
./install-hermes-macos.sh
RC=$?
echo ""
if [ "$RC" -ne 0 ]; then
  echo "[x] Installer berhenti dengan kode $RC."
else
  echo "[OK] Selesai. Buka Terminal baru lalu jalankan: hermes"
fi
echo ""
printf "Tekan Enter untuk menutup..."
read -r _
exit "$RC"
