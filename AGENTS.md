# AGENTS.md

Proyecto para un **ESP-01 (flash 4MB)** con firmware **NodeMCU (Lua)**: el código vive en `nodemcu-main/` (init.lua + page.html). Usa Lua/NodeMCU — **no Arduino**. La verificación es subir + leer el log serial. Respondé a este usuario en español.

## Comandos (sin PlatformIO)
Todo el flujo usa esptool instalado por pip en el Python del sistema + scripts PowerShell puros en `tools/`:

- Flashear firmware NodeMCU: `tools\flash.ps1`.
- Borrar TODO el flash: `tools\erase.ps1` (cuidado: deja el chip sin firmware).
- Subir init.lua + page.html: `tools\upload-lua.ps1`.
- Leer log serial / monitor: `tools\monitor.ps1`.
- Enviar comando Lua por serial: `nodemcu-main\serial-cmd.ps1 -Cmd "..."`.
- Limpiar FS de Lua (sin tocar firmware): `tools\clean-lua.ps1`.

Firmware binario: `nodemcu-main\nodemcu-release-8mod-float.bin` (NodeMCU 3.0.0 float, módulos `file,gpio,net,node,pwm,tmr,uart,wifi`).

## Trampas del entorno
- La PC de desarrollo solo tiene **Ethernet (sin WiFi)** — el portal del AP solo se prueba desde un celular.
- El puerto serie CH340 oscila entre **COM3 / COM4**. Re-detectar con `Get-PnpDevice -Class Ports`. Los scripts usan COM4 por defecto (`-ComPort` para cambiarlo).
- Solo **GPIO2** tiene LED onboard (activo en bajo). GPIO1=TX y GPIO3=RX rompen el serial si se usan como salida; ningún otro GPIO tiene LED.
- `file.list()` en NodeMCU 3.0 devuelve **tabla** (usar `for k,v in pairs(file.list()) do print(k,v) end`), NO es iterable con `for n in file.list()`.
- Para resetear + capturar log de arranque: abrir puerto a 115200, `setDTR(False)`, pulso `setRTS(True)` ~150ms, soltá, leé.
- `init.lua` se compila en RAM al bootear: si supera ~6400B falla con `E:M <n> not enough memory`. Mantenerlo compacto; `node.compile` tampoco entra en el chip.

## Estado del firmware (`nodemcu-main/`)
- AP `ESP12-CONFIG` / `12345678`, portal web en `172.217.28.1` (IP **pública** a propósito: Android 10+ solo abre el captive portal si la IP del gateway no es privada).
- **Flujo**: arranca en AP+STA (`wifi.sta.autoconnect(0)`) y **sin red guardada** (las credenciales son solo variables de sesión `cfgSSID`/`cfgPWD`; NO se persisten en `wifi.dat`). Al conectar a una red con `wifi.sta.config` `save=false` y obtener IP, el watchdog **apaga el AP** (`wifi.setmode(wifi.STATION)`). Si se pierde la conexión STA, el watchdog **reabre el AP** y reconfigura `ESP12-CONFIG`.
- **Captive portal**: mini servidor DNS (UDP 53) responde toda consulta con `172.217.28.1`; el servidor web responde `302 Location: http://172.217.28.1/` a cualquier Host que no sea la IP del AP, así el celular abre el portal solo.
- **Pines**: salidas 6, 7, 8, 0; PWM pin 4 (500 Hz, duty 0-1023). Endpoints: `/cmd /toggle /pwm /state` (handleGet), `/scan`, `/connect`, `/wifi`.

## Notas de esptool
- esptool instalado por pip (v5.3.1, trae pyserial). `python -m esptool version` para verificar.
- Opciones típicas: `--port COM4 --baud 460800 write_flash --verify -fm qio -fs 4MB -ff 40m 0x0 <bin>`.

## Estado del proyecto
- `app/` (Flutter) fue **eliminada por decisión del usuario**; se hará de cero cuando el sistema NodeMCU/Lua esté funcionando correctamente.
- Proyecto limpio para repositorio: solo `nodemcu-main/` (código Lua + scripts serial + firmware) y `tools/` (scripts PowerShell).