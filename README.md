# Ubuntu-NVIDIA-Setup-Docs
Este repositorio le permite al usuario realizar la preparación de los equipos con Ubuntu y graficos de NVIDIA correctamente.

## Índice
- [Requisitos previos](#requisitos-previos)
- [Instalación de Sistema Operativo Ubuntu](#instalación-ubuntu)
- [Instalación de controladores NVIDIA](#instalación-de-controladores-nvidia)
- [Configuraciones opcionales](#configuraciones-opcionales)
- [Solución de problemas](#solución-de-problemas)

# Requisitos Previos para Configurar Equipos con Ubuntu y Gráficos NVIDIA

Esta guía describe los requisitos previos para instalar y configurar Ubuntu 22.04 LTS o 24.04 LTS en equipos con tarjetas gráficas NVIDIA. Algunos pasos son opcionales dependiendo del hardware y los casos de uso (por ejemplo, gaming, machine learning, o servidores).

## 1. Preparar una unidad USB booteable
Para instalar Ubuntu, necesitas una unidad USB con la imagen ISO de Ubuntu. Sigue estos pasos:

### 1.1. Descargar la ISO de Ubuntu
- **Ubuntu 22.04 LTS** (Jammy Jellyfish): Descarga desde [el sitio oficial](https://releases.ubuntu.com/22.04/). Recomendado para estabilidad a largo plazo (soporte hasta 2027).
- **Ubuntu 24.04 LTS** (Noble Numbat): Descarga desde [el sitio oficial](https://releases.ubuntu.com/24.04/). Recomendado para hardware más reciente o nuevas funcionalidades (soporte hasta 2029).
- **Tamaño mínimo de la unidad USB**: 8 GB (se recomienda 16 GB o más para mejor rendimiento).

### 1.2. Crear una unidad USB booteable
Usa una herramienta para flashear la ISO en la unidad USB. Las opciones recomendadas son:

#### Opción 1: Rufus (Windows)
- Descarga [Rufus](https://rufus.ie/) (versión portable recomendada).
- Pasos:
  1. Inserta la unidad USB.
  2. Abre Rufus, selecciona la ISO de Ubuntu descargada.
  3. Elige el esquema de partición **MBR** (para compatibilidad con sistemas BIOS) o **GPT** (para UEFI, común en equipos modernos).
  4. Formatea la unidad y escribe la ISO.
- **Nota**: Rufus es ideal para configuraciones simples y equipos con Windows.

#### Opción 2: Ventoy (Multiplataforma)
- Descarga [Ventoy](https://www.ventoy.net/) e instálalo en la unidad USB.
- Pasos:
  1. Inserta la unidad USB.
  2. Ejecuta Ventoy y selecciona la unidad para instalarlo.
  3. Copia la ISO de Ubuntu a la partición creada por Ventoy.
  4. Reinicia el equipo y selecciona la ISO desde el menú de Ventoy.
- **Ventaja**: Permite almacenar múltiples ISOs en la misma unidad USB, ideal para probar diferentes versiones de Ubuntu.

**Opcional**: Verifica la integridad de la ISO descargada comparando su hash (SHA256) con el proporcionado en el sitio oficial de Ubuntu:
```bash
sha256sum ubuntu-22.04-desktop-amd64.iso
