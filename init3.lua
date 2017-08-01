-- local configuration
owpin = 1
local mqttHeartTopic = "lcn/therm/boot"
local mqttHeartTick  = 600000
mqttTargTopic  = "lcn/therm/target"
mqttModeTopic  = "lcn/therm/mode"
mqttFanTopic   = "lcn/therm/fan"
mqttPubRoot    = "lcn/therm/"

-- modules
nwfnet = require "nwfnet"
mqc, mqcu = dofile("nwfmqtt.lc").mkclient("nwfmqtt.conf")

mqcCan = false

-- rtcfifo conditional init
if rtcfifo.ready() == 0 then rtcfifo.prepare() end

-- timers
tq = (dofile "tq.lc")(tmr.create())

-- setup peripherals
ow.setup(owpin)
i2c.setup(0,2,3,i2c.SLOW)

-- hook registry, MQTT connection management
local mqtt_beat_cancel
local mqtt_reconn_poller
local function mqtt_reconn()
  mqtt_reconn_poller = tq:queue(30000,mqtt_reconn)
  mqc:close(); dofile("nwfmqtt.lc").connect(mqc,"nwfmqtt.conf")
end

nwfnet.onnet["init"] = function(e,c)
  if     e == "mqttdscn" and c == mqc then
    if mqtt_beat_cancel then mqtt_beat_cancel(); mqtt_beat_cancel = nil end
    if not mqtt_reconn_poller then mqtt_reconn() end
    mqcCan = false
  elseif e == "mqttconn" and c == mqc then
    if mqtt_reconn_poller then tq:dequeue(mqtt_reconn_poller); mqtt_reconn_poller = nil end
    if not mqtt_beat_cancel then mqtt_beat_cancel = dofile("nwfmqtt.lc").heartbeat(mqc,mqttHeartTopic,tq,mqttHeartTick) end
    mqc:publish(mqttHeartTopic,"alive",1,1)
    mqc:subscribe(mqttTargTopic,1)
    mqc:subscribe(mqttModeTopic,1)
    mqc:subscribe(mqttFanTopic ,1)
    mqcCan = true
  elseif e == "wstagoip"              then
    if not mqtt_reconn_poller then mqtt_reconn() end
  end
end

-- data logging
function logdata(v,e,n)
  local t = rtctime.get()
  if mqcCan then mqc:publish(mqttPubRoot..n,sjson.encode({ ['t']=t, ['v']=v, ['e']=e }),1,1) end
  if v then rtcfifo.put(t,v,e,n) end
end

-- go online
dofile("nwfnet-go.lc")

-- do thermostat stuff
dofile("thermostat.lc")
