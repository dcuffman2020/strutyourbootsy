local _,ns=...
local Core,Network,Session=assert(ns.Core),assert(ns.Network),assert(ns.Session)
local Sync=assert(ns.Sync)
local Transport=assert(ns.SnapshotTransport)
local host,peer,localState
local hostSync,peerSync
local snapshotPeer,outbound,lastFragmentAt,acknowledged = nil,nil,-999,{}
local function say(s) DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aStrut Your Bootsy:|r "..s) end
local function leader(roster)
 for guid,member in pairs(roster) do if member.leader then return guid,member end end
end
local function announce()
 if not host then return false,"no_session" end
 if hostSync and (hostSync.ended or hostSync.suspended) then return false,"session_suspended" end
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
   peerSync=Sync.New(GetTime())
   snapshotPeer=Transport.NewPeer(msg.session,guid)
   say("Registration opened. /syb join contestant or /syb join spectator")
  end
 elseif msg.kind=="REGISTER" and host and hostSync and not hostSync.suspended and not hostSync.ended and msg.session==host.id then
  local ok=Session.Register(host,roster,guid,msg)
  if not ok then return end
  local delivered,why=Network.Send("REG_ACK",host.id,guid.."."..msg.payload)
  if not delivered then say("Registration saved; ACK not queued: "..tostring(why)) end
  say(roster[guid].name.." registered as "..msg.payload)
  outbound=Transport.Build(host)
 elseif msg.kind=="SNAP_REQ" and host and hostSync and not hostSync.suspended and not hostSync.ended
  and msg.session==host.id and msg.payload=="sync" and roster[guid] and roster[guid].addon then
  outbound=Transport.Build(host)
 elseif msg.kind=="SNAP_PART" and peer and snapshotPeer and msg.session==peer.id then
  local leaderGuid=leader(roster)
  local ok,reason=Transport.Receive(snapshotPeer,guid,leaderGuid==guid,msg,GetTime())
  if ok and reason=="completed" then
   Network.Send("SNAP_ACK",peer.id,tostring(snapshotPeer.ackVersion))
  elseif not ok and reason=="version_gap" then
   Transport.ResetForResync(snapshotPeer)
   snapshotPeer.lastRequestAt=nil
  end
 elseif msg.kind=="SNAP_ACK" and host and msg.session==host.id and roster[guid] and roster[guid].addon then
  local version=tonumber(msg.payload)
  if version and version%1==0 and version>=1 and version<=host.state.version then
   acknowledged[guid]=version
  end
 elseif msg.kind=="REG_ACK" and peer then
  local ok=Session.ApplyAck(peer,roster,guid,msg)
  if ok and msg.payload:match("^([%w%-]+)%.")==UnitGUID("player") then
   if peerSync then Sync.Confirmed(peerSync,peer.registrations[UnitGUID("player")]) end
   say("Your registration was confirmed by the raid leader.")
  end
 end
end)
-- Send one bounded snapshot frame at a time. WoW delivery is not guaranteed.
C_Timer.NewTicker(0.5,function()
 if not outbound or not host or not hostSync or hostSync.ended or hostSync.suspended then return end
 if GetTime()-lastFragmentAt<0.5 then return end
 local part=Transport.Next(outbound)
 if not part then outbound=nil;return end
 local ok=Network.Send("SNAP_PART",host.id,part)
 if ok then
  Transport.Advance(outbound)
  lastFragmentAt=GetTime()
 else
  lastFragmentAt=GetTime()
 end
end)
-- Registered registration messages are retried while awaiting an ACK.
-- Periodic announcements help late joiners; no contest transitions are enabled.
C_Timer.NewTicker(2,function()
 local now=GetTime()
 local roster=Network.GetRoster()
 if host and hostSync and not hostSync.ended then
  local member=roster[host.adminGuid]
  local active=member and member.leader and member.online~=false
  local currentLeader=leader(roster)
  if currentLeader and currentLeader~=host.adminGuid then
   hostSync.ended=true
   say("Raid leadership transferred; registration session ended.")
  else
   local state=Sync.Tick(hostSync,now,active and true or false)
   if state=="ended" then say("Administrator unavailable for five minutes; session ended.") end
   if state=="active" and Sync.ShouldAdvertise(hostSync,now) then
    local ok=announce()
    if ok then Sync.Advertised(hostSync,now) end
   end
  end
 end
 if peer and snapshotPeer and not snapshotPeer.replica.conflicted then
  local member=roster[peer.adminGuid]
  if member and member.leader and member.online~=false and Transport.ShouldRequest(snapshotPeer,now) then
   local ok=Network.Send("SNAP_REQ",peer.id,"sync")
   if ok then Transport.Requested(snapshotPeer,now) end
  end
 end
 if peer and peerSync and peerSync.pending then
  local member=roster[peer.adminGuid]
  if member and member.leader and member.online~=false and Sync.ShouldRetry(peerSync,now) then
   local ok=Network.Send("REGISTER",peer.id,peerSync.pending.role)
   if ok then Sync.SentRequest(peerSync,now) end
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
   if hostSync and (hostSync.suspended or hostSync.ended) then ok=false;why=hostSync.ended and "session_ended" or "session_suspended" end
   say("Host: "..registered.." registered; "..Session.Pending(host,roster).." pending addon peers; start eligible "..tostring(ok)..(why and " ("..why..")" or ""))
  elseif peer then say("Peer session "..peer.id.."; replicated version "..(snapshotPeer and snapshotPeer.replica.version or 0).."; registration only.")
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
  hostSync=Sync.New(GetTime())
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
  if ok then
   if not peerSync then peerSync=Sync.New(GetTime()) end
   Sync.Request(peerSync,role,GetTime())
   Sync.SentRequest(peerSync,GetTime())
   say("Registration requested; awaiting confirmation.")
  else say("Request failed: "..tostring(why)) end
 elseif input=="resume-registration" then
  if not host or not hostSync then say("You are not hosting a session.");return end
  if hostSync.ended then say("This session ended and cannot be resumed.");return end
  if not ns.Authority.IsLeaderStillAuthorized(host.authority,roster) then
   say("Only the original raid leader may resume.");return
  end
  hostSync.suspended=false
  Sync.LeaderSeen(hostSync,GetTime())
  say("Registration resumed.")
  announce()
 elseif input=="devstart" then
  localState=Core.New(UnitName("player"),1)
  say("Local developer-only session created.")
 else
  say("Commands: /syb host 1..5; /syb join contestant; /syb join spectator; /syb status; /syb peers; /syb refresh; /syb resume-registration; /syb devstart")
 end
end
