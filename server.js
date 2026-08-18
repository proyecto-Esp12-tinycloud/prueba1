const http = require('http');
const fs = require('fs');
const path = require('path');
const dgram = require('dgram');

const ROOT = path.join(__dirname, 'pwa');
const PORT = 8080;
const TV_PORT = 2870;
const DEFAULT_MAC = 'f8:28:19:2b:43:13';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

function isIpv4(v) {
  const parts = String(v).split('.');
  if (parts.length !== 4) return false;
  return parts.every(p => /^\d{1,3}$/.test(p) && parseInt(p, 10) <= 255);
}

function isSubnet(v) {
  const parts = String(v).split('.');
  if (parts.length !== 3) return false;
  return parts.every(p => /^\d{1,3}$/.test(p) && parseInt(p, 10) <= 255);
}

function isUpnpName(v) {
  return /^[A-Za-z0-9]+$/.test(v);
}

function sendSoap(ip, service, action, body) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: ip,
      port: TV_PORT,
      path: '/control/' + service,
      method: 'POST',
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPACTION': '"urn:schemas-upnp-org:service:' + service + ':3#' + action + '"',
        'Content-Length': Buffer.byteLength(body),
        'Connection': 'close'
      },
      timeout: 8000
    }, res => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', c => { data += c; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

function fetchDmr(ip, timeoutMs) {
  return new Promise(resolve => {
    const req = http.get({ host: ip, port: TV_PORT, path: '/dmr.xml', timeout: timeoutMs }, res => {
      let data = '';
      res.on('data', c => { data += c; });
      res.on('end', () => {
        const m = data.match(/<friendlyName>([^<]*)<\/friendlyName>/);
        const name = m ? m[1] : '';
        resolve({ ip: ip, name: name, found: name !== '' });
      });
    });
    req.on('timeout', () => { req.destroy(); resolve({ ip: ip, name: '', found: false }); });
    req.on('error', () => resolve({ ip: ip, name: '', found: false }));
  });
}

async function scanSubnet(subnet) {
  const found = [];
  const BATCH = 40;
  for (let start = 1; start <= 254; start += BATCH) {
    const batch = [];
    for (let i = start; i < Math.min(start + BATCH, 255); i++) {
      batch.push(fetchDmr(subnet + '.' + i, 500));
    }
    const results = await Promise.all(batch);
    results.forEach(r => { if (r.found) found.push(r); });
  }
  return found;
}

function sendWol(broadcast, mac) {
  return new Promise((resolve, reject) => {
    const hex = String(mac).split(':').map(h => parseInt(h, 16));
    const payload = Buffer.alloc(6 + 16 * 6);
    for (let i = 0; i < 6; i++) payload[i] = 0xff;
    for (let i = 0; i < 16; i++) {
      for (let j = 0; j < 6; j++) payload[6 + i * 6 + j] = hex[j];
    }
    const sock = dgram.createSocket('udp4');
    sock.send(payload, 0, payload.length, 9, broadcast, err => {
      sock.close();
      if (err) reject(err);
      else resolve(true);
    });
  });
}

const CDP_PORT = 9222;

function cdpGetJson(ip, pathname) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: ip, port: CDP_PORT, path: pathname, timeout: 4000 }, res => {
      let data = '';
      res.on('data', c => { data += c; });
      res.on('end', () => resolve(data));
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
  });
}

function cdpEvaluate(ip, expression) {
  return new Promise((resolve, reject) => {
    let ws = null;
    let settled = false;
    const finish = (fn, v) => {
      if (settled) return;
      settled = true;
      try { if (ws) ws.close(); } catch (e) {}
      fn(v);
    };
    const timer = setTimeout(() => finish(reject, new Error('timeout CDP')), 7000);
    cdpGetJson(ip, '/json/list').then(raw => {
      let list;
      try { list = JSON.parse(raw); } catch (e) { throw new Error('respuesta CDP invalida'); }
      const target = (list || []).find(t => t && t.webSocketDebuggerUrl);
      if (!target) throw new Error('la TV no expone la pagina de control (9222)');
      ws = new WebSocket(target.webSocketDebuggerUrl);
      ws.onopen = () => {
        ws.send(JSON.stringify({
          id: 1,
          method: 'Runtime.evaluate',
          params: { expression: expression, returnByValue: true }
        }));
      };
      ws.onmessage = ev => {
        let msg;
        try { msg = JSON.parse(ev.data); } catch (e) { return; }
        if (!msg || msg.id !== 1) return;
        clearTimeout(timer);
        if (msg.error) return finish(reject, new Error('CDP: ' + (msg.error.message || 'error')));
        const r = msg.result && msg.result.result;
        if (r && r.exceptionDetails) {
          const desc = r.exceptionDetails.exception && r.exceptionDetails.exception.description;
          return finish(reject, new Error('JS: ' + (desc || r.exceptionDetails.text)));
        }
        finish(resolve, r ? r.value : undefined);
      };
      ws.onerror = () => finish(reject, new Error('no se pudo conectar al CDP de la TV'));
      ws.onclose = () => { clearTimeout(timer); if (!settled) finish(reject, new Error('CDP cerrado')); };
    }).catch(err => { clearTimeout(timer); finish(reject, err); });
  });
}

function readBody(req) {
  return new Promise(resolve => {
    let data = '';
    req.on('data', c => { data += c; });
    req.on('end', () => resolve(data));
  });
}

function sendJson(res, code, obj) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(JSON.stringify(obj));
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const pathname = url.pathname;
  const cors = { 'Access-Control-Allow-Origin': '*' };

  if (req.method === 'OPTIONS') {
    res.writeHead(204, Object.assign({
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    }, cors));
    res.end();
    return;
  }

  if (pathname === '/proxy') {
    if (req.method !== 'POST') { sendJson(res, 405, { error: 'POST only' }); return; }
    const ip = url.searchParams.get('ip');
    const service = url.searchParams.get('service');
    const action = url.searchParams.get('action');
    if (!isIpv4(ip)) { sendJson(res, 400, { error: 'IP invalida' }); return; }
    if (!isUpnpName(service) || !isUpnpName(action)) { sendJson(res, 400, { error: 'service/action invalido' }); return; }
    const body = await readBody(req);
    try {
      const r = await sendSoap(ip, service, action, body);
      res.writeHead(r.status, Object.assign({
        'Content-Type': 'text/xml; charset=utf-8',
        'Cache-Control': 'no-store'
      }, cors));
      res.end(r.body);
    } catch (err) {
      sendJson(res, 502, { error: 'No pude contactar la TV: ' + err.message });
    }
    return;
  }

  if (pathname === '/wol') {
    if (req.method !== 'POST') { sendJson(res, 405, { error: 'POST only' }); return; }
    const subnet = url.searchParams.get('subnet');
    const mac = url.searchParams.get('mac') || DEFAULT_MAC;
    if (!isSubnet(subnet)) { sendJson(res, 400, { error: 'subnet invalida' }); return; }
    try {
      await sendWol(subnet + '.255', mac);
      sendJson(res, 200, { ok: true, broadcast: subnet + '.255', mac: mac });
    } catch (err) {
      sendJson(res, 502, { error: err.message });
    }
    return;
  }

  if (pathname === '/scan') {
    const subnet = url.searchParams.get('subnet');
    if (!isSubnet(subnet)) { sendJson(res, 400, { error: 'subnet invalida' }); return; }
    const found = await scanSubnet(subnet);
    sendJson(res, 200, { found: found });
    return;
  }

  if (pathname === '/tv/status') {
    const ip = url.searchParams.get('ip');
    if (!isIpv4(ip)) { sendJson(res, 400, { error: 'IP invalida' }); return; }
    try {
      const info = await cdpEvaluate(ip, '(function(){ try { var m = mtvuiChannel.mtvObj; var i = m.getCurrentChannelInfo(); return { ok: true, channel: i ? { name: i.SERVICE_NAME, major: i.MAJOR_NUM, minor: i.MINOR_NUM, id: i.CHANNEL_ID } : null }; } catch(e){ return { ok: false, error: e.message }; } })()');
      const volBody = '<?xml version="1.0" encoding="utf-8"?>' +
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">' +
        '<s:Body><u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:3"><InstanceID>0</InstanceID><Channel>Master</Channel></u:GetVolume></s:Body></s:Envelope>';
      let volume = null;
      for (let attempt = 0; attempt < 3 && volume === null; attempt++) {
        try {
          const soapRes = await sendSoap(ip, 'RenderingControl', 'GetVolume', volBody);
          const m = soapRes.body.match(/<CurrentVolume>(\d+)<\/CurrentVolume>/);
          volume = m ? parseInt(m[1], 10) : null;
        } catch (e) { volume = null; }
        if (volume === null) await new Promise(r => setTimeout(r, 500));
      }
      sendJson(res, 200, Object.assign({ cdp: true, volume: volume }, info));
    } catch (err) {
      sendJson(res, 200, { cdp: false, ok: false, error: err.message });
    }
    return;
  }

  if (pathname === '/tv/channel') {
    const ip = url.searchParams.get('ip');
    const dir = url.searchParams.get('dir');
    if (!isIpv4(ip)) { sendJson(res, 400, { error: 'IP invalida' }); return; }
    if (dir !== 'up' && dir !== 'down') { sendJson(res, 400, { error: 'dir debe ser up o down' }); return; }
    try {
      const expr = dir === 'up'
        ? "(function(){ try { var m = mtvuiChannel.mtvObj; var cur = m.getCurrentChannelInfo(); if (!cur) return { ok:false, error:'sin canal actual' }; var list = m.getChannelListEx(cur.SVL_ID, cur.CHANNEL_ID, 0, 0, 'NEXT', 2); var next = (list && list.length) ? list[0] : null; if (!next) return { ok:false, error:'no hay canal siguiente' }; m.setBrdcastChgChannel(next.CHANNEL_ID); return { ok:true, from: cur.SERVICE_NAME, to: next.SERVICE_NAME, id: next.CHANNEL_ID }; } catch(e){ return { ok:false, error:e.message }; } })()"
        : "(function(){ try { var m = mtvuiChannel.mtvObj; var cur = m.getCurrentChannelInfo(); if (!cur) return { ok:false, error:'sin canal actual' }; var all = m.getChannelListEx(cur.SVL_ID, 0, 0, 0, 'NEXT', 300); if (!all || !all.length) return { ok:false, error:'lista de canales vacia' }; var idx = -1; for (var i = 0; i < all.length; i++) { if (all[i].CHANNEL_ID === cur.CHANNEL_ID) { idx = i; break; } } var prev = idx > 0 ? all[idx - 1] : all[all.length - 1]; if (!prev) return { ok:false, error:'no hay canal anterior' }; m.setBrdcastChgChannel(prev.CHANNEL_ID); return { ok:true, from: cur.SERVICE_NAME, to: prev.SERVICE_NAME, id: prev.CHANNEL_ID }; } catch(e){ return { ok:false, error:e.message }; } })()";
      const result = await cdpEvaluate(ip, expr);
      sendJson(res, 200, result);
    } catch (err) {
      sendJson(res, 200, { ok: false, error: err.message });
    }
    return;
  }

  if (pathname === '/tv/vol') {
    const ip = url.searchParams.get('ip');
    const dir = url.searchParams.get('dir');
    if (!isIpv4(ip)) { sendJson(res, 400, { error: 'IP invalida' }); return; }
    if (dir !== 'up' && dir !== 'down') { sendJson(res, 400, { error: 'dir debe ser up o down' }); return; }
    try {
      let cur = null;
      const volBody = '<?xml version="1.0" encoding="utf-8"?>' +
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">' +
        '<s:Body><u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:3"><InstanceID>0</InstanceID><Channel>Master</Channel></u:GetVolume></s:Body></s:Envelope>';
      for (let attempt = 0; attempt < 4 && cur === null; attempt++) {
        try {
          const soapRes = await sendSoap(ip, 'RenderingControl', 'GetVolume', volBody);
          const m = soapRes.body.match(/<CurrentVolume>(\d+)<\/CurrentVolume>/);
          cur = m ? parseInt(m[1], 10) : null;
        } catch (e) {
          cur = null;
        }
        if (cur === null) await new Promise(r => setTimeout(r, 600));
      }
      if (cur === null) { sendJson(res, 200, { ok: false, error: 'no pude leer el volumen' }); return; }
      const target = dir === 'up' ? Math.min(100, cur + 5) : Math.max(0, cur - 5);
      await cdpEvaluate(ip, 'mtvuiChannel.mtvObj.setVolumeValue(' + target + ')');
      sendJson(res, 200, { ok: true, from: cur, volume: target });
    } catch (err) {
      sendJson(res, 200, { ok: false, error: err.message });
    }
    return;
  }

  if (pathname === '/tv/mute') {
    const ip = url.searchParams.get('ip');
    const on = url.searchParams.get('on');
    if (!isIpv4(ip)) { sendJson(res, 400, { error: 'IP invalida' }); return; }
    if (on !== '0' && on !== '1') { sendJson(res, 400, { error: 'on debe ser 0 o 1' }); return; }
    try {
      await cdpEvaluate(ip, 'mtvuiChannel.mtvObj.setVolumeMute(' + on + ')');
      sendJson(res, 200, { ok: true, mute: on === '1' });
    } catch (err) {
      sendJson(res, 200, { ok: false, error: err.message });
    }
    return;
  }

  let urlPath = decodeURIComponent(url.pathname);
  if (urlPath === '/') urlPath = '/index.html';
  const file = path.join(ROOT, urlPath);
  if (!file.startsWith(ROOT)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404); res.end('Not found: ' + urlPath); return;
    }
    res.writeHead(200, Object.assign({
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store'
    }, cors));
    res.end(data);
  });
}).listen(PORT, '0.0.0.0', () => {
  console.log('Sirviendo en http://0.0.0.0:' + PORT);
});