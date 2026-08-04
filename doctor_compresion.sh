#!/bin/bash
# =============================================================================
# Doctor de Verificación - Estaciones de Compresión
# Verifica que todos los componentes necesarios estén instalados correctamente.
# Basado en las secciones 3-6 de la guía de configuración.
#
# Uso:
#   ./doctor_compresion.sh          Solo verificar
#   ./doctor_compresion.sh --fix    Verificar e instalar faltantes
# =============================================================================

set -uo pipefail

# --- Cargar librería compartida ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/doctor_lib.sh"

# --- Parsear argumentos ---
parse_args "$@"

# =============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Doctor de Verificación - Estación de Compresión        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Host:  $(hostname)"
# =============================================================================

# --- 1. Sistema Base ---
section "1. Sistema Operativo"

check_and_fix "Ubuntu instalado" "lsb_release -a 2>/dev/null | grep -qi ubuntu"

ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "desconocida")
info "Versión detectada: ${ubuntu_version}"

check_and_fix "Kernel Linux" "uname -r"
info "Kernel: $(uname -r)"

check_and_fix "Arquitectura x86_64" "uname -m | grep -q x86_64"

# --- 2. Preparación del Sistema (Sección 3) ---
section "2. Preparación del Sistema"

check_and_fix "build-essential instalado" \
    "dpkg -l build-essential 2>/dev/null | grep -q '^ii'" \
    "fix_apt build-essential"
check_and_fix "dkms instalado" \
    "dpkg -l dkms 2>/dev/null | grep -q '^ii'" \
    "fix_apt dkms"
check_and_fix "pkg-config instalado" \
    "command -v pkg-config" \
    "fix_apt pkg-config"
check_and_fix "GCC disponible" \
    "command -v gcc" \
    "fix_apt gcc"

gcc_version=$(gcc --version 2>/dev/null | head -1 || echo "no instalado")
info "GCC: ${gcc_version}"

check_and_fix "Git instalado" "command -v git" "fix_apt git"
check_and_fix "curl instalado" "command -v curl" "fix_apt curl"
check_and_fix "wget instalado" "command -v wget" "fix_apt wget"
check_and_fix "vim instalado" "command -v vim" "fix_apt vim"
check_and_fix "htop instalado" "command -v htop" "fix_apt htop"
check_and_fix "ncdu instalado" "command -v ncdu" "fix_apt ncdu"
check_and_fix "tree instalado" "command -v tree" "fix_apt tree"
check_and_fix "traceroute instalado" "command -v traceroute" "fix_apt traceroute"
check_and_fix "nmap instalado" "command -v nmap" "fix_apt nmap"
check_and_fix "inxi instalado" "command -v inxi" "fix_apt inxi"
check_and_fix "net-tools instalado" "command -v ifconfig" "fix_apt net-tools"
check_and_fix "lm-sensors instalado" "command -v sensors" "fix_apt lm-sensors"
check_and_fix "neofetch instalado" "command -v neofetch" "fix_neofetch"
check_and_fix "mesa-utils instalado" "command -v glxinfo" "fix_apt mesa-utils"

check_and_fix "Librerías OpenGL (libglvnd-dev)" \
    "dpkg -l libglvnd-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libglvnd-dev"
check_and_fix "Librerías Mesa (libgl1-mesa-dev)" \
    "dpkg -l libgl1-mesa-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libgl1-mesa-dev"
check_and_fix "Librerías EGL (libegl1-mesa-dev)" \
    "dpkg -l libegl1-mesa-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libegl1-mesa-dev"
check_and_fix "Librerías GLES (libgles2-mesa-dev)" \
    "dpkg -l libgles2-mesa-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libgles2-mesa-dev"
check_and_fix "Librerías X11 (libx11-dev)" \
    "dpkg -l libx11-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libx11-dev"
check_and_fix "Librerías Xmu (libxmu-dev)" \
    "dpkg -l libxmu-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libxmu-dev"
check_and_fix "Librerías Xi (libxi-dev)" \
    "dpkg -l libxi-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libxi-dev"
check_and_fix "Librerías GLU (libglu1-mesa-dev)" \
    "dpkg -l libglu1-mesa-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libglu1-mesa-dev"
check_and_fix "Librerías GStreamer dev" \
    "dpkg -l libgstreamer1.0-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libgstreamer1.0-dev"
check_and_fix "Librerías GStreamer plugins base dev" \
    "dpkg -l libgstreamer-plugins-base1.0-dev 2>/dev/null | grep -q '^ii'" \
    "fix_apt libgstreamer-plugins-base1.0-dev"

# --- 3. Wayland/Xorg ---
section "3. Entorno Gráfico"

session_type="${XDG_SESSION_TYPE:-desconocido}"
if [ "$session_type" = "x11" ]; then
    echo -e "  ${PASS} Sesión Xorg activa (Wayland desactivado)"
    total=$((total + 1))
    passed=$((passed + 1))
elif [ "$session_type" = "wayland" ]; then
    echo -e "  ${WARN} Sesión Wayland activa (se recomienda Xorg para NVIDIA)"
    total=$((total + 1))
    warnings=$((warnings + 1))
else
    echo -e "  ${INFO} Sesión gráfica: ${session_type} (modo texto o sin sesión gráfica)"
    total=$((total + 1))
    passed=$((passed + 1))
fi

target=$(systemctl get-default 2>/dev/null || echo "desconocido")
info "Target actual: ${target}"

# --- 4. SSH y Firewall ---
section "4. SSH y Firewall"

check_and_fix "OpenSSH Server instalado" \
    "dpkg -l openssh-server 2>/dev/null | grep -q '^ii'" \
    "fix_apt openssh-server"
check_and_fix_warn "Servicio SSH activo" "systemctl is-active ssh"
check_and_fix_warn "UFW instalado" "command -v ufw" "fix_apt ufw"

if command -v ufw > /dev/null 2>&1; then
    ufw_status=$(sudo ufw status 2>/dev/null | head -1 || echo "no disponible")
    info "UFW: ${ufw_status}"
fi

# --- 5. Drivers NVIDIA (Sección 4) ---
section "5. Drivers NVIDIA"

check_manual "nvidia-smi disponible" \
    "command -v nvidia-smi" \
    "Instala drivers NVIDIA siguiendo la sección 4 de la guía"

if command -v nvidia-smi > /dev/null 2>&1; then
    if nvidia-smi > /dev/null 2>&1; then
        echo -e "  ${PASS} Driver NVIDIA funcionando"
        passed=$((passed + 1))
        total=$((total + 1))

        driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        gpu_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)

        info "GPU: ${gpu_name}"
        info "Driver: ${driver_version}"
        info "VRAM: ${gpu_mem}"
    else
        echo -e "  ${FAIL} nvidia-smi existe pero falla al ejecutar"
        failed=$((failed + 1))
        total=$((total + 1))
    fi
else
    info "nvidia-smi no encontrado, omitiendo detalles de GPU"
fi

check_and_fix "Módulo NVIDIA cargado en kernel" "check_nvidia_kernel_module"
check_and_fix "GPU NVIDIA detectada" "check_nvidia_gpu"

# --- 6. CUDA Toolkit (Sección 5) ---
section "6. CUDA Toolkit"

# Detectar CUDA desde el filesystem si no está en el PATH
detect_cuda_from_system

check_manual "nvcc (compilador CUDA) disponible" \
    "command -v nvcc" \
    "Instala CUDA Toolkit siguiendo la sección 5 de la guía"

if command -v nvcc > /dev/null 2>&1; then
    cuda_version=$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release //' | sed 's/,.*//')
    info "CUDA: ${cuda_version}"
fi

check_and_fix "PATH incluye CUDA" "echo \"\$PATH\" | grep -qi cuda"
check_and_fix "LD_LIBRARY_PATH incluye CUDA" "echo \"\${LD_LIBRARY_PATH:-}\" | grep -qi cuda"
check_and_fix "Configuración CUDA en el sistema" "check_cuda_configured"

# --- 7. MongoDB (Sección 6) ---
section "7. MongoDB"

check_manual "Kernel compatible con MongoDB 8 (fuera de 6.19-7.0.13)" \
    "check_kernel_mongodb_ok" \
    "Kernel $(uname -r) bloquea el arranque de mongod (SERVER-121912). Aplica la Sección 14 del README: volver al track GA 6.8."

check_and_fix "MongoDB instalado (mongod)" \
    "command -v mongod" \
    "fix_mongodb_repo_and_install"
check_and_fix "MongoDB Shell (mongosh)" \
    "command -v mongosh"
check_and_fix_warn "Servicio mongod activo" \
    "systemctl is-active mongod" \
    "fix_mongodb_service"
check_and_fix_warn "Servicio mongod habilitado al inicio" \
    "systemctl is-enabled mongod" \
    "sudo systemctl enable mongod"

if systemctl is-active mongod > /dev/null 2>&1; then
    mongo_version=$(mongod --version 2>/dev/null | head -1 || echo "desconocida")
    info "MongoDB: ${mongo_version}"
fi

check_and_fix_warn "MongoDB Compass instalado" \
    "command -v mongodb-compass" \
    "fix_deb_url '${MONGODB_COMPASS_URL}'"

# --- 8. EMQX (Sección 6) ---
section "8. EMQX (Broker MQTT)"

check_and_fix "EMQX instalado" \
    "command -v emqx" \
    "fix_emqx_repo_and_install"
check_and_fix_warn "Servicio EMQX activo" \
    "systemctl is-active emqx" \
    "fix_emqx_service"
check_and_fix_warn "Servicio EMQX habilitado al inicio" \
    "systemctl is-enabled emqx" \
    "sudo systemctl enable emqx"

if systemctl is-active emqx > /dev/null 2>&1; then
    info "Dashboard EMQX: http://localhost:18083"
fi

# --- 9. Golang (Sección 6) ---
section "9. Golang"

check_and_fix "Go instalado" "command -v go" "fix_snap go"

if command -v go > /dev/null 2>&1; then
    go_version=$(go version 2>/dev/null || echo "desconocida")
    info "${go_version}"
fi

# --- 10. Visual Studio Code (Sección 6) ---
section "10. Visual Studio Code"

check_and_fix "VSCode instalado" "command -v code" "fix_snap code"

if command -v code > /dev/null 2>&1; then
    code_version=$(code --version 2>/dev/null | head -1 || echo "desconocida")
    info "VSCode: ${code_version}"
fi

# --- 11. GStreamer (Sección 6) ---
section "11. GStreamer y Plugins"

check_and_fix "GStreamer instalado (gst-launch-1.0)" \
    "command -v gst-launch-1.0" \
    "fix_apt gstreamer1.0-tools"
check_and_fix "gst-inspect-1.0 disponible" \
    "command -v gst-inspect-1.0" \
    "fix_apt gstreamer1.0-tools"
check_and_fix "Plugin base" \
    "dpkg -l gstreamer1.0-plugins-base 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-plugins-base"
check_and_fix "Plugin good" \
    "dpkg -l gstreamer1.0-plugins-good 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-plugins-good"
check_and_fix "Plugin bad" \
    "dpkg -l gstreamer1.0-plugins-bad 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-plugins-bad"
check_and_fix "Plugin ugly" \
    "dpkg -l gstreamer1.0-plugins-ugly 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-plugins-ugly"
check_and_fix "Plugin libav" \
    "dpkg -l gstreamer1.0-libav 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-libav"
check_and_fix "Plugin RTSP" \
    "dpkg -l gstreamer1.0-rtsp 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-rtsp"
check_and_fix "Plugin tools" \
    "dpkg -l gstreamer1.0-tools 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-tools"
check_and_fix "Plugin X11" \
    "dpkg -l gstreamer1.0-x 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-x"
check_and_fix "Plugin ALSA" \
    "dpkg -l gstreamer1.0-alsa 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-alsa"
check_and_fix "Plugin OpenGL" \
    "dpkg -l gstreamer1.0-gl 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-gl"
check_and_fix "Plugin GTK3" \
    "dpkg -l gstreamer1.0-gtk3 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-gtk3"
check_and_fix "Plugin Qt5" \
    "dpkg -l gstreamer1.0-qt5 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-qt5"
check_and_fix "Plugin PulseAudio" \
    "dpkg -l gstreamer1.0-pulseaudio 2>/dev/null | grep -q '^ii'" \
    "fix_apt gstreamer1.0-pulseaudio"
check_and_fix_warn "Plugin NVIDIA (nvh264enc)" "gst-inspect-1.0 nvh264enc"
check_and_fix_warn "Plugin rtspclientsink" "gst-inspect-1.0 rtspclientsink"

# --- 12. Herramientas de Red y Soporte Remoto (Sección 6) ---
section "12. Herramientas de Red y Soporte Remoto"

check_and_fix_warn "Angry IP Scanner instalado" \
    "command -v ipscan" \
    "fix_deb_url '${IPSCAN_URL}'"
check_and_fix_warn "AnyDesk instalado" \
    "command -v anydesk" \
    "fix_anydesk_repo_and_install"
check_and_fix_warn "RustDesk instalado" \
    "command -v rustdesk" \
    "fix_deb_url '${RUSTDESK_URL}'"

# --- 13. Puertos (Sección 6) ---
section "13. Puertos y Conectividad"

check_and_fix "Conexión a internet" "ping -c 1 -W 3 8.8.8.8"
check_and_fix "Resolución DNS" "host google.com"

if command -v ufw > /dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "active"; then
    info "Verificando reglas de firewall..."
    check_and_fix_minor "Puerto SSH (22) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])22(/|[^0-9]|\$)'" \
        "sudo ufw allow ssh"
    check_and_fix_minor "Puerto MongoDB (27017) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])27017(/|[^0-9]|\$)'" \
        "sudo ufw allow 27017/tcp"
    check_and_fix_minor "Puerto EMQX MQTT (1883) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])1883(/|[^0-9]|\$)'" \
        "sudo ufw allow 1883/tcp"
    check_and_fix_minor "Puerto EMQX Dashboard (18083) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])18083(/|[^0-9]|\$)'" \
        "sudo ufw allow 18083/tcp"
    check_and_fix_minor "Puerto GStreamer RTSP (554) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])554(/|[^0-9]|\$)'" \
        "sudo ufw allow 554/tcp && sudo ufw allow 554/udp"
    check_and_fix_minor "Puerto AnyDesk HTTP (80) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])80(/|[^0-9]|\$)'" \
        "sudo ufw allow 80/tcp"
    check_and_fix_minor "Puerto AnyDesk HTTPS (443) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])443(/|[^0-9]|\$)'" \
        "sudo ufw allow 443/tcp"
    check_and_fix_minor "Puerto AnyDesk (6568) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])6568(/|[^0-9]|\$)'" \
        "sudo ufw allow 6568/tcp"
    check_and_fix_minor "Puerto AnyDesk UDP (50001-50003) configurado" \
        "sudo ufw status | grep -qE '(^|[^0-9])50001(/|[^0-9]|\$|:)'" \
        "sudo ufw allow 50001:50003/udp"
else
    info "UFW no activo, omitiendo verificación de puertos"
fi

# --- 14. Versión de Ubuntu específica ---
section "14. Dependencias Específicas por Versión"

if [[ "$ubuntu_version" == "24.04"* ]]; then
    check_and_fix_warn "libtinfo5 instalado (requerido en 24.04)" \
        "dpkg -l libtinfo5 2>/dev/null | grep -q '^ii'" \
        "fix_libtinfo5"
elif [[ "$ubuntu_version" == "22.04"* ]]; then
    check_and_fix "GCC-12 instalado" "gcc-12 --version" "fix_gcc12"
    check_and_fix "G++-12 instalado" "g++-12 --version"
fi

# =============================================================================
print_summary "compresión"
exit $((failed > 255 ? 1 : failed))
