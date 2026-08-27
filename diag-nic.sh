#!/usr/bin/env bash
#
# diag-nic.sh - Diagnostico de conectividad para un puerto de red especifico
#
# Recorre las capas usadas para descartar causas en fallas de red post cambio
# de kernel/driver (chip zombie, driver incorrecto r8169/r8125, VLAN/PVID mal
# asignado en el switch, DHCP sin respuesta, persistencia de config, etc).
#
# QUE SEPARA ESTE SCRIPT
#   Un diagnostico util tiene que distinguir tres preguntas distintas:
#     1. La NIC esta funcionando AHORA?
#     2. Va a seguir funcionando despues del proximo reboot?
#     3. Hay evidencia de un fallo real de driver/hardware?
#   Por eso los hallazgos van a buckets separados por severidad y por bloque,
#   y el resumen nunca dice "se detectaron N causas" mezclando una mala
#   practica de netplan con un chip colgado.
#
# DOS COSAS QUE NO HACE, A PROPOSITO
#   - No trata 'driver activo = r8169' como problema por si solo. Solo lo es
#     con un RTL8125D (XID 688) en el track GA 6.8. Ver nic_lib.sh.
#   - No confirma un chip 'zombie' con una sola senal. rx_packets estatico
#     unos segundos es UNA senal; hace falta evidencia combinada.
#
# Uso:
#   sudo ./diag-nic.sh <interfaz> [duracion_captura_seg] [gateway_prueba]
#
# Ejemplos:
#   sudo ./diag-nic.sh enp13s0
#   sudo ./diag-nic.sh enp13s0 30
#   sudo ./diag-nic.sh enp13s0 30 172.20.66.1
#
# Codigos de salida (utiles para consolidar flota):
#   0 = sin hallazgos por encima de informativo
#   1 = hay avisos / riesgos de configuracion o de persistencia
#   2 = hay sospechas que requieren mas evidencia
#   3 = hay al menos un fallo confirmado de driver/hardware/link
#
set -uo pipefail

IFACE="${1:-}"
CAPTURE_SECS="${2:-20}"
TEST_GATEWAY="${3:-}"
TS="$(date +%Y%m%d-%H%M%S)"
LOGFILE="./diag-${IFACE:-unknown}-${TS}.log"
CAPFILE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/nic_lib.sh" ]]; then
  echo "Falta nic_lib.sh junto a este script (tiene el conocimiento de revisiones"
  echo "Realtek y las reglas de diagnostico). Copia el repo completo, no solo este archivo."
  exit 1
fi
# shellcheck source=nic_lib.sh
source "$SCRIPT_DIR/nic_lib.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "$@" | tee -a "$LOGFILE"; }
section() { echo -e "\n${BOLD}${CYAN}==> $*${NC}" | tee -a "$LOGFILE"; }
ok()      { echo -e "  ${GREEN}[OK]${NC} $*" | tee -a "$LOGFILE"; }
warn()    { echo -e "  ${YELLOW}[!!]${NC} $*" | tee -a "$LOGFILE"; }
fail()    { echo -e "  ${RED}[XX]${NC} $*" | tee -a "$LOGFILE"; }
info()    { echo -e "  $*" | tee -a "$LOGFILE"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

#===============================================================================
# Buckets de hallazgos
#
# Cada hallazgo es "<SEV>|<BLOQUE>|<texto>". Un hallazgo NUNCA cambia de
# severidad por acumulacion: si es una buena practica pendiente, se queda en
# WARN aunque haya diez.
#
#   INFO  observacion, nada que hacer
#   WARN  aviso o riesgo (config fragil, persistencia dudosa, pista de switch)
#   SUSP  sospecha: compatible con una falla, falta evidencia para afirmarla
#   FAIL  fallo confirmado con la evidencia disponible
#
# Bloques del resumen:
#   LINK     salud actual del link
#   DRIVER   driver / hardware
#   L3       DHCP / IP / alcance
#   PERSIST  que sobrevive al proximo reboot
#   CONFIG   riesgos de configuracion y pistas del lado del switch
#===============================================================================
FINDINGS=()
add_finding() { FINDINGS+=("$1|$2|$3"); }
f_info() { add_finding INFO "$1" "$2"; }
f_warn() { add_finding WARN "$1" "$2"; }
f_susp() { add_finding SUSP "$1" "$2"; }
f_fail() { add_finding FAIL "$1" "$2"; }

count_sev() {
  local want="$1" n=0 e
  for e in ${FINDINGS[@]+"${FINDINGS[@]}"}; do [[ "${e%%|*}" == "$want" ]] && n=$((n + 1)); done
  echo "$n"
}

#===============================================================================
# Validaciones de entrada
#===============================================================================
if [[ -z "$IFACE" ]]; then
  echo "Uso: sudo $0 <interfaz> [duracion_captura_seg] [gateway_prueba]"
  echo ""
  echo "Interfaces disponibles:"
  ip -br link show
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Este script necesita privilegios root (dmesg, tcpdump, ethtool). Reintenta con sudo."
  exit 1
fi

if [[ ! -e "/sys/class/net/${IFACE}" ]]; then
  echo "La interfaz '${IFACE}' no existe. Interfaces disponibles:"
  ip -br link show
  exit 1
fi

KVER="$(uname -r)"
log "${BOLD}Diagnostico de red - interfaz: ${IFACE}${NC}"
log "Fecha: $(date)"
log "Host: $(hostname)   Kernel: ${KVER}"
log "Log completo en: ${LOGFILE}"

#===============================================================================
section "CAPA 0 - Inventario basico"
#===============================================================================
ip -br link show "$IFACE" | tee -a "$LOGFILE"
ip -br addr show "$IFACE" | tee -a "$LOGFILE"

LINK_ADMIN_STATE=$(ip -br link show "$IFACE" | awk '{print $2}')
if [[ "$LINK_ADMIN_STATE" == "UP" ]]; then
  ok "Interfaz administrativamente UP"
  ADMIN_UP=1
else
  fail "Interfaz administrativamente DOWN (${LINK_ADMIN_STATE}) - subela con: ip link set ${IFACE} up"
  f_fail LINK "Interfaz ${IFACE} administrativamente DOWN (${LINK_ADMIN_STATE})"
  ADMIN_UP=0
fi

#===============================================================================
section "CAPA 1 - Identidad de hardware y driver (hechos, sin veredicto)"
#===============================================================================
if command_exists lshw; then
  lshw -C network -short 2>/dev/null | tee -a "$LOGFILE"
fi

# Fuente de verdad del driver: el binding real en sysfs, equivalente a
# 'ethtool -i'. Nunca lsmod: r8169 y r8125 pueden estar los dos cargados y eso
# no dice quien maneja la placa.
DRIVER=$(nic_bound_driver "$IFACE" || echo "?")
info "Driver bindeado (sysfs): ${DRIVER}"

if command_exists ethtool; then
  ETHTOOL_I=$(ethtool -i "$IFACE" 2>&1)
  echo "$ETHTOOL_I" | tee -a "$LOGFILE"
  ETHTOOL_DRV=$(awk -F': ' '/^driver:/ {print $2; exit}' <<<"$ETHTOOL_I")
  if [[ -n "$ETHTOOL_DRV" && "$ETHTOOL_DRV" != "$DRIVER" ]]; then
    warn "ethtool -i dice '${ETHTOOL_DRV}' y sysfs dice '${DRIVER}' - revisar a mano"
    f_warn DRIVER "Discrepancia entre 'ethtool -i' (${ETHTOOL_DRV}) y el binding de sysfs (${DRIVER})"
  fi
else
  warn "ethtool no instalado (sudo apt install ethtool) - se usa solo sysfs"
fi

PCI_ADDR=$(nic_pci_addr "$IFACE" || echo "")
PCI_ID=$(nic_pci_id "$IFACE" || echo "?")
[[ -n "$PCI_ADDR" ]] && info "Direccion PCI: ${PCI_ADDR}"
info "PCI ID (vendor:device): ${PCI_ID}"

XID_MAP=$(nic_xid_map)
XID="?"
if [[ -n "$PCI_ADDR" ]]; then
  XID=$(nic_xid_for_pci "$PCI_ADDR" "$XID_MAP" || echo "?")
fi
if [[ "$XID" != "?" ]]; then
  info "Revision del chip: $(nic_rev_from_xid "$XID") (XID ${XID})"
else
  info "Revision del chip: no determinable (dmesg rotado o el driver no la reporta)"
fi

if command_exists dkms; then
  DKMS_OUT=$(dkms status 2>/dev/null || true)
  if [[ -n "$DKMS_OUT" ]]; then
    info "Estado DKMS del equipo:"
    sed 's/^/    /' <<<"$DKMS_OUT" | tee -a "$LOGFILE"
  else
    info "Sin modulos DKMS registrados (normal si todos los drivers son in-kernel)"
  fi
fi

#===============================================================================
section "CAPA 2 - Estado del link fisico"
#===============================================================================
CARRIER=$(cat "/sys/class/net/${IFACE}/carrier" 2>/dev/null || echo 0)
LINK_STATUS="desconocido"
if command_exists ethtool; then
  ETHTOOL_OUT=$(ethtool "$IFACE" 2>&1)
  echo "$ETHTOOL_OUT" | tee -a "$LOGFILE"
  if grep -qi "Link detected: yes" <<<"$ETHTOOL_OUT"; then
    ok "Link fisico detectado"
    LINK_STATUS="si"; CARRIER=1
  else
    fail "Sin link fisico detectado - revisar cable/switch antes de seguir con capas superiores"
    f_fail LINK "Sin link fisico en ${IFACE}: cable, transceiver o puerto de switch"
    LINK_STATUS="no"; CARRIER=0
  fi
else
  if [[ "$CARRIER" == "1" ]]; then
    ok "Carrier detectado (via sysfs, sin ethtool)"
    LINK_STATUS="si"
  else
    fail "Sin carrier (via sysfs, sin ethtool)"
    f_fail LINK "Sin carrier en ${IFACE}: cable, transceiver o puerto de switch"
    LINK_STATUS="no"
  fi
fi

#===============================================================================
section "CAPA 3 - Contadores del chip (RX / TX / interrupciones)"
#===============================================================================
rx_now()  { cat "/sys/class/net/${IFACE}/statistics/rx_packets" 2>/dev/null || echo 0; }
tx_now()  { cat "/sys/class/net/${IFACE}/statistics/tx_packets" 2>/dev/null || echo 0; }
# Suma de todas las lineas de /proc/interrupts cuyo nombre incluya la interfaz
# (r8169/r8125 registran varias colas: enp7s0, enp7s0-rx-0, enp7s0-tx-0...).
irq_now() {
  awk -v i="$IFACE" '$0 ~ (i "([^a-zA-Z0-9_-]|$)") {
        for (j = 2; j <= NF; j++) if ($j ~ /^[0-9]+$/) s += $j
      } END { print s + 0 }' /proc/interrupts
}

info "Muestreo corto (4 muestras cada 3s) para ver actividad inmediata..."
declare -a RX_SAMPLES
RX_SAMPLES[0]=$(rx_now)
for i in 1 2 3; do sleep 3; RX_SAMPLES[$i]=$(rx_now); done
info "rx_packets (t=0,3,6,9s): ${RX_SAMPLES[0]} ${RX_SAMPLES[1]} ${RX_SAMPLES[2]} ${RX_SAMPLES[3]}"

# La ventana LARGA es la que vale: arranca aca y se cierra despues de la
# captura de la Capa 5, o sea >= 30s con la duracion por defecto. Un RX
# estatico durante 12s no distingue "chip colgado" de "red silenciosa".
RX_WINDOW_START="${RX_SAMPLES[0]}"
TX_WINDOW_START=$(tx_now)
IRQ_WINDOW_START=$(irq_now)
WINDOW_T0=$(date +%s)

RX_ERRORS=$(cat "/sys/class/net/${IFACE}/statistics/rx_errors" 2>/dev/null || echo 0)
RX_DROPPED=$(cat "/sys/class/net/${IFACE}/statistics/rx_dropped" 2>/dev/null || echo 0)
info "rx_errors: ${RX_ERRORS}   rx_dropped: ${RX_DROPPED}   interrupciones acumuladas: ${IRQ_WINDOW_START}"
if [[ "$RX_ERRORS" -gt 0 ]]; then
  warn "rx_errors distinto de cero (${RX_ERRORS}) - puede ser cableado, autonegociacion o el propio chip"
  f_warn DRIVER "rx_errors=${RX_ERRORS} en ${IFACE}"
fi

section "dmesg relevante"
dmesg 2>/dev/null | grep -iE "${IFACE}|r8125|r8169|watchdog" | tail -30 | tee -a "$LOGFILE"

# NETDEV WATCHDOG: solo cuenta como evidencia si se puede fechar y es reciente.
# dmesg es por arranque, pero en un equipo con 40 dias de uptime un watchdog de
# hace un mes no prueba nada sobre el estado actual.
WATCHDOG_RECENT=0
WD_LINE=$(dmesg 2>/dev/null | grep -i "NETDEV WATCHDOG" | grep -i "$IFACE" | tail -1 || true)
if [[ -n "$WD_LINE" ]]; then
  WD_TS=$(grep -oE '^\[[[:space:]]*[0-9]+\.[0-9]+\]' <<<"$WD_LINE" | tr -d '[] ' | cut -d. -f1)
  UPTIME_S=$(cut -d. -f1 /proc/uptime)
  if [[ -n "$WD_TS" ]]; then
    WD_AGE=$(( UPTIME_S - WD_TS ))
    if [[ "$WD_AGE" -le 3600 ]]; then
      fail "NETDEV WATCHDOG hace ${WD_AGE}s en ${IFACE} - la cola de TX se colgo hace poco"
      f_fail DRIVER "NETDEV WATCHDOG reciente (hace ${WD_AGE}s) en ${IFACE}: la cola de TX se colgo"
      WATCHDOG_RECENT=1
    else
      warn "NETDEV WATCHDOG presente pero viejo (hace ${WD_AGE}s) - historico, no evidencia del estado actual"
      f_warn DRIVER "NETDEV WATCHDOG historico en ${IFACE} (hace ${WD_AGE}s)"
    fi
  else
    warn "NETDEV WATCHDOG presente pero sin timestamp legible - no se puede fechar"
    f_warn DRIVER "NETDEV WATCHDOG en ${IFACE}, sin timestamp para fecharlo"
  fi
else
  ok "Sin NETDEV WATCHDOG para ${IFACE} en este arranque"
fi

#===============================================================================
section "CAPA 4 - Gestion de NetworkManager"
#===============================================================================
NM_MANAGED="desconocido"
if command_exists nmcli; then
  nmcli device show "$IFACE" 2>&1 | tee -a "$LOGFILE"
  NM_STATE=$(nmcli -t -g GENERAL.STATE device show "$IFACE" 2>/dev/null || true)
  case "$NM_STATE" in
    *unmanaged*) NM_MANAGED="no" ;;
    "")          NM_MANAGED="desconocido" ;;
    *)           NM_MANAGED="si" ;;
  esac
  echo "" | tee -a "$LOGFILE"
  nmcli connection show | tee -a "$LOGFILE"
  echo "" | tee -a "$LOGFILE"
  info "Ultimas lineas de journal relacionadas a DHCP/${IFACE}:"
  journalctl -u NetworkManager -b --no-pager 2>/dev/null | grep -iE "dhcp|${IFACE}" | tail -20 | tee -a "$LOGFILE"
else
  warn "nmcli no disponible"
fi

#===============================================================================
section "CAPA 5 - Trafico real en el cable (captura sin filtro, ${CAPTURE_SECS}s)"
#===============================================================================
TOTAL_PKTS=-1     # -1 = no se pudo capturar (distinto de "capturo cero")
CAPTURE_OK=0      # 1 solo si tcpdump realmente corrio y escribio el pcap
DHCP_DISCOVER_SIN_OFFER=0
if command_exists tcpdump; then
  CAPFILE="./diag-${IFACE}-${TS}.pcap"
  # -U: vuelca cada paquete a disco de inmediato (evita esperas por buffering).
  # -c 20000: tope de seguridad si el puerto esta en modo promiscuo viendo
  #           trafico de todo el segmento/VLAN.
  # timeout -k 5: SIGKILL si tcpdump no responde a SIGTERM en 5s extra.
  timeout -k 5 "${CAPTURE_SECS}" tcpdump -i "$IFACE" -n -U -c 20000 -w "$CAPFILE" 2>/dev/null

  PCAP_SIZE=$(du -h "$CAPFILE" 2>/dev/null | cut -f1)
  info "Tamano del pcap: ${PCAP_SIZE:-desconocido}"

  # Un pcap valido trae siempre su cabecera (24 bytes) aunque no haya capturado
  # nada. Si el archivo no existe o esta vacio, tcpdump NO llego a correr (falta
  # de permisos, interfaz ocupada): eso es "no se pudo medir", no "no hay
  # trafico", y no puede sumar evidencia de chip colgado.
  if [[ -s "$CAPFILE" ]]; then
    CAPTURE_OK=1
    DUMP_TXT=$(tcpdump -r "$CAPFILE" -n 2>/dev/null)
    TOTAL_PKTS=$(grep -c . <<<"$DUMP_TXT" || true)
    [[ -z "$DUMP_TXT" ]] && TOTAL_PKTS=0
    info "Paquetes totales capturados: ${TOTAL_PKTS} (guardados en ${CAPFILE})"
  else
    DUMP_TXT=""
    warn "tcpdump no pudo escribir la captura - no se cuenta como 'cero trafico', se pierde una senal"
    f_info LINK "No se pudo capturar trafico en ${IFACE}: el diagnostico de chip colgado corre con una senal menos"
  fi

  if [[ "$TOTAL_PKTS" -ge 20000 ]]; then
    warn "Se alcanzo el tope de 20000 paquetes - el puerto puede estar en modo promiscuo viendo todo el segmento"
    f_info CONFIG "Captura tope de 20000 paquetes: verificar 'ip link show ${IFACE} | grep -i promisc'"
  fi

  if [[ "$CAPTURE_OK" -eq 0 ]]; then
    : # ya avisado arriba
  elif [[ "$TOTAL_PKTS" -eq 0 ]]; then
    warn "CERO paquetes en ${CAPTURE_SECS}s, ni broadcast ni STP - senal fuerte, se combina mas abajo"
  else
    ok "Trafico detectado (${TOTAL_PKTS} paquetes) - el chip esta recibiendo"
    STP_COUNT=$(grep -c "STP" <<<"$DUMP_TXT" || true)
    ARP_COUNT=$(grep -c "ARP" <<<"$DUMP_TXT" || true)
    DHCP_COUNT=$(grep -c "BOOTP/DHCP" <<<"$DUMP_TXT" || true)
    LLDP_COUNT=$(grep -c "LLDP" <<<"$DUMP_TXT" || true)
    info "  STP: ${STP_COUNT}   ARP: ${ARP_COUNT}   DHCP: ${DHCP_COUNT}   LLDP: ${LLDP_COUNT}"
    if [[ "$DHCP_COUNT" -gt 0 ]]; then
      if grep -qi "BOOTP/DHCP, Reply" <<<"$DUMP_TXT"; then
        ok "Se ven DHCPOFFER/Reply en la captura"
      else
        warn "Salen DHCPDISCOVER pero no se ve ningun Reply/Offer en esta ventana"
        DHCP_DISCOVER_SIN_OFFER=1
      fi
    fi
  fi
else
  warn "tcpdump no disponible - no se pudo capturar trafico (queda una senal menos para decidir)"
fi

# Cierre de la ventana larga
RX_WINDOW_END=$(rx_now)
TX_WINDOW_END=$(tx_now)
IRQ_WINDOW_END=$(irq_now)
WINDOW_SECS=$(( $(date +%s) - WINDOW_T0 ))
RX_DELTA=$(( RX_WINDOW_END - RX_WINDOW_START ))
TX_DELTA=$(( TX_WINDOW_END - TX_WINDOW_START ))
IRQ_DELTA=$(( IRQ_WINDOW_END - IRQ_WINDOW_START ))
info "Ventana larga: ${WINDOW_SECS}s   rx +${RX_DELTA}   tx +${TX_DELTA}   irq +${IRQ_DELTA}"

#===============================================================================
section "CAPA 5b - Identificacion de switch/VLAN via LLDP"
#===============================================================================
# LLDP NO sirve como prueba negativa: un switch puede simplemente no anunciarlo.
# Se usa solo para enriquecer el diagnostico, nunca para declarar un fallo.
PVID="n/a"
if command_exists tcpdump; then
  LLDP_PKT=$(timeout 15 tcpdump -i "$IFACE" -n -v -c 1 'ether proto 0x88cc' 2>/dev/null)
  if [[ -n "$LLDP_PKT" ]]; then
    echo "$LLDP_PKT" | tee -a "$LOGFILE"
    if grep -q "PVID" <<<"$LLDP_PKT"; then
      PVID=$(grep -oP '(?<=PVID\): )[0-9]+' <<<"$LLDP_PKT" || echo "?")
      info "PVID del puerto del switch: ${PVID}"
      if [[ "$PVID" == "1" ]]; then
        warn "PVID = 1 (VLAN por defecto) - pista, no prueba: puede ser un puerto sin asignar a la VLAN correcta"
        f_warn CONFIG "PVID=1 (VLAN default) en el puerto del switch: pista de puerto mal asignado, confirmar con el equipo de redes"
      fi
    fi
  else
    info "No se recibio LLDP en 15s - informativo: muchos switches no lo anuncian. No es un fallo."
    f_info CONFIG "Sin LLDP en 15s: no se pudo identificar switch/puerto/PVID (el switch puede no anunciarlo)"
  fi
fi

#===============================================================================
section "SINTESIS - reglas de decision"
#===============================================================================
# Todo lo anterior fueron hechos. Aca se aplican las reglas de nic_lib.sh, que
# son puras y estan cubiertas por self_check_nic_lib.sh.

# --- La interfaz esta operativa AHORA? Se usa para desempatar la regla del
#     driver cuando el XID no se puede determinar. ---
LINK_OK=0
if [[ "$TOTAL_PKTS" -gt 0 ]] || [[ "$RX_DELTA" -gt 0 ]]; then LINK_OK=1; fi

# --- Regla 1: driver ---
DRIVER_VERDICT=$(nic_assess_driver "$KVER" "$PCI_ID" "$XID" "$DRIVER" "$LINK_OK")
DRIVER_SEV=$(awk '{print $1}' <<<"$DRIVER_VERDICT")
DRIVER_CODE=$(awk '{print $2}' <<<"$DRIVER_VERDICT")
DRIVER_TEXT=$(cut -d' ' -f3- <<<"$DRIVER_VERDICT")
case "$DRIVER_SEV" in
  FAIL) fail "$DRIVER_TEXT"; f_fail DRIVER "$DRIVER_TEXT" ;;
  SUSP) warn "$DRIVER_TEXT"; f_susp DRIVER "$DRIVER_TEXT" ;;
  *)    ok   "$DRIVER_TEXT"; f_info DRIVER "$DRIVER_TEXT" ;;
esac

# --- Regla 2: chip zombie, por evidencia combinada ---
ZOMBIE_EVIDENCE=()
# Solo cuenta como "congelado" sobre la ventana larga (>=30s por defecto).
[[ "$RX_DELTA" -eq 0 && "$WINDOW_SECS" -ge 25 ]] && ZOMBIE_EVIDENCE+=(rx_frozen)
[[ "$RX_WINDOW_END" -eq 0 ]]                      && ZOMBIE_EVIDENCE+=(rx_zero)
[[ "$IRQ_DELTA" -eq 0 && "$IRQ_WINDOW_START" -ge 0 ]] && ZOMBIE_EVIDENCE+=(irq_frozen)
# no_capture solo si la captura REALMENTE corrio y volvio vacia.
[[ "$CAPTURE_OK" -eq 1 && "$TOTAL_PKTS" -eq 0 ]]  && ZOMBIE_EVIDENCE+=(no_capture)
[[ "$TOTAL_PKTS" -gt 0 ]]                         && ZOMBIE_EVIDENCE+=(capture_traffic)
# El contador RX es prueba de recepcion por si mismo, y sigue disponible aunque
# tcpdump no haya podido correr.
[[ "$RX_DELTA" -gt 0 ]]                           && ZOMBIE_EVIDENCE+=(rx_active)
[[ "$WATCHDOG_RECENT" -eq 1 ]]                    && ZOMBIE_EVIDENCE+=(watchdog)
[[ "$TX_DELTA" -gt 0 && "$RX_DELTA" -eq 0 ]]      && ZOMBIE_EVIDENCE+=(tx_active)

# Con la interfaz administrativamente DOWN no hay nada que evaluar: el chip no
# tiene por que recibir. Se fuerza la rama SIN_LINK para no inventar sospechas.
ZOMBIE_CARRIER="$CARRIER"
[[ "$ADMIN_UP" == "1" ]] || ZOMBIE_CARRIER=0
ZOMBIE_VERDICT=$(nic_assess_zombie "$ZOMBIE_CARRIER" ${ZOMBIE_EVIDENCE[@]+"${ZOMBIE_EVIDENCE[@]}"})
ZOMBIE_LEVEL=$(awk '{print $1}' <<<"$ZOMBIE_VERDICT")
ZOMBIE_SCORE=$(awk '{print $2}' <<<"$ZOMBIE_VERDICT")
ZOMBIE_DETAIL=$(cut -d' ' -f3- <<<"$ZOMBIE_VERDICT")
info "Evidencia de chip colgado: ${ZOMBIE_DETAIL}"
case "$ZOMBIE_LEVEL" in
  SIN_LINK)
    if [[ "$ADMIN_UP" != "1" ]]; then
      info "No se evalua 'zombie': la interfaz esta administrativamente DOWN. Subela primero (ip link set ${IFACE} up)."
    else
      info "No se evalua 'zombie': sin carrier el diagnostico correcto es cable/switch/link fisico."
    fi ;;
  NORMAL)
    ok "Chip recibiendo con normalidad (score ${ZOMBIE_SCORE})"
    f_info LINK "Chip ${IFACE} recibiendo con normalidad" ;;
  SOSPECHOSO)
    warn "Senales aisladas (score ${ZOMBIE_SCORE}) - NO alcanza para declarar chip colgado"
    f_warn LINK "Senales aisladas de RX inactivo en ${IFACE} (score ${ZOMBIE_SCORE}): insuficiente para declarar chip colgado" ;;
  PROBABLE)
    fail "ALTA PROBABILIDAD de chip colgado (score ${ZOMBIE_SCORE})"
    f_susp LINK "Alta probabilidad de chip colgado en ${IFACE} (score ${ZOMBIE_SCORE}): ${ZOMBIE_DETAIL}" ;;
  MUY_FUERTE)
    fail "EVIDENCIA MUY FUERTE de chip colgado (score ${ZOMBIE_SCORE}) - remediar: unbind/bind o remove/rescan del device PCI; si no responde, corte de AC"
    f_fail LINK "Evidencia muy fuerte de chip colgado en ${IFACE} (score ${ZOMBIE_SCORE}): ${ZOMBIE_DETAIL}" ;;
esac

#===============================================================================
section "CAPA 6 - DHCP / conectividad L3"
#===============================================================================
CURRENT_IP=$(ip -br addr show "$IFACE" | awk '{print $3}')
if [[ -n "$CURRENT_IP" && "$CURRENT_IP" != *"169.254"* ]]; then
  ok "La interfaz ya tiene una IP valida (${CURRENT_IP}) - no se fuerza DHCP para no cortar la sesion activa"
elif [[ "$NM_MANAGED" == "si" ]]; then
  # No se lanza dhclient sobre una interfaz gestionada por NetworkManager: NM
  # trae su propio cliente DHCP y los dos peleando dan un diagnostico peor que
  # el problema original.
  warn "Sin IP valida y la interfaz la gestiona NetworkManager - no se fuerza dhclient (pelearia con el cliente interno de NM)"
  warn "Para reintentar a mano: nmcli device disconnect ${IFACE} && nmcli device connect ${IFACE}"
  f_warn L3 "${IFACE} sin IP valida bajo gestion de NetworkManager (IP actual: ${CURRENT_IP:-ninguna})"
elif command_exists dhclient; then
  info "Sin IP valida y la interfaz no la gestiona NM. Intentando DHCP explicito (timeout 30s)..."
  timeout 30 dhclient -v "$IFACE" 2>&1 | tee -a "$LOGFILE" || true
  CURRENT_IP=$(ip -br addr show "$IFACE" | awk '{print $3}')
  if [[ -n "$CURRENT_IP" && "$CURRENT_IP" != *"169.254"* ]]; then
    ok "IP obtenida tras el intento: ${CURRENT_IP}"
  else
    fail "No se obtuvo IP valida por DHCP (IP actual: ${CURRENT_IP:-ninguna})"
    f_fail L3 "Sin lease DHCP en ${IFACE} tras intento explicito"
  fi
else
  warn "Sin IP valida y dhclient no disponible - no se pudo forzar la prueba de DHCP"
  f_warn L3 "${IFACE} sin IP valida; no se pudo probar DHCP (falta dhclient)"
fi

# Escenario de terreno: el DISCOVER sale y no vuelve nada, pero la NIC si recibe
# otro trafico. Eso apunta a DHCP/VLAN/switch, no al driver.
if [[ "$DHCP_DISCOVER_SIN_OFFER" -eq 1 ]]; then
  if [[ "$TOTAL_PKTS" -gt 0 ]]; then
    warn "DHCPDISCOVER sin Offer, pero la NIC recibe otro trafico - driver/hardware probablemente vivos; sospechar DHCP/VLAN/switch"
    f_susp L3 "DHCPDISCOVER sin Offer con la NIC recibiendo otro trafico: apuntar a servidor DHCP, VLAN o puerto de switch, no al driver"
  else
    f_susp L3 "DHCPDISCOVER sin Offer y sin ningun otro trafico entrante"
  fi
fi

if [[ -n "$TEST_GATEWAY" ]]; then
  section "Prueba de ping directo a ${TEST_GATEWAY} (por ${IFACE})"
  if ping -I "$IFACE" -c 4 -W 2 "$TEST_GATEWAY" 2>&1 | tee -a "$LOGFILE"; then
    ok "Ping a ${TEST_GATEWAY} respondio"
  else
    fail "Sin respuesta de ${TEST_GATEWAY}"
    f_warn L3 "El gateway de prueba ${TEST_GATEWAY} no responde por ${IFACE} (puede ser ICMP filtrado)"
  fi
fi

#===============================================================================
section "CAPA 7 - Persistencia de configuracion de red (netplan / NetworkManager)"
#===============================================================================
info "Esta capa NO evalua conectividad actual, sino si la config sobrevive un reboot."

IFACE_MAC=$(cat "/sys/class/net/${IFACE}/address" 2>/dev/null || echo "")
info "MAC de ${IFACE}: ${IFACE_MAC:-desconocida}"

NETPLAN_PERSISTENT="n/a"
NETPLAN_MATCH_MAC="n/a"
DHCP_STATIC_CONFLICT="no"
ORPHAN_PROFILE_RISK="no"

# --- 7.1: IP secundaria dinamica conviviendo con una estatica ---
# Se buscan los dos flags por separado: el orden en que iproute2 los imprime
# no es estable entre versiones (aparece 'noprefixroute' en el medio).
SECONDARY_DYNAMIC=0
while IFS= read -r line; do
  [[ "$line" == *" secondary "* && "$line" == *" dynamic "* ]] && SECONDARY_DYNAMIC=$((SECONDARY_DYNAMIC + 1))
done < <(ip -o addr show "$IFACE" 2>/dev/null)
if [[ "$SECONDARY_DYNAMIC" -gt 0 ]]; then
  warn "IP marcada 'secondary'+'dynamic' junto a la principal - sintoma de dhcp4:true compitiendo con una IP estatica"
  f_warn CONFIG "IP secundaria por DHCP conviviendo con configuracion estatica en ${IFACE}"
  DHCP_STATIC_CONFLICT="si"
else
  ok "Sin IPs secundarias dinamicas inesperadas en ${IFACE}"
fi

# --- 7.2: el perfil de NetworkManager activo, persistido o efimero? ---
if command_exists nmcli; then
  ACTIVE_CONN=$(nmcli -t -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null)
  if [[ -n "$ACTIVE_CONN" && "$ACTIVE_CONN" != "--" ]]; then
    info "Perfil de NetworkManager activo para ${IFACE}: '${ACTIVE_CONN}'"
    CONN_UUID=$(nmcli -t -g connection.uuid connection show "$ACTIVE_CONN" 2>/dev/null)
    CONN_IFNAME_BOUND=$(nmcli -t -g connection.interface-name connection show "$ACTIVE_CONN" 2>/dev/null)

    if [[ -n "$CONN_UUID" ]] && grep -rl "$CONN_UUID" /etc/NetworkManager/system-connections/ 2>/dev/null | grep -q .; then
      ok "El perfil '${ACTIVE_CONN}' esta persistido en /etc/NetworkManager/system-connections - sobrevive un reboot"
      NETPLAN_PERSISTENT="si"
    elif [[ -n "$CONN_UUID" ]] && grep -rl "$CONN_UUID" /run/NetworkManager/system-connections/ 2>/dev/null | grep -q .; then
      warn "El perfil '${ACTIVE_CONN}' solo existe en /run (memoria) - NO sobrevive un reboot"
      f_warn PERSIST "Perfil de NetworkManager '${ACTIVE_CONN}' efimero (solo en /run) para ${IFACE}: al reiniciar, NM recreara un perfil por defecto"
      NETPLAN_PERSISTENT="no"
    else
      warn "No se pudo confirmar donde esta persistido el perfil '${ACTIVE_CONN}' - revisar a mano"
      f_warn PERSIST "No se pudo confirmar la persistencia del perfil '${ACTIVE_CONN}' de ${IFACE}"
      NETPLAN_PERSISTENT="desconocido"
    fi

    if [[ -z "$CONN_IFNAME_BOUND" ]]; then
      warn "El perfil '${ACTIVE_CONN}' no esta atado a ${IFACE} por 'interface-name'"
      f_warn CONFIG "El perfil '${ACTIVE_CONN}' no fija 'interface-name': podria re-aplicarse a otra interfaz si el nombre cambia"
    fi
  else
    warn "No se pudo determinar el perfil de NetworkManager activo para ${IFACE}"
  fi
fi

# --- 7.3: archivos netplan que mencionan esta interfaz ---
if [[ -d /etc/netplan ]]; then
  FILES_BY_NAME=$(grep -rl -E "^[[:space:]]*${IFACE}:" /etc/netplan/*.yaml 2>/dev/null || true)
  FILES_BY_MAC=""
  [[ -n "$IFACE_MAC" ]] && FILES_BY_MAC=$(grep -rli "$IFACE_MAC" /etc/netplan/*.yaml 2>/dev/null || true)
  NETPLAN_FILES=$(printf '%s\n%s\n' "$FILES_BY_NAME" "$FILES_BY_MAC" | sort -u | grep -v '^$' || true)
  NETPLAN_FILE_COUNT=$(grep -c . <<<"$NETPLAN_FILES" || true)
  [[ -z "$NETPLAN_FILES" ]] && NETPLAN_FILE_COUNT=0

  if [[ "$NETPLAN_FILE_COUNT" -eq 0 ]]; then
    warn "Ningun archivo en /etc/netplan referencia a ${IFACE} - depende de un perfil autogenerado de NetworkManager"
    f_warn PERSIST "Sin cobertura de netplan para ${IFACE}: depende de un perfil autogenerado de NM (ver 7.2)"
  else
    info "Archivos netplan que mencionan ${IFACE}:"
    sed 's/^/    /' <<<"$NETPLAN_FILES" | tee -a "$LOGFILE"

    if [[ "$NETPLAN_FILE_COUNT" -gt 1 ]]; then
      warn "Mas de un archivo netplan referencia a ${IFACE} - netplan los combina, revisar que no compitan"
      f_warn CONFIG "${NETPLAN_FILE_COUNT} archivos netplan referencian a ${IFACE}: netplan los combina, verificar que no compitan"
    fi

    DHCP_TRUE_FILES=""; STATIC_ADDR_FILES=""; MAC_MATCH_FILES=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      grep -qE "dhcp4:[[:space:]]*(true|yes)" "$f" && DHCP_TRUE_FILES="${DHCP_TRUE_FILES}${f} "
      grep -qE "^[[:space:]]*addresses:" "$f" && STATIC_ADDR_FILES="${STATIC_ADDR_FILES}${f} "
      grep -qi "macaddress" "$f" && MAC_MATCH_FILES="${MAC_MATCH_FILES}${f} "
    done <<<"$NETPLAN_FILES"

    if [[ -n "$DHCP_TRUE_FILES" && -n "$STATIC_ADDR_FILES" ]]; then
      warn "Conflicto: dhcp4:true en [${DHCP_TRUE_FILES}] y direccion estatica en [${STATIC_ADDR_FILES}]"
      f_warn CONFIG "netplan: dhcp4:true y direccion estatica compitiendo para ${IFACE}"
      DHCP_STATIC_CONFLICT="si"
    fi

    if [[ -z "$MAC_MATCH_FILES" ]]; then
      warn "Ningun archivo matchea ${IFACE} por 'macaddress' - el match por nombre es fragil ante cambios de kernel/driver"
      f_warn CONFIG "Sin match por MAC en netplan para ${IFACE}: buena practica pendiente, no un fallo actual"
      NETPLAN_MATCH_MAC="no"
    else
      ok "Hay match por MAC para ${IFACE}"
      NETPLAN_MATCH_MAC="si"
    fi
  fi

  # --- 7.4: landmine de instalacion (Subiquity/cloud-init) ---
  if [[ -f /etc/netplan/50-cloud-init.yaml ]]; then
    if grep -q "50-cloud-init.yaml" <<<"$NETPLAN_FILES"; then
      warn "/etc/netplan/50-cloud-init.yaml (config congelada de la instalacion) referencia a ${IFACE}"
      f_warn PERSIST "50-cloud-init.yaml compitiendo con la config deseada para ${IFACE}: causa conocida de IPs estaticas que no sobreviven reboots"
    else
      info "/etc/netplan/50-cloud-init.yaml existe pero no referencia a ${IFACE} directamente"
    fi
  fi
fi

# --- 7.5: perfiles genericos de NetworkManager sin interfaz asignada ---
if command_exists nmcli; then
  ORPHAN_PROFILES=""
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    ctype=$(nmcli -t -g connection.type connection show "$cname" 2>/dev/null)
    [[ "$ctype" != "802-3-ethernet" ]] && continue
    ifname_bound=$(nmcli -t -g connection.interface-name connection show "$cname" 2>/dev/null)
    autoc=$(nmcli -t -g connection.autoconnect connection show "$cname" 2>/dev/null)
    if [[ -z "$ifname_bound" && "$autoc" == "yes" ]]; then
      ORPHAN_PROFILES="${ORPHAN_PROFILES}${cname}; "
    fi
  done < <(nmcli -t -f NAME connection show 2>/dev/null)

  if [[ -n "$ORPHAN_PROFILES" ]]; then
    warn "Perfiles ethernet genericos con autoconnect=yes y sin interfaz asignada: ${ORPHAN_PROFILES}"
    f_warn CONFIG "Perfiles NetworkManager genericos sin interfaz asignada (${ORPHAN_PROFILES}): pueden 'atrapar' cualquier NIC nueva ('Wired connection N')"
    ORPHAN_PROFILE_RISK="si"
  else
    ok "Sin perfiles ethernet genericos huerfanos detectados"
  fi
fi

#===============================================================================
section "CAPA 8 - Preparacion para el kernel GA 6.8 (fail-safe pre-downgrade)"
#===============================================================================
# Motivo: la regla de oro del Caso C es "necesitas red para arreglar la red".
# Si esta placa tiene una Realtek 2.5GbE y el equipo todavia NO corre el GA,
# hay que saber ANTES del reboot si el r8125 esta listo para el kernel destino.
GA_READY="n/a"
if [[ "$PCI_ID" != "$NIC_PCI_ID_8125" ]]; then
  info "La interfaz no es 10ec:8125; esta capa no aplica."
elif nic_kernel_is_ga68 "$KVER"; then
  info "El equipo ya corre el track GA (${KVER}): la red de este kernel ya demostro funcionar."
  GA_READY="ya_en_ga"
elif ! GA_KVER=$(nic_newest_ga68_installed); then
  info "No hay modulos de ningun kernel GA 6.8 instalados todavia; nada que verificar aun."
  GA_READY="sin_ga"
else
  info "Kernel GA destino detectado: ${GA_KVER}"
  KO_INFO=$(nic_r8125_ko_ok "$GA_KVER"); KO_RC=$?
  KO_PATH=$(awk '{print $1}' <<<"$KO_INFO")
  KO_VER=$(awk '{print $2}' <<<"$KO_INFO")
  case "$KO_RC" in
    0)
      if nic_alias_has_r8125 "$GA_KVER"; then
        ok "r8125 ${KO_VER} construido e indexado para ${GA_KVER} (${KO_PATH})"
        GA_READY="listo"
      else
        warn "r8125 ${KO_VER} existe para ${GA_KVER} pero NO esta indexado en modules.alias - udev no lo cargara"
        f_warn PERSIST "r8125 presente para ${GA_KVER} pero sin alias PCI indexado: correr 'sudo depmod -a ${GA_KVER}' antes de reiniciar al GA"
        GA_READY="sin_alias"
      fi ;;
    1)
      warn "No hay r8125.ko en ${GA_KVER}/updates. Si esta placa es un RTL8125D, reiniciar al GA deja el equipo SIN RED."
      warn "Enfoque fail-safe del proyecto: preparar el driver ANTES del reboot (sudo omnifish-nic-rescue, o ./fix-r8125-downgrade-6.8.sh)."
      f_warn PERSIST "Sin r8125 construido para el GA ${GA_KVER}: NO reiniciar al GA hasta prepararlo (fail-safe del Caso C, aunque el XID no sea 688)"
      GA_READY="falta" ;;
    2)
      fail "r8125 ${KO_VER} presente para ${GA_KVER} pero es MENOR que ${NIC_R8125_MIN_VER}: no cubre el RTL8125D."
      fail "Este es el falso verde clasico: el r8125-dkms 9.011.00 de noble tambien deja un .ko en updates/dkms."
      f_warn PERSIST "r8125 ${KO_VER} < ${NIC_R8125_MIN_VER} para ${GA_KVER}: falso verde, no cubre RTL8125D. NO REINICIAR al GA sin reemplazarlo por el driver del fabricante"
      GA_READY="version_insuficiente" ;;
    3)
      warn "Hay un r8125.ko para ${GA_KVER} pero no declara version - no se puede afirmar que cubra el RTL8125D."
      f_warn PERSIST "r8125 para ${GA_KVER} sin version declarada (${KO_PATH}): verificar a mano con 'modinfo ${KO_PATH}'"
      GA_READY="version_desconocida" ;;
  esac
fi

if BL_FILES=$(nic_r8169_blacklisted); then
  fail "Hay blacklist de r8169 en: $(tr '\n' ' ' <<<"$BL_FILES")"
  f_fail CONFIG "Blacklist de r8169 en $(tr '\n' ' ' <<<"$BL_FILES"): mata las RTL8168/8111 y no hace falta"
else
  ok "Sin blacklist de r8169 en /etc/modprobe.d/"
fi

#===============================================================================
section "RESUMEN"
#===============================================================================
N_FAIL=$(count_sev FAIL); N_SUSP=$(count_sev SUSP); N_WARN=$(count_sev WARN); N_INFO=$(count_sev INFO)

print_block() {
  local blk="$1" titulo="$2" e sev b txt any=0
  for e in ${FINDINGS[@]+"${FINDINGS[@]}"}; do
    sev="${e%%|*}"; b="${e#*|}"; b="${b%%|*}"; txt="${e##*|}"
    [[ "$b" == "$blk" ]] || continue
    if [[ $any -eq 0 ]]; then
      echo -e "\n  ${BOLD}${titulo}${NC}" | tee -a "$LOGFILE"; any=1
    fi
    case "$sev" in
      FAIL) echo -e "    ${RED}[FALLO]${NC}   $txt" | tee -a "$LOGFILE" ;;
      SUSP) echo -e "    ${YELLOW}[SOSPECHA]${NC} $txt" | tee -a "$LOGFILE" ;;
      WARN) echo -e "    ${YELLOW}[AVISO]${NC}   $txt" | tee -a "$LOGFILE" ;;
      *)    echo -e "    ${GREEN}[INFO]${NC}    $txt" | tee -a "$LOGFILE" ;;
    esac
  done
}

print_block LINK    "SALUD ACTUAL DEL LINK"
print_block DRIVER  "DRIVER / HARDWARE"
print_block L3      "DHCP / L3"
print_block PERSIST "PERSISTENCIA TRAS REBOOT"
print_block CONFIG  "RIESGOS DE CONFIGURACION Y PISTAS DE SWITCH"

echo "" | tee -a "$LOGFILE"
log "  Conteo: ${N_FAIL} fallo(s), ${N_SUSP} sospecha(s), ${N_WARN} aviso(s), ${N_INFO} observacion(es)."
if [[ "$N_FAIL" -eq 0 && "$N_SUSP" -eq 0 ]]; then
  ok "Sin fallos ni sospechas. Los avisos son riesgos de configuracion o de persistencia, no fallas actuales."
fi
if [[ "$N_FAIL" -eq 0 && "$N_SUSP" -eq 0 && "$N_WARN" -eq 0 ]]; then
  info "Si el problema persiste igual, lo mas probable es que sea del lado del switch/servidor DHCP."
  info "Coordinar con el equipo de redes usando este log como evidencia."
fi
if [[ "$GA_READY" == "falta" || "$GA_READY" == "version_insuficiente" || "$GA_READY" == "sin_alias" ]]; then
  echo "" | tee -a "$LOGFILE"
  fail "NO REINICIAR al kernel GA todavia: el r8125 no esta listo para el kernel destino (ver CAPA 8)."
fi

#===============================================================================
# Linea CSV para consolidar la flota
#===============================================================================
FINAL_IP=$(ip -br addr show "$IFACE" | awk '{print $3}')
DHCP_STATUS="sin_ip"
[[ -n "$FINAL_IP" && "$FINAL_IP" != *"169.254"* ]] && DHCP_STATUS="ok"

CSV_FILE="./diag-results.csv"
CSV_HEADER="timestamp,hostname,interfaz,kernel,pci_id,xid,driver,driver_verdict,link,zombie_nivel,zombie_score,pvid,dhcp_status,ip,ga_ready,netplan_persistente,netplan_match_mac,conflicto_dhcp_estatica,perfil_generico_riesgo,fallos,sospechas,avisos"
# Si el CSV viene de una version anterior con otras columnas, se aparta en vez
# de mezclar filas con distinto formato (nadie quiere depurar eso en terreno).
if [[ -f "$CSV_FILE" ]] && [[ "$(head -n1 "$CSV_FILE")" != "$CSV_HEADER" ]]; then
  mv "$CSV_FILE" "${CSV_FILE%.csv}-${TS}.csv.bak"
  log "CSV previo con otro formato: se movio a ${CSV_FILE%.csv}-${TS}.csv.bak"
fi
[[ -f "$CSV_FILE" ]] || echo "$CSV_HEADER" > "$CSV_FILE"
echo "${TS},$(hostname),${IFACE},${KVER},${PCI_ID},${XID},${DRIVER},${DRIVER_CODE},${LINK_STATUS},${ZOMBIE_LEVEL},${ZOMBIE_SCORE},${PVID},${DHCP_STATUS},${FINAL_IP:-ninguna},${GA_READY},${NETPLAN_PERSISTENT},${NETPLAN_MATCH_MAC},${DHCP_STATIC_CONFLICT},${ORPHAN_PROFILE_RISK},${N_FAIL},${N_SUSP},${N_WARN}" >> "$CSV_FILE"

log "\nLog completo guardado en: ${LOGFILE}"
[[ -n "$CAPFILE" && -f "$CAPFILE" ]] && log "Captura pcap guardada en: ${CAPFILE}"
log "Linea de resumen agregada a: ${CSV_FILE}"

if   [[ "$N_FAIL" -gt 0 ]]; then exit 3
elif [[ "$N_SUSP" -gt 0 ]]; then exit 2
elif [[ "$N_WARN" -gt 0 ]]; then exit 1
fi
exit 0
