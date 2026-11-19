-- DEV-02 discovery transport. Contest commands are deliberately not applied yet.
local _, ns = ...
ns=ns or {}
local P,R=assert(ns.Protocol),assert(ns.Roster)
local N={}
ns.Network=N
local roster,byName={},{}
local seq,lastHello=0,-99999
local prefixReady=false
local callback
local function notify(event,...)
 if callback then callback(event,...) end
end
local function rebuild()
 roster,byName=R.Build(roster)
 notify("ROSTER_CHANGED",roster)
end
local function sendHello()
 if not prefixReady or not IsInRaid() then return end
 local now=GetTime()
 if now-lastHello<10 then return end
 lastHello=now
 seq=seq+1
 local packet=P.Encode("HELLO","-",seq,"v1")
 if not packet then return end
 local result=C_ChatInfo.SendAddonMessage(P.PREFIX,packet,"RAID")
 if result~=0 then notify("SEND_FAILED",result) end
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(_,event,...)
 if event=="PLAYER_LOGIN" then
  -- Registration returns an enum: 0 success, 1 already registered.
  local result=C_ChatInfo.RegisterAddonMessagePrefix(P.PREFIX)
  prefixReady=(result==0 or result==1)
  if not prefixReady then notify("PREFIX_FAILED",result) end
  rebuild()
  sendHello()
 elseif event=="GROUP_ROSTER_UPDATE" then
  rebuild()
  sendHello()
 elseif event=="CHAT_MSG_ADDON" then
  local prefix,wire,channel,sender=...
  if prefix~=P.PREFIX or channel~="RAID" then return end
  local guid=R.Resolve(byName,sender)
  if not guid or not roster[guid] then return end
  local message=P.Decode(wire)
  if not message then return end
  -- HELLO is a bounded discovery message with no contest authority.
  -- Before it is accepted the sender must still belong to the live roster.
  if message.kind=="HELLO" and message.session=="-" and message.payload=="v1" then
   roster[guid].addon=true
   notify("ADDON_DISCOVERED",guid,roster[guid].name)
   return
  end
  -- Future session commands require the explicit session/authority adapter.
  notify("SESSION_MESSAGE_PENDING",guid,message)
 end
end)
function N.SetCallback(fn) callback=fn end
function N.GetRoster() return roster end
function N.Refresh() rebuild();sendHello() end
return N
