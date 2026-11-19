-- WoW addon message adapter. Only discovery and registration traffic is active.
local _,ns=...
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
 -- The local player is installed even before receiving discovery echo.
 local selfGuid=UnitGUID("player")
 if selfGuid and roster[selfGuid] then roster[selfGuid].addon=true end
 notify("ROSTER_CHANGED",roster)
end
function N.Send(kind,session,payload)
 if not prefixReady then return false,"prefix_unavailable" end
 if not IsInRaid() then return false,"not_in_raid" end
 local nextSeq=seq+1
 local wire,reason=P.Encode(kind,session,nextSeq,payload)
 if not wire then return false,reason end
 local result=C_ChatInfo.SendAddonMessage(P.PREFIX,wire,"RAID")
 if result~=0 then
  notify("SEND_FAILED",result)
  return false,"send_result_"..tostring(result)
 end
 seq=nextSeq
 return true
end
local function sendHello()
 if not prefixReady or not IsInRaid() then return end
 local now=GetTime()
 if now-lastHello<10 then return end
 local ok=N.Send("HELLO","-","v1")
 if ok then lastHello=now end
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(_,event,...)
 if event=="PLAYER_LOGIN" then
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
  if not guid or not roster[guid] or guid==UnitGUID("player") then return end
  local message=P.Decode(wire)
  if not message then return end
  if message.kind=="HELLO" then
   if message.session~="-" or message.payload~="v1" then return end
   local isNew=not roster[guid].addon
   roster[guid].addon=true
   if isNew then notify("ADDON_DISCOVERED",guid,roster[guid].name) end
   -- Answer newly discovered peers, without creating an echo loop.
   if isNew then sendHello() end
   return
  end
  -- A valid leader announcement also proves that the roster-verified
  -- leader has our addon; its HELLO may have been delayed by throttling.
  if message.kind=="ANNOUNCE" and roster[guid].leader then
   roster[guid].addon=true
  end
  if not roster[guid].addon then return end
  notify("SESSION_MESSAGE",guid,message,roster)
 end
end)
function N.SetCallback(fn) callback=fn end
function N.GetRoster() return roster end
function N.Refresh() rebuild();sendHello() end
function N.IsReady() return prefixReady end
return N
