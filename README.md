# Guía Mejorada de Configuración de Estaciones de Trabajo Ubuntu con GPU NVIDIA

> **Última actualización:** 16 de Octubre de 2025

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
* [11. Script de Post-Instalación (Opcional)](#11-script-de-post-instalación-opcional)
* [12. Buenas Prácticas de Seguridad (Opcional)](#12-buenas-prácticas-de-seguridad-opcional)
* [FAQ: Preguntas Frecuentes](#faq-preguntas-frecuentes)
* [Anexo A: Identificación de GPUs NVIDIA](#anexo-a-identificación-de-gpus-nvidia)
* [Anexo B: Verificación de Compatibilidad](#anexo-b-verificación-de-compatibilidad)

---

> **¡Bienvenido!** Esta guía mejorada te ayudará a instalar y configurar Ubuntu con GPU NVIDIA, optimizando cada paso y explicando el porqué de cada acción. Los comandos y procedimientos originales se mantienen intactos, pero se agregan explicaciones, tips y advertencias para facilitar el proceso.

---

## Resumen Visual del Proceso

`BIOS/UEFI` → `Instalación de Ubuntu` → `Preparación del Sistema` → `Drivers NVIDIA` → `CUDA Toolkit` → `Configuración Específica`

---

## 1. Requisitos Previos a la Instalación


### ¿Qué necesitas antes de comenzar?

* **Unidad USB booteable** Usa Ventoy o BalenaEtcher para crearla.
* **Imagen de Ubuntu Desktop** Descarga la versión LTS recomendada (22.04 o 24.04).
* **Propósito del equipo** Define si será para Compresión/Data o Analítica.

> **Tip:** Ubuntu Desktop es la opción más estándar y compatible para este tipo de configuraciones.

---

## 2. Instalación del Sistema Ubuntu


### Pasos clave y recomendaciones

1. **Accede a la BIOS/UEFI** (teclas comunes: F2, F8, F11, F12, DEL, BACKSPACE).
2. **Configura la BIOS/UEFI:**
  * Desactiva Secure Boot y TPM.
  * (Opcional) Configura AC Power Loss en Always On para servidores.
3. **Guarda y reinicia** (usualmente F10).
4. **Bootea desde USB** y selecciona la imagen de Ubuntu.
5. **Edita parámetros de arranque:**
  * Agrega `nomodeset` después de `---` para evitar conflictos gráficos.
  * Explicación: Esto previene problemas con GPUs nuevas no soportadas por drivers genéricos.
6. **Instala Ubuntu:**
  * Elige idioma, teclado, instalación normal y marca las opciones de software de terceros y multimedia.
  * Configura usuario y zona horaria.
  * **Advertencia:** "Borrar disco e instalar Ubuntu" elimina todos los datos.
7. **Reinicia y retira la USB.**

> **Nota:** Si tienes dudas sobre alguna opción de BIOS, consulta el manual de tu placa madre.

---

## 3. Preparación Inicial del Sistema Ubuntu
* **Configuración de GDM3 (Opcional pero Recomendado para Instalación Gráfica):** Si vas a usar la interfaz gráfica, es recomendable deshabilitar Wayland para evitar problemas con drivers propietarios.

  Edita el archivo de configuración:
  ```bash
  sudo nano /etc/gdm3/custom.conf
  ```
  Busca la línea `#WaylandEnable=false` y **elimina el `#`** para descomentarla. Quedaría:
  ```
  WaylandEnable=false
  ```
  Guarda (Ctrl+O, Enter) y cierra (Ctrl+X).


### Antes de instalar drivers, prepara el sistema

* **Actualiza el sistema**

  ```bash
  sudo apt update && sudo apt upgrade -y
  ```

* **Reinicia para aplicar actualizaciones**

  ```bash
  sudo reboot
  ```

* **Instala dependencias comunes**

  ```bash
  sudo apt install -y build-essential dkms pkg-config libglvnd-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev mesa-utils inxi net-tools openssh-server curl git wget
  ```

* **Configura GDM3 (opcional):** Desactiva Wayland para evitar problemas con drivers propietarios.

* **Configura el firewall para SSH**

  ```bash
  sudo ufw allow ssh
  sudo ufw --force enable
  ```

* **Preparación específica por versión de Ubuntu**
  * **Ubuntu 22.04:** Instala y configura GCC/G++ 12.
  * **Ubuntu 24.04:** Instala la dependencia `libtinfo5` (necesaria para algunos drivers/herramientas antiguas). Puedes descargar el paquete directamente desde el repositorio oficial:

    [Descargar libtinfo5 para Ubuntu 24.04 (noble)](http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb)

    ```bash
    wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
    sudo apt install ./libtinfo5_6.3-2ubuntu0.1_amd64.deb
    rm libtinfo5_6.3-2ubuntu0.1_amd64.deb # Limpia el archivo descargado
    ```

> **Advertencia:** Verifica compatibilidad de drivers y CUDA antes de instalar. Los comandos con `sudo` pueden alterar el sistema.

---

## 4. Instalación de Drivers de NVIDIA en Ubuntu
* **Preparación para Instalación:**
  Asegúrate de que no esté corriendo el entorno gráfico (GDM) o cámbiate al modo texto:
  ```bash
  sudo systemctl set-default multi-user.target
  sudo reboot
  ```
  Da permisos de ejecución al archivo `.run`:
  ```bash
  sudo chmod +x NVIDIA-Linux-x86_64-XXX.XX.run # Reemplaza XXX.XX por el número de versión descargado
  ```
* **Instalación del Driver:**
  Ejecuta el instalador con `sudo` y el flag `--dkms` para facilitar actualizaciones de kernel:
  ```bash
  sudo ./NVIDIA-Linux-x86_64-XXX.XX.run --dkms
  ```
  El instalador te hará preguntas:
  - `The distribution-provided pre-install script failed! Are you sure you want to continue?` -> `Continue Installation`
  - `Would you like to register the kernel module sou...` -> `Yes` (si usaste `--dkms`)
  - `Install NVIDIA's 32-bit compatibility libraries?` -> `Yes`
  - `Would you like to run nvidia-xconfig?` -> `No` (a menos que tengas una configuración X11 específica)
  - `Would you like to enable nvidia-apply-extra-quirks?` -> `Yes` (si está disponible)


### ¿Cómo instalar correctamente los drivers?

* **Identifica tu GPU**

  ```bash
  lspci | grep -i nvidia
  ```

* **Verifica compatibilidad** Consulta la tabla de GPUs y el Anexo B.

* **Elimina drivers antiguos**

  ```bash
  sudo apt-get purge '^nvidia-.*'
  sudo apt-get purge nvidia-* --autoremove -y
  sudo apt-get autoremove -y
  sudo reboot
  ```

* **Descarga el driver oficial** desde la web de NVIDIA:

  [Página oficial de drivers NVIDIA](https://www.nvidia.com/drivers/)

  Selecciona tu GPU, sistema operativo y versión. Descarga el archivo `.run` manualmente desde la web, o copia el enlace directo y descárgalo por terminal con `wget`:

  ```bash
  wget https://us.download.nvidia.com/XFree86/Linux-x86_64/XXX.XX/NVIDIA-Linux-x86_64-XXX.XX.run
  # Reemplaza XXX.XX por la versión que corresponda a tu GPU y sistema
  ```

* **Prepara la instalación**
  * Cambia a modo texto si es necesario.
  * Da permisos de ejecución al archivo `.run`.

* **Instala el driver**
  * Usa el flag `--dkms` para facilitar actualizaciones de kernel.
  * Responde a las preguntas del instalador según las recomendaciones.

* **Verifica la instalación**

  ```bash
  nvidia-smi
  ```
  * Si ves información de tu GPU, ¡todo está correcto!

> **Tip:** Si tienes problemas con el entorno gráfico, revisa la sección de gestión de la interfaz gráfica.

---

## 5. Instalación de CUDA Toolkit

### Instala CUDA de forma segura y compatible

> **Importante:** Verifica compatibilidad en el Anexo B antes de instalar. Asegúrate de que tu GPU y driver NVIDIA sean compatibles con la versión de CUDA deseada.

Existen dos métodos principales para instalar CUDA Toolkit: mediante repositorio APT (recomendado para facilidad de actualización) o instalación manual con el archivo `.run` (mayor control).

---

#### **Método 1: Instalación mediante Repositorio APT (Recomendado)**

Este método facilita las actualizaciones y gestión de paquetes.

1. **Descarga e instala la clave del repositorio:**

   Para Ubuntu 24.04:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   ```

   Para Ubuntu 22.04:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   ```

2. **Instala CUDA Toolkit:**

   Para instalar la última versión disponible:
   ```bash
   sudo apt-get install -y cuda-toolkit
   ```

   Para instalar una versión específica (ejemplo: CUDA 12.8):
   ```bash
   sudo apt-get install -y cuda-toolkit-12-8
   ```

3. **Configura variables de entorno:**

   Edita tu archivo `.bashrc`:
   ```bash
   nano ~/.bashrc
   ```

   Agrega estas líneas al final (ajusta la versión según lo instalado):
   ```bash
   export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
   export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
   ```

   Guarda (Ctrl+O, Enter) y cierra (Ctrl+X).

   Recarga el archivo `.bashrc`:
   ```bash
   source ~/.bashrc
   ```

4. **Verifica la instalación:**

   ```bash
   nvcc --version
   ```

   Deberías ver información sobre la versión de CUDA instalada.

---

#### **Método 2: Instalación Manual con archivo .run**

Este método ofrece mayor control sobre qué componentes instalar.

1. **Descarga el instalador desde la web oficial:**

   Visita [https://developer.nvidia.com/cuda-downloads](https://developer.nvidia.com/cuda-downloads) y selecciona:
   - Sistema operativo: Linux
   - Arquitectura: x86_64
   - Distribución: Ubuntu
   - Versión: 22.04 o 24.04
   - Installer Type: **runfile (local)**

   Descarga con `wget` (ejemplo para CUDA 12.8):
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_550.54.15_linux.run
   ```

2. **Prepara el sistema:**

   Cambia a modo texto (opcional pero recomendado):
   ```bash
   sudo systemctl set-default multi-user.target
   sudo reboot
   ```

   Da permisos de ejecución:
   ```bash
   chmod +x cuda_12.8.0_550.54.15_linux.run
   ```

3. **Ejecuta el instalador:**

   ```bash
   sudo sh cuda_12.8.0_550.54.15_linux.run
   ```

   **Durante la instalación:**
   - Acepta el EULA (End User License Agreement)
   - **NO instales el driver si ya tienes uno instalado** (desmarca esa opción)
   - Selecciona los componentes que deseas instalar:
     - CUDA Toolkit (obligatorio)
     - CUDA Samples (opcional)
     - CUDA Documentation (opcional)

4. **Configura variables de entorno:**

   Edita tu archivo `.bashrc`:
   ```bash
   nano ~/.bashrc
   ```

   Agrega estas líneas al final:
   ```bash
   export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
   export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
   ```

   Guarda (Ctrl+O, Enter) y cierra (Ctrl+X).

   Recarga el archivo `.bashrc`:
   ```bash
   source ~/.bashrc
   ```

5. **Verifica la instalación:**

   ```bash
   nvcc --version
   nvidia-smi
   ```

6. **Reactiva el entorno gráfico (si lo desactivaste):**

   ```bash
   sudo systemctl set-default graphical.target
   sudo reboot
   ```

---

### ¿Qué método elegir?

| Característica | Repositorio APT | Instalador .run |
|----------------|-----------------|-----------------|
| **Facilidad de instalación** | ⭐⭐⭐⭐⭐ Muy fácil | ⭐⭐⭐ Moderado |
| **Actualizaciones** | ⭐⭐⭐⭐⭐ Automáticas con `apt` | ⭐⭐ Manual |
| **Control de componentes** | ⭐⭐⭐ Limitado | ⭐⭐⭐⭐⭐ Total |
| **Múltiples versiones** | ⭐⭐⭐ Posible pero complejo | ⭐⭐⭐⭐⭐ Fácil |
| **Recomendado para** | Usuarios generales | Desarrolladores avanzados |

> **Recomendación:** Para la mayoría de usuarios, el método de repositorio APT es más conveniente y facilita el mantenimiento del sistema.

> **Advertencia:** Instalar CUDA puede requerir reiniciar el sistema. Si encuentras conflictos con drivers, revisa la sección 4 sobre drivers NVIDIA.

> **Nota:** Para Ubuntu 24.04, CUDA 12.8 o superior es recomendado. Consulta siempre la compatibilidad en el Anexo B.

---

## 6. Configuración Específica para Estaciones de Compresión
* **Instalación de MongoDB:**
  Importe la clave GPG oficial:
  ```bash
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  ```
  Agrega el repositorio de MongoDB (ajusta `jammy` por `noble` si usas Ubuntu 24.04):
  ```bash
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  ```
  Actualiza e instala MongoDB:
  ```bash
  sudo apt-get update
  sudo apt-get install -y mongodb-org
  ```
  Inicia y habilita el servicio:
  ```bash
  sudo systemctl start mongod
  sudo systemctl enable mongod
  ```
  (Opcional) Verifica el estado:
  ```bash
  sudo systemctl status mongod
  ```


### Herramientas recomendadas para compresión/data

A continuación se listan las instalaciones de herramientas adicionales para estaciones de compresión/data.

* **Instalación de EMQX:**
  
  Agrega el repositorio e instala:
  ```bash
  curl -sL https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
  sudo apt-get install emqx
  ```
  
  Inicia y habilita el servicio:
  ```bash
  sudo systemctl start emqx
  sudo systemctl enable emqx
  ```
  
  (Opcional) Verifica el estado:
  ```bash
  sudo systemctl status emqx
  ```

* **Instalación de Golang (Snap):**
  
  ```bash
  sudo snap install go --classic
  ```

* **Instalación de Visual Studio Code (Snap):**
  
  ```bash
  sudo snap install code --classic
  ```

* **Instalación de GStreamer y Plugins:**
  
  Instala los plugins necesarios:
  ```bash
  sudo apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio gstreamer1.0-rtsp
  ```
  
  Verifica la instalación de plugins específicos:
  ```bash
  gst-inspect-1.0 rtspclientsink
  gst-inspect-1.0 nvh264enc
  ```

* **Instalación de Angry IP Scanner:**
  
  Descarga el paquete `.deb` desde [Angry IP Scanner Releases](https://github.com/angryip/ipscan/releases) e instálalo:
  ```bash
  sudo apt install ./ipscan_<version>_amd64.deb
  # Reemplaza <version> por el archivo descargado
  ```

* **Instalación de Anydesk para soporte remoto:**
  
  Agrega el repositorio oficial e instala:
  ```bash
  sudo apt update
  sudo apt install ca-certificates curl apt-transport-https
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
  sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
  echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list > /dev/null
  sudo apt update
  sudo apt install anydesk
  ```
  
  > **Importante:** Toma nota del ID de Anydesk y configura una contraseña única.

* **Instalación de Rustdesk para soporte remoto:**
  
  Descarga el paquete `.deb` desde [Rustdesk Releases](https://github.com/rustdesk/rustdesk/releases) (versión x86-64 para Ubuntu) e instálalo:
  ```bash
  sudo apt install ./<paquete.deb>
  # Reemplaza <paquete.deb> por el nombre del archivo descargado
  ```
  
  > **Importante:** Toma nota del ID de Rustdesk, configura una contraseña única y marca la casilla que permite conexión con IP directa.

* **Tips:**
  * Verifica el estado de los servicios tras la instalación.
  * Configura contraseñas únicas para acceso remoto.
  * Revisa la instalación de plugins específicos con `gst-inspect-1.0`.

> **Recursos Adicionales:**
> * [Documentación oficial de MongoDB](https://www.mongodb.com/docs/)
> * [Documentación oficial de EMQX](https://www.emqx.io/docs/)
> * [Documentación oficial de GStreamer](https://gstreamer.freedesktop.org/documentation/)

---

## 7. Configuración Específica para Estaciones de Analítica
* **Configuración de MongoDB (Creación de Base de Datos y Usuario):**
  Accede a la consola de MongoDB:
  ```bash
  mongosh
  ```
  Crea la base de datos y un usuario con permisos de lectura/escritura (reemplaza `NOMBRE_BD`, `USUARIO`, `PASSWORD` por tus valores reales):
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
  Edita la configuración de MongoDB para habilitar la autorización:
  ```bash
  sudo nano /etc/mongod.conf
  ```
  Descomenta la sección `security:` y agrega debajo (indentando 2 espacios):
  ```yaml
  security:
    authorization: enabled
  ```
  Guarda (Ctrl+O, Enter) y cierra (Ctrl+X).
  Reinicia el servicio para aplicar los cambios:
  ```bash
  sudo systemctl restart mongod
  ```
* **Instalación de NodeRED:**
  Ejecuta el script de instalación:
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
  ```
  (Opcional) Habilita el servicio manualmente si no lo hizo el script:
  ```bash
  sudo systemctl enable nodered
  sudo systemctl start nodered
  ```
  (Opcional) Verifica el estado:
  ```bash
  sudo systemctl status nodered
  ```


### Herramientas recomendadas para analítica/machine learning

A continuación se listan las instalaciones de herramientas adicionales para estaciones de analítica.

* **Instalación de Python y Pip:**
  
  ```bash
  sudo apt install -y python3 python3-pip
  ```

* **Instalación de Bibliotecas Python para Machine Learning:**
  
  Actualiza pip:
  ```bash
  pip3 install --upgrade pip
  ```
  
  Instala las bibliotecas necesarias:
  ```bash
  pip3 install pandas numpy scikit-learn paho-mqtt ultralytics
  ```
  
  > **Nota:** Puedes agregar más bibliotecas según tus necesidades (matplotlib, tensorflow, pytorch, opencv-python, etc.).

> **Recursos Adicionales:**
> * [Documentación oficial de Node-RED](https://nodered.org/docs/)
> * [Documentación de MongoDB](https://www.mongodb.com/docs/)
> * [Pandas Documentation](https://pandas.pydata.org/docs/)
> * [Scikit-learn Documentation](https://scikit-learn.org/stable/)

> **Tip:** Actualiza pip regularmente y considera usar entornos virtuales para proyectos específicos.

---

## 8. Gestión de la Interfaz Gráfica


### ¿Cómo activar o desactivar el entorno gráfico?

* **Desactivar**

  ```bash
  sudo systemctl disable gdm3
  sudo systemctl set-default multi-user.target
  sudo reboot
  ```

* **Reactivar**

  ```bash
  sudo systemctl enable gdm3
  sudo systemctl set-default graphical.target
  sudo reboot
  ```

> **Explicación:** Desactivar la interfaz gráfica libera recursos, útil en servidores administrados por SSH.

---

## 9. Solución de Problemas Comunes con Redes en Placas Nuevas


### ¿Problemas con Realtek RTL8125?

En placas madre muy nuevas, especialmente las que usan chips Realtek RTL8125, puede ocurrir que el controlador predeterminado (`r8169`) no funcione correctamente, y sea necesario usar el controlador `r8125` específico.

1.  **Diagnóstico:** Verifique si la interfaz de red está presente y activa:

    ```bash
    ip link show
    # Busque una interfaz tipo ethX o enpXsY que no esté "DOWN"
    ```

    Si no aparece o está inactiva, puede ser un problema de controlador.
2.  **Actualizar el sistema:**

    ```bash
    sudo apt update && sudo apt full-upgrade -y
    ```
3.  **Agregar PPA y reinstalar controlador:**
    *(Este PPA contiene versiones actualizadas de controladores)*

    ```bash
    sudo add-apt-repository ppa:kelebek333/rtl-kernel -y
    sudo apt update
    sudo apt install r8125-dkms -y
    ```
4.  **Bloquear controlador antiguo:** Cree un archivo para evitar que el kernel cargue el controlador `r8169`.

    ```bash
    echo 'blacklist r8169' | sudo tee /etc/modprobe.d/blacklist-r8169.conf
    ```
5.  **Actualizar initramfs:** Esto asegura que el cambio se aplique al arranque.

    ```bash
    sudo update-initramfs -u
    ```
6.  **Reiniciar:**

    ```bash
    sudo reboot
    ```
7.  **Verificación Post-Reinicio:** Confirme que la interfaz de red ahora esté disponible.

    ```bash
    ip link show
    lspci | grep -i ethernet
    ```

> **Tip:** Si la red sigue sin funcionar, revisa el modelo exacto de tu placa y busca controladores específicos.

---

## 10. Wake-on-LAN (WOL): Windows a Windows y Ubuntu a Windows

#### Ejemplo de script PowerShell para Windows → Windows
<details>
<summary>Click para ver el script de PowerShell para WOL</summary>

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

</details>

#### Ejemplo de envío desde Ubuntu
```bash
wakeonlan -i 192.168.6.255 AA:BB:CC:DD:EE:FF
# o
sudo etherwake -i eno1 AA:BB:CC:DD:EE:FF
```


### ¿Cómo despertar un PC por red?

* Configura correctamente la BIOS y Windows en el equipo destino.
* Envía el paquete mágico desde Windows (PowerShell) o Ubuntu (`wakeonlan` o `etherwake`).
* Verifica el envío con Wireshark o tcpdump.
* Consulta la sección de problemas comunes si no funciona.

> **Nota:** WOL por Wi-Fi casi nunca está soportado. Usa siempre Ethernet.

---

## 11. Script de Post-Instalación (Opcional)

Para automatizar la preparación del sistema, puedes crear un script `setup.sh` con los siguientes comandos. Esto consolida la actualización e instalación de dependencias en un solo paso.

**Contenido de `setup.sh`:**
```bash
#!/bin/bash
# Script para la preparación inicial del sistema Ubuntu

echo "--- Actualizando el sistema ---"
sudo apt update && sudo apt upgrade -y

echo "--- Instalando dependencias comunes ---"
sudo apt install -y build-essential dkms pkg-config libglvnd-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev mesa-utils inxi net-tools openssh-server curl git wget

echo "--- Habilitando firewall para SSH ---"
sudo ufw allow ssh
sudo ufw --force enable

echo "--- Preparación completada. Se recomienda reiniciar el sistema. ---"
read -p "¿Deseas reiniciar ahora? (s/n): " choice
case "$choice" in
  s|S ) sudo reboot;;
  * ) echo "Reinicio manual requerido.";;
esac
```

**Cómo usarlo:**
1. Guarda el contenido anterior en un archivo llamado `setup.sh`.
2. Dale permisos de ejecución: `chmod +x setup.sh`
3. Ejecútalo: `./setup.sh`

---

## 12. Buenas Prácticas de Seguridad (Opcional)

Una vez que tu estación de trabajo esté operativa, considera aplicar estas medidas de seguridad básicas, especialmente si será accesible remotamente:

*   **Cambiar el puerto de SSH:** Edita el archivo `/etc/ssh/sshd_config` y cambia la línea `Port 22` a un puerto no estándar (ej. `Port 2222`). Esto reduce la exposición a bots automatizados. No olvides permitir el nuevo puerto en el firewall (`sudo ufw allow 2222`).
*   **Usar autenticación por clave SSH:** Deshabilita el login por contraseña para SSH. Es mucho más seguro.
    1.  Genera un par de claves en tu máquina local: `ssh-keygen -t rsa -b 4096`
    2.  Copia tu clave pública al servidor: `ssh-copy-id usuario@ip_del_servidor`
    3.  Deshabilita la autenticación por contraseña en `/etc/ssh/sshd_config` cambiando `PasswordAuthentication yes` a `no`.
*   **Mantener el sistema actualizado:** Ejecuta `sudo apt update && sudo apt upgrade -y` periódicamente para aplicar parches de seguridad.

---

## FAQ: Preguntas Frecuentes

* **¿Qué hago si el driver NVIDIA no se instala correctamente?**
  * Revisa la compatibilidad en el Anexo B y asegúrate de haber eliminado drivers antiguos.

* **¿Cómo sé qué versión de CUDA instalar?**
  * Consulta la web oficial y verifica la compatibilidad con tu GPU y driver.

* **¿Por qué no funciona Wake-on-LAN?**
  * Verifica configuración de BIOS, opciones de energía y que el equipo esté conectado por cable.

* **¿Puedo usar esta guía en variantes de Ubuntu?**
  * Sí, pero puede haber diferencias menores. Se recomienda Ubuntu Desktop.

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
