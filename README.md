# Guía Mejorada de Configuración de Estaciones de Trabajo Ubuntu con GPU NVIDIA

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
* [FAQ: Preguntas Frecuentes](#faq-preguntas-frecuentes)
* [Anexo A: Identificación de GPUs NVIDIA](#anexo-a-identificación-de-gpus-nvidia)
* [Anexo B: Verificación de Compatibilidad](#anexo-b-verificación-de-compatibilidad)

---

> **¡Bienvenido!** Esta guía mejorada te ayudará a instalar y configurar Ubuntu con GPU NVIDIA, optimizando cada paso y explicando el porqué de cada acción. Los comandos y procedimientos originales se mantienen intactos, pero se agregan explicaciones, tips y advertencias para facilitar el proceso.

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

* **Verifica compatibilidad** Consulta el Anexo B antes de instalar.

* **Descarga e instala el repositorio APT**
  * Sigue los pasos de la web oficial de CUDA.

* **Configura variables de entorno**
  * Edita `.bashrc` y agrega las rutas de CUDA.

* **Verifica la instalación**

  ```bash
  nvcc --version
  ```

> **Nota:** Ajusta la versión de CUDA según tu hardware y necesidades.

---

## 6. Configuración Específica para Estaciones de Compresión


### Herramientas recomendadas para compresión/data

* Instala paquetes comunes, MongoDB, EMQX, Golang, VS Code, GStreamer, Angry IP Scanner, Anydesk y Rustdesk siguiendo los comandos originales.

* **Tips:**
  * Verifica el estado de los servicios tras la instalación.
  * Configura contraseñas únicas para acceso remoto.
  * Revisa la instalación de plugins específicos con `gst-inspect-1.0`.

---

## 7. Configuración Específica para Estaciones de Analítica


### Herramientas recomendadas para analítica/machine learning

* Instala MongoDB y configúralo con usuario y base de datos.
* Instala NodeRED y habilita el servicio.
* Instala Python, pip y las bibliotecas necesarias para análisis de datos y machine learning.

> **Tip:** Actualiza pip antes de instalar las bibliotecas.

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

* Diagnostica la interfaz de red y actualiza el sistema.
* Instala el controlador adecuado y bloquea el antiguo.
* Actualiza initramfs y reinicia.
* Verifica la interfaz tras el reinicio.

> **Tip:** Si la red sigue sin funcionar, revisa el modelo exacto de tu placa y busca controladores específicos.

---

## 10. Wake-on-LAN (WOL): Windows a Windows y Ubuntu a Windows


### ¿Cómo despertar un PC por red?

* Configura correctamente la BIOS y Windows en el equipo destino.
* Envía el paquete mágico desde Windows (PowerShell) o Ubuntu (`wakeonlan` o `etherwake`).
* Verifica el envío con Wireshark o tcpdump.
* Consulta la sección de problemas comunes si no funciona.

> **Nota:** WOL por Wi-Fi casi nunca está soportado. Usa siempre Ethernet.

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