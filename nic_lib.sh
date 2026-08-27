#!/usr/bin/env bash
#===============================================================================
# nic_lib.sh - Conocimiento canonico sobre las NIC Realtek 2.5GbE (10ec:8125)
#
# Existe para que diag-nic.sh y fix-r8125-downgrade-6.8.sh no tengan cada uno
# su propia definicion de "RTL8125D", de "modulo valido" o de "driver activo".
# Antes de este archivo habia tres definiciones distintas en tres scripts.
#
# NO se ejecuta directo: se sourcea.
#     source "$(dirname "$0")/nic_lib.sh"
#
# omnifish-nic-rescue (repo Ubuntu-NVIDIA-Deb-Packages) NO usa esta libreria
# a proposito: es agnostico al XID por diseno fail-safe. Ver Seccion 14 Caso C.
#
# Toda funcion acepta las rutas del sistema como parametro opcional para poder
# probarla contra arboles falsos (self_check_nic_lib.sh).
#===============================================================================
# shellcheck shell=bash
# Las constantes y varios parametros opcionales los consumen los scripts que
# sourcean esta libreria, no la libreria misma.
# shellcheck disable=SC2034,SC2120

# --- Constantes canonicas (fuente: README.md Seccion 9 y Seccion 14 Caso C) ---

# Primera version del driver del fabricante con soporte RTL8125D. El r8125-dkms
# de noble es 9.011.00 y NO la cubre: su switch de deteccion llega hasta la
# revision C y manda el XID 688 a "unknown chip version".
NIC_R8125_MIN_VER="9.014.01"

# PCI ID de la familia Realtek 2.5GbE completa (A, B, C y D comparten ID).
NIC_PCI_ID_8125="10ec:8125"

# XID de la revision D, la unica que el r8169 del GA 6.8 no maneja. El r8169
# igual engancha el device y recien ahi se rinde con "unknown chip XID 688",
# asi que para cuando falla ya no queda nadie para levantar la interfaz.
NIC_XID_8125D="688"

# Revisiones que el r8169 in-tree del GA 6.8 si maneja. Lista de referencia
# para el diagnostico; no se usa para decidir instalaciones.
NIC_XID_8125_ABC="605 641 648"

#--------------------------- Kernel -------------------------------------------

# El unico dato de kernel del que el proyecto tiene evidencia directa es este:
# el track GA 6.8.x no soporta el RTL8125D, y el HWE 7.0.x si. Deliberadamente
# NO se afirma nada sobre los kernels intermedios (6.9 a 6.19): inventar una
# tabla de versiones seria adivinar, y de eso salen los falsos positivos.
nic_kernel_is_ga68() {
    local k="${1:-$(uname -r)}"
    [[ "$k" == 6.8.* ]]
}

# Kernel GA 6.8 mas nuevo con modulos instalados (no solo headers), o vacio.
nic_newest_ga68_installed() {
    local base="${1:-/lib/modules}" d found=()
    for d in "$base"/6.8.*; do
        [[ -d "$d/kernel" ]] && found+=("$(basename "$d")")
    done
    [[ ${#found[@]} -gt 0 ]] || return 1
    printf '%s\n' "${found[@]}" | sort -V | tail -1
}

#--------------------------- Identidad del dispositivo ------------------------

# Driver REALMENTE bindeado al device. Fuente de verdad, equivalente a
# 'ethtool -i <iface>'. Nunca 'lsmod': r8169 y r8125 pueden estar los dos
# cargados a la vez y eso no dice quien maneja la placa.
nic_bound_driver() {
    local iface="$1" base="${2:-/sys/class/net}" p
    # -e y no solo readlink: 'readlink -f' canonicaliza y devuelve 0 aunque el
    # ultimo componente no exista, asi que sin esto un device SIN driver
    # bindeado devolveria un nombre igual. Ese es justo el caso que importa.
    [[ -e "$base/$iface/device/driver" ]] || return 1
    p=$(readlink -f "$base/$iface/device/driver" 2>/dev/null) || return 1
    [[ -n "$p" ]] || return 1
    basename "$p"
}

# Direccion PCI de la interfaz (ej: 0000:07:00.0), o vacio si no es PCI.
nic_pci_addr() {
    local iface="$1" base="${2:-/sys/class/net}" p
    p=$(readlink -f "$base/$iface/device" 2>/dev/null) || return 1
    [[ "$(basename "$p")" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]$ ]] || return 1
    basename "$p"
}

# PCI ID en formato vendor:device, minusculas (ej: 10ec:8125).
nic_pci_id() {
    local iface="$1" base="${2:-/sys/class/net}" v d
    v=$(cat "$base/$iface/device/vendor" 2>/dev/null) || return 1
    d=$(cat "$base/$iface/device/device" 2>/dev/null) || return 1
    printf '%s:%s\n' "${v#0x}" "${d#0x}"
}

#--------------------------- Revision / XID -----------------------------------

# El propio r8169 imprime direccion PCI y XID en la misma linea:
#   r8169 0000:07:00.0 eth1: RTL8125B, 10:7c:61:45:e0:18, XID 641, IRQ 161
# Emite una linea "<pci> <xid>" por device. Sin pipe a grep -q en ningun lado:
# bajo pipefail eso mata al productor con SIGPIPE (141) y da falso negativo.
nic_xid_map() {
    local src="${1:-}" line addr xid
    if [[ -z "$src" ]]; then
        src=$( { dmesg 2>/dev/null || true; journalctl -k -b --no-pager 2>/dev/null || true; } \
               | grep -Ei 'r816[89]|r8125' || true)
    fi
    [[ -n "$src" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == *XID* ]] || continue
        addr=$(grep -oE '[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]' <<<"$line" | head -n1)
        xid=$(grep -oE 'XID [0-9]+' <<<"$line" | grep -oE '[0-9]+' | head -n1)
        [[ -n "$addr" && -n "$xid" ]] && printf '%s %s\n' "$addr" "$xid"
    done <<<"$src"
}

# XID de una direccion PCI concreta. Devuelve vacio y rc=1 si no se pudo
# determinar (dmesg rotado, formato inesperado): ese caso NO es "no es 8125D",
# es "no se sabe", y cada script decide su politica fail-safe.
nic_xid_for_pci() {
    local pci="$1" map xid
    # Se distingue "no me pasaron mapa" de "el mapa vino vacio": con dmesg
    # rotado el mapa vacio es un resultado legitimo y no puede caer de nuevo
    # a leer el dmesg real.
    if [[ $# -ge 2 ]]; then map="$2"; else map=$(nic_xid_map); fi
    xid=$(awk -v p="$pci" '$1==p {print $2; exit}' <<<"$map")
    [[ -n "$xid" ]] || return 1
    printf '%s\n' "$xid"
}

# Nombre legible de la revision a partir del XID.
nic_rev_from_xid() {
    local xid="${1:-}"
    [[ -n "$xid" ]] || { echo "desconocida"; return 1; }
    if [[ "$xid" == "$NIC_XID_8125D" ]]; then
        echo "RTL8125D"
    elif [[ " $NIC_XID_8125_ABC " == *" $xid "* ]]; then
        echo "RTL8125A/B/C"
    else
        echo "no catalogada (XID $xid)"
    fi
}

nic_xid_is_8125d() { [[ "${1:-}" == "$NIC_XID_8125D" ]]; }

#--------------------------- Modulo r8125 para un kernel ----------------------

# Ruta del .ko bajo updates/, que es el arbol que le gana al in-tree. Se busca
# por ARCHIVO y no con 'modinfo -k <kver> r8125': en arboles /lib/modules
# creados solo por dkms, sin paquete de kernel, modinfo por nombre da falsos
# negativos. Este es el criterio que decide si es seguro reiniciar.
nic_r8125_ko() {
    local kver="$1" base="${2:-/lib/modules}"
    find "$base/$kver/updates" -name 'r8125.ko*' -print -quit 2>/dev/null || true
}

# Version que declara el modulo. El paquete del fabricante la expone en
# 'modinfo -F version'; si no la declara devuelve vacio y rc=1.
nic_r8125_ko_version() {
    local ko="$1" v
    v=$(modinfo -F version "$ko" 2>/dev/null | head -n1 | tr -d '[:space:]')
    [[ -n "$v" ]] || return 1
    printf '%s\n' "$v"
}

# El .ko existe Y es suficiente para el RTL8125D.
#
# Este chequeo es el que faltaba en todo el proyecto y era el falso verde mas
# peligroso: el r8125-dkms 9.011.00 de noble tambien deja un r8125.ko en
# updates/dkms/, asi que "existe el .ko" daba por buena una placa rev D que
# igual se quedaba sin red tras el reboot.
#
# Salida por stdout: "<ruta> <version|desconocida>". rc:
#   0 = listo    1 = no existe    2 = existe pero version insuficiente
#   3 = existe pero no declara version (no se puede afirmar que sirva)
nic_r8125_ko_ok() {
    local kver="$1" base="${2:-/lib/modules}" ko ver
    ko=$(nic_r8125_ko "$kver" "$base")
    [[ -n "$ko" ]] || return 1
    if ! ver=$(nic_r8125_ko_version "$ko"); then
        printf '%s desconocida\n' "$ko"
        return 3
    fi
    printf '%s %s\n' "$ko" "$ver"
    dpkg --compare-versions "$ver" ge "$NIC_R8125_MIN_VER" || return 2
    return 0
}

# udev carga el driver al arrancar consultando modules.alias. Que exista el .ko
# no alcanza si depmod no lo indexo.
nic_alias_has_r8125() {
    local kver="$1" base="${2:-/lib/modules}" mods
    mods=$(awk '$1=="alias" && index($2,"pci:v000010ECd00008125")==1 {print $3}' \
           "$base/$kver/modules.alias" 2>/dev/null | sort -u | tr '\n' ' ')
    [[ "$mods" == *r8125* ]]
}

#--------------------------- Blacklist de r8169 -------------------------------

# Blacklistear r8169 es un reflejo comun y aca hace dano: mata las RTL8168/8111
# (10ec:8168), que en placas de dos puertos suelen ser el unico enlace que
# funciona. Tampoco hace falta: los dos modulos declaran el alias del 10ec:8125,
# el device se lo queda el primero cuyo probe funcione, y el r8169 libera el
# device cuando no soporta la revision.
# Imprime los archivos con el blacklist; rc=0 si hay alguno.
nic_r8169_blacklisted() {
    local dir="${1:-/etc/modprobe.d}" hits
    hits=$(grep -rls 'blacklist[[:space:]]\+r8169' "$dir" 2>/dev/null || true)
    [[ -n "$hits" ]] || return 1
    printf '%s\n' "$hits"
}

#===============================================================================
# Reglas de diagnostico (puras: solo hechos entran, un veredicto sale)
#
# Viven aca y no dentro de diag-nic.sh para poder probarlas sin hardware, sin
# root y sin red (self_check_nic_lib.sh). Son reglas explicitas a proposito:
# el proyecto prefiere claridad sobre sofisticacion.
#===============================================================================

# --- Regla del driver ---------------------------------------------------------
#
# El punto de partida es que 'driver activo = r8169' NO es por si solo un
# problema. Lo unico documentado es que el r8169 del GA 6.8 no maneja el
# RTL8125D. Todo lo demas necesita evidencia adicional.
#
#   nic_assess_driver <kver> <pci_id> <xid|?> <driver|?> <link_ok:0|1>
#
# Salida por stdout: "<SEV> <codigo> <texto>"   SEV in OBS | SUSP | FAIL
nic_assess_driver() {
    local kver="$1" pci_id="${2,,}" xid="${3:-?}" drv="${4:-?}" link_ok="${5:-0}"

    if [[ "$drv" == "?" || -z "$drv" ]]; then
        echo "FAIL sin_driver El dispositivo $pci_id no tiene ningun driver bindeado: el del kernel tomo el device y fallo el probe, o no existe modulo para el"
        return 0
    fi

    if [[ "$pci_id" != "$NIC_PCI_ID_8125" ]]; then
        echo "OBS otro_chip $pci_id manejado por $drv; fuera del caso Realtek 2.5GbE de la Seccion 14 Caso C"
        return 0
    fi

    if [[ "$drv" == "r8125" ]]; then
        echo "OBS r8125_bindeado El driver del fabricante r8125 esta bindeado al 10ec:8125, que cubre las revisiones A/B/C/D"
        return 0
    fi

    if [[ "$drv" != "r8169" ]]; then
        echo "OBS driver_inesperado 10ec:8125 manejado por '$drv', que no es ni r8169 ni r8125; revisar a mano"
        return 0
    fi

    # A partir de aca: 10ec:8125 bindeado a r8169.
    if ! nic_kernel_is_ga68 "$kver"; then
        echo "OBS r8169_kernel_no_ga En $kver el r8169 in-tree soporta la familia 8125 completa; r8169 aca es correcto y no hay que instalar nada"
        return 0
    fi

    if nic_xid_is_8125d "$xid"; then
        echo "FAIL r8169_con_8125d RTL8125D (XID $xid) bindeado a r8169 en el GA $kver: el r8169 de este track no lo maneja. Requiere el r8125 del fabricante >= $NIC_R8125_MIN_VER"
        return 0
    fi

    if [[ "$xid" != "?" && -n "$xid" && " $NIC_XID_8125_ABC " == *" $xid "* ]]; then
        echo "OBS r8169_correcto_abc $(nic_rev_from_xid "$xid") (XID $xid) con r8169 en el GA $kver: es el driver correcto, no instalar r8125"
        return 0
    fi

    # XID desconocido o no catalogado. El comportamiento real de la interfaz
    # desempata: si esta recibiendo, el r8169 la esta manejando y punto.
    if [[ "$link_ok" == "1" ]]; then
        echo "OBS r8169_funcionando_xid_desconocido 10ec:8125 con r8169 en el GA $kver y XID '$xid': la interfaz esta operativa, asi que el r8169 la maneja. No hay driver incorrecto"
        return 0
    fi

    echo "SUSP r8169_posible_8125d 10ec:8125 con r8169 en el GA $kver, XID '$xid' y sin trafico: compatible con un RTL8125D no soportado, pero falta confirmarlo (leer el XID en dmesg o probar el r8125 del fabricante)"
}

# --- Regla del estado 'zombie' ------------------------------------------------
#
#   nic_assess_zombie <carrier:0|1> [token ...]
#
# Un rx_packets estatico durante unos segundos es UNA senal, nunca una
# confirmacion. Cada token pesa segun cuanto descarta explicaciones benignas:
#
#   rx_frozen        +1  RX sin cambios en la ventana larga. Una red silenciosa
#                        tambien lo produce, por eso pesa poco.
#   rx_zero          +1  Cero paquetes desde el boot. Mas fuerte que lo anterior
#                        porque ni siquiera vio broadcast/STP al arrancar.
#   irq_frozen       +1  El chip no genero interrupciones: descarta que el
#                        problema sea del stack por encima del driver.
#   no_capture       +2  tcpdump sin filtro no vio NADA con carrier UP. Descarta
#                        casi todas las explicaciones benignas de una vez.
#   watchdog         +2  NETDEV WATCHDOG en este boot: el kernel ya declaro que
#                        la cola de TX se colgo. Evidencia de hardware/driver.
#   tx_active        +1  Estamos transmitiendo y no entra nada: el cable y el
#                        puerto responden lo suficiente como para descartar
#                        "interfaz apagada".
#   capture_traffic  tope duro: si tcpdump vio trafico, el chip recibe. No puede
#                        pasar de SOSPECHOSO por mas senales que haya.
#   rx_active        tope duro, por el mismo motivo: si rx_packets subio en la
#                        ventana, el chip recibe. Vale aunque tcpdump no haya
#                        podido correr (falta el binario, falta permiso).
#
# Salida: "<NIVEL> <score> <detalle>"
# NIVEL: SIN_LINK | NORMAL | SOSPECHOSO | PROBABLE | MUY_FUERTE
nic_assess_zombie() {
    local carrier="${1:-0}"; shift || true
    local score=0 capped=0 t detalle=""

    if [[ "$carrier" != "1" ]]; then
        echo "SIN_LINK 0 sin carrier: el problema es cable/switch/puerto fisico, no un chip colgado"
        return 0
    fi

    for t in "$@"; do
        case "$t" in
            rx_frozen)       score=$((score + 1)); detalle+="rx_frozen(+1) " ;;
            rx_zero)         score=$((score + 1)); detalle+="rx_zero(+1) " ;;
            irq_frozen)      score=$((score + 1)); detalle+="irq_frozen(+1) " ;;
            no_capture)      score=$((score + 2)); detalle+="no_capture(+2) " ;;
            watchdog)        score=$((score + 2)); detalle+="watchdog(+2) " ;;
            tx_active)       score=$((score + 1)); detalle+="tx_active(+1) " ;;
            capture_traffic) capped=1;             detalle+="capture_traffic(tope) " ;;
            rx_active)       capped=1;             detalle+="rx_active(tope) " ;;
            "") ;;
            *) detalle+="$t(ignorado) " ;;
        esac
    done

    # El chip demostro que recibe (por captura o por contador). Nada puede elevar
    # esto por encima de sospecha, y ese es el corte que evita el falso positivo
    # de "rx_packets no subio en 12s".
    if [[ $capped -eq 1 && $score -gt 2 ]]; then
        score=2
        detalle+="[tope aplicado: hubo recepcion demostrada] "
    fi

    local nivel
    if   [[ $score -eq 0 ]]; then nivel="NORMAL"
    elif [[ $score -le 2 ]]; then nivel="SOSPECHOSO"
    elif [[ $score -le 4 ]]; then nivel="PROBABLE"
    else                          nivel="MUY_FUERTE"
    fi
    echo "$nivel $score ${detalle:-sin senales}"
}
