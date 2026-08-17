local AP_SSID = "ESP12-CONFIG"
local AP_PWD = "12345678"
local AP_IP = "192.168.4.1"

local pinStates = {[6] = 0, [7] = 0, [8] = 0, [0] = 0}
local pwmPin = 4
local pwmFreq = 500
local dutyCycle = 0
local J = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"

for pin, _ in pairs(pinStates) do
    gpio.mode(pin, gpio.OUTPUT)
    gpio.write(pin, gpio.LOW)
end

pwm.setup(pwmPin, pwmFreq, dutyCycle)
pwm.start(pwmPin)

wifi.setmode(wifi.STATIONAP)
wifi.ap.config({ssid = AP_SSID, pwd = AP_PWD})
wifi.ap.setip({ip = AP_IP, netmask = "255.255.255.0", gateway = AP_IP})
wifi.sta.autoconnect(0)

local cfgSSID = nil
local cfgPWD = ""
print("Portal " .. AP_IP)

tmr.create():alarm(2000, tmr.ALARM_AUTO, function()
    if not wifi.sta.getip() and cfgSSID then
        local st=wifi.sta.status()
        if st==wifi.STA_IDLE or st==wifi.STA_FAIL then
            wifi.sta.connect()
        end
    end
end)

local dns = net.createUDPSocket()
dns:on("receive", function(s, d, port, ip)
    local e = 13
    while d:byte(e) ~= 0 do
        e = e + d:byte(e) + 1
    end
    local q = d:sub(13, e + 4)
    local r = d:sub(1, 2) .. "\129\128\0\1\0\1\0\0\0\0\0\0" .. q .. "\192\12\0\1\0\1\0\0\0\60\0\4\192\168\4\1"
    s:send(port, ip, r)
end)
dns:listen(53)

local function urldecode(s)
    if not s then return "" end
    s = s:gsub("+", " ")
    return s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
end

local function sendState(conn)
    local body = "{\"pins\":{"
    local first = true
    for pin, st in pairs(pinStates) do
        if not first then body = body .. "," end
        first = false
        body = body .. "\"" .. pin .. "\":" .. st
    end
    body = body .. "},\"duty\":" .. dutyCycle .. "}"
    conn:send(J .. body, function() conn:close() end)
end

local function sendPage(conn)
    conn:send("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n", function()
        local f = file.open("page.html", "r")
        if not f then
            conn:send("<h1>page.html no encontrado</h1>", function() conn:close() end)
            return
        end
        local function nextChunk()
            local x = f:read(200)
            if not x then
                f:close()
                conn:close()
                return
            end
            conn:send(x, nextChunk)
        end
        nextChunk()
    end)
end

local function handleScan(conn)
    wifi.sta.getap(function(aps)
        local body = "{\"nets\":["
        if aps then
            local first = true
            for ssid, v in pairs(aps) do
                if not first then body = body .. "," end
                first = false
                local auth, rssi = v:match("([^,]+),([^,]+)")
                body = body .. "{\"ssid\":\"" .. ssid .. "\",\"rssi\":" .. (rssi or 0) .. ",\"auth\":" .. ((tonumber(auth) or 0) > 0 and 1 or 0) .. "}"
            end
        end
        body = body .. "]}"
        conn:send(J .. body, function() conn:close() end)
    end)
end

local function blinkAp()
    wifi.setmode(wifi.STATION)
    tmr.create():alarm(10000, tmr.ALARM_SINGLE, function()
        wifi.setmode(wifi.STATIONAP)
        wifi.ap.config({ssid = AP_SSID, pwd = AP_PWD})
        wifi.ap.setip({ip = AP_IP, netmask = "255.255.255.0", gateway = AP_IP})
    end)
end

local function handleConnect(conn, payload)
    local ssid = urldecode(payload:match("ssid=([^&%s]+)"))
    local pwd = urldecode(payload:match("pwd=([^&%s]+)"))
    cfgSSID = ssid
    cfgPWD = pwd
    wifi.sta.config({ssid = ssid, pwd = pwd, save = false})
    wifi.sta.connect()
    local tries = 0
    local t = tmr.create()
    t:alarm(500, tmr.ALARM_AUTO, function()
        local ip = wifi.sta.getip()
        tries = tries + 1
        if ip or tries > 30 then
            t:unregister()
            local body = "{\"ok\":true,\"ssid\":\"" .. ssid .. "\",\"ip\":\"" .. (ip or "") .. "\",\"ap\":\"" .. AP_IP .. "\"}"
            conn:send(J .. body, function() conn:close() end)
            if ip then blinkAp() end
        end
    end)
end

local function handleWifiStatus(conn)
    local ip = wifi.sta.getip()
    local body = "{\"connected\":" .. (ip and "true" or "false") .. ",\"ip\":\"" .. (ip or "") .. "\",\"ssid\":\"" .. (cfgSSID or "") .. "\",\"ap\":\"" .. AP_IP .. "\"}"
    conn:send(J .. body, function() conn:close() end)
end

local function handleGet(conn, payload)
    local cmd = payload:match("all=([%a]+)")
    if cmd then
        local v = (cmd:lower() == "on") and 1 or 0
        for pin, _ in pairs(pinStates) do
            pinStates[pin] = v
            gpio.write(pin, v == 1 and gpio.HIGH or gpio.LOW)
        end
    end
    local pin = payload:match("pin=(%d+)")
    if pin then
        pin = tonumber(pin)
        if pinStates[pin] then
            pinStates[pin] = (pinStates[pin] == 1) and 0 or 1
            gpio.write(pin, pinStates[pin] == 1 and gpio.HIGH or gpio.LOW)
        end
    end
    local duty = payload:match("duty=(%d+)")
    if duty then
        dutyCycle = tonumber(duty)
        pwm.setduty(pwmPin, dutyCycle)
    end
    sendState(conn)
end

local function startServer()
    collectgarbage()
    local srv = net.createServer(net.TCP)
    srv:listen(80, function(conn)
        local responded = false
        conn:on("receive", function(conn, payload)
            if responded then return end
            responded = true
            if payload:find("GET /cmd") or payload:find("GET /toggle") or payload:find("GET /pwm") or payload:find("GET /state") then
                handleGet(conn, payload)
            elseif payload:find("GET /scan") then
                handleScan(conn)
            elseif payload:find("GET /connect") then
                handleConnect(conn, payload)
            elseif payload:find("GET /wifi") then
                handleWifiStatus(conn)
            else
                local host = payload:match("[Hh]ost:%s*([^%s%r%n]+)") or ""
                if host:find(AP_IP) then
                    sendPage(conn)
                else
                    conn:send("HTTP/1.1 302 Found\r\nLocation: http://" .. AP_IP .. "/\r\nContent-Length: 0\r\n\r\n", function() conn:close() end)
                end
            end
        end)
    end)
end

tmr.create():alarm(1500, tmr.ALARM_SINGLE, function()
    startServer()
end)

tmr.create():alarm(30000, tmr.ALARM_AUTO, function()
    collectgarbage()
end)