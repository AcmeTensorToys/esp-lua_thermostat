-- local configuration (TODO: pull in from json?)
local owtherm = encoder.fromHex("1013878a02080098")
local pcfaddr = 0x38
local pcfhigh = 0xF0
local tcPollIval = 9000   -- + 1 second for 1w read, too
local tcVWin     = 10     -- longest sliding sampling window
local tcFOffDly  = 180000 -- run the fan after turning of H/AC

-- remote configuration (set by MQTT)
local tctarget   = 55
local tcmode     = "off" -- "off" "cool" "heat" "emht"
local tcfan      = false -- should we keep the fan on?

-- state
local driving          = false -- are we driving?
local fanOffDelayTQ    = nil   -- a tq object for nixing the fan
local vdenom           = 0     -- window votes elapsed
local vnum             = 0     -- window votes accumulated
local verr             = 0     -- errors during voting window

local function resetTempAcc()
  verr  = 0
  vdenom = 0
  vnum = 0
end

local function mkRelays(mode, drive, forcefan)
  local v = 0xF -- "off"

  if drive then
    if     mode == "cool" then v = 0xC
    elseif mode == "heat" then v = 0xA
    elseif mode == "emht" then v = 0x6
    end
  end 
  if forcefan then v = bit.band(v, 0xE) end

  return v
end

local i2cu = require "i2cu"

function doRelays()
  local v = mkRelays(tcmode, driving, tcfan)
  i2cu.writen(pcfaddr, string.char(bit.bor(pcfhigh, v)))
  return v -- XXX debug
end

nwfnet.onmqtt["th"] = function(c,t,m)
  if not m then return end
  if     t == mqttTargTopic then
    driving = false; resetTempAcc()
    tctarget = tonumber(m) or tctarget
  elseif t == mqttModeTopic then
    driving = false; resetTempAcc()
    tcmode    = m
  elseif t == mqttFanTopic  then
    nextFan    = (m == "on" or m == "1")

    if fanOffDelayTQ == nil then
      -- we aren't about to automate the fan off, so go ahead and let the
      -- setting have immediate effect
      tcfan = nextFan
    else
      -- we are about to turn off the fan anyway; is that what we should do?
      if nextFan then -- no, keep the fan on
        tq:dequeue(fanOffDelayTQ)
        fanOffDelayTQ = nil
        tcfan = nextFan
      -- else let the callback turn it off for us
      end
    end
  else   return -- not for us?
  end

  doRelays()
end

local function startDrive()
  driving = true
  -- nix any future fan-off we might have had scheduled
  if fanOffDelayTQ ~= nil then tq:dequeue(fanOffDelayTQ); fanOffDelayTQ = nil end
end

local function stopDrive()
  driving = false
  -- if we aren't forcing the fan on, schedule it to be turned off later
  if not tcfan and fanOffDelayTQ == nil then
    tcfan = true
    fanOffDelayTQ = tq:queue(tcFOffDly, function()
      fanOffDelayTQ = nil
      tcfan = false
      doRelays()
    end)
  end
end

local function therm_res(t)
  logdata(t,0,"th")

  local m
  if driving then m = "S-on" else m = "S-off" end
 
  -- no action needed, will have been set when mode set; we may have left
  -- the polling loop active to continue to log data and all that
  if     tcmode == "off" then m = "Off"
  elseif tcmode == "fan" then m = "Fan"
  else
    -- OK, maybe we need to act

    vdenom = vdenom + 1

    -- push a little past the target in the direction indicated
    local thresh = tctarget
    if driving then
      if     tcmode == "cool" then thresh = thresh - 2
      elseif tcmode == "heat" then thresh = thresh + 2
      end
    end

    -- Vote to engage or stay on
    if     t == nil                            then verr  = verr  + 1
    elseif tcmode == "cool" and t > thresh then vnum = vnum + 1
    elseif tcmode == "heat" and t < thresh then vnum = vnum + 1
    elseif tcmode == "emht" and t < thresh then vnum = vnum + 1
    end

    if     verr  >= 3 then
      -- This window is definitely an error; shutdown now
      m = "Error"
      stopDrive()
      resetTempAcc()
    elseif vnum >= 7 then
      -- This window is definitely voting for driving; start now
      if driving
       then m = "Keepon"
       else m = "Drive"; startDrive()
      end
      resetTempAcc()
    elseif vdenom >= tcVWin - 1 and vnum <= 2 then
      -- This window is definitely voting to shut down
      if driving
        then m = "Cancel"; stopDrive()
	    else m = "Keepoff"
      end
      resetTempAcc()
    elseif vdenom >= tcVWin then
      -- This window has elapsed with no conclusion reached.
      resetTempAcc()
    end
  end

  local r = doRelays()

  -- XXX debug
  if mqcCan then
    mqc:publish(mqttPubRoot.."zz",
      sjson.encode({ ['m']=m, ['r']=r, ['h']=node.heap(),
                     ['f']=tempAccFan, ['ftq']=(fanOffDelayTQ ~= nil),
                     ['c']=vdenom, ['v']=vnum, ['e']=verr }),
      1,1)
  end

end
local function thermpoller()
  dofile("ow-ds18b20.lc")(tq, owpin, owtherm, 0,
    function(r)
      therm_res(r)
      therm_poll_cancel = tq:queue(tcPollIval,thermpoller)
    end)
end

doRelays()    -- turn everything off at boot
thermpoller() -- start polling
