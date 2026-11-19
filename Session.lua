-- Session.lua: pure Lua administrator-authoritative registration coordinator.
-- Players are identified by raid GUIDs, never payload-asserted names.
local _, ns = ...
ns = ns or {}
local Core, Authority = assert(ns.Core), assert(ns.Authority)
local S = {}
ns.Session = S
local function validId(value)
 return type(value)=="string" and #value>=8 and #value<=64 and value:match("^[%w%-]+$")~=nil
end
function S.New(sessionId, adminGuid, adminName, rounds)
 assert(validId(sessionId),"session id required")
 local self={id=sessionId,adminGuid=adminGuid,authority=Authority.New(sessionId,adminGuid),
   state=Core.New(adminName,rounds),guids={},rounds=rounds}
 return self
end
function S.Register(self,roster,senderGuid,message)
 if type(message)~="table" or message.kind~="REGISTER" then return false,"invalid_message" end
 if self.state.phase~="registration" then return false,"registration_closed" end
 local ok,reason=Authority.Validate(self.authority,roster,senderGuid,message)
 if not ok then return false,reason end
 if message.payload~="contestant" and message.payload~="spectator" then return false,"invalid_role" end
 if self.guids[senderGuid] then
  if self.guids[senderGuid]~=message.payload then return false,"role_locked" end
  -- An ACK may have been throttled or lost. Accept a fresh sequence number
  -- for the same role so the leader can re-send confirmation idempotently.
  Authority.Accept(self.authority,senderGuid,message)
  return true,"already_registered"
 end
 local member=roster[senderGuid]
 if type(member.name)~="string" or member.name=="" then return false,"missing_identity" end
 ok,reason=Core.Register(self.state,member.name,message.payload)
 if not ok then return false,reason end
 self.guids[senderGuid]=message.payload
 Authority.Accept(self.authority,senderGuid,message)
 return true
end
function S.Pending(self,roster)
 local n=0
 for guid,member in pairs(roster) do
  if guid~=self.adminGuid and member.addon and not self.guids[guid] then n=n+1 end
 end
 return n
end
function S.CanStart(self,roster)
 if not Authority.IsLeaderStillAuthorized(self.authority,roster) then return false,"admin_not_leader" end
 return Core.CanStart(self.state,S.Pending(self,roster))
end
-- Peer shadow view accepts only leader-confirmed registration acknowledgments.
function S.NewPeer(sessionId,adminGuid,rounds)
 assert(validId(sessionId))
 return {id=sessionId,adminGuid=adminGuid,rounds=rounds,registrations={}}
end
function S.ApplyAck(peer,roster,senderGuid,message)
 if type(message)~="table" or message.kind~="REG_ACK" or message.session~=peer.id then return false,"wrong_message" end
 local member=roster[senderGuid]
 if senderGuid~=peer.adminGuid or not member or member.leader~=true or member.addon~=true then
  return false,"not_authorized_admin"
 end
 -- ACK format: Player-GUID,role; GUID must exist in current raid roster.
 local guid,role=message.payload:match("^([%w%-]+)%.(contestant)$")
 if not guid then guid,role=message.payload:match("^([%w%-]+)%.(spectator)$") end
 if not guid or not roster[guid] then return false,"unknown_player" end
 if peer.registrations[guid] and peer.registrations[guid]~=role then return false,"conflicting_ack" end
 peer.registrations[guid]=role
 return true
end
return S
