# Smart LED ESP-01 con NodeMCU/Lua

Firmware para **ESP8266 (ESP-01, flash 4MB)** con **NodeMCU (Lua)**: el ESP crea un AP WiFi (`ESP12-CONFIG`) con portal web para configurar la red y controlar pines. Toda la lógica vive en `firmware/init.lua`, la UI en `firmware/page.html`.

> **Sin PlatformIO ni Arduino.** Se usa esptool (pip) + scripts PowerShell en `tools/`.

## Instalación del framework

1. Instalar Python y esptool:
   ```
   pip install esptool
   ```
2. Verificar: `python -m esptool version`.
3. Flashear el firmware NodeMCU (el binario ya está en `firmware/`):
   ```
   powershell -ExecutionPolicy Bypass -File tools\flash.ps1
   ```
4. Subir el código (`init.lua` + `page.html`):
   ```
   powershell -ExecutionPolicy Bypass -File tools\upload-lua.ps1
   ```

Si el puerto serie falla, detectar con `Get-PnpDevice -Class Ports` (CH340 oscila entre COM3/COM4) y usar `-ComPort`.

## Pines

| Pin | Función | Nota |
|---|---|---|
| 6 | GPIO salida | controlado por el portal |
| 7 | GPIO salida | controlado por el portal |
| 8 | GPIO salida | controlado por el portal |
| 0 | GPIO salida | controlado por el portal |
| 4 | PWM | duty 0-1023, 500 Hz |
| 2 | LED onboard | activo en bajo; no usado |
| 1 (TX) / 3 (RX) | serial | no usar como salida |

## Funciones del script (`firmware/init.lua`)

- `urldecode(s)` — decodifica cadenas URL-encoded (para ssid/pwd).
- `sendState(conn)` — responde JSON con el estado de los pines y el duty del PWM.
- `sendPage(conn)` — sirve `page.html` en fragmentos de 200 bytes.
- `handleScan(conn)` — escanea redes WiFi (`wifi.sta.getap`) y responde JSON.
- `handleConnect(conn, payload)` — configura y conecta a una red STA; espera IP (máx 15s).
- `handleWifiStatus(conn)` — responde JSON con estado STA (conectado/IP/ssid) + IP del AP.
- `handleGet(conn, payload)` — procesa `/cmd`, `/toggle`, `/pwm`, `/state`.
- `startServer()` — servidor TCP en puerto 80; enruta endpoints y redirige (302) al portal a cualquier otro Host.
- Servidor DNS (UDP 53) — responde toda consulta con la IP del AP (captive portal).
- Watchdog (2s) — solo reintenta la conexión STA si hay red configurada; **no apaga el AP**.

## Uso

1. Conectarse a `ESP12-CONFIG` (clave `12345678`); abrir `http://192.168.4.1` a mano (en Android 10+ el captive portal no se abre solo).
2. Escanear, elegir red, poner clave, conectar.
3. Al obtener IP, el AP **sigue activo** en `192.168.4.1`; el portal también muestra la IP STA dinámica para entrar desde la red del router.