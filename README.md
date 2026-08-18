# TvRemote

Control remoto para **TV Halley** desde el celular, via PWA + mini servidor
Node. Control 100% local (mismo WiFi que la TV); sin internet, sin servidores
externos, sin dependencias.

## Estado

- `pwa/index.html` — control: ENCENDER (WOL), VOL +/-, MUTE, cambio de canal
  (CH+ / CH-), escaneo de subred y estado en vivo (volumen + canal actual).
  Sin controles DLNA/cast (descartados). El boton APAGAR informa que esta TV no
  permite apagado por software.
  Se abre en Chrome del celular contra `http://IP-DE-LA-PC:8080`.
- `server.js` — mini server Node (sin deps) que sirve `pwa/` en `:8080` y
  agrega el control:

  Capa DLNA/UPnP (puerto 2870):
  - `POST /proxy?ip=…&service=…&action=…` — reenvia el SOAP UPnP a la TV
    (resuelve el bloqueo CORS del navegador contra el servidor UPnP).
  - `POST /wol?subnet=…` — magic packet UDP para encender la TV.
  - `GET /scan?subnet=192.168.1` — barre la subred buscando el `dmr.xml`.

  Capa CDP/Chromium (puerto 9222, la TV corre su UI en HTML5):
  - `POST /tv/status?ip=…` — estado de la TV (canal actual + volumen).
  - `POST /tv/channel?ip=…&dir=up|down` — cambia de canal.
  - `POST /tv/vol?ip=…&dir=up|down` — sube/baja el volumen (paso de 5; lee el
    valor actual por DLNA `GetVolume` porque la API nativa devuelve null).
  - `POST /tv/mute?ip=…&on=0|1` — mute on/off.
- `app/` — app React Native original para **Philips** (JointSpace), sin cambios.

## Datos verificados (2026-08-17)

- TV: **Halley** ("halleyTV", DLNA "IPI Media Renderer", UI HBBTV/Chromium en
  puerto 9222 con DevTools abiertos)
- IP: 192.168.1.108 (DHCP — puede cambiar; reservar IP estatica en el router,
  MAC `f8:28:19:2b:43:13`)
- Control UPnP/SOAP (version de servicio `:3`):
  - `RenderingControl` — `Get/SetVolume` (0-100), `Get/SetMute`
  - `AVTransport` — `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `Next`,
    `Previous`, `Seek`, `GetTransportInfo`
- Control nativo (via CDP): `setVolumeValue`, `setVolumeMute`,
  `getChannelListEx(...)` + `setBrdcastChgChannel(...)` para cambiar canal.
- Encendido: WOL magic packet UDP a `subnet.255:9`, MAC `f8:28:19:2b:43:13`

## Limitaciones (verificadas en el firmware)

- **Apagar por software: NO existe.** Se probaron todos los caminos disponibles:
  enumeracion completa de objetos nativos del launcher (no hay API de standby),
  `startNativeApp` con valores `PowerOff/Standby/Power/PowerSave` (devuelve -1),
  `opera_omi.sendPlatformMessage` con 7 mensajes candidatos, y la tecla POWER
  (409) por CDP (no llega al firmware). Solo se apaga con el control fisico; el
  encendido es por WOL.
- **Netflix / YouTube: NO hay apps.** Esta TV no tiene Netflix, YouTube ni
  NetTV configurado (config del sistema `g_misc__tv_guide_from_network` = 0,
  sin apps de terceros instaladas). Solo TV digital + reproduccion local.
- El cambio de canal funciona sobre la lista de TV digital (87 canales en esta
  instalacion). Ojo: la API nativa ignora la direccion `PRE` (devuelve lo mismo
  que `NEXT`); por eso "canal abajo" busca el anterior sobre la lista completa.

## Uso

```
node server.js
# en el celular (mismo WiFi que la PC y la TV), abrir http://IP-DE-LA-PC:8080
```