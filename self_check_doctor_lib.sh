#!/bin/bash
# Self-check de los chequeos de red de doctor_lib.sh (Sección 14 Caso C).
# No toca el sistema: arma árboles falsos en un tmpdir. Correr desde el repo:
#   ./self_check_doctor_lib.sh
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# doctor_lib.sh define colores y contadores y espera FIX_MODE; solo se necesitan
# las funciones, así que se sourcea con lo mínimo.
# shellcheck disable=SC2034  # lo consume doctor_lib.sh, no este script
FIX_MODE=false
# shellcheck source=doctor_lib.sh
source ./doctor_lib.sh >/dev/null 2>&1 || true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fallos=0

t() {  # t <descripcion> <esperado 0|1> <comando...>
  local desc="$1" esperado="$2"; shift 2
  "$@" >/dev/null 2>&1
  local rc=$?
  (( rc == esperado )) || { echo "   FALLA: $desc (esperado rc=$esperado, obtenido $rc)"; fallos=$((fallos+1)); }
}

echo "1. check_nic_driver_bound"
mkdir -p "$TMP/pci/0000:07:00.0" "$TMP/pci/0000:00:1f.3"
echo 0x020000 >"$TMP/pci/0000:07:00.0/class"     # Ethernet sin driver
echo 0x040300 >"$TMP/pci/0000:00:1f.3/class"     # audio sin driver, no cuenta
t "Ethernet sin driver tiene que fallar" 1 check_nic_driver_bound "$TMP/pci"
mkdir -p "$TMP/drivers/r8125"
ln -s "$TMP/drivers/r8125" "$TMP/pci/0000:07:00.0/driver"
t "Ethernet con driver tiene que pasar" 0 check_nic_driver_bound "$TMP/pci"
t "equipo sin NIC PCI no puede dar error" 0 check_nic_driver_bound "$TMP/vacio"

echo "2. check_dkms_current_kernel"
STATUS_OK='nvidia/580.173.02, 6.8.0-138-generic, x86_64: installed
realtek-r8125/9.016.01, 6.8.0-138-generic, x86_64: installed'
STATUS_VIEJO='nvidia/580.173.02, 6.8.0-138-generic, x86_64: installed
realtek-r8125/9.016.01, 6.8.0-137-generic, x86_64: installed'
t "todos los módulos al día" 0 check_dkms_current_kernel "$STATUS_OK" 6.8.0-138-generic
t "r8125 solo para el kernel anterior" 1 check_dkms_current_kernel "$STATUS_VIEJO" 6.8.0-138-generic
t "sin DKMS instalado no es un error" 0 check_dkms_current_kernel " " 6.8.0-138-generic

echo "3. check_no_r8169_blacklist"
mkdir -p "$TMP/modprobe"
echo 'options r8169 foo=1' >"$TMP/modprobe/limpio.conf"
t "sin blacklist tiene que pasar" 0 check_no_r8169_blacklist "$TMP/modprobe"
echo 'blacklist   r8169' >"$TMP/modprobe/r8125.conf"
t "blacklist de r8169 tiene que fallar" 1 check_no_r8169_blacklist "$TMP/modprobe"

echo
if (( fallos == 0 )); then
  echo "OK: todos los self-checks pasaron"
else
  echo "FALLARON $fallos self-checks"
  exit 1
fi
