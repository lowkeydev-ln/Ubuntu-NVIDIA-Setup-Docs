#!/usr/bin/env bash
#===============================================================================
# fix-r8125-downgrade-6.8.sh
#
# Flota OmniFish - Ubuntu 24.04 LTS
#
# FASE 0: Comprueba conectividad. Si hay acceso a repos de Ubuntu y/o GitHub,
#   los paquetes se resuelven online (apt / wget). Si no, modo offline
#   con .deb previamente copiados por scp a $DEB_DIR.
#
# FASE 1 (condicional): Detecta si la placa tiene un NIC Realtek RTL8125D
#   (XID 688), que el r8169 in-tree del kernel 6.8 NO soporta. Si lo detecta
#   y el modulo r8125 DKMS no esta construido para el kernel objetivo,
#   instala el paquete .deb local (entorno sin internet) y lo compila
#   contra los headers 6.8 ANTES de reiniciar. Asi el equipo no queda
#   sin red al bajar de kernel.
#
# FASE 2 (incondicional): Downgrade al track GA (6.8.x):
#   - Verifica imagen y headers 6.8 instalados
#   - Pin de apt para bloquear el track HWE (7.0.x)
#   - Hold de paquetes via dpkg --set-selections
#   - grub-reboot (arranque one-shot seguro) hacia 6.8
#
# USO:
#   sudo ./fix-r8125-downgrade-6.8.sh [--dry-run]
#
# REQUISITO OFFLINE: dejar el .deb del driver en $DEB_DIR antes de ejecutar:
#   realtek-r8125-dkms_9.016.01-1_amd64.deb (o superior, minimo 9.014.01)
#===============================================================================
set -euo pipefail

#--------------------------- Configuracion ------------------------------------
TARGET_KVER="6.8.0-137-generic"          # kernel GA objetivo
DEB_DIR="/opt/omnifish/debs"             # donde se copian los .deb por scp
R8125_DEB_VER="9.016.01-1"               # version a descargar de GitHub si hay red (min 9.014.01)
PIN_FILE="/etc/apt/preferences.d/99-omnifish-pin-ga-kernel"
LOG_FILE="/var/log/omnifish-kernel-downgrade.log"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

#--------------------------- Libreria compartida ------------------------------
# nic_lib.sh tiene el conocimiento canonico de revisiones Realtek y, sobre todo,
# la validacion de VERSION del r8125.ko. Antes cada script tenia su propia idea
# de "el modulo ya esta", y la de este daba por bueno el r8125-dkms 9.011.00 de
# noble, que no soporta el RTL8125D.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/nic_lib.sh" ]]; then
    echo "Falta nic_lib.sh junto a este script. Copia el repo completo, no solo este archivo." >&2
    exit 1
fi
# shellcheck source=nic_lib.sh
source "$SCRIPT_DIR/nic_lib.sh"

#--------------------------- Utilidades ---------------------------------------
log()  { echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die()  { log "ERROR: $*"; exit 1; }
run()  {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "(dry-run) $*"
    else
        log "+ $*"
        # eval a proposito: run() recibe la orden como texto, con pipes y
        # redirecciones incluidas (ej: run "echo '$p hold' | dpkg --set-selections").
        # shellcheck disable=SC2294
        eval "$@" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# Escribe el archivo SOLO si el contenido difiere del que ya esta en disco.
# Contenido por stdin. Segundo argumento opcional: modo (default 0644).
#   rc 0 = el archivo cambio  -> hay que recargar/reiniciar lo que dependa de el
#   rc 1 = ya estaba igual    -> no se toco nada
#
# Este script se reejecuta seguido (una fase falla, se corrige algo, se vuelve a
# correr). Sin esto, cada corrida reescribia archivos identicos y disparaba un
# update-initramfs (~30s), un udevadm reload y un daemon-reload que no hacian
# falta. En dry-run no escribe nada y reporta si HABRIA cambiado.
write_if_changed() {
    local dest="$1" modo="${2:-0644}" tmp rc=0
    tmp=$(mktemp)
    cat >"$tmp"
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        log "(dry-run) escribiria $dest"
    else
        install -D -m "$modo" "$tmp" "$dest" || rc=1
    fi
    rm -f "$tmp"
    return $rc
}

[[ $EUID -eq 0 ]] || die "Ejecutar como root (sudo)."
touch "$LOG_FILE" || die "No se puede escribir $LOG_FILE"

log "================================================================"
log "Inicio - host: $(hostname) - kernel actual: $(uname -r)"
[[ $DRY_RUN -eq 1 ]] && log "MODO DRY-RUN: no se aplican cambios"
log "================================================================"

#===============================================================================
# FASE 0: Comprobacion de acceso a red / internet
#===============================================================================
log ""
log "--- FASE 0: Comprobacion de conectividad ---"

ONLINE_APT=0     # alcanza los repos de Ubuntu -> puede usar apt
ONLINE_GH=0      # alcanza GitHub -> puede bajar el deb del driver

tcp_check() { timeout 6 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }

if tcp_check archive.ubuntu.com 80 || tcp_check security.ubuntu.com 80; then
    ONLINE_APT=1
    log "OK: acceso a repos de Ubuntu -> los paquetes de kernel se resolveran via apt."
else
    log "SIN acceso a repos de Ubuntu -> modo offline: se usaran .deb de $DEB_DIR."
fi
if tcp_check github.com 443; then
    ONLINE_GH=1
    log "OK: acceso a GitHub -> el deb del driver puede descargarse directo."
else
    log "SIN acceso a GitHub -> el deb del driver debe estar en $DEB_DIR."
fi

APT_UPDATED=0
apt_update_once() {
    [[ $APT_UPDATED -eq 1 ]] && return 0
    run "apt-get update"
    APT_UPDATED=1
}

# Ubica el .ko de r8125 VALIDO para un kernel dado. Busca por archivo bajo
# updates/ (que es el arbol que le gana al in-tree) y no por 'modinfo -k <kver>
# r8125', que da falsos negativos en arboles creados solo por dkms.
#
# Ademas exige version >= $NIC_R8125_MIN_VER. Sin ese filtro, el r8125.ko del
# r8125-dkms 9.011.00 de noble contaba como "ya esta listo" y el script daba
# via libre al reboot con una placa rev D que iba a quedar sin red.
# Devuelve ruta vacia si no hay modulo utilizable.
r8125_ko_path() {
    local info rc=0
    info=$(nic_r8125_ko_ok "$1") || rc=$?
    [[ $rc -eq 0 ]] || return 0
    awk '{print $1}' <<<"$info"
}

#===============================================================================
# FASE 1: Analisis y remediacion condicional del driver Ethernet
#===============================================================================
log ""
log "--- FASE 1: Analisis del NIC Realtek 8125 ---"

NEEDS_R8125=0
REQUIRED_R8125=0   # queda en 1 si la maquina NECESITA r8125 en 6.8 (para re-verificar tras Fase 2)
OVERRIDE_PCI_LIST=()   # direcciones PCI que necesitan driver_override -> r8125 (r8169 SI las reclama)

# Revisiones de RTL8125 catalogadas por XID:
#   NATIVE_REJECT_XIDS: r8169 de 6.8 las rechaza el solo (-ENODEV) y r8125
#     las toma sin competir con nadie. No requiere ninguna accion de binding.
#   OVERRIDE_XIDS: r8169 de 6.8 SI las reclama con exito, pero la flota ha
#     confirmado en campo que necesitan r8125 igual. Para estas NO alcanza
#     con instalar el driver: hay que forzar el binding via 'driver_override'
#     scoped a la direccion PCI exacta (nunca blacklist global de r8169,
#     que rompería otros Realtek de la misma placa, ej. RTL8168h).
#   Si aparece una revision nueva con problemas confirmados, agregar su XID
#   a OVERRIDE_XIDS aca.
NATIVE_REJECT_XIDS="$NIC_XID_8125D"          # 688, definido en nic_lib.sh
OVERRIDE_XIDS="${OMNIFISH_OVERRIDE_XIDS:-641}"

# NOTA SOBRE OVERRIDE_XIDS="641" - CONTRADICCION ABIERTA CON EL MANUAL
#   El manual (Seccion 9 y Seccion 14 Caso C) y el gate de omnifish-nvidia-setup
#   tratan el XID 641 (RTL8125B) como una revision que el r8169 del GA 6.8
#   maneja bien; --skip-nic-check la cita explicitamente como el caso seguro.
#   Aca esta catalogada como necesitando r8125 por evidencia de campo.
#
#   Se mantiene porque la asimetria de costo favorece el override: el driver del
#   fabricante cubre A/B/C/D, asi que forzarlo en un 8125B es inocuo, y no
#   forzarlo en una placa que si lo necesita significa perder la red tras un
#   reboot remoto. Es el mismo criterio fail-safe de omnifish-nic-rescue.
#
#   Riesgo residual, a tener presente: driver_override ELIMINA el fallback a
#   r8169. Si un update de kernel deja el DKMS sin recompilar, ese device queda
#   sin ningun driver. Por eso el gate de FASE 5 exige el .ko antes de armar el
#   reboot, y los doctor verifican DKMS contra el kernel en ejecucion.
#
#   Para desactivarlo en un equipo puntual, sin editar el script:
#     sudo OMNIFISH_OVERRIDE_XIDS="" ./fix-r8125-downgrade-6.8.sh

xid_in_list() {
    local needle=" $1 " hay=" $2 "
    [[ "$hay" == *"$needle"* ]]
}

# 1a. ¿Existe fisicamente un dispositivo 10ec:8125? (puede haber mas de uno)
if lspci -n | grep -qi '10ec:8125'; then
    PCI_ADDRS=$(lspci -Dn | grep -i '10ec:8125' | awk '{print $1}' | tr '\n' ' ')
    log "Detectado(s) NIC(s) 10ec:8125 en: $PCI_ADDRS"

    # Auditoria: registrar los XID que reporto r8169 en este arranque
    XID_LINES=$(dmesg | grep -Ei 'r8169.*XID' || journalctl -k -b 2>/dev/null | grep -Ei 'r8169.*XID' || true)
    [[ -n "$XID_LINES" ]] && log "XIDs reportados por r8169:\n$XID_LINES"

    # 1b. Parsear XID POR DIRECCION PCI (el propio log de r8169 trae ambos
    #     datos en la misma linea, ej: "r8169 0000:0d:00.0 eth0: RTL8125B,
    #     d8:..:e6, XID 641, IRQ 51"). Evaluado sobre $XID_LINES (variable
    #     ya capturada, sin pipe) por el mismo motivo de pipefail/SIGPIPE
    #     documentado mas abajo en la verificacion de XID 688 historica.
    declare -A PCI_XID_MAP=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        addr=$(grep -oE '[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]' <<< "$line" | head -n1)
        xid=$(grep -oE 'XID [0-9]+' <<< "$line" | grep -oE '[0-9]+' | head -n1)
        [[ -n "$addr" && -n "$xid" ]] && PCI_XID_MAP["$addr"]="$xid"
    done <<< "$XID_LINES"

    if [[ -z "$XID_LINES" ]]; then
        # Sin evidencia de XID (dmesg rotado y sin journal): no se puede
        # descartar ninguna revision problematica. Fail-safe: instalar el
        # driver Y aplicar override a TODAS las direcciones 8125 detectadas,
        # porque el costo de no tenerlo es perder la red tras el downgrade.
        log "ADVERTENCIA: hay NIC(s) 8125 pero no se pudo leer ningun XID (dmesg rotado?)."
        log "Fail-safe: se instalara r8125 y se forzara override en: $PCI_ADDRS"
        NEEDS_R8125=1
        REQUIRED_R8125=1
        for pci in $PCI_ADDRS; do OVERRIDE_PCI_LIST+=("$pci"); done
    else
        for pci in $PCI_ADDRS; do
            xid="${PCI_XID_MAP[$pci]:-}"
            if [[ -z "$xid" ]]; then
                log "  $pci: XID no encontrado para esta direccion especifica (formato de log inesperado?)."
                log "  Fail-safe: se tratara como necesitando override explicito."
                NEEDS_R8125=1
                REQUIRED_R8125=1
                OVERRIDE_PCI_LIST+=("$pci")
            elif xid_in_list "$xid" "$NATIVE_REJECT_XIDS"; then
                log "  $pci: XID $xid - r8169 de 6.8 lo rechaza nativamente (-ENODEV). Coexistencia pacifica, sin override."
                NEEDS_R8125=1
                REQUIRED_R8125=1
            elif xid_in_list "$xid" "$OVERRIDE_XIDS"; then
                log "  $pci: XID $xid - r8169 SI lo reclama, pero esta catalogado en la flota como necesitando r8125 (evidencia de campo). Se forzara override."
                NEEDS_R8125=1
                REQUIRED_R8125=1
                OVERRIDE_PCI_LIST+=("$pci")
            else
                log "  $pci: XID $xid - revision no catalogada como problematica. r8169 in-tree de 6.8 deberia soportarla; no se fuerza r8125."
                log "  (Si esta revision presenta fallas a futuro, agregar XID $xid a OVERRIDE_XIDS en este script.)"
            fi
        done
    fi
else
    log "No hay NIC 10ec:8125 en esta placa. No se requiere accion de driver."
fi

# 1c. ¿Ya esta un modulo r8125 UTILIZABLE construido para el kernel objetivo?
if [[ $NEEDS_R8125 -eq 1 ]]; then
    KO_RC=0
    KO_INFO=$(nic_r8125_ko_ok "$TARGET_KVER") || KO_RC=$?
    KO_PRE=$(awk '{print $1}' <<<"$KO_INFO")
    KO_VER=$(awk '{print $2}' <<<"$KO_INFO")
    case $KO_RC in
        0) log "OK: r8125 $KO_VER ya existe para $TARGET_KVER ($KO_PRE). Nada que compilar."
           NEEDS_R8125=0 ;;
        1) log "No hay r8125.ko bajo /lib/modules/$TARGET_KVER/updates: hay que instalarlo." ;;
        2) log "ADVERTENCIA: hay un r8125 $KO_VER para $TARGET_KVER, MENOR que $NIC_R8125_MIN_VER."
           log "  Es el r8125-dkms de noble: no cubre el RTL8125D (manda el XID 688 a 'unknown chip version')."
           log "  Se reemplaza por el del fabricante." ;;
        3) log "ADVERTENCIA: hay un r8125.ko en $KO_PRE que no declara version."
           log "  No se puede afirmar que cubra la rev D; se instala el del fabricante igual." ;;
    esac
fi

# 1d. Instalacion offline del paquete DKMS
if [[ $NEEDS_R8125 -eq 1 ]]; then
    # Headers del kernel objetivo son prerequisito de compilacion.
    if ! dpkg -s "linux-headers-$TARGET_KVER" &>/dev/null; then
        if [[ $ONLINE_APT -eq 1 ]]; then
            apt_update_once
            run "apt-get install -y --no-install-recommends linux-headers-$TARGET_KVER"
        else
            HDEBS=$(ls -1 "$DEB_DIR"/linux-headers-*"${TARGET_KVER%%-generic}"*.deb 2>/dev/null || true)
            [[ -n "$HDEBS" ]] || die "Faltan linux-headers-$TARGET_KVER y no hay .deb en $DEB_DIR (sin red)."
            run "dpkg -i $DEB_DIR/linux-headers-*${TARGET_KVER%%-generic}*.deb"
        fi
        dpkg -s "linux-headers-$TARGET_KVER" &>/dev/null \
            || die "No se pudieron instalar los headers de $TARGET_KVER."
    fi

    # Obtener el .deb del driver: primero local, si no hay y hay red -> GitHub
    DEB=$(ls -1 "$DEB_DIR"/realtek-r8125-dkms_*.deb 2>/dev/null | sort -V | tail -n1 || true)
    if [[ -z "$DEB" && $ONLINE_GH -eq 1 ]]; then
        log "No hay deb local del driver; descargando desde GitHub..."
        mkdir -p "$DEB_DIR"
        R8125_URL="https://github.com/awesometic/realtek-r8125-dkms/releases/download/${R8125_DEB_VER}/realtek-r8125-dkms_${R8125_DEB_VER}_amd64.deb"
        run "wget -q -O '$DEB_DIR/realtek-r8125-dkms_${R8125_DEB_VER}_amd64.deb' '$R8125_URL'"
        DEB="$DEB_DIR/realtek-r8125-dkms_${R8125_DEB_VER}_amd64.deb"
    fi
    [[ -n "$DEB" && -s "$DEB" ]] || die "No se encontro realtek-r8125-dkms_*.deb en $DEB_DIR y no hay acceso a GitHub. Copiarlo por scp desde una maquina con internet."

    # Version minima con soporte 8125D
    DEB_VER=$(dpkg-deb -f "$DEB" Version | cut -d- -f1)
    if dpkg --compare-versions "$DEB_VER" lt "$NIC_R8125_MIN_VER"; then
        die "El paquete es $DEB_VER; se requiere >= $NIC_R8125_MIN_VER para soportar RTL8125D."
    fi

    # El r8125-dkms de noble (9.011.00) tiene que salir del camino: su switch de
    # deteccion llega hasta la revision C y manda el XID 688 a 'unknown chip
    # version'. Si queda instalado junto al del fabricante habria dos modulos
    # reclamando el 10ec:8125. Mismo criterio que omnifish-nic-rescue.
    if [[ "$(dpkg-query -W -f='${Status}' r8125-dkms 2>/dev/null || true)" == *" ok installed" ]]; then
        UB_VER=$(dpkg-query -W -f='${Version}' r8125-dkms 2>/dev/null | cut -d- -f1)
        if dpkg --compare-versions "$UB_VER" lt "$NIC_R8125_MIN_VER"; then
            log "r8125-dkms $UB_VER de Ubuntu no soporta RTL8125D (min $NIC_R8125_MIN_VER); se remueve."
            run "apt-get purge -y r8125-dkms"
        else
            log "r8125-dkms $UB_VER ya alcanza el minimo $NIC_R8125_MIN_VER; se deja."
        fi
    fi

    # ESCENARIO 7.0 -> 6.8: este script corre normalmente sobre el kernel 7.0.
    # El postinst del paquete intenta compilar para el kernel CORRIENDO (7.0),
    # y el driver vendor puede fallar contra APIs de kernels nuevos. Ese fallo
    # NO importa: en 7.0 el r8169 in-tree ya soporta el 8125D. Lo unico critico
    # es que el modulo quede compilado para 6.8. Por eso se tolera el error de
    # dpkg y luego se fuerza el ciclo dkms explicitamente contra 6.8.
    log "Instalando $DEB (version $DEB_VER)..."
    log "(nota: si el build para el kernel corriendo $(uname -r) falla, se ignora)"
    if [[ $DRY_RUN -eq 0 ]]; then
        dpkg -i "$DEB" 2>&1 | tee -a "$LOG_FILE" || \
            log "dpkg reporto error (probable fallo de build para $(uname -r)); continuando..."
    else
        log "(dry-run) dpkg -i '$DEB'"
    fi

    # El modulo debe quedar al menos registrado en el arbol dkms.
    # OJO: el paquete de awesometic lo registra como 'realtek-r8125' (no 'r8125'),
    # aunque el .ko final si se llama r8125.ko. Detectar el nombre dinamicamente.
    DKMS_LINE=$(dkms status 2>/dev/null | grep -E '^(realtek-)?r8125[/,]' | head -n1 || true)
    if [[ -z "$DKMS_LINE" && $DRY_RUN -eq 0 ]]; then
        # dpkg fallo antes de registrar: agregar el source manualmente
        SRC_DIR=$(ls -d /usr/src/*r8125-* 2>/dev/null | sort -V | tail -n1 || true)
        [[ -n "$SRC_DIR" ]] || die "dkms no registro el modulo y no hay source *r8125* en /usr/src. Revisar $LOG_FILE."
        SRC_BASE=$(basename "$SRC_DIR")               # ej: realtek-r8125-9.016.01
        DKMS_NAME="${SRC_BASE%-*}"                    # ej: realtek-r8125
        DKMS_VER="${SRC_BASE##*-}"                    # ej: 9.016.01
        run "dkms add $DKMS_NAME/$DKMS_VER || true"
        DKMS_LINE=$(dkms status 2>/dev/null | grep -E '^(realtek-)?r8125[/,]' | head -n1 || true)
    fi
    if [[ $DRY_RUN -eq 0 ]]; then
        [[ -n "$DKMS_LINE" ]] || die "No se pudo registrar el modulo r8125 en dkms."
        DKMS_NAME=$(sed -E 's|^([^/,]+).*|\1|' <<< "$DKMS_LINE")
        DKMS_VER=$(sed -E 's|^[^/,]+[/,] *([^,: ]+).*|\1|' <<< "$DKMS_LINE")
        log "Modulo dkms detectado: $DKMS_NAME version $DKMS_VER"
    else
        DKMS_NAME="realtek-r8125"; DKMS_VER="$R8125_DEB_VER"
    fi

    # Build + install SOLO contra el kernel objetivo 6.8 (nunca modprobe en 7.0:
    # ahi r8169 in-tree ya maneja el chip y no queremos dos drivers compitiendo)
    if [[ $DRY_RUN -eq 0 ]]; then
        if ! dkms status "$DKMS_NAME/$DKMS_VER" -k "$TARGET_KVER" 2>/dev/null | grep -q installed; then
            run "dkms build $DKMS_NAME/$DKMS_VER -k $TARGET_KVER"
            run "dkms install $DKMS_NAME/$DKMS_VER -k $TARGET_KVER"
        fi
    else
        log "(dry-run) dkms build/install $DKMS_NAME -k $TARGET_KVER"
    fi

    # Verificacion final: SOLO importa el estado para 6.8. Se verifica por
    # archivo y por ruta directa (no por nombre via indice, que dio falsos
    # negativos), y se valida el alias PCI que udev usara al arrancar en 6.8.
    if [[ $DRY_RUN -eq 0 ]]; then
        KO=$(r8125_ko_path "$TARGET_KVER")
        if [[ -z "$KO" ]]; then
            log "DIAGNOSTICO: contenido de /lib/modules/$TARGET_KVER:"
            ls -la "/lib/modules/$TARGET_KVER/" 2>&1 | tee -a "$LOG_FILE" || true
            die "No existe r8125.ko para $TARGET_KVER. NO REINICIAR: el equipo quedaria sin red en 6.8."
        fi
        modinfo "$KO" &>/dev/null \
            || die "El archivo $KO existe pero no es un modulo valido. NO REINICIAR."
        run "depmod -a $TARGET_KVER"
        # udev carga el driver al boot via modules.alias: verificar el alias PCI
        if grep -Eq '10EC.*8125.* r8125$' "/lib/modules/$TARGET_KVER/modules.alias" 2>/dev/null; then
            log "OK: r8125 listo para $TARGET_KVER ($KO) con alias PCI registrado."
        else
            log "ADVERTENCIA: no se encontro el alias PCI de r8125 en modules.alias."
            log "Verificar manualmente antes de reiniciar: grep 8125 /lib/modules/$TARGET_KVER/modules.alias"
        fi
        log "(no se carga r8125 en el kernel actual: en $(uname -r) el 8125D ya funciona con r8169 in-tree)"
    fi

else
    log "FASE 1: sin acciones de instalacion necesarias."
fi

#===============================================================================
# FASE 1b: binding del driver. Se ejecuta siempre que la maquina REQUIERA r8125,
# no solo cuando hubo que instalarlo.
#
# Antes esto vivia dentro del bloque de instalacion, asi que en la segunda
# corrida (con el .ko ya construido) el script dejaba de sacar un blacklist de
# r8169 y dejaba de aplicar el override: no era idempotente y perdia justo las
# protecciones que justifican su existencia.
#===============================================================================
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    log ""
    log "--- FASE 1b: blacklist y binding del driver ---"

    # CRITICO en esta flota: el paquete vendor puede blacklistear r8169, lo que
    # mataria el NIC secundario RTL8168h (unico enlace funcional en 6.8). Para
    # XID 688 no hace falta nada mas: r8169 lo rechaza solo (-ENODEV). Para las
    # revisiones en OVERRIDE_XIDS (r8169 SI las reclama), el binding se fuerza
    # mas abajo via driver_override scoped a la direccion PCI exacta - nunca via
    # blacklist global, que es lo que este bloque protege.
    # Se captura en variable, sin "grep -rls | grep -q": ese pipeline muere con
    # SIGPIPE (141) bajo pipefail y dejaria el blacklist puesto.
    if BL_FILES=$(nic_r8169_blacklisted); then
        log "ATENCION: se detecto blacklist de r8169. Eliminandolo (protege el RTL8168h)..."
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            run "sed -i '/blacklist[[:space:]]\+r8169/d' '$f'"
        done <<< "$BL_FILES"
        run "update-initramfs -u -k $TARGET_KVER"
    else
        log "OK: no hay blacklist de r8169 en /etc/modprobe.d/."
    fi

    # Override de driver por direccion PCI exacta, SOLO para las revisiones
    # que r8169 reclama con exito (OVERRIDE_PCI_LIST, ver 1b). Usa el mismo
    # mecanismo que la herramienta 'driverctl' (driver_override en sysfs +
    # regla udev), pero sin depender de tenerla instalada. Scoped a la
    # direccion PCI: nunca afecta a otros Realtek de la misma placa.
    if [[ ${#OVERRIDE_PCI_LIST[@]} -gt 0 ]]; then
        log "Aplicando override de driver (r8125) para: ${OVERRIDE_PCI_LIST[*]}"
        for pci in "${OVERRIDE_PCI_LIST[@]}"; do
            RULE_FILE="/etc/udev/rules.d/90-omnifish-r8125-override-$(tr ':.' '__' <<< "$pci").rules"
            if echo "ACTION==\"add\", SUBSYSTEM==\"pci\", KERNEL==\"$pci\", DRIVER==\"r8169\", ATTR{driver_override}=\"r8125\"" \
               | write_if_changed "$RULE_FILE"; then
                log "  OK: $RULE_FILE escrito para $pci."
                if [[ $DRY_RUN -eq 0 ]]; then
                    run "udevadm control --reload-rules" \
                        || log "ADVERTENCIA: fallo recargar reglas udev; el override tomara efecto igual en el proximo boot via $RULE_FILE."
                fi
            else
                log "  OK: $RULE_FILE ya estaba correcto para $pci; no se recargan reglas udev."
            fi
            # Best-effort para el kernel actual (normalmente no aplica: en 7.0 el
            # 8125D ya funciona con r8169; el efecto real de esta regla es tras
            # el reboot, cuando 6.8 intente bindear el chip). Idempotente.
            if [[ $DRY_RUN -eq 0 ]]; then
                echo "r8125" > "/sys/bus/pci/devices/$pci/driver_override" 2>/dev/null || true
            fi
        done
    else
        log "Sin direcciones PCI que requieran override explicito de driver."
    fi
else
    log ""
    log "--- FASE 1b: no aplica (esta maquina no requiere r8125) ---"
fi

#===============================================================================
# FASE 1.5: Hardening ASPM/EEE del driver r8125 (opcional, no bloqueante)
#
# Motivo: en la flota se observo un patron de NETDEV WATCHDOG recurrente
# ("transmit queue 0 timed out") en equipos con r8125, cada ~90-100 min,
# coincidiendo con contencion de CPU (ver 'workqueue ... hogged CPU' en
# dmesg). Eventualmente el chip queda 'zombie' (rx_packets estancado en 0
# con link UP) sin autorepararse. Deshabilitar ASPM y EEE es la mitigacion
# recomendada por el propio driver vendor para este patron de inestabilidad.
# Esto NO reemplaza el watchdog de auto-sanacion (FASE 3): es prevencion,
# el watchdog es la red de seguridad si igual ocurre.
#===============================================================================
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    log ""
    log "--- FASE 1.5: Hardening ASPM/EEE del driver r8125 ---"
    R8125_OPTS_FILE="/etc/modprobe.d/omnifish-r8125-options.conf"
    KO_FOR_OPTS=$(r8125_ko_path "$TARGET_KVER")

    if [[ -n "$KO_FOR_OPTS" ]]; then
        SUPPORTED_PARAMS=""
        for p in aspm eee_enable; do
            if modinfo "$KO_FOR_OPTS" 2>/dev/null | grep -q "^parm:[[:space:]]*${p}:"; then
                SUPPORTED_PARAMS="${SUPPORTED_PARAMS}${p}=0 "
            else
                log "Parametro '$p' no reportado por modinfo para esta version del driver; se omite."
            fi
        done

        if [[ -n "$SUPPORTED_PARAMS" ]]; then
            # update-initramfs tarda ~30s: solo si el archivo realmente cambio.
            if echo "options r8125 ${SUPPORTED_PARAMS}" | write_if_changed "$R8125_OPTS_FILE"; then
                log "Escrito $R8125_OPTS_FILE con: ${SUPPORTED_PARAMS}"
                run "update-initramfs -u -k $TARGET_KVER" \
                    || log "ADVERTENCIA: fallo update-initramfs tras escribir $R8125_OPTS_FILE; verificar manualmente."
            else
                log "OK: $R8125_OPTS_FILE ya tenia '${SUPPORTED_PARAMS}'; no se regenera el initramfs."
            fi
        else
            log "Ningun parametro de hardening soportado por esta version del driver; se omite."
        fi
    else
        log "No se encontro r8125.ko para $TARGET_KVER; se omite hardening (revisar FASE 1)."
    fi
else
    log ""
    log "--- FASE 1.5: no aplica (esta maquina no requiere r8125) ---"
fi

#===============================================================================
# FASE 2: Downgrade de kernel al track GA 6.8 (siempre se ejecuta)
#===============================================================================
log ""
log "--- FASE 2: Downgrade y pin del kernel a $TARGET_KVER ---"

# 2a. Imagen y headers del kernel objetivo. Si faltan, intentar instalarlos
#     offline desde $DEB_DIR (deben haberse copiado por scp previamente):
#     linux-image-, linux-modules-, linux-modules-extra-, linux-headers-6.8.0-137*
KPKGS=("linux-image-$TARGET_KVER" "linux-modules-$TARGET_KVER" \
       "linux-modules-extra-$TARGET_KVER" "linux-headers-$TARGET_KVER")

# Estado REAL del paquete. Un paquete a medio configurar (postinst fallido)
# figura instalado para 'dpkg -s' pero no tiene initramfs/grub generados -> hay
# que tratarlo como roto.
# El patron es '* ok installed' y no 'install ok installed' exacto: un paquete
# en hold reporta "hold ok installed", y exigir el literal lo daba por roto.
# Mismo criterio que omnifish-nic-rescue; este script pone paquetes en hold en
# la FASE 2c, asi que el caso no es hipotetico.
pkg_ok()     { [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == *" ok installed" ]]; }
pkg_exists() { dpkg-query -W "$1" &>/dev/null; }

# Nombre/version del modulo dkms r8125 registrado (si existe)
r8125_dkms_id() {
    dkms status 2>/dev/null | grep -E '^(realtek-)?r8125[/,]' | head -n1 \
        | sed -E 's|^([^/,]+)[/,] *([^,: ]+).*|\1/\2|' || true
}

# Recuperacion del fallo tipico: el autoinstall dkms del postinst de
# linux-image choca con un r8125.ko que nosotros instalamos antes
# ("already installed ... override by specifying --force") y deja
# linux-image a medio configurar.
kernel_configure_recovery() {
    local id; id=$(r8125_dkms_id)
    if [[ -n "$id" ]]; then
        log "Recuperacion: forzando reinstalacion dkms de $id para $TARGET_KVER..."
        dkms install "$id" -k "$TARGET_KVER" --force 2>&1 | tee -a "$LOG_FILE" || true
    fi
    log "Recuperacion: completando configuracion pendiente de dpkg..."
    dpkg --configure -a 2>&1 | tee -a "$LOG_FILE" || true
}

MISSING=(); BROKEN=()
for pkg in "${KPKGS[@]}"; do
    if ! pkg_exists "$pkg"; then
        MISSING+=("$pkg")
    elif ! pkg_ok "$pkg"; then
        BROKEN+=("$pkg")
    fi
done

# Paquetes a medio configurar de una corrida anterior: repararlos primero
if [[ ${#BROKEN[@]} -gt 0 && $DRY_RUN -eq 0 ]]; then
    log "Paquetes a medio configurar detectados: ${BROKEN[*]}"
    kernel_configure_recovery
    for pkg in "${BROKEN[@]}"; do
        pkg_ok "$pkg" || die "$pkg sigue a medio configurar tras la recuperacion. Revisar $LOG_FILE."
    done
    log "OK: configuracion pendiente reparada."
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log "Faltan paquetes del kernel objetivo: ${MISSING[*]}"

    # PREVENCION del conflicto dkms: si vamos a instalar linux-image y ya
    # existe un r8125.ko puesto por nosotros en el arbol del kernel objetivo,
    # retirarlo de dkms para ese kernel. El autoinstall del postinst lo
    # recompila e instala limpio como parte de la instalacion del kernel.
    if [[ " ${MISSING[*]} " == *"linux-image-"* && $DRY_RUN -eq 0 ]]; then
        DKMS_ID=$(r8125_dkms_id)
        if [[ -n "$DKMS_ID" && -n "$(r8125_ko_path "$TARGET_KVER")" ]]; then
            log "Prevencion: retirando $DKMS_ID de $TARGET_KVER para que el postinst del kernel lo reinstale limpio..."
            dkms remove "$DKMS_ID" -k "$TARGET_KVER" 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi

    INSTALL_RC=0
    if [[ $ONLINE_APT -eq 1 ]]; then
        log "Instalando via apt (hay acceso a repos)..."
        apt_update_once
        if [[ $DRY_RUN -eq 0 ]]; then
            set +e
            apt-get install -y --no-install-recommends "${MISSING[@]}" 2>&1 | tee -a "$LOG_FILE"
            INSTALL_RC=${PIPESTATUS[0]}
            set -e
        else
            log "(dry-run) apt-get install ${MISSING[*]}"
        fi
    else
        KDEBS=$(ls -1 "$DEB_DIR"/linux-*"${TARGET_KVER%%-generic}"*.deb 2>/dev/null || true)
        [[ -n "$KDEBS" ]] || die "Sin red y sin .deb del kernel 6.8 en $DEB_DIR. En una maquina con internet: apt-get download ${KPKGS[*]} linux-headers-${TARGET_KVER%%-generic} y copiarlos por scp."
        log "Instalando .deb del kernel desde $DEB_DIR (modo offline)..."
        if [[ $DRY_RUN -eq 0 ]]; then
            set +e
            dpkg -i "$DEB_DIR"/linux-*"${TARGET_KVER%%-generic}"*.deb 2>&1 | tee -a "$LOG_FILE"
            INSTALL_RC=${PIPESTATUS[0]}
            set -e
        else
            log "(dry-run) dpkg -i $DEB_DIR/linux-*.deb"
        fi
    fi

    # Si el postinst fallo (tipicamente por dkms), recuperar en vez de abortar
    if [[ $INSTALL_RC -ne 0 && $DRY_RUN -eq 0 ]]; then
        log "La instalacion del kernel devolvio error ($INSTALL_RC); intentando recuperacion..."
        kernel_configure_recovery
    fi

    for pkg in "${KPKGS[@]}"; do
        [[ $DRY_RUN -eq 1 ]] && break
        pkg_ok "$pkg" || die "$pkg no quedo correctamente instalado/configurado. Revisar $LOG_FILE."
    done
fi

# Estado final del kernel objetivo: binario, initramfs y (si aplica) el driver
if [[ $DRY_RUN -eq 0 ]]; then
    [[ -f "/boot/vmlinuz-$TARGET_KVER" ]] || die "No existe /boot/vmlinuz-$TARGET_KVER"
    if [[ ! -f "/boot/initrd.img-$TARGET_KVER" ]]; then
        log "Falta initramfs de $TARGET_KVER; generandolo..."
        run "update-initramfs -c -k $TARGET_KVER"
        [[ -f "/boot/initrd.img-$TARGET_KVER" ]] || die "No se pudo generar el initramfs de $TARGET_KVER."
    fi
    # Re-verificar el driver: la instalacion del kernel puede haberlo tocado
    if [[ $REQUIRED_R8125 -eq 1 ]]; then
        if [[ -z "$(r8125_ko_path "$TARGET_KVER")" ]]; then
            log "El r8125.ko no esta tras instalar el kernel; reinstalando via dkms..."
            DKMS_ID=$(r8125_dkms_id)
            [[ -n "$DKMS_ID" ]] || die "r8125 no esta registrado en dkms. NO REINICIAR."
            dkms install "$DKMS_ID" -k "$TARGET_KVER" --force 2>&1 | tee -a "$LOG_FILE" || true
            [[ -n "$(r8125_ko_path "$TARGET_KVER")" ]] \
                || die "No se pudo dejar r8125 instalado para $TARGET_KVER. NO REINICIAR: el equipo quedaria sin red."
        fi
        run "depmod -a $TARGET_KVER"
        log "OK: driver r8125 verificado para $TARGET_KVER tras la instalacion del kernel."
    fi
fi
log "OK: imagen, modulos y headers $TARGET_KVER presentes."

# 2b. Pin de apt: bloquear el track HWE (7.0.x) permitiendo solo 6.8.x
#
# Si el equipo se aprovisiono con los .deb de OmniFish, el instalador ya dejo su
# propio pin en 99-no-hwe-kernel. Escribir un segundo archivo que bloquea lo
# mismo no aporta nada y deja al operador con dos fuentes de verdad que hay que
# recordar borrar juntas el dia que se abra el carril HWE. Se detecta y se
# respeta el que ya esta.
INSTALLER_PIN="/etc/apt/preferences.d/99-no-hwe-kernel"
if [[ -f "$INSTALLER_PIN" ]] && grep -q 'Pin-Priority: *-1' "$INSTALLER_PIN"; then
    log "Pin del instalador ya presente en $INSTALLER_PIN; no se escribe un segundo pin."
    log "  (para removerlo mas adelante hay UN solo archivo, no dos)"
    PIN_FILE="$INSTALLER_PIN"
elif [[ $DRY_RUN -eq 1 ]]; then
    log "(dry-run) crearia $PIN_FILE"
else
    log "Escribiendo pin de apt en $PIN_FILE..."
fi
if [[ ! -f "$INSTALLER_PIN" ]]; then
    if write_if_changed "$PIN_FILE" <<'EOF'
# OmniFish - Pin de flota al kernel GA (6.8.x)
# Motivo: incompatibilidad TCMalloc/rseq de MongoDB 8.0 con track HWE 7.0.x
# y perdida de driver RTL8125D en downgrades. NO ELIMINAR sin aprobacion.
Package: linux-generic-hwe-24.04 linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04
Pin: release *
Pin-Priority: -1

Package: linux-image-7.* linux-headers-7.* linux-modules-7.* linux-modules-extra-7.*
Pin: release *
Pin-Priority: -1
EOF
    then
        log "OK: pin escrito en $PIN_FILE."
    else
        log "OK: el pin de $PIN_FILE ya estaba aplicado; no se reescribe."
    fi
fi

# 2c. Hold robusto via dpkg --set-selections (el pin puede dejar sin candidato
#     a apt-mark hold, por eso se usa dpkg directamente - leccion del runbook)
log "Aplicando hold a paquetes HWE instalados..."
HWE_PKGS=$(dpkg -l | awk '/^ii/ && ($2 ~ /^linux-(image|headers|modules|modules-extra)-7\./ || $2 ~ /hwe-24\.04/) {print $2}')
if [[ -n "$HWE_PKGS" ]]; then
    for p in $HWE_PKGS; do
        run "echo '$p hold' | dpkg --set-selections"
    done
    log "Paquetes en hold: $(echo $HWE_PKGS | tr '\n' ' ')"
else
    log "No hay paquetes HWE instalados que poner en hold."
fi

# 2d. Entrada de GRUB para el kernel objetivo.
#     El arranque one-shot NO se arma aca: se arma al final, despues del gate
#     de pre-reboot. Antes se armaba en este punto, asi que un fallo en las
#     fases 3 o 4 mataba el script con el one-shot ya puesto y el operador
#     podia reiniciar hacia un equipo a medio preparar.
GRUB_ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux $TARGET_KVER"
if ! grep -q "with Linux $TARGET_KVER" /boot/grub/grub.cfg; then
    run "update-grub"
    grep -q "with Linux $TARGET_KVER" /boot/grub/grub.cfg \
        || die "grub.cfg no contiene entrada para $TARGET_KVER tras update-grub."
fi
log "OK: grub.cfg tiene entrada para $TARGET_KVER (el one-shot se arma al final)."

#===============================================================================
# FASE 3: Watchdog de auto-sanacion para el estado 'zombie' del r8125
#
# Motivo: el zombie visto en la flota (rx_packets estancado en 0 con link UP,
# tras NETDEV WATCHDOG recurrente) es un problema de RUNTIME continuo, no de
# instalacion - puede reaparecer horas o dias despues de un reboot exitoso.
# Este watchdog corre periodicamente via systemd timer, detecta el patron
# y aplica el mismo remove/rescan del bus PCI que se usa manualmente hoy.
# Si no logra autosanarse, deja una bandera en disco (no reintenta sin
# limite) para que fleetstat/el operador sepan que ese equipo necesita
# corte de energia (unico fix conocido para el subconjunto que no responde
# a remove/rescan).
#===============================================================================
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    log ""
    log "--- FASE 3: Instalando watchdog de auto-sanacion (r8125 zombie) ---"

    WATCHDOG_BIN="/opt/omnifish/bin/r8125-zombie-watchdog.sh"
    WATCHDOG_SERVICE="/etc/systemd/system/omnifish-r8125-watchdog.service"
    WATCHDOG_TIMER="/etc/systemd/system/omnifish-r8125-watchdog.timer"

    if [[ $DRY_RUN -eq 0 ]]; then
        mkdir -p "$(dirname "$WATCHDOG_BIN")"

        # NOTA: delimitador 'WDEOF' entre comillas simples a proposito, para
        # que $IFACE, $RX1, etc. queden LITERALES en el script generado y no
        # se expandan ahora contra el entorno de este script de fix.
        WD_CHANGED=0
        if write_if_changed "$WATCHDOG_BIN" 0755 <<'WDEOF'
#!/usr/bin/env bash
# Auto-generado por fix-r8125-downgrade-6.8.sh - NO editar a mano.
#
# Detecta y autorepara el estado 'zombie' del RTL8125 (chip con link UP que
# dejo de recibir), visto en la flota tras watchdogs de TX recurrentes.
#
# POR QUE EXIGE VARIAS EVIDENCIAS
#   La version anterior actuaba con una sola senal: rx_packets sin cambios en
#   6 segundos. Una red simplemente silenciosa produce exactamente eso, y la
#   remediacion (sacar el device del bus PCI) corta la red de verdad. Ahora
#   hacen falta tres cosas independientes antes de tocar nada:
#     1. RX congelado en una ventana corta (6s)   -> descarta trafico normal
#     2. RX congelado en una ventana larga (30s)
#        Y sin interrupciones nuevas del chip     -> descarta red silenciosa;
#           si el chip interrumpe, esta vivo y el problema esta mas arriba
#     3. Un probe activo falla (ping al gateway)  -> confirma que no hay
#           camino, en vez de asumirlo
#   Si no hay gateway por esa interfaz, se exige en su lugar que estemos
#   transmitiendo sin recibir nada (tx sube, rx no): hablamos y nadie contesta.
#
# POR QUE YA NO HACE 'modprobe -r r8125'
#   Descargar el modulo tumba TODAS las interfaces r8125 de la placa, no solo
#   la sospechosa. Ahora se hace unbind/bind del device puntual y, si eso no
#   alcanza, remove/rescan del bus. Las dos operaciones son por direccion PCI.
set -uo pipefail

LOG="/var/log/omnifish-r8125-watchdog.log"
FLAG_DIR="/var/log/omnifish-r8125-watchdog-flags"
COOLDOWN_OK=900        # 15 min entre intentos normales
COOLDOWN_UNRESOLVED=21600   # 6 h si el ultimo intento no lo resolvio: no tiene
                            # sentido seguir arrancando del bus un chip que no vuelve
mkdir -p "$FLAG_DIR"
log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

rx_of()  { cat "/sys/class/net/$1/statistics/rx_packets" 2>/dev/null || echo 0; }
tx_of()  { cat "/sys/class/net/$1/statistics/tx_packets" 2>/dev/null || echo 0; }
irq_of() {
    awk -v i="$1" '$0 ~ (i "([^a-zA-Z0-9_-]|$)") {
          for (j = 2; j <= NF; j++) if ($j ~ /^[0-9]+$/) s += $j
        } END { print s + 0 }' /proc/interrupts
}
# Recibe algo en $2 segundos?
rx_moves() {
    local iface="$1" secs="$2" a b
    a=$(rx_of "$iface"); sleep "$secs"; b=$(rx_of "$iface")
    [[ "$a" != "$b" ]]
}

for pci in $(lspci -Dn 2>/dev/null | grep -i '10ec:8125' | awk '{print $1}'); do
    IFACE=$(ls "/sys/bus/pci/devices/$pci/net/" 2>/dev/null | head -n1)
    [[ -z "$IFACE" ]] && continue

    DRIVER=$(basename "$(readlink -f "/sys/class/net/$IFACE/device/driver" 2>/dev/null)" 2>/dev/null || echo "")
    # Solo actuamos si r8125 esta manejando la interfaz. Si quedo en r8169
    # (chip que no es revision D), no es responsabilidad de este watchdog.
    [[ "$DRIVER" != "r8125" ]] && continue

    CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0)
    [[ "$CARRIER" != "1" ]] && continue   # sin link: es cable/switch, no zombie
    [[ "$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)" == "down" ]] && continue

    # --- Evidencia 1: ventana corta ---
    if rx_moves "$IFACE" 6; then
        continue
    fi

    # --- Evidencia 2: ventana larga + interrupciones ---
    RX_A=$(rx_of "$IFACE"); TX_A=$(tx_of "$IFACE"); IRQ_A=$(irq_of "$IFACE")
    sleep 30
    RX_B=$(rx_of "$IFACE"); TX_B=$(tx_of "$IFACE"); IRQ_B=$(irq_of "$IFACE")

    if [[ "$RX_A" != "$RX_B" ]]; then
        log "$IFACE ($pci): RX se movio en la ventana larga ($RX_A -> $RX_B). Red lenta, no zombie."
        continue
    fi
    if [[ "$IRQ_A" != "$IRQ_B" ]]; then
        log "$IFACE ($pci): RX congelado pero el chip sigue generando interrupciones ($IRQ_A -> $IRQ_B). No se remedia: el problema no es el chip."
        continue
    fi

    # --- Evidencia 3: probe activo ---
    GW=$(ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3}' | head -n1)
    if [[ -n "$GW" ]]; then
        if ping -I "$IFACE" -c 2 -W 2 "$GW" >/dev/null 2>&1; then
            log "$IFACE ($pci): RX e IRQ congelados pero el gateway $GW responde. No se remedia."
            continue
        fi
        EVIDENCIA="gateway $GW sin respuesta"
    elif [[ "$TX_B" -gt "$TX_A" ]]; then
        EVIDENCIA="sin gateway conocido; tx subio ($TX_A -> $TX_B) y rx no se movio"
    else
        log "$IFACE ($pci): RX e IRQ congelados, pero sin gateway y sin TX propio no hay como confirmar. No se remedia (puede ser un puerto legitimamente inactivo)."
        continue
    fi

    log "ZOMBIE con evidencia multiple en $IFACE ($pci): rx=$RX_B congelado 36s, irq=$IRQ_B congeladas, $EVIDENCIA"

    FLAG_FILE="$FLAG_DIR/$(echo "$pci" | tr '/:.' '_').lastattempt"
    UNRESOLVED_FLAG="$FLAG_DIR/$(echo "$pci" | tr '/:.' '_').unresolved"
    NOW=$(date +%s)
    LAST=0
    [[ -f "$FLAG_FILE" ]] && LAST=$(cat "$FLAG_FILE" 2>/dev/null || echo 0)
    COOLDOWN=$COOLDOWN_OK
    [[ -f "$UNRESOLVED_FLAG" ]] && COOLDOWN=$COOLDOWN_UNRESOLVED
    if (( NOW - LAST < COOLDOWN )); then
        log "Ultimo intento hace $(( NOW - LAST ))s, cooldown ${COOLDOWN}s. Se omite esta pasada."
        continue
    fi
    echo "$NOW" > "$FLAG_FILE"

    # --- Remediacion 1 (la menos invasiva): unbind/bind del device puntual ---
    log "Remediacion 1/2: unbind + bind de $pci en r8125"
    echo "$pci" > /sys/bus/pci/drivers/r8125/unbind 2>>"$LOG"
    sleep 2
    echo "$pci" > /sys/bus/pci/drivers/r8125/bind 2>>"$LOG"
    sleep 8

    NEW_IFACE=$(ls "/sys/bus/pci/devices/$pci/net/" 2>/dev/null | head -n1)
    if [[ -n "$NEW_IFACE" ]] && rx_moves "$NEW_IFACE" 6; then
        log "OK: $NEW_IFACE recibiendo tras unbind/bind. Zombie resuelto sin tocar el bus."
        rm -f "$UNRESOLVED_FLAG"
        continue
    fi

    # --- Remediacion 2: remove/rescan del bus PCI ---
    log "Remediacion 2/2: remove + rescan del bus para $pci"
    echo 1 > "/sys/bus/pci/devices/$pci/remove" 2>>"$LOG"
    sleep 3
    echo 1 > /sys/bus/pci/rescan 2>>"$LOG"
    sleep 8

    NEW_IFACE=$(ls "/sys/bus/pci/devices/$pci/net/" 2>/dev/null | head -n1)
    if [[ -z "$NEW_IFACE" ]]; then
        log "SIN EXITO: la interfaz no reaparecio tras el rescan del bus PCI ($pci)."
        echo "$NOW" > "$UNRESOLVED_FLAG"
    elif rx_moves "$NEW_IFACE" 6; then
        log "OK: $NEW_IFACE recibiendo tras remove/rescan. Zombie resuelto."
        rm -f "$UNRESOLVED_FLAG"
    else
        log "SIN EXITO: $NEW_IFACE sigue sin recibir. Requiere corte de energia (AC) para reset completo del chip."
        echo "$NOW" > "$UNRESOLVED_FLAG"
    fi
done
WDEOF
        then WD_CHANGED=1; log "Watchdog escrito en $WATCHDOG_BIN"; else log "Watchdog ya estaba al dia"; fi

        if write_if_changed "$WATCHDOG_SERVICE" <<'EOF'
[Unit]
Description=OmniFish - Chequeo y auto-sanacion de zombie RTL8125 (r8125)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/omnifish/bin/r8125-zombie-watchdog.sh
EOF
        then WD_CHANGED=1; fi

        if write_if_changed "$WATCHDOG_TIMER" <<'EOF'
[Unit]
Description=OmniFish - Timer periodico del watchdog r8125

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        then WD_CHANGED=1; fi

        # daemon-reload solo si alguno de los tres archivos cambio. 'enable --now'
        # si es idempotente y barato, asi que se ejecuta siempre para reparar un
        # timer que alguien haya deshabilitado a mano.
        if [[ $WD_CHANGED -eq 1 ]]; then
            run "systemctl daemon-reload" \
                || log "ADVERTENCIA: fallo systemctl daemon-reload; el watchdog puede no quedar activo."
        else
            log "Watchdog, service y timer sin cambios; no se recarga systemd."
        fi
        run "systemctl enable --now omnifish-r8125-watchdog.timer" \
            || log "ADVERTENCIA: fallo activar el timer del watchdog; revisar 'systemctl status omnifish-r8125-watchdog.timer'."

        log "OK: watchdog instalado (chequeo cada 15 min, cooldown de 15 min entre remediaciones)."
        log "  Log: /var/log/omnifish-r8125-watchdog.log"
        log "  Banderas de zombie NO resuelto (requiere corte de AC): /var/log/omnifish-r8125-watchdog-flags/*.unresolved"
    else
        log "(dry-run) instalaria $WATCHDOG_BIN, $WATCHDOG_SERVICE, $WATCHDOG_TIMER y activaria el timer"
    fi
else
    log ""
    log "--- FASE 3: no aplica (esta maquina no requiere r8125) ---"
fi

#===============================================================================
# FASE 4: Persistencia de red para la interfaz r8125 (netplan por MAC)
#
# Motivo: el propio reboot que provoca este script es el tipo de evento que
# puede disparar el bug de "perfil huerfano" de NetworkManager (interfaz sin
# cobertura de netplan -> NetworkManager crea un perfil generico por DHCP
# que no persiste igual que uno gestionado por netplan). Visto en la flota
# en una interfaz con IP ESTATICA que se revertia a DHCP en cada reboot.
#
# Esta fase es puramente ADITIVA: solo CREA un archivo netplan nuevo cuando
# confirma que (a) la interfaz no tiene ninguna cobertura de netplan hoy, y
# (b) tiene una IP estatica activa que vale la pena preservar. Nunca edita
# ni borra archivos existentes, y nunca inventa una IP.
#===============================================================================
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    log ""
    log "--- FASE 4: Verificando persistencia de red para la interfaz r8125 ---"

    for pci in $PCI_ADDRS; do
        NP_IFACE=$(ls "/sys/bus/pci/devices/$pci/net/" 2>/dev/null | head -n1 || true)
        if [[ -z "$NP_IFACE" ]]; then
            log "  $pci: sin interfaz de red asociada actualmente. Se omite (revisar tras el reboot)."
            continue
        fi
        log "  $pci -> $NP_IFACE"

        NP_MAC=$(cat "/sys/class/net/$NP_IFACE/address" 2>/dev/null || echo "")

        # Algunas maquinas de la flota no usan netplan en absoluto (red
        # gestionada 100% por NetworkManager, sin /etc/netplan). En ese caso
        # NO corresponde crear un netplan nuevo (cambiaria el modelo de
        # gestion de la maquina sin que nadie lo pidiera, y ademas el intento
        # de escritura fallaria contra un directorio inexistente). Se hace en
        # su lugar una verificacion de solo lectura: si el perfil activo de
        # NetworkManager esta persistido en disco.
        if [[ ! -d /etc/netplan ]]; then
            log "    /etc/netplan no existe en este equipo: la red se gestiona directo por NetworkManager (sin netplan)."
            if command -v nmcli &>/dev/null; then
                NP_CONN=$(nmcli -t -g GENERAL.CONNECTION device show "$NP_IFACE" 2>/dev/null || true)
                if [[ -n "$NP_CONN" && "$NP_CONN" != "--" ]]; then
                    NP_UUID=$(nmcli -t -g connection.uuid connection show "$NP_CONN" 2>/dev/null || true)
                    if [[ -n "$NP_UUID" ]] && grep -rl "$NP_UUID" /etc/NetworkManager/system-connections/ 2>/dev/null | grep -q .; then
                        log "    OK: perfil '$NP_CONN' persistido en /etc/NetworkManager/system-connections. Sobrevive un reboot."
                    else
                        log "    ADVERTENCIA: no se pudo confirmar que '$NP_CONN' este persistido en disco (UUID no encontrado en /etc/NetworkManager/system-connections). Revisar manualmente."
                    fi
                else
                    log "    Sin conexion activa determinable en $NP_IFACE ahora mismo (puede estar en pleno reintento de DHCP/VLAN). Revisar manualmente tras el reboot."
                fi
            else
                log "    ADVERTENCIA: nmcli no disponible; no se pudo verificar la persistencia del perfil de red."
            fi
            continue
        fi

        NP_COVERAGE=0
        if grep -rq -E "^[[:space:]]*${NP_IFACE}:" /etc/netplan/*.yaml 2>/dev/null; then
            NP_COVERAGE=1
        fi
        if [[ -n "$NP_MAC" ]] && grep -rqi "$NP_MAC" /etc/netplan/*.yaml 2>/dev/null; then
            NP_COVERAGE=1
        fi

        if [[ "$NP_COVERAGE" -eq 1 ]]; then
            log "    OK: ya existe cobertura de netplan para $NP_IFACE. No se toca."
            continue
        fi

        if ! command -v nmcli &>/dev/null; then
            log "    ADVERTENCIA: sin cobertura de netplan y nmcli no disponible para verificar la config actual. Revisar manualmente."
            continue
        fi

        NP_CONN=$(nmcli -t -g GENERAL.CONNECTION device show "$NP_IFACE" 2>/dev/null || true)
        if [[ -z "$NP_CONN" || "$NP_CONN" == "--" ]]; then
            log "    Sin conexion activa de NetworkManager en $NP_IFACE ahora mismo. Sin cobertura de netplan, pero nada que preservar; revisar tras el reboot."
            continue
        fi

        NP_METHOD=$(nmcli -t -g ipv4.method connection show "$NP_CONN" 2>/dev/null || echo "")
        if [[ "$NP_METHOD" != "manual" ]]; then
            log "    $NP_IFACE esta en DHCP actualmente (perfil '$NP_CONN'). Sin cobertura de netplan por MAC, pero el impacto de un perfil efimero es menor al ser DHCP. Se recomienda igual agregar match por MAC a futuro."
            continue
        fi

        NP_ADDRS=$(nmcli -t -g ipv4.addresses connection show "$NP_CONN" 2>/dev/null || true)
        if [[ -z "$NP_ADDRS" ]]; then
            log "    ADVERTENCIA: $NP_IFACE tiene ipv4.method=manual pero sin direcciones legibles via nmcli. Revisar manualmente."
            continue
        fi

        log "    SIN cobertura de netplan y con IP ESTATICA activa ($NP_ADDRS) en $NP_IFACE via el perfil efimero '$NP_CONN' - en riesgo de perderse en el proximo reboot."
        NP_FILE="/etc/netplan/90-omnifish-r8125-persist-${NP_IFACE}.yaml"
        log "    Generando $NP_FILE para preservar la IP actual, matcheado por MAC (${NP_MAC})..."

        if [[ $DRY_RUN -eq 0 ]]; then
            {
                echo "network:"
                echo "  version: 2"
                echo "  ethernets:"
                echo "    ${NP_IFACE}:"
                echo "      match:"
                echo "        macaddress: \"${NP_MAC}\""
                echo "      set-name: ${NP_IFACE}"
                echo "      dhcp4: false"
                echo "      addresses: [${NP_ADDRS}]"
            } > "$NP_FILE"
            chmod 600 "$NP_FILE"
            run "netplan generate" \
                || log "ADVERTENCIA: fallo 'netplan generate' tras crear $NP_FILE; revisar sintaxis manualmente."
            log "    OK: $NP_FILE creado. No se aplica ahora (netplan apply) para no interrumpir la sesion actual;"
            log "    tomara efecto en el proximo reboot (el que este mismo script va a provocar)."
        else
            log "    (dry-run) crearia $NP_FILE con addresses: $NP_ADDRS"
        fi
    done
else
    log ""
    log "--- FASE 4: no aplica (esta maquina no requiere r8125) ---"
fi

#===============================================================================
# FASE 5: GATE DE PRE-REBOOT
#
# Nada de lo anterior sirve si el equipo reinicia hacia un kernel que no puede
# levantar la red: perder conectividad remota es el fallo mas caro de esta
# flota. Este gate junta en un solo lugar todo lo que tiene que estar en su
# sitio, lo imprime como checklist auditable, y SOLO entonces arma el arranque
# one-shot. Si falta algo critico, no lo arma y dice NO REINICIAR.
#===============================================================================
log ""
log "--- FASE 5: GATE DE PRE-REBOOT ---"

GATE_FAIL=()
GATE_WARN=()

gate_ok()   { log "  [OK]    $1"; }
gate_fail() { log "  [FALTA] $1"; GATE_FAIL+=("$1"); }
gate_warn() { log "  [AVISO] $1"; GATE_WARN+=("$1"); }

# 1. Imagen e initramfs del kernel objetivo
if [[ -f "/boot/vmlinuz-$TARGET_KVER" ]]; then
    gate_ok "imagen del kernel: /boot/vmlinuz-$TARGET_KVER"
else
    gate_fail "no existe /boot/vmlinuz-$TARGET_KVER"
fi
if [[ -f "/boot/initrd.img-$TARGET_KVER" ]]; then
    gate_ok "initramfs: /boot/initrd.img-$TARGET_KVER"
else
    gate_fail "no existe /boot/initrd.img-$TARGET_KVER"
fi

# 2. Paquetes del kernel objetivo correctamente configurados
for pkg in "${KPKGS[@]}"; do
    if pkg_ok "$pkg"; then
        gate_ok "paquete configurado: $pkg"
    else
        gate_fail "paquete ausente o a medio configurar: $pkg"
    fi
done

# 3. Entrada de GRUB
if grep -q "with Linux $TARGET_KVER" /boot/grub/grub.cfg 2>/dev/null; then
    gate_ok "entrada de GRUB para $TARGET_KVER"
else
    gate_fail "grub.cfg no tiene entrada para $TARGET_KVER"
fi

# 4. Pin de apt (no bloquea el reboot, pero sin el vuelve el HWE)
if [[ -f "$PIN_FILE" ]]; then
    gate_ok "pin de apt: $PIN_FILE"
else
    gate_warn "falta el pin de apt $PIN_FILE: un apt upgrade futuro reinstala el HWE"
fi

# 5. Blacklist accidental de r8169: mataria las RTL8168/8111
if BL_LEFT=$(nic_r8169_blacklisted); then
    gate_fail "quedo un blacklist de r8169 en: $(tr '\n' ' ' <<<"$BL_LEFT")"
else
    gate_ok "sin blacklist de r8169"
fi

# 6. Driver r8125, solo si esta maquina lo necesita
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    G_RC=0
    G_INFO=$(nic_r8125_ko_ok "$TARGET_KVER") || G_RC=$?
    G_KO=$(awk '{print $1}' <<<"$G_INFO")
    G_VER=$(awk '{print $2}' <<<"$G_INFO")
    case $G_RC in
        0) gate_ok "r8125 $G_VER construido para $TARGET_KVER ($G_KO)" ;;
        1) gate_fail "no existe r8125.ko bajo /lib/modules/$TARGET_KVER/updates" ;;
        2) gate_fail "r8125 $G_VER < $NIC_R8125_MIN_VER: no cubre el RTL8125D" ;;
        3) gate_fail "el r8125.ko de $TARGET_KVER no declara version: no se puede afirmar que sirva" ;;
    esac

    if [[ -n "$G_KO" ]] && modinfo "$G_KO" &>/dev/null; then
        gate_ok "el modulo es valido para modinfo"
    else
        gate_fail "el r8125.ko de $TARGET_KVER no es un modulo valido"
    fi

    # depmod antes de mirar el alias: lo que carga el driver al arrancar es udev
    # consultando modules.alias, y que exista el .ko no alcanza si no esta indexado.
    if [[ $DRY_RUN -eq 0 ]]; then
        run "depmod -a $TARGET_KVER" || gate_warn "fallo 'depmod -a $TARGET_KVER'"
    fi
    if nic_alias_has_r8125 "$TARGET_KVER"; then
        gate_ok "alias PCI 10ec:8125 -> r8125 indexado en modules.alias"
    else
        gate_fail "r8125 no quedo indexado para 10ec:8125 en modules.alias de $TARGET_KVER"
    fi
else
    gate_ok "esta maquina no requiere r8125 (no hay revision problematica detectada)"
fi

log ""
if [[ ${#GATE_FAIL[@]} -gt 0 ]]; then
    log "================================================================"
    log "  NO REINICIAR"
    log "================================================================"
    log "Faltan ${#GATE_FAIL[@]} elemento(s) criticos para arrancar en $TARGET_KVER:"
    for g in "${GATE_FAIL[@]}"; do log "  - $g"; done
    log ""
    log "El arranque one-shot NO se armo: el equipo sigue arrancando el kernel actual."
    if [[ $DRY_RUN -eq 1 ]]; then
        log "(dry-run: esto es esperable, porque no se instalo ni compilo nada. La corrida real"
        log " tiene que llegar a este gate con la lista completa.)"
    fi
    log "Resolver lo de arriba y volver a correr este script. Log: $LOG_FILE"
    log "================================================================"
    exit 1
fi

for g in ${GATE_WARN[@]+"${GATE_WARN[@]}"}; do log "AVISO pendiente: $g"; done
log "Gate de pre-reboot COMPLETO. Armando arranque one-shot: $GRUB_ENTRY"
run "grub-reboot '$GRUB_ENTRY'"

#===============================================================================
# Resumen
#===============================================================================
log ""
log "================================================================"
log "COMPLETADO. Estado:"
if lspci -n | grep -qi '10ec:8125'; then
    # Por archivo y con validacion de version, nunca 'modinfo -k <kver> r8125':
    # por nombre da falsos negativos en arboles solo-DKMS, y sin mirar version
    # el r8125-dkms 9.011.00 de noble pasaba por bueno.
    SUM_RC=0
    SUM_INFO=$(nic_r8125_ko_ok "$TARGET_KVER") || SUM_RC=$?
    if [[ $SUM_RC -eq 0 ]]; then
        log "  - Driver r8125 $(awk '{print $2}' <<<"$SUM_INFO") listo para $TARGET_KVER (RTL8125D cubierto)"
    elif [[ $REQUIRED_R8125 -eq 1 ]]; then
        log "  - NIC 8125 presente y esta maquina la requiere, pero NO hay r8125 utilizable para $TARGET_KVER"
    else
        log "  - NIC 8125 presente sin revision problematica detectada: usara r8169 in-tree en $TARGET_KVER"
    fi
fi
log "  - Pin apt activo: $PIN_FILE"
log "  - grub-reboot apuntando a $TARGET_KVER (one-shot)"
if [[ $REQUIRED_R8125 -eq 1 && $DRY_RUN -eq 0 ]]; then
    if [[ -f /etc/modprobe.d/omnifish-r8125-options.conf ]]; then
        log "  - Hardening ASPM/EEE: aplicado"
    else
        log "  - Hardening ASPM/EEE: omitido (ver log arriba)"
    fi
    if systemctl is-enabled omnifish-r8125-watchdog.timer &>/dev/null; then
        log "  - Watchdog de auto-sanacion: activo (cada 15 min)"
    else
        log "  - Watchdog de auto-sanacion: NO activo (revisar systemctl status omnifish-r8125-watchdog.timer)"
    fi
    log "  - Persistencia netplan de la interfaz r8125: ver detalle de FASE 4 arriba"
fi
log ""
log "GATE DE PRE-REBOOT: COMPLETO -> SEGURO REINICIAR"
log "SIGUIENTE PASO: sudo reboot"
log "Tras validar red y servicios en 6.8, fijar el default permanente:"
log "  sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"$GRUB_ENTRY\"/' /etc/default/grub"
log "  sudo update-grub"
if [[ $REQUIRED_R8125 -eq 1 ]]; then
    log ""
    log "RECOMENDADO tras el reboot: correr diag-nic.sh sobre la interfaz r8125"
    log "para confirmar Capa 3 (sin zombie) y Capa 7 (persistencia de red OK)."
fi
log "================================================================"
