# Guía de Configuración de Estaciones de Trabajo Ubuntu con GPU NVIDIA

---

## Índice

* [1. Requisitos Previos a la Instalación](#1-requisitos-previos-a-la-instalación)
* [2. Instalación del Sistema Ubuntu](#2-instalación-del-sistema-ubuntu)
* [3. Preparación Inicial del Sistema Ubuntu](#3-preparación-inicial-del-sistema-ubuntu)
* [4. Instalación de Drivers de NVIDIA en Ubuntu](#4-instalación-de-drivers-de-nvidia-en-ubuntu)
* [5. Instalación de CUDA Toolkit](#5-instalación-de-cuda-toolkit)
* [6. Configuración Específica para Estaciones de Compresión](#6-configuración-específica-para-estaciones-de-compresión)
* [7. Configuración Específica para Estaciones de Analítica](#7-configuración-específica-para-estaciones-de-analítica)
* [8. Gestión de la Interfaz Gráfica](#8-gestión-de-la-interfaz-gráfica)
* [9. Solución de Problemas Comunes con Redes en Placas Nuevas](#9-solución-de-problemas-comunes-con-redes-en-placas-nuevas)
* [10. Wake-on-LAN (WOL): Windows a Windows y Ubuntu a Windows](#10-wake-on-lan-wol-windows-a-windows-y-ubuntu-a-windows)
* [Anexo A: Identificación de GPUs NVIDIA](#anexo-a-identificación-de-gpus-nvidia)
* [Anexo B: Verificación de Compatibilidad](#anexo-b-verificación-de-compatibilidad)

---

## 1. Requisitos Previos a la Instalación

* **Unidad de Instalación:** Una unidad flash USB booteable (Ventoy o BalenaEtcher pueden ser utilizados para crearla).
* **Imagen del Sistema:** Descargar previamente una versión de Ubuntu LTS:

  * Ubuntu Desktop 22.04 LTS o 24.04 LTS.
  * **Importante:** Las variantes (Kubuntu, Xubuntu, etc.) y Linux Mint *no* están oficialmente cubiertas en esta guía, aunque pueden seguir pasos similares. Se recomienda Ubuntu Desktop para una experiencia más estandarizada.
* **Propósito del Equipo:** Tener claro si el equipo será utilizado para **Compresión/Data** o para **Analítica**, ya que esto determinará las instalaciones posteriores específicas.

---

## 2. Instalación del Sistema Ubuntu

1. **Acceso a la BIOS/UEFI:** Reiniciar el equipo y presionar una tecla específica durante el arranque para acceder a la BIOS/UEFI (comúnmente `F2`, `F8`, `F11`, `F12`, `DEL` o `BACKSPACE`). Consulte el manual de su placa madre si no está seguro.
2. **Configuración de BIOS/UEFI:** Dentro de la BIOS/UEFI, navegue a la sección de configuración de seguridad y/o arranque y realice los siguientes cambios:

   * **Secure Boot:** Cambiar de `Enabled` a `Disabled`.
   * **TPM (si está presente):** Cambiar de `Enabled` a `Disabled`. *(Opcional en algunos casos, pero recomendado para evitar problemas de arranque con drivers de GPU)*
   * *(Opcional, pero recomendado para servidores)* **AC Power Loss:** Cambiar de `Always Off` a `Always On`.
3. **Guardar y Salir:** Guarde los cambios (generalmente `F10`) y salga de la BIOS/UEFI para reiniciar el equipo.
4. **Booteo desde USB:** Con la unidad flash conectada, el equipo debería arrancar desde ella. Si no lo hace, puede ser necesario seleccionar el dispositivo de arranque en el menú de arranque (usualmente `F12` u otra tecla específica).
5. **Selección de Imagen (si usa Ventoy):** Si usa Ventoy, seleccione la imagen de Ubuntu descargada.
6. **Inicio de Ubuntu (Modo de Prueba):** Seleccione la opción "Try or Install Ubuntu". **Antes de presionar Enter**, presione la tecla `E`. Esto abrirá un editor de texto con los parámetros de arranque.
7. **Edición de Parámetros de Arranque:**

   * Localice la línea que contiene `---`.
   * Agregue `nomodeset` después de los tres guiones, dejando un espacio entre `---` y `nomodeset`. *(Ejemplo: `... quiet splash --- nomodeset`)*
   * Presione `Ctrl+X` o `F10` para guardar temporalmente los cambios y arrancar.
   * **Explicación:** `nomodeset` deshabilita los drivers de video modernos durante el arranque, lo cual previene conflictos con tarjetas gráficas nuevas o no soportadas por los drivers genéricos incluidos en la ISO de Ubuntu.
8. **Asistente de Instalación:**

   * Una vez en el escritorio de Ubuntu, ejecute el asistente de instalación.
   * **Idioma:** Español.
   * **Opciones de Accesibilidad:** Siguiente.
   * **Disposición del Teclado:** Español Latinoamericano.
   * **Tipo de Instalación:** Seleccione "Instalación Normal".
   * **Opciones Adicionales:** Marque ambas casillas:

     * "Instalar software de terceros para gráficos y dispositivos de Wi-Fi"
     * "Descargar e instalar compatibilidad para más formatos multimedia"
   * **Instalación en Disco:** Seleccione "Borrar disco e instalar Ubuntu". *(Advertencia: Esto eliminará todos los datos del disco seleccionado).*
   * **Configuración de Usuario:** Ingrese su nombre, nombre de usuario (nombre corto sin espacios), contraseña y **desmarque** la opción "Solicitar mi contraseña para acceder".
   * **Zona Horaria:** Seleccione "Santiago".
   * **Confirmación y Reinicio:** Revise los datos y presione "Instalar". Al finalizar, el sistema solicitará reiniciar. Hágalo.
9. **Reinicio Final:** Al reiniciar, se le pedirá que retire la unidad flash USB. Hágalo y presione Enter.

---

## 3. Preparación Inicial del Sistema Ubuntu

⚠️ **ADVERTENCIA IMPORTANTE:**

* Los comandos que utilizan `sudo` otorgan privilegios de administrador y pueden alterar el sistema. Ejecútelos solo si entiende su función.
* Las credenciales mostradas en esta guía son **EJEMPLOS**. **Reemplácelas con sus propios datos.**
* **Verifique la compatibilidad** de los drivers de NVIDIA y CUDA con su hardware y versión de Ubuntu antes de proceder.

1. **Actualización del Sistema:** Abra una terminal y ejecute:

   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

   Ingrese su contraseña si se solicita y confirme con `Y` si es necesario.
2. **Reinicio:** Reinicie el sistema para aplicar las actualizaciones.

   ```bash
   sudo reboot
   ```
3. **Instalación de Dependencias Comunes:** Una vez reiniciado y logueado, instale paquetes necesarios para la instalación de drivers NVIDIA y otras herramientas.

   ```bash
   sudo apt install -y build-essential dkms pkg-config libglvnd-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev mesa-utils inxi net-tools openssh-server curl git wget
   ```

   Confirme con `Y` si es necesario.
4. **Configuración de GDM3 (Opcional pero Recomendado para Instalación Gráfica):** Si va a usar la interfaz gráfica, es recomendable deshabilitar Wayland para evitar problemas con drivers de GPU propietarios.

   * Edite el archivo de configuración:

     ```bash
     sudo nano /etc/gdm3/custom.conf
     ```
   * Busque la línea `#WaylandEnable=false` y **elimine el `#`** para descomentarla. *(Quedaría: `WaylandEnable=false`)*
   * Guarde (Ctrl+O, Enter) y cierre (Ctrl+X).
5. **Configuración de Firewall para SSH:** Permita el acceso SSH si planea administrar el sistema remotamente.

   ```bash
   sudo ufw allow ssh
   sudo ufw --force enable # Esto activa el firewall si aún no lo estaba
   ```
6. **Preparación Específica por Versión de Ubuntu:**

   * **Ubuntu 22.04 LTS:**

     * Instale GCC/G++ 12:

       ```bash
       sudo apt install -y gcc-12 g++-12
       ```
     * Configure `update-alternatives` para usar GCC/G++ 12:

       ```bash
       sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 1200 --slave /usr/bin/g++ g++ /usr/bin/g++-12
       ```
     * Verifique la versión:

       ```bash
       gcc --version
       g++ --version
       ```

       Debe mostrar `gcc (Ubuntu 12.x.x-0ubuntu1~22.04) 12.x.x` o similar.
   * **Ubuntu 24.04 LTS:**

     * Instale dependencia `libtinfo5` (necesaria para algunos drivers antiguos o herramientas):

       ```bash
       wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
       sudo apt install ./libtinfo5_6.3-2ubuntu0.1_amd64.deb
       rm libtinfo5_6.4+20231202-1_amd64.deb # Limpia el archivo descargado
       ```
7. **Reinicio Final:** Reinicie el sistema para aplicar todos los cambios.

   ```bash
   sudo reboot
   ```

---

## 4. Instalación de Drivers de NVIDIA en Ubuntu

1. **Identificación de la GPU:** Antes de descargar e instalar, identifique su tarjeta gráfica.

   * Ejecute:

     ```bash
     lspci | grep -i nvidia
     ```

     *(Opcional, para info gráfica)*

     ```bash
     DISPLAY=:0 glxinfo | grep "OpenGL renderer"
     ```
   * Consulte la [tabla de identificación de GPUs](#anexo-a-identificación-de-gpus-nvidia) para determinar la serie (3000, 4000, 5000).
2. **Verificación de Compatibilidad:** Consulte el [Anexo B](#anexo-b-verificación-de-compatibilidad) para asegurarse de que el driver y CUDA sean compatibles con su GPU y versión de Ubuntu.
3. **Eliminación de Drivers Antiguos:** Si ha instalado drivers de NVIDIA anteriormente (o paquetes como `nouveau`), es recomendable eliminarlos limpiamente.

   ```bash
   sudo apt-get purge nvidia-* --autoremove -y
   sudo apt-get autoremove -y
   ```

   Reinicie el sistema después de esta limpieza.

   ```bash
   sudo reboot
   ```
4. **Descarga del Driver:**

   * Vaya a la [página oficial de drivers de NVIDIA](https://www.nvidia.com/drivers/).
   * Seleccione su producto: GPU (GeForce, Quadro, etc.), Serie (GeForce RTX 40 Series), Modelo (RTX 4080), Sistema Operativo (Linux 64-bit), Versión (Ubuntu 22.0 o 24.0).
   * Descargue el archivo `.run` (driver de GPU).
   * *(Si no tiene GUI, copie el enlace de descarga directa y use `wget` en la terminal)*
5. **Preparación para Instalación:**

   * Asegúrese de que no esté corriendo el entorno gráfico (GDM) o cámbiese al modo texto (`sudo systemctl set-default multi-user.target` y reinicie).
   * Dé permisos de ejecución al archivo `.run`:

     ```bash
     chmod +x NVIDIA-Linux-x86_64-XXX.XX.run # Reemplace XXX.XX por el número de versión descargado
     ```
6. **Instalación del Driver:**

   * Ejecute el instalador con `sudo` y el flag `--dkms` para facilitar actualizaciones de kernel:

     ```bash
     sudo ./NVIDIA-Linux-x86_64-XXX.XX.run --dkms
     ```
   * El instalador le hará preguntas:

     * `The distribution-provided pre-install script failed! Are you sure you want to continue?` -> `Continue Installation`
     * `Would you like to register the kernel module sou...` -> `Yes` (si usó `--dkms`)
     * `Install NVIDIA's 32-bit compatibility libraries?` -> `Yes`
     * `Would you like to run nvidia-xconfig?` -> `No` (a menos que tenga una configuración X11 específica)
     * `Would you like to enable nvidia-apply-extra-quirks?` -> `Yes` (si está disponible)
   * El proceso tomará unos minutos.
7. **Verificación de la Instalación:**

   * Reinicie el sistema:

     ```bash
     sudo reboot
     ```
   * Después de reiniciar (y haber iniciado sesión en el entorno gráfico si lo usa), abra una terminal y ejecute:

     ```bash
     nvidia-smi
     ```
   * Si se muestra información sobre su GPU y la versión del driver, la instalación fue exitosa.

---

## 5. Instalación de CUDA Toolkit

1. **Verificación de Compatibilidad:** Asegúrese de que la versión de CUDA Toolkit que va a instalar sea compatible con su GPU y el driver de NVIDIA instalado. Consulte el [Anexo B](#anexo-b-verificación-de-compatibilidad).
2. **Descarga e Instalación del Repositorio (APT):**

   * Determine su versión de Ubuntu (22.04 o 24.04).
   * Siga los pasos en la [página de descargas de CUDA](https://developer.nvidia.com/cuda-downloads) para "Linux" -> "x86_64" -> "Ubuntu" -> "22.04" (o "24.04").
   * *(Ejemplo para Ubuntu 22.04 y CUDA 12.8)*

     * Descargue la clave GPG:

       ```bash
       wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
       ```
     * Instale la clave:

       ```bash
       sudo dpkg -i cuda-keyring_1.1-1_all.deb
       ```
     * Actualice la lista de paquetes:

       ```bash
       sudo apt-get update
       ```
     * Instale el toolkit:

       ```bash
       sudo apt-get -y install cuda-toolkit-12-8 # Ajuste la versión según la descargada
       ```
3. **Configuración de Variables de Entorno:**

   * Edite el archivo `.bashrc` de su usuario:

     ```bash
     nano ~/.bashrc
     ```
   * Al final del archivo, agregue las siguientes líneas (ajuste la versión de CUDA si es diferente):

     ```bash
     # CUDA Toolkit
     export PATH=/usr/local/cuda-12.8/bin:$PATH
     export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH
     ```
   * Guarde (Ctrl+O, Enter) y cierre (Ctrl+X).
   * Aplique los cambios en la sesión actual:

     ```bash
     source ~/.bashrc
     ```
4. **Verificación de la Instalación:**

   * Verifique la versión de `nvcc`:

     ```bash
     nvcc --version
     ```
   * Debería mostrar la versión de CUDA Toolkit instalada.

---

## 6. Configuración Específica para Estaciones de Compresión

Esta sección cubre las herramientas específicas necesarias para estaciones dedicadas a tareas de compresión y procesamiento de datos.

1. **Instalación de Paquetes Comunes:**

   ```bash
   sudo apt install -y terminator nvtop ffmpeg
   ```
2. **Instalación de MongoDB:**

   * Importe la clave GPG oficial:

     ```bash
     curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
     ```
   * Agregue el repositorio de MongoDB (ajuste `jammy` por `noble` si usa Ubuntu 24.04):

     ```bash
     echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
     ```
   * Actualice e instale MongoDB:

     ```bash
     sudo apt-get update
     sudo apt-get install -y mongodb-org
     ```
   * Inicie e habilite el servicio:

     ```bash
     sudo systemctl start mongod
     sudo systemctl enable mongod
     ```
   * *(Opcional)* Verifique el estado:

     ```bash
     sudo systemctl status mongod
     ```
3. **Instalación de MongoDB Compass (Interfaz Gráfica):**

   * Descargue el paquete `.deb` desde [MongoDB Compass Downloads](https://www.mongodb.com/products/compass).
   * Instálelo:

     ```bash
     sudo apt install ./mongodb-compass-<version>.deb # Reemplace <version> por el archivo descargado
     ```
4. **Instalación de EMQX:**

   * Agregue el repositorio (esto descarga e instala el script):

     ```bash
     curl -sL https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
     ```
   * Instale EMQX:

     ```bash
     sudo apt-get install emqx
     ```
   * Inicie el servicio:

     ```bash
     sudo systemctl start emqx
     sudo systemctl enable emqx
     ```
5. **Instalación de Golang (Snap):**

   ```bash
   sudo snap install go --classic
   ```
6. **Instalación de Visual Studio Code (Snap):**

   ```bash
   sudo snap install code --classic
   ```
7. **Instalación de GStreamer y Plugins:**

   ```bash
   sudo apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio gstreamer1.0-rtsp
   ```

   * Verifique la instalación de plugins específicos (ej. `rtspclientsink`, `nvh264enc`):

     ```bash
     gst-inspect-1.0 rtspclientsink
     gst-inspect-1.0 nvh264enc
     ```

     Si no se encuentran, puede ser necesario reinstalar los paquetes o verificar dependencias.
8. **Instalación de Angry IP Scanner:**

   * Descargue el paquete `.deb` desde [Angry IP Scanner Releases](https://github.com/angryip/ipscan/releases).
   * Instálelo:

     ```bash
     sudo apt install ./ipscan_<version>_amd64.deb # Reemplace <version> por el archivo descargado
     ```

---

## 7. Configuración Específica para Estaciones de Analítica

Esta sección cubre las herramientas específicas necesarias para estaciones dedicadas a tareas de análisis y machine learning.

1. **Instalación de MongoDB:**

   * Siga los mismos pasos que en la [sección 6, paso 2](#6-configuración-específica-para-estaciones-de-compresión).
2. **Configuración de MongoDB (Creación de Base de Datos y Usuario):**

   * Acceda a la consola de MongoDB:

     ```bash
     mongosh
     ```
   * Cree la base de datos y un usuario con permisos de lectura/escritura (reemplace `NOMBRE_BD`, `USUARIO`, `PASSWORD` por sus valores reales):

     ```javascript
     use NOMBRE_BD
     db.createUser({
       user: "USUARIO",
       pwd: "PASSWORD",
       roles: [
         {
           role: "readWrite",
           db: "NOMBRE_BD"
         }
       ]
     })
     ```
   * Edite la configuración de MongoDB para habilitar la autorización:

     ```bash
     sudo nano /etc/mongod.conf
     ```
   * Descomente la sección `security:` y agregue debajo (indentando 2 espacios):

     ```yaml
     security:
       authorization: enabled
     ```
   * Guarde (Ctrl+O, Enter) y cierre (Ctrl+X).
   * Reinicie el servicio para aplicar los cambios:

     ```bash
     sudo systemctl restart mongod
     ```
3. **Instalación de NodeRED:**

   * Ejecute el script de instalación:

     ```bash
     bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
     ```
   * Siga las instrucciones del script para configurar usuario y contraseña (reemplace `USUARIO_NODERED`, `PASSWORD_NODERED`):

     * Seleccione `Install` (o `Update` si ya está instalado).
     * Seleccione `Yes` para instalar Node.js si es necesario.
     * Configure usuario y contraseña.
     * Seleccione `Yes` para habilitar el arranque automático.
   * *(Opcional)* Habilite el servicio manualmente si no lo hizo el script:

     ```bash
     sudo systemctl enable nodered
     sudo systemctl start nodered
     ```
4. **Instalación de Python y Pip:**

   ```bash
   sudo apt install -y python3 python3-pip
   ```
5. **Instalación de Bibliotecas Python:**

   * Actualice pip:

     ```bash
     pip3 install --upgrade pip
     ```
   * Instale las bibliotecas necesarias:

     ```bash
     pip3 install pandas numpy scikit-learn paho-mqtt ultralytics
     ```

---

## 8. Gestión de la Interfaz Gráfica

Esta sección explica cómo activar o desactivar el entorno gráfico, útil para servidores que no lo necesitan.

* **Desactivar Interfaz Gráfica (Modo Servidor):**

  * Esto detiene el servicio de display manager (GDM) y cambia el target de arranque predeterminado a `multi-user.target`.

    ```bash
    sudo systemctl disable gdm3
    sudo systemctl set-default multi-user.target
    sudo reboot
    ```
* **Reactivar Interfaz Gráfica:**

  * Esto habilita el servicio de display manager (GDM) y cambia el target de arranque predeterminado a `graphical.target`.

    ```bash
    sudo systemctl enable gdm3
    sudo systemctl set-default graphical.target
    sudo reboot
    # Opcional: Iniciar GDM manualmente si no arranca con el target
    # sudo systemctl start gdm3
    ```
* **Explicación:** Desactivar la interfaz gráfica libera recursos del sistema (RAM, CPU) y es común en servidores dedicados que se administran por SSH. Reactivarla es necesario si necesita acceso visual o herramientas gráficas.

---

## 9. Solución de Problemas Comunes con Redes en Placas Nuevas

En placas madre muy nuevas, especialmente las que usan chips Realtek RTL8125, puede ocurrir que el controlador predeterminado (`r8169`) no funcione correctamente, y sea necesario usar el controlador `r8125` específico.

1. **Diagnóstico:** Verifique si la interfaz de red está presente y activa:

   ```bash
   ip link show
   # Busque una interfaz tipo ethX o enpXsY que no esté "DOWN"
   ```

   Si no aparece o está inactiva, puede ser un problema de controlador.
2. **Actualizar el sistema:**

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   ```
3. **Agregar PPA y reinstalar controlador:**
   *(Este PPA contiene versiones actualizadas de controladores)*

   ```bash
   sudo add-apt-repository ppa:kelebek333/rtl-kernel -y
   sudo apt update
   sudo apt install r8125-dkms -y
   ```
4. **Bloquear controlador antiguo:** Cree un archivo para evitar que el kernel cargue el controlador `r8169` para este hardware específico.

   ```bash
   echo 'blacklist r8169' | sudo tee /etc/modprobe.d/blacklist-r8169.conf
   ```
5. **Actualizar initramfs:** Esto asegura que el cambio se aplique al arranque.

   ```bash
   sudo update-initramfs -u
   ```
6. **Reiniciar:**

   ```bash
   sudo reboot
   ```
7. **Verificación Post-Reinicio:** Confirme que la interfaz de red ahora esté disponible y funcional.

   ```bash
   ip link show
   # Debe aparecer una interfaz UP
   lspci | grep -i ethernet # Debe mostrar el controlador, p. ej., 'RTL8125'
   ```

---

## 10. Wake-on-LAN (WOL): Windows a Windows y Ubuntu a Windows

> **Objetivo**: Encender (o reactivar) un PC con **Windows** a través de la red local, enviando un **paquete mágico** desde otro **Windows** o desde **Ubuntu**.

### 0) Requisitos previos en el PC **destino** (Windows)

* BIOS/UEFI:

  * Activa **Wake on LAN (WOL)** / **Power On by PCI‑E** / **S5 Wake on LAN** (nombres varían por fabricante).
  * Desactiva opciones de ahorro de energía profundo tipo **ERP/Deep Sleep** si el NIC queda sin energía al apagar.
* Windows → **Administrador de dispositivos** → *Adaptadores de red* → (tu NIC) → **Administración de energía**:

  * ☑ **Permitir que este dispositivo reactive el equipo**
  * ☑ **Sólo permitir un paquete mágico para reactivar el equipo**
  * ☑ **Permitir que el equipo apague este dispositivo para ahorrar energía** (suele ayudar en suspensión/hibernación)
* Windows → (misma tarjeta) → **Avanzado** (si existe):

  * **Wake on Magic Packet** → *Enabled*
  * **Shutdown Wake-On-Lan** / **WOL & Shutdown Link Speed** → *Enabled*
  * **Energy Efficient Ethernet (EEE)** → *Disabled* (si hay problemas de WOL)
* Desactivar **Inicio rápido** (Fast Startup):

  * Panel de control → *Opciones de energía* → *Elegir la acción de los botones de inicio/apagado* → *Cambiar configuración actualmente no disponible* → desmarca **Activar inicio rápido**.
* **Apagado correcto** (prueba WOL desde S5):

  * Menú *Apagar* o: `shutdown /s /t 0`
* **Anota la MAC** del adaptador (será necesaria para el envío):

  * `ipconfig /all` → *Dirección física* (ej.: `3C-52-82-11-22-33`).

> **Nota**: WOL por **Wi‑Fi** casi nunca está soportado. Usa **Ethernet**.

---

### 1) Enviar WOL **desde Windows** → **Windows**

#### 1.1 Opción recomendada: **PowerShell** (sin instalar nada)

**Crear el script** `Send-WOL.ps1` con el contenido siguiente:

```powershell
# Send-WOL.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Mac,
    [string]$Broadcast = "255.255.255.255",
    [int]$Port = 9
)

$macClean = ($Mac -replace '[:-]','')
if ($macClean.Length -ne 12) { throw "MAC inválida: $Mac" }

$macBytes = 0..5 | ForEach-Object { [Convert]::ToByte($macClean.Substring($_*2,2),16) }

$packet = New-Object byte[] (6 + 16*6)
for ($i=0; $i -lt 6; $i++) { $packet[$i] = 0xFF }
for ($i=0; $i -lt 16; $i++) { [Array]::Copy($macBytes, 0, $packet, 6 + $i*6, 6) }

$udp = New-Object System.Net.Sockets.UdpClient
$udp.EnableBroadcast = $true
[void]$udp.Send($packet, $packet.Length, $Broadcast, $Port)
$udp.Close()
Write-Host "WOL enviado a $Mac via $Broadcast:$Port"
```

**Uso rápido** (en la carpeta donde guardaste el script):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
./Send-WOL.ps1 -Mac "3C:52:82:11:22:33" -Broadcast "192.168.6.255" -Port 9
```

**One‑liner** (sin archivo, para casos puntuales):

```powershell
$mac="3C:52:82:11:22:33";$b="192.168.6.255";$p=9;$m=($mac -replace '[:-]','');$mb=0..5|%{[Convert]::ToByte($m.Substring($_*2,2),16)};$pkt=New-Object byte[](102);0..5|%{$pkt[$_]=0xFF};0..15|%{[Array]::Copy($mb,0,$pkt,6+$_*6,6)};$u=New-Object Net.Sockets.UdpClient;$u.EnableBroadcast=$true;$u.Send($pkt,$pkt.Length,$b,$p)|Out-Null;$u.Close()
```

**Verificar el envío**:

* Con **Wireshark** (en el equipo emisor): filtro `wol` o `udp.port == 9 or udp.port == 7`.

#### 1.2 Opción alternativa: herramienta de terceros (GUI/CLI)

Puedes usar cualquier utilidad de “Wake on LAN” para Windows (GUI o línea de comandos). Datos típicos a completar:

* **MAC** del destino (obligatoria)
* **Broadcast** de la subred (ej.: `192.168.6.255`)
* **Puerto** UDP (9 recomendado; 7 también funciona)

---

### 2) Enviar WOL **desde Ubuntu** → **Windows**

#### 2.1 Instalación de utilidades

```bash
sudo apt update
sudo apt install wakeonlan tcpdump   # (opcional) etherwake
```

#### 2.2 Envío del paquete mágico

* Con **wakeonlan** (simple):

```bash
wakeonlan -i 192.168.6.255 3C:52:82:11:22:33
```

* Con **etherwake** (indicando interfaz, p. ej. `eno1`):

```bash
sudo etherwake -i eno1 3C:52:82:11:22:33
```

#### 2.3 Verificar que el paquete salió (opcional)

```bash
sudo tcpdump -i eno1 -nn 'udp and (port 9 or port 7)'
```

En otra terminal lanza el `wakeonlan`; deberías ver un datagrama UDP al broadcast (x.x.x.255) en el puerto 9 o 7.

---

### 3) Comprobaciones en el PC **destino** (Windows)

* Espera 10–60 s y prueba conectividad:

```bash
ping 192.168.6.X
```

* Opcional: verifica servicios (RDP/SSH/HTTP) desde la red.
* Comando útil en el destino para ver el último origen de activación:

```powershell
powercfg -lastwake
powercfg -devicequery wake_armed
```

---

### 4) Problemas comunes y soluciones

* **No despierta desde apagado (S5), sólo desde suspensión**:

  * Activa **S5 Wake on LAN** o **Power On by PCI‑E** en BIOS.
* **Inicio rápido activo**:

  * Desactívalo (ver sección 0).
* **El LED del puerto se apaga al apagar**:

  * La placa corta energía al NIC. Revisa BIOS (ERP/Deep Sleep) y opciones de *Shutdown WOL*.
* **WOL por Wi‑Fi**:

  * Generalmente **no soportado**. Usa Ethernet.
* **El switch/router “silencia” el broadcast**:

  * En la **misma subred** no debería pasar. Entre **subredes/VLAN** necesitas **directed broadcast** en el router o un **WOL relay/proxy**.
* **Drivers Intel/Realtek**:

  * Revisa en *Avanzado*: *Wake on Magic Packet*, *Shutdown WOL*, y prueba **desactivar EEE**.
* **ARP perdido tras apagado prolongado** (cuando envías WOL desde otra subred):

  * Usa **static ARP** en el gateway o un **WOL proxy** siempre encendido en la LAN del destino.

---

### 5) Buenas prácticas

* Documenta **MAC**, **IP**, **broadcast** y **puerto** usados.
* Prueba primero en la **misma LAN** antes de montar WOL entre subredes o por Internet.
* Estándar de puertos: preferir **UDP/9** (o **UDP/7** si tu herramienta lo usa por defecto).

---

### 6) Plantillas rápidas

**Windows → Windows (PowerShell):**

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
./Send-WOL.ps1 -Mac "AA:BB:CC:DD:EE:FF" -Broadcast "192.168.6.255" -Port 9
```

**Ubuntu → Windows:**

```bash
wakeonlan -i 192.168.6.255 AA:BB:CC:DD:EE:FF
# o
sudo etherwake -i eno1 AA:BB:CC:DD:EE:FF
```

**Verificación en Ubuntu:**

```bash
sudo tcpdump -i eno1 -nn 'udp and (port 9 or port 7)'
```

**Verificación en Windows (destino):**

```powershell
powercfg -lastwake
powercfg -devicequery wake_armed
```

---

#### Glosario mínimo

* **Paquete mágico**: Trama que empieza con 6 bytes `FF` y contiene 16 repeticiones de la MAC del destino.
* **Broadcast**: IP de difusión de la subred (ej. `192.168.6.255` para /24).
* **Directed broadcast**: Envío de broadcast a otra subred (requiere soporte del router y, a veces, reglas específicas).

> **Listo**: con este manual puedes despertar un Windows desde otro Windows o desde Ubuntu en tu LAN. Ajusta los ejemplos con tu **MAC** real y el **broadcast** de tu red.

---

## Anexo A: Identificación de GPUs NVIDIA

Esta tabla ayuda a identificar la generación de su GPU NVIDIA basándose en la salida de `lspci | grep VGA`.

# NVIDIA GeForce RTX Serie 3000 - Identificación PCI

Esta tabla lista los Device IDs para las tarjetas RTX de la serie 3000 (arquitectura Ampere), útiles para identificar con `lspci | grep VGA`.

| Serie | Modelo      | Device ID (hex) |
| ----- | ----------- | --------------- |
| 3000  | RTX 3090    | 2204            |
| 3000  | RTX 3090 Ti | 22C6            |
| 3000  | RTX 3080    | 2206            |
| 3000  | RTX 3080 Ti | 2382            |
| 3000  | RTX 3070 Ti | 24C0            |
| 3000  | RTX 3070    | 2484            |
| 3000  | RTX 3060 Ti | 2489            |
| 3000  | RTX 3060    | 2503            |
| 3000  | RTX 3050 Ti | 2191            |
| 3000  | RTX 3050    | 25A0            |

# NVIDIA GeForce RTX Serie 4000 - Identificación PCI

Esta tabla lista los Device IDs para las tarjetas RTX de la serie 4000 (arquitectura Ada Lovelace), útiles para identificar con `lspci | grep VGA`.

| Serie | Modelo            | Device ID (hex) |
| ----- | ----------------- | --------------- |
| 4000  | RTX 4090          | 2684            |
| 4000  | RTX 4080 Super    | 2702            |
| 4000  | RTX 4080          | 2704            |
| 4000  | RTX 4070 Ti Super | 26B0            |
| 4000  | RTX 4070 Ti       | 2782            |
| 4000  | RTX 4070 Super    | 2788            |
| 4000  | RTX 4070          | 2786            |
| 4000  | RTX 4060 Ti       | 28A3            |
| 4000  | RTX 4060          | 2882            |
| 4000  | RTX 4050          | 28A1            |

# NVIDIA GeForce RTX Serie 5000 - Identificación PCI

Esta tabla lista los Device IDs para las tarjetas RTX de la serie 5000 (arquitectura Blackwell), útiles para identificar con `lspci | grep VGA`. Nota: Los IDs están basados en datos iniciales de 2025 y podrían actualizarse.

| Serie | Modelo      | Device ID (hex) |
| ----- | ----------- | --------------- |
| 5000  | RTX 5090    | 2B80            |
| 5000  | RTX 5080    | 2B81            |
| 5000  | RTX 5070 Ti | 2B82            |
| 5000  | RTX 5070    | 2B83            |
| 5000  | RTX 5060 Ti | 2B84            |
| 5000  | RTX 5060    | 2B85            |

---

## Anexo B: Verificación de Compatibilidad

Antes de instalar drivers o CUDA, verifique la compatibilidad.

1. **GPU y Driver NVIDIA:**

   * Visite [https://www.nvidia.com/drivers/](https://www.nvidia.com/drivers/).
   * Seleccione su GPU y sistema operativo. La página mostrará los drivers compatibles.
2. **Driver NVIDIA y CUDA Toolkit:**

   * Visite [https://developer.nvidia.com/cuda-downloads](https://developer.nvidia.com/cuda-downloads).
   * Busque la "CUDA Compatibility" o "CUDA Requirements" en la documentación o en la propia página de descargas.
   * Por ejemplo, CUDA 12.8 requiere un driver de NVIDIA >= 525.x.
   * Verifique la versión de su driver con `nvidia-smi`. El número de versión debe ser mayor o igual al mínimo requerido por CUDA.
3. **CUDA Toolkit y Ubuntu:**

   * La página de descargas de CUDA mencionada arriba también lista las versiones de Ubuntu soportadas para cada versión de CUDA Toolkit.
