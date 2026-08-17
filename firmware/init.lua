AP_SSID="ESP12-CONFIG" AP_PWD="12345678" AP_IP="192.168.4.1"
pinStates={[6]=0,[7]=0,[8]=0,[0]=0}
pwmPin=4 dutyCycle=0
J="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
for pin in pairs(pinStates) do
    gpio.mode(pin,gpio.OUTPUT) gpio.write(pin,gpio.LOW)
end
pwm.setup(pwmPin,500,dutyCycle) pwm.start(pwmPin)
wifi.setmode(wifi.STATIONAP)
wifi.ap.config({ssid=AP_SSID,pwd=AP_PWD})
wifi.sta.autoconnect(0)
cfgSSID=nil
print("Portal "..AP_IP)
tmr.create():alarm(2000,tmr.ALARM_AUTO,function()
    if not wifi.sta.getip() and cfgSSID then
        local st=wifi.sta.status()
        if st==wifi.STA_IDLE or st==wifi.STA_FAIL then wifi.sta.connect() end
    end
end)
local dns=net.createUDPSocket()
dns:on("receive",function(s,d,port,ip)
    local e=13
    while d:byte(e)~=0 do e=e+d:byte(e)+1 end
    local q=d:sub(13,e+4)
    local r=d:sub(1,2).."\129\128\0\1\0\1\0\0\0\0\0\0"..q.."\192\12\0\1\0\1\0\0\0\60\0\4\192\168\4\1"
    s:send(port,ip,r)
end)
dns:listen(53)
blinkAp=function()
    tmr.create():alarm(3000,tmr.ALARM_SINGLE,function()
        wifi.setmode(wifi.STATION)
        tmr.create():alarm(42000,tmr.ALARM_SINGLE,function()
            wifi.setmode(wifi.STATIONAP)
            wifi.ap.config({ssid=AP_SSID,pwd=AP_PWD})
        end)
    end)
end
tmr.create():alarm(1500,tmr.ALARM_SINGLE,function()
    dofile("web.lua")
end)