#!/usr/bin/env bash
# Self-check de nic_lib.sh y de las reglas de diagnostico de diag-nic.sh.
# No toca el sistema, no necesita root, no necesita hardware: arma arboles
# falsos en un tmpdir y llama a las funciones puras. Correr desde el repo:
#   ./self_check_nic_lib.sh
#
# Los escenarios A a I son los casos de terreno que estas reglas tienen que
# resolver bien; estan numerados igual que en la Seccion 12 del manual.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=nic_lib.sh
source ./nic_lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fallos=0

# eq <descripcion> <esperado> <obtenido>
eq() {
  if [[ "$2" != "$3" ]]; then
    echo "   FALLA: $1"
    echo "          esperado: $2"
    echo "          obtenido: $3"
    fallos=$((fallos + 1))
  fi
}

# rc <descripcion> <rc esperado> <comando...>
rc() {
  local desc="$1" esperado="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  (( got == esperado )) || { echo "   FALLA: $desc (esperado rc=$esperado, obtenido $got)"; fallos=$((fallos + 1)); }
}

# Primer campo de la salida de las reglas (severidad / nivel).
sev() { awk '{print $1}' <<<"$1"; }
cod() { awk '{print $2}' <<<"$1"; }

echo "1. nic_kernel_is_ga68"
rc "6.8.0-137-generic es GA"        0 nic_kernel_is_ga68 "6.8.0-137-generic"
rc "6.8.0-79-generic es GA"         0 nic_kernel_is_ga68 "6.8.0-79-generic"
rc "7.0.0-28-generic no es GA"      1 nic_kernel_is_ga68 "7.0.0-28-generic"
rc "6.11.0-9-generic no es GA 6.8"  1 nic_kernel_is_ga68 "6.11.0-9-generic"
# Trampa clasica de comparar por prefijo: 6.80 no es 6.8.
rc "6.80.0-1-generic no es GA 6.8"  1 nic_kernel_is_ga68 "6.80.0-1-generic"

echo "2. nic_xid_map / nic_xid_for_pci"
DMESG='r8169 0000:06:00.0 eth0: RTL8168h/8111h, 74:fe:ce:4e:b5:9a, XID 541, IRQ 158
r8169 0000:07:00.0 eth1: RTL8125B, 10:7c:61:45:e0:18, XID 641, IRQ 161
r8169 0000:0d:00.0 eth2: unknown chip XID 688'
MAP=$(nic_xid_map "$DMESG")
eq "XID del 8125B por direccion PCI" "641" "$(nic_xid_for_pci 0000:07:00.0 "$MAP")"
eq "XID del 8168h por direccion PCI" "541" "$(nic_xid_for_pci 0000:06:00.0 "$MAP")"
eq "XID 688 aunque la linea no traiga modelo" "688" "$(nic_xid_for_pci 0000:0d:00.0 "$MAP")"
rc "direccion PCI ausente no inventa XID" 1 nic_xid_for_pci 0000:99:00.0 "$MAP"
rc "dmesg rotado no inventa XID" 1 nic_xid_for_pci 0000:07:00.0 ""

echo "3. nic_rev_from_xid"
eq "688 es la rev D"       "RTL8125D"           "$(nic_rev_from_xid 688)"
eq "641 es A/B/C"          "RTL8125A/B/C"       "$(nic_rev_from_xid 641)"
eq "XID nuevo no catalogado" "no catalogada (XID 699)" "$(nic_rev_from_xid 699)"
eq "sin XID"               "desconocida"        "$(nic_rev_from_xid '')"

echo "4. nic_r8125_ko_ok  (el falso verde del r8125-dkms de noble)"
mkdir -p "$TMP/mods/6.8.0-137-generic/updates/dkms"
rc "sin .ko para el kernel objetivo" 1 nic_r8125_ko_ok 6.8.0-137-generic "$TMP/mods"
: >"$TMP/mods/6.8.0-137-generic/updates/dkms/r8125.ko"
# modinfo sobre un archivo vacio no devuelve version: no se puede afirmar que
# sirva, y eso tiene que ser distinto de "listo".
rc "un .ko sin version declarada no es 'listo'" 3 nic_r8125_ko_ok 6.8.0-137-generic "$TMP/mods"
# El chequeo de version en si se prueba aparte, sin depender de modinfo.
rc "9.011.00 (noble) es menor que el minimo" 1 dpkg --compare-versions 9.011.00 ge "$NIC_R8125_MIN_VER"
rc "9.014.01 alcanza el minimo"              0 dpkg --compare-versions 9.014.01 ge "$NIC_R8125_MIN_VER"
rc "9.016.01 alcanza el minimo"              0 dpkg --compare-versions 9.016.01 ge "$NIC_R8125_MIN_VER"
eq "el minimo sigue siendo el documentado"   "9.014.01" "$NIC_R8125_MIN_VER"

echo "5. nic_alias_has_r8125"
ALIASF="$TMP/mods/6.8.0-137-generic/modules.alias"
echo 'alias pci:v000010ECd00008125sv*sd*bc*sc*i* r8169' >"$ALIASF"
rc "solo el alias del r8169 no alcanza" 1 nic_alias_has_r8125 6.8.0-137-generic "$TMP/mods"
echo 'alias pci:v000010ECd00008125sv*sd*bc*sc*i* r8125' >>"$ALIASF"
rc "con r8125 indexado, listo"          0 nic_alias_has_r8125 6.8.0-137-generic "$TMP/mods"

echo "6. nic_r8169_blacklisted"
mkdir -p "$TMP/modprobe"
echo 'options r8125 aspm=0 eee_enable=0' >"$TMP/modprobe/omnifish.conf"
rc "sin blacklist"                 1 nic_r8169_blacklisted "$TMP/modprobe"
echo 'blacklist   r8169'           >"$TMP/modprobe/r8125.conf"
rc "con blacklist"                 0 nic_r8169_blacklisted "$TMP/modprobe"

echo "7. nic_bound_driver / nic_pci_id  (sysfs falso)"
mkdir -p "$TMP/net/enp7s0/device" "$TMP/drivers/r8169"
ln -s "$TMP/drivers/r8169" "$TMP/net/enp7s0/device/driver"
echo 0x10ec >"$TMP/net/enp7s0/device/vendor"
echo 0x8125 >"$TMP/net/enp7s0/device/device"
eq "driver bindeado por sysfs" "r8169" "$(nic_bound_driver enp7s0 "$TMP/net")"
eq "PCI id por sysfs"          "10ec:8125" "$(nic_pci_id enp7s0 "$TMP/net")"
mkdir -p "$TMP/net/enp9s0/device"
rc "device sin driver bindeado" 1 nic_bound_driver enp9s0 "$TMP/net"

echo
echo "--- Escenarios de terreno (regla del driver) ---"

echo "A. kernel 6.8 + RTL8125B (XID 641) + r8169 + red funcionando"
out=$(nic_assess_driver 6.8.0-137-generic 10ec:8125 641 r8169 1)
eq "A: no puede ser un hallazgo"      "OBS" "$(sev "$out")"
eq "A: r8169 es el driver correcto"   "r8169_correcto_abc" "$(cod "$out")"

echo "B. kernel 6.8 + RTL8125D (XID 688) + r8169"
out=$(nic_assess_driver 6.8.0-137-generic 10ec:8125 688 r8169 0)
eq "B: es un fallo real"              "FAIL" "$(sev "$out")"
eq "B: identificado como 8125D"       "r8169_con_8125d" "$(cod "$out")"
# El veredicto no puede depender de que la interfaz parezca viva o no.
eq "B: sigue siendo fallo con link_ok=1" "FAIL" "$(sev "$(nic_assess_driver 6.8.0-137-generic 10ec:8125 688 r8169 1)")"

echo "C. kernel 7.0 + RTL8125D + r8169 + red funcionando"
out=$(nic_assess_driver 7.0.0-28-generic 10ec:8125 688 r8169 1)
eq "C: normal, sin falso positivo"    "OBS" "$(sev "$out")"
eq "C: motivo = kernel no GA"         "r8169_kernel_no_ga" "$(cod "$out")"

echo "I. 10ec:8125 con XID indeterminable"
out=$(nic_assess_driver 6.8.0-137-generic 10ec:8125 '?' r8169 1)
eq "I: interfaz operativa -> observacion, no fallo" "OBS" "$(sev "$out")"
out=$(nic_assess_driver 6.8.0-137-generic 10ec:8125 '?' r8169 0)
eq "I: sin trafico -> sospecha, no confirmacion"    "SUSP" "$(sev "$out")"

echo "   extras de la regla del driver"
eq "device sin driver es fallo"       "FAIL" "$(sev "$(nic_assess_driver 6.8.0-137-generic 10ec:8125 688 '?' 0)")"
eq "r8125 bindeado es observacion"    "OBS"  "$(sev "$(nic_assess_driver 6.8.0-137-generic 10ec:8125 688 r8125 1)")"
eq "otro chip no entra al caso 8125"  "otro_chip" "$(cod "$(nic_assess_driver 6.8.0-137-generic 8086:125c '?' igc 1)")"
eq "XID no catalogado con link OK"    "OBS"  "$(sev "$(nic_assess_driver 6.8.0-137-generic 10ec:8125 699 r8169 1)")"

echo
echo "--- Escenarios de terreno (regla del zombie) ---"

echo "D. carrier=yes, RX congelado unos segundos, pero tcpdump recibe trafico"
out=$(nic_assess_zombie 1 rx_frozen capture_traffic)
eq "D: no se declara zombie"          "SOSPECHOSO" "$(sev "$out")"
# Ni acumulando senales: la captura con trafico es tope duro.
out=$(nic_assess_zombie 1 rx_frozen irq_frozen watchdog capture_traffic)
eq "D: el tope aguanta mas senales"   "SOSPECHOSO" "$(sev "$out")"

echo "E. carrier=yes, RX congelado, 0 paquetes, IRQ congeladas, NETDEV WATCHDOG"
out=$(nic_assess_zombie 1 rx_frozen no_capture irq_frozen watchdog)
eq "E: evidencia muy fuerte"          "MUY_FUERTE" "$(sev "$out")"
eq "E: score esperado"                "6" "$(awk '{print $2}' <<<"$out")"

echo "F. sin carrier"
out=$(nic_assess_zombie 0 rx_frozen rx_zero no_capture irq_frozen watchdog)
eq "F: prioriza el link fisico"       "SIN_LINK" "$(sev "$out")"

echo "G. DHCP Discover sin Offer, pero la NIC recibe otros paquetes"
out=$(nic_assess_zombie 1 capture_traffic tx_active)
eq "G: driver/hardware vivo"          "SOSPECHOSO" "$(sev "$out")"
out=$(nic_assess_zombie 1 capture_traffic)
eq "G: sin otras senales, normal"     "NORMAL" "$(sev "$out")"

echo "   rx_active: el contador RX tambien prueba recepcion"
# Reproduce el falso positivo encontrado en el smoke test: RX incrementando pero
# tcpdump sin poder correr no puede sumar hacia "chip colgado".
out=$(nic_assess_zombie 1 rx_active)
eq "RX subiendo es normal"            "NORMAL" "$(sev "$out")"
out=$(nic_assess_zombie 1 rx_active no_capture irq_frozen watchdog)
eq "RX subiendo topea igual que la captura" "SOSPECHOSO" "$(sev "$out")"

echo "   extras de la regla del zombie"
eq "solo RX congelado no confirma nada" "SOSPECHOSO" "$(sev "$(nic_assess_zombie 1 rx_frozen)")"
eq "RX en 0 desde el boot, sin captura aun" "SOSPECHOSO" "$(sev "$(nic_assess_zombie 1 rx_frozen rx_zero)")"
eq "sin senales es normal"            "NORMAL" "$(sev "$(nic_assess_zombie 1)")"
eq "tres senales sin captura = probable" "PROBABLE" "$(sev "$(nic_assess_zombie 1 rx_frozen rx_zero irq_frozen)")"

echo
echo "--- Regresiones de diag-nic.sh ---"
DIAG=./diag-nic.sh
if [[ ! -f "$DIAG" ]]; then
  echo "   FALLA: no existe $DIAG"; fallos=$((fallos + 1))
else
  bash -n "$DIAG" || { echo "   FALLA: error de sintaxis en $DIAG"; fallos=$((fallos + 1)); }
  # El falso positivo original: cualquier r8169 generaba un veredicto de
  # "driver incorrecto" sin mirar kernel ni XID.
  if grep -nE '^\s*if \[\[ "\$DRIVER" == "r8169" \]\]' "$DIAG" | grep -q .; then
    echo "   FALLA: $DIAG vuelve a juzgar r8169 por si solo"; fallos=$((fallos + 1))
  fi
  grep -q 'nic_assess_driver' "$DIAG" || { echo "   FALLA: $DIAG no usa la regla del driver"; fallos=$((fallos + 1)); }
  grep -q 'nic_assess_zombie' "$DIAG" || { echo "   FALLA: $DIAG no usa la regla del zombie"; fallos=$((fallos + 1)); }
  # 'zombie confirmado' no puede volver a salir de una sola muestra de rx.
  if grep -qi 'zombie.*confirmado con alta confianza' "$DIAG"; then
    echo "   FALLA: $DIAG vuelve a confirmar zombie con una sola senal"; fallos=$((fallos + 1))
  fi
fi

echo
echo "--- Regresiones de fix-r8125-downgrade-6.8.sh ---"
FIX=./fix-r8125-downgrade-6.8.sh
if [[ ! -f "$FIX" ]]; then
  echo "   FALLA: no existe $FIX"; fallos=$((fallos + 1))
else
  bash -n "$FIX" || { echo "   FALLA: error de sintaxis en $FIX"; fallos=$((fallos + 1)); }
  # El .ko tiene que buscarse en updates/, que es el arbol que le gana al
  # in-tree, y no en todo /lib/modules.
  grep -q 'nic_r8125_ko_ok' "$FIX" \
    || { echo "   FALLA: $FIX no valida la version del r8125.ko (falso verde del 9.011.00)"; fallos=$((fallos + 1)); }
  # modinfo -k por nombre da falsos negativos en arboles solo-DKMS.
  if grep -qE 'modinfo -k "\$TARGET_KVER" r8125' "$FIX"; then
    echo "   FALLA: $FIX vuelve a usar 'modinfo -k <kver> r8125'"; fallos=$((fallos + 1))
  fi
  # grub-reboot tiene que quedar despues del gate de pre-reboot.
  l_gate=$(grep -n 'GATE DE PRE-REBOOT' "$FIX" | head -1 | cut -d: -f1)
  l_grub=$(grep -n '^run "grub-reboot' "$FIX" | head -1 | cut -d: -f1)
  if [[ -z "$l_gate" || -z "$l_grub" || "$l_grub" -lt "$l_gate" ]]; then
    echo "   FALLA: $FIX arma el grub-reboot antes del gate de pre-reboot"; fallos=$((fallos + 1))
  fi
  # El watchdog no puede tumbar todas las 8125 de la placa de una.
  if grep -qE '^\s*modprobe -r r8125' "$FIX"; then
    echo "   FALLA: el watchdog vuelve a hacer 'modprobe -r r8125' global"; fallos=$((fallos + 1))
  fi
  grep -q 'r8125-dkms' "$FIX" \
    || { echo "   FALLA: $FIX no contempla el r8125-dkms viejo de noble"; fallos=$((fallos + 1)); }

  # pkg_ok tiene que aceptar "hold ok installed": el propio script pone paquetes
  # en hold, y exigir "install ok installed" literal los daba por rotos.
  pkg_ok_body=$(awk '/^pkg_ok\(\)/,/;[[:space:]]*}$/' "$FIX")
  if [[ -z "$pkg_ok_body" ]]; then
    echo "   FALLA: no se pudo extraer pkg_ok de $FIX"; fallos=$((fallos + 1))
  else
    for caso in "install ok installed:0" "hold ok installed:0" "install ok half-configured:1" ":1"; do
      estado="${caso%:*}"; esperado="${caso##*:}"
      got=$(bash -c "dpkg-query() { printf '%s' '$estado'; }
$pkg_ok_body
pkg_ok cualquiera; echo \$?" 2>/dev/null)
      [[ "$got" == "$esperado" ]] || {
        echo "   FALLA: pkg_ok con estado '$estado' devolvio $got, esperado $esperado"
        fallos=$((fallos + 1)); }
    done
  fi
fi

  # Idempotencia: reejecutar el script no puede reescribir archivos identicos
  # ni disparar update-initramfs / udevadm reload / daemon-reload por gusto.
  grep -q '^write_if_changed()' "$FIX" \
    || { echo "   FALLA: $FIX no define write_if_changed"; fallos=$((fallos + 1)); }
  for sitio in '"\$PIN_FILE"' '"\$R8125_OPTS_FILE"' '"\$RULE_FILE"' \
               '"\$WATCHDOG_BIN"' '"\$WATCHDOG_SERVICE"' '"\$WATCHDOG_TIMER"'; do
    if grep -qE "^\s*(cat|echo)[^|]*> $sitio" "$FIX"; then
      echo "   FALLA: $FIX escribe $sitio sin pasar por write_if_changed"
      fallos=$((fallos + 1))
    fi
  done
  # update-initramfs cuesta ~30s: no puede colgar de una escritura incondicional.
  if ! grep -B4 'update-initramfs -u -k \$TARGET_KVER' "$FIX" | grep -q 'write_if_changed\|BL_FILES'; then
    echo "   FALLA: $FIX corre update-initramfs sin comprobar que algo cambio"
    fallos=$((fallos + 1))
  fi

  # Comportamiento real de write_if_changed, extraido del propio script.
  wic=$(awk '/^write_if_changed\(\) \{/,/^\}/' "$FIX")
  if [[ -z "$wic" ]]; then
    echo "   FALLA: no se pudo extraer write_if_changed de $FIX"; fallos=$((fallos + 1))
  else
    d="$TMP/wic"; mkdir -p "$d"
    probar_wic() {  # <descripcion> <rc esperado> <contenido>
      local got
      got=$(bash -c "DRY_RUN=0
$wic
log() { :; }
printf '%s' '$3' | write_if_changed '$d/f'; echo \$?" 2>/dev/null)
      [[ "$got" == "$2" ]] || { echo "   FALLA: write_if_changed $1 -> rc=$got, esperado $2"; fallos=$((fallos + 1)); }
    }
    probar_wic "archivo nuevo"      0 "uno"
    probar_wic "contenido igual"    1 "uno"
    probar_wic "contenido distinto" 0 "dos"
    [[ "$(cat "$d/f")" == "dos" ]] \
      || { echo "   FALLA: write_if_changed no dejo el contenido nuevo"; fallos=$((fallos + 1)); }
  fi

  # En dry-run no puede tocar el disco.
  if [[ -n "$wic" ]]; then
    rm -f "$TMP/wic/dry"
    bash -c "DRY_RUN=1
$wic
log() { :; }
printf 'x' | write_if_changed '$TMP/wic/dry'" >/dev/null 2>&1
    [[ ! -f "$TMP/wic/dry" ]] \
      || { echo "   FALLA: write_if_changed escribio en modo dry-run"; fallos=$((fallos + 1)); }
  fi

echo
if (( fallos == 0 )); then
  echo "OK: todos los self-checks pasaron"
else
  echo "FALLARON $fallos self-checks"
  exit 1
fi
