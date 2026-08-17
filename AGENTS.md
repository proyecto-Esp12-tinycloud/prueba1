# AGENTS.md

Proyecto para un **ESP-01 (flash 4MB)** con firmware **NodeMCU (Lua)**: el código vive en `firmware/` (init.lua + page.html) y los scripts en `tools/`. Usa Lua/NodeMCU — **no Arduino**. La verificación es subir + leer el log serial. Respondé a este usuario en español.

## Estructura
- `firmware/` — lo que se graba en el chip: `init.lua`, `page.html`, `nodemcu-release-8mod-float.bin`.
- `tools/` — scripts PowerShell: flash, erase, upload, monitor, clean-lua, serial-cmd, serial-read, nodemcu-upload, read-file.

## Comandos (sin PlatformIO)
Todo el flujo usa esptool instalado por pip en el Python del sistema + scripts PowerShell puros en `tools/`:

- Flashear firmware NodeMCU: `tools\flash.ps1`.
- Borrar TODO el flash: `tools\erase.ps1` (cuidado: deja el chip sin firmware).
- Subir init.lua + page.html: `tools\upload-lua.ps1`.
- Leer log serial / monitor: `tools\monitor.ps1`.
- Enviar comando Lua por serial: `tools\serial-cmd.ps1 -Cmd "..."`.
- Limpiar FS de Lua (sin tocar firmware): `tools\clean-lua.ps1`.
- **Extraer un archivo del chip** (init.lua/page.html) a `firmware/`: `tools\read-file.ps1 -File init.lua`.

Firmware binario: `firmware\nodemcu-release-8mod-float.bin` (NodeMCU 3.0.0 float, módulos `file,gpio,net,node,pwm,tmr,uart,wifi`).

## Trampas del entorno
- La PC de desarrollo solo tiene **Ethernet (sin WiFi)** — el portal del AP solo se prueba desde un celular.
- El puerto serie CH340 oscila entre **COM3 / COM4**. Re-detectar con `Get-PnpDevice -Class Ports`. Los scripts usan COM4 por defecto (`-ComPort` para cambiarlo).
- Solo **GPIO2** tiene LED onboard (activo en bajo). GPIO1=TX y GPIO3=RX rompen el serial si se usan como salida; ningún otro GPIO tiene LED.
- `file.list()` en NodeMCU 3.0 devuelve **tabla** (usar `for k,v in pairs(file.list()) do print(k,v) end`), NO es iterable con `for n in file.list()`.
- Para resetear + capturar log de arranque: abrir puerto a 115200, `setDTR(False)`, pulso `setRTS(True)` ~150ms, soltá, leé.
- `init.lua` se compila en RAM al bootear: si supera ~6400B falla con `E:M <n> not enough memory`. Mantenerlo compacto; `node.compile` tampoco entra en el chip.
- El REPL de NodeMCU tiene buffer de ~256B por comando serial: comandos más largos se truncan con `<eof> expected near 'end'`. Partir en varios envíos o acortar.
- **Leer un archivo grande desde el chip**: no usar `f:read("*a")` (falla `E:M not enough memory`) ni `print` de chunks crudos (el `\n` de `print` corrompe el contenido). Usar `tools\read-file.ps1`, que lee en chunks de 60B codificados en **hex** por línea (fiel para UTF-8).

## Estado del firmware (`firmware/`)
- AP `ESP12-CONFIG` / `12345678`, portal web en `192.168.4.1` (**IP privada**; el usuario la acepta: en Android 10+ el captive portal NO se abre solo, hay que escribir `http://192.168.4.1` a mano).
- **Flujo**: arranca en AP+STA (`wifi.sta.autoconnect(0)`) y **sin red guardada** (las credenciales son solo variables de sesión `cfgSSID`/`cfgPWD`; NO se persisten en `wifi.dat`). Al conectar a una red con `wifi.sta.config` `save=false` y obtener IP, el chip hace **"AP corto y vuelve"**: apaga el AP ~10s (para que el celular vuelva solo a su red WiFi) y lo reenciende con `ESP12-CONFIG` en `192.168.4.1`. El portal queda accesible en la IP fija del AP y en la IP STA dinámica (mostrada en `/connect` y `/wifi`).
- **Captive portal**: mini servidor DNS (UDP 53) responde toda consulta con `192.168.4.1`; el servidor web responde `302 Location: http://192.168.4.1/` a cualquier Host que no sea la IP del AP.
- **Pines**: salidas 6, 7, 8, 0; PWM pin 4 (500 Hz, duty 0-1023). Endpoints: `/cmd /toggle /pwm /state` (handleGet), `/scan`, `/connect`, `/wifi` (el JSON incluye `"ap":"192.168.4.1"`).

## Notas de esptool
- esptool instalado por pip (v5.3.1, trae pyserial). `python -m esptool version` para verificar.
- Opciones típicas: `--port COM4 --baud 460800 write_flash --verify -fm qio -fs 4MB -ff 40m 0x0 <bin>`.

## Estado del proyecto
- `app/` (Flutter) fue **eliminada por decisión del usuario**; se hará de cero cuando el sistema NodeMCU/Lua esté funcionando correctamente.
- Repositorio en `https://github.com/proyecto-Esp12-tinycloud/prueba1.git` (rama única `main`). Proyecto limpio: `firmware/` + `tools/`.