#!/bin/bash
# =============================================================================
# Librería Compartida - Scripts Doctor
# Funciones comunes de verificación e instalación.
# Uso: source doctor_lib.sh (desde doctor_compresion.sh o doctor_analitica.sh)
# =============================================================================

# --- Colores y símbolos ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}[OK]${NC}"
FAIL="${RED}[FALLO]${NC}"
WARN="${YELLOW}[AVISO]${NC}"
MINOR="${CYAN}[NOTA]${NC}"
INFO="${CYAN}[INFO]${NC}"
FIXED="${GREEN}[INSTALADO]${NC}"
FIX_FAIL="${RED}[NO SE PUDO INSTALAR]${NC}"

# --- Contadores ---
total=0
passed=0
failed=0
warnings=0
minors=0
fixed=0

# --- Modo de operación ---
FIX_MODE=false
LOG_FILE=""

# --- Versiones de paquetes .deb (actualizar cuando cambien) ---
MONGODB_COMPASS_VERSION="1.43.4"
MONGODB_COMPASS_URL="https://downloads.mongodb.com/compass/mongodb-compass_${MONGODB_COMPASS_VERSION}_amd64.deb"
IPSCAN_VERSION="3.9.1"
IPSCAN_URL="https://github.com/angryip/ipscan/releases/download/${IPSCAN_VERSION}/ipscan_${IPSCAN_VERSION}_amd64.deb"
RUSTDESK_VERSION="1.2.3"
RUSTDESK_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.deb"

# =============================================================================
# --- Parseo de argumentos ---
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix)
                FIX_MODE=true
                shift
                ;;
            *)
                echo "Uso: $0 [--fix]"
                echo "  --fix    Instala componentes faltantes automáticamente"
                exit 1
                ;;
        esac
    done

    if $FIX_MODE; then
        LOG_FILE="/tmp/doctor_fix_$(date '+%Y%m%d_%H%M%S').log"
        echo -e "${YELLOW}${BOLD}  Modo --fix activado. Se instalarán componentes faltantes.${NC}"
        echo -e "  Log de instalación: ${LOG_FILE}"
        echo ""

        # Solicitar sudo una vez al inicio
        if ! sudo -v 2>/dev/null; then
            echo -e "  ${RED}Se requiere sudo para --fix. Ejecuta con un usuario con permisos sudo.${NC}"
            exit 1
        fi

        # Actualizar índice de paquetes una vez
        echo -e "  ${INFO} Actualizando índice de paquetes..."
        sudo apt-get update >> "$LOG_FILE" 2>&1
    fi
}

# =============================================================================
# --- Funciones auxiliares ---
# =============================================================================
info() {
    echo -e "  ${INFO} $1"
}

section() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# --- Ejecutar fix y loggear ---
run_fix() {
    local fix_cmd="$1"
    echo ">>> $(date '+%H:%M:%S') Ejecutando: ${fix_cmd}" >> "$LOG_FILE" 2>&1
    eval "$fix_cmd" >> "$LOG_FILE" 2>&1
    return $?
}

# =============================================================================
# --- Funciones de verificación con auto-instalación ---
# =============================================================================

# check_and_fix <descripción> <comando_check> <comando_fix>
# Si el check falla y --fix está activo, ejecuta el fix y re-verifica.
check_and_fix() {
    local description="$1"
    local check_cmd="$2"
    local fix_cmd="${3:-}"
    total=$((total + 1))

    if eval "$check_cmd" > /dev/null 2>&1; then
        echo -e "  ${PASS} ${description}"
        passed=$((passed + 1))
        return 0
    fi

    # Check falló
    if $FIX_MODE && [ -n "$fix_cmd" ]; then
        echo -ne "  ${YELLOW}[INSTALANDO]${NC} ${description}..."
        if run_fix "$fix_cmd"; then
            # Re-verificar después de instalar
            if eval "$check_cmd" > /dev/null 2>&1; then
                echo -e "\r  ${FIXED} ${description}          "
                fixed=$((fixed + 1))
                passed=$((passed + 1))
                return 0
            fi
        fi
        echo -e "\r  ${FIX_FAIL} ${description}          "
        failed=$((failed + 1))
        return 1
    fi

    echo -e "  ${FAIL} ${description}"
    failed=$((failed + 1))
    return 1
}

# check_and_fix_warn - igual que check_and_fix pero cuenta como warning si falla
check_and_fix_warn() {
    local description="$1"
    local check_cmd="$2"
    local fix_cmd="${3:-}"
    total=$((total + 1))

    if eval "$check_cmd" > /dev/null 2>&1; then
        echo -e "  ${PASS} ${description}"
        passed=$((passed + 1))
        return 0
    fi

    # Check falló
    if $FIX_MODE && [ -n "$fix_cmd" ]; then
        echo -ne "  ${YELLOW}[INSTALANDO]${NC} ${description}..."
        if run_fix "$fix_cmd"; then
            if eval "$check_cmd" > /dev/null 2>&1; then
                echo -e "\r  ${FIXED} ${description}          "
                fixed=$((fixed + 1))
                passed=$((passed + 1))
                return 0
            fi
        fi
        echo -e "\r  ${FIX_FAIL} ${description} (opcional)          "
        warnings=$((warnings + 1))
        return 1
    fi

    echo -e "  ${WARN} ${description} (opcional)"
    warnings=$((warnings + 1))
    return 1
}

# check_and_fix_minor - para verificaciones de baja prioridad (puertos, configs opcionales)
check_and_fix_minor() {
    local description="$1"
    local check_cmd="$2"
    local fix_cmd="${3:-}"
    total=$((total + 1))

    if eval "$check_cmd" > /dev/null 2>&1; then
        echo -e "  ${PASS} ${description}"
        passed=$((passed + 1))
        return 0
    fi

    # Check falló
    if $FIX_MODE && [ -n "$fix_cmd" ]; then
        echo -ne "  ${YELLOW}[CONFIGURANDO]${NC} ${description}..."
        if run_fix "$fix_cmd"; then
            if eval "$check_cmd" > /dev/null 2>&1; then
                echo -e "\r  ${GREEN}[CONFIGURADO]${NC} ${description}          "
                fixed=$((fixed + 1))
                passed=$((passed + 1))
                return 0
            fi
        fi
        echo -e "\r  ${MINOR} ${description} (no configurado)          "
        minors=$((minors + 1))
        return 1
    fi

    echo -e "  ${MINOR} ${description} (no configurado)"
    minors=$((minors + 1))
    return 1
}

# check_manual - para cosas que no se pueden automatizar
check_manual() {
    local description="$1"
    local check_cmd="$2"
    local manual_msg="$3"
    total=$((total + 1))

    if eval "$check_cmd" > /dev/null 2>&1; then
        echo -e "  ${PASS} ${description}"
        passed=$((passed + 1))
    else
        echo -e "  ${FAIL} ${description}"
        if $FIX_MODE; then
            echo -e "        ${YELLOW}→ Manual: ${manual_msg}${NC}"
        fi
        failed=$((failed + 1))
    fi
}

# =============================================================================
# --- Detección de CUDA desde filesystem ---
# =============================================================================

# Verificar si CUDA está configurado en el sistema (profile.d, bashrc, etc.)
check_cuda_configured() {
    # Verificar en ~/.bashrc
    grep -q 'export PATH=.*cuda' ~/.bashrc 2>/dev/null && return 0
    # Verificar en /etc/profile.d/ (método APT)
    ls /etc/profile.d/cuda*.sh > /dev/null 2>&1 && return 0
    # Verificar en /etc/environment
    grep -qi 'cuda' /etc/environment 2>/dev/null && return 0
    # Verificar en /etc/profile
    grep -qi 'cuda' /etc/profile 2>/dev/null && return 0
    return 1
}

detect_cuda_from_system() {
    # Si nvcc ya está en el PATH, no hacer nada
    if command -v nvcc > /dev/null 2>&1; then
        return 0
    fi

    # Buscar nvcc directamente en el filesystem
    local cuda_bin=""
    local cuda_lib=""

    # Buscar en rutas estándar de CUDA (más reciente primero)
    for dir in /usr/local/cuda/bin /usr/local/cuda-*/bin; do
        if [ -x "${dir}/nvcc" ] 2>/dev/null; then
            cuda_bin="$dir"
            break
        fi
    done

    if [ -n "$cuda_bin" ]; then
        export PATH="${cuda_bin}:${PATH}"
        info "nvcc encontrado en filesystem: ${cuda_bin}/nvcc"

        # Buscar lib64 correspondiente
        local cuda_base="${cuda_bin%/bin}"
        if [ -d "${cuda_base}/lib64" ]; then
            cuda_lib="${cuda_base}/lib64"
            export LD_LIBRARY_PATH="${cuda_lib}:${LD_LIBRARY_PATH:-}"
            info "LD_LIBRARY_PATH cargado: ${cuda_lib}"
        fi
    fi

    # Verificar si CUDA está configurado en algún lugar del sistema
    if check_cuda_configured; then
        info "Configuración CUDA detectada en el sistema"
    else
        if [ -n "$cuda_bin" ]; then
            echo -e "  ${WARN} CUDA encontrado pero NO configurado en el sistema"
            if $FIX_MODE; then
                echo -e "        ${YELLOW}→ Agregar manualmente a ~/.bashrc:${NC}"
                echo -e "        ${YELLOW}  export PATH=${cuda_bin}\${PATH:+:\${PATH}}${NC}"
                if [ -n "$cuda_lib" ]; then
                    echo -e "        ${YELLOW}  export LD_LIBRARY_PATH=${cuda_lib}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}${NC}"
                fi
            fi
        fi
    fi
}

# =============================================================================
# --- Detección de módulos NVIDIA en kernel ---
# =============================================================================

# Verificar si NVIDIA está funcionando en el kernel (módulos open o propietarios)
check_nvidia_kernel_module() {
    # Verificar módulos clásicos y open
    lsmod 2>/dev/null | grep -qi 'nvidia' && return 0
    # Verificar vía /proc (funciona con módulos open y propietarios)
    [ -f /proc/driver/nvidia/version ] && return 0
    # Verificar si nvidia-smi funciona (prueba definitiva)
    nvidia-smi > /dev/null 2>&1 && return 0
    return 1
}

# Verificar si hay GPU NVIDIA en el sistema
check_nvidia_gpu() {
    # Verificar vía lspci (puede no estar en PATH)
    lspci 2>/dev/null | grep -qi 'nvidia\|GeForce\|Quadro\|Tesla' && return 0
    /usr/bin/lspci 2>/dev/null | grep -qi 'nvidia\|GeForce\|Quadro\|Tesla' && return 0
    /sbin/lspci 2>/dev/null | grep -qi 'nvidia\|GeForce\|Quadro\|Tesla' && return 0
    # Fallback: si nvidia-smi funciona, hay GPU
    nvidia-smi > /dev/null 2>&1 && return 0
    return 1
}

# =============================================================================
# --- Verificación de kernel para MongoDB 8 ---
# =============================================================================

# MongoDB 8 se niega a arrancar en kernels 6.19 - 7.0.13 (SERVER-121912).
# El guard de MongoDB lee el string de uname, no el sublevel upstream real, así que
# comparamos exactamente lo mismo que mira MongoDB. Ver Sección 14 del README.
# ponytail: dpkg --compare-versions en vez de parseo propio de versiones
check_kernel_mongodb_ok() {
    local kver="${1:-$(uname -r)}"
    kver="${kver%%-*}"                                  # 7.0.0-28-generic -> 7.0.0
    dpkg --compare-versions "$kver" lt 6.19
}

# =============================================================================
# --- Verificación de paquetes Python ---
# =============================================================================

# Verificar paquete Python usando pip3 show (más robusto que import)
check_pip_package() {
    local package="$1"
    pip3 show "$package" > /dev/null 2>&1 && return 0
    # Fallback: intentar import
    python3 -c "import ${package}" > /dev/null 2>&1 && return 0
    return 1
}

# =============================================================================
# --- Funciones de instalación específicas ---
# =============================================================================

# Instalar paquete(s) apt
fix_apt() {
    sudo apt-get install -y "$@"
}

# Instalar paquete snap
fix_snap() {
    sudo snap install "$1" --classic
}

# Instalar .deb desde URL
fix_deb_url() {
    local url="$1"
    local deb_file="/tmp/$(basename "$url")"
    wget -q -O "$deb_file" "$url" && \
    sudo apt-get install -y "$deb_file" && \
    rm -f "$deb_file"
}

# Instalar paquete(s) pip
fix_pip() {
    pip3 install --break-system-packages "$@"
}

# --- Repositorio MongoDB ---
fix_mongodb_repo_and_install() {
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "noble")
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg 2>/dev/null
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
    sudo apt-get update && sudo apt-get install -y mongodb-org
}

# --- Servicio MongoDB ---
fix_mongodb_service() {
    sudo systemctl start mongod && sudo systemctl enable mongod
}

# --- Repositorio EMQX ---
fix_emqx_repo_and_install() {
    curl -sL https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
    sudo apt-get install -y emqx
}

# --- Servicio EMQX ---
fix_emqx_service() {
    sudo systemctl start emqx && sudo systemctl enable emqx
}

# --- Repositorio AnyDesk ---
fix_anydesk_repo_and_install() {
    sudo apt-get install -y ca-certificates curl apt-transport-https
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
    sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
    echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list > /dev/null
    sudo apt-get update && sudo apt-get install -y anydesk
}

# --- Node-RED ---
fix_nodered() {
    bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --confirm-install --confirm-pi --no-init
}

# --- Servicio Node-RED ---
fix_nodered_service() {
    sudo systemctl enable nodered && sudo systemctl start nodered
}

# --- Neofetch ---
fix_neofetch() {
    sudo apt-get install -y neofetch
}

# --- libtinfo5 para Ubuntu 24.04 ---
fix_libtinfo5() {
    wget -q -O /tmp/libtinfo5.deb http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb && \
    sudo apt-get install -y /tmp/libtinfo5.deb && \
    rm -f /tmp/libtinfo5.deb
}

# --- GCC-12 para Ubuntu 22.04 ---
fix_gcc12() {
    sudo apt-get install -y gcc-12 g++-12 && \
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 && \
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120
}

# =============================================================================
# --- Resumen final ---
# =============================================================================
print_summary() {
    local station_type="$1"
    section "RESUMEN"

    echo ""
    echo -e "  Total de verificaciones:  ${BOLD}${total}${NC}"
    echo -e "  Correctas:                ${GREEN}${passed}${NC}"
    echo -e "  Fallidas:                 ${RED}${failed}${NC}"
    echo -e "  Avisos (críticos):        ${YELLOW}${warnings}${NC}"
    echo -e "  Notas (menores):          ${CYAN}${minors}${NC}"
    if $FIX_MODE; then
        echo -e "  Instalados con --fix:     ${GREEN}${fixed}${NC}"
    fi
    echo ""

    if [ "$failed" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}Estado: SALUDABLE${NC}"
        echo -e "  Todos los componentes de ${station_type} están instalados correctamente."
        if [ "$minors" -gt 0 ]; then
            echo -e "  ${CYAN}Hay ${minors} nota(s) menor(es) (puertos/configs opcionales).${NC}"
        fi
    elif [ "$failed" -eq 0 ]; then
        echo -e "  ${YELLOW}${BOLD}Estado: SALUDABLE CON AVISOS${NC}"
        echo -e "  Componentes esenciales OK. Revisa los avisos críticos."
    elif [ "$failed" -le 3 ]; then
        echo -e "  ${YELLOW}${BOLD}Estado: ATENCIÓN REQUERIDA${NC}"
        echo -e "  Algunos componentes faltan. Revisa los fallos indicados."
    else
        echo -e "  ${RED}${BOLD}Estado: REQUIERE INTERVENCIÓN${NC}"
        echo -e "  Múltiples componentes faltan. Revisa la guía de instalación."
    fi

    if $FIX_MODE; then
        echo ""
        echo -e "  Log completo: ${LOG_FILE}"
        if [ "$fixed" -gt 0 ]; then
            echo -e "  ${GREEN}Se instalaron ${fixed} componente(s) exitosamente.${NC}"
        fi
    elif [ "$failed" -gt 0 ]; then
        echo ""
        echo -e "  ${CYAN}Tip: Ejecuta con --fix para instalar componentes faltantes automáticamente.${NC}"
    fi

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}
