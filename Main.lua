local _,ns=...
local Core,Network,Session=assert(ns.Core),assert(ns.Network),assert(ns.Session)
local host,peer,localState
local function say(s) DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r "..s) end
local function leader(roster)
 for guid,member in pairs(roster) do if member.leader then return guid,member end end
end
local function announce()
 if not host then return false,"no_session" end
 if not ns.Authority.IsLeaderStillAuthorized(host.authority,Network.GetRoster()) then return false,"leader_changed" end
 return Network.Send("ANNOUNCE",host.id,tostring(host.rounds))
end
Network.SetCallback(function(event,guid,msg,roster)
 if event=="PREFIX_FAILED" or event=="SEND_FAILED" then say(event..": "..tostring(guid));return end
 if event=="ADDON_DISCOVERED" and host then announce();return end
 if event=="ROSTER_CHANGED" then
  if host and not ns.Authority.IsLeaderStillAuthorized(host.authority,guid) then
   say("Raid leader changed: registration suspended.")
  end
  return
 end
 if event~="SESSION_MESSAGE" then return end
 if msg.kind=="ANNOUNCE" then
  local admin=leader(roster)
  local rounds=tonumber(msg.payload)
  if guid~=admin or not rounds or rounds%1~=0 or rounds<1 or rounds>5 then return end
  if not peer or peer.id~=msg.session then
   peer=Session.NewPeer(msg.session,guid,rounds)
   say("Registration opened. /syb join contestant or /syb join spectator")
  end
 elseif msg.kind=="REGISTER" and host and msg.session==host.id then
  local ok=Session.Register(host,roster,guid,msg)
  if not ok then return end
  local delivered,why=Network.Send("REG_ACK",host.id,guid.."."..msg.payload)
  if not delivered then say("Registration saved; ACK not queued: "..tostring(why)) end
  say(roster[guid].name.." registered as "..msg.payload)
 elseif msg.kind=="REG_ACK" and peer then
  local ok=Session.ApplyAck(peer,roster,guid,msg)
  if ok and msg.payload:match("^([%w%-]+)%.")==UnitGUID("player") then
   say("Your registration was confirmed by the raid leader.")
  end
 end
end)
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent",function()
 SYBCharacterDB=SYBCharacterDB or {preferences={}}
 say("Registration prototype loaded. /syb help")
end)
SLASH_STRUTYOURBOOTSY1="/syb"
SlashCmdList.STRUTYOURBOOTSY=function(input)
 input=(input or ""):lower():match("^%s*(.-)%s*$")
 local roster=Network.GetRoster()
 if input=="status" then
  if host then
   local registered=0
   for _ in pairs(host.guids) do registered=registered+1 end
   local ok,why=Session.CanStart(host,roster)
   say("Host: "..registered.." registered; "..Session.Pending(host,roster).." pending addon peers; start eligible "..tostring(ok)..(why and " ("..why..")" or ""))
  elseif peer then say("Peer session "..peer.id.."; registration only.")
  elseif localState then say("Local dev session: "..localState.phase)
  else say("No active session.") end
 elseif input=="peers" then
  local total,confirmed=0,0
  for _,v in pairs(roster) do total=total+1;if v.addon then confirmed=confirmed+1 end end
  say("Raid "..total.." members; "..confirmed.." addon clients confirmed.")
 elseif input=="refresh" then
  Network.Refresh()
  if host then local ok,why=announce();if not ok then say("Announce failed: "..tostring(why)) end end
 elseif input:match("^host%s+[1-5]$") then
  local rounds=tonumber(input:match("%d+"))
  local guid,member=leader(roster)
  if not Network.IsReady() or not IsInRaid() or guid~=UnitGUID("player") then
   say("An addon-equipped raid leader in a raid is required.");return
  end
  if host then say("Already hosting. /syb refresh to announce again.");return end
  host=Session.New(tostring(GetServerTime()).."-"..tostring(math.random(100000,999999)),guid,member.name,rounds)
  local ok,why=announce()
  if not ok then host=nil;say("Announcement failed: "..tostring(why));return end
  say("Registration announced for "..rounds.." rounds.")
 elseif input=="join contestant" or input=="join spectator" then
  if not peer then say("No raid leader announcement received.");return end
  if UnitGUID("player")==peer.adminGuid then say("The administrator cannot participate.");return end
  local mine=peer.registrations[UnitGUID("player")]
  if mine then say("Already registered as "..mine);return end
  local role=input:match("join%s+(%w+)")
  local ok,why=Network.Send("REGISTER",peer.id,role)
  if ok then say("Registration requested; awaiting confirmation.")
  else say("Request failed: "..tostring(why)) end
 elseif input=="devstart" then
  localState=Core.New(UnitName("player"),1)
  say("Local developer-only session created.")
 else
  say("Commands: /syb host 1..5; /syb join contestant; /syb join spectator; /syb status; /syb peers; /syb refresh; /syb devstart")
 end
end
