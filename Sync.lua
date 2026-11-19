-- DEV-02: deterministic retry cadence and administrator liveness supervision.
-- Pure Lua: caller supplies elapsed time; this module never invokes a WoW API.
local _, ns = ...
ns = ns or {}
local Sync = {}
ns.Sync = Sync
local function validTime(now)
 return type(now)=="number" and now==now and now>=0
end
function Sync.New(now)
 assert(validTime(now), "valid time required")
 return {
  pending=nil, lastAdvertise=now-20, lastLeaderSeen=now,
  suspended=false, ended=false, lastRequestAt=nil,
 }
end
function Sync.Request(self, role, now)
 if not validTime(now) then return false,"invalid_time" end
 if role~="contestant" and role~="spectator" then return false,"invalid_role" end
 if self.ended then return false,"session_ended" end
 if self.pending and self.pending.role~=role then return false,"role_locked" end
 self.pending={role=role, lastSent=nil}
 return true
end
-- Each request uses a NEW network sequence; repeats are not protocol replays.
function Sync.ShouldRetry(self, now)
 if not validTime(now) or not self.pending or self.ended then return false end
 return self.pending.lastSent==nil or now-self.pending.lastSent>=8
end
function Sync.SentRequest(self, now)
 if validTime(now) and self.pending then self.pending.lastSent=now end
end
function Sync.Confirmed(self, role)
 if self.pending and self.pending.role==role then self.pending=nil;return true end
 return false
end
function Sync.ShouldAdvertise(self, now)
 return validTime(now) and not self.suspended and not self.ended and now-self.lastAdvertise>=20
end
function Sync.Advertised(self, now)
 if validTime(now) then self.lastAdvertise=now end
end
function Sync.LeaderSeen(self, now)
 if validTime(now) and not self.ended then self.lastLeaderSeen=now end
end
function Sync.Tick(self, now, isLeaderPresent)
 if not validTime(now) then return "invalid_time" end
 if self.ended then return "ended" end
 if isLeaderPresent then
  self.lastLeaderSeen=now
  return self.suspended and "paused" or "active"
 end
 self.suspended=true
 if now-self.lastLeaderSeen>=300 then
  self.ended=true
  self.pending=nil
  return "ended"
 end
 return "paused"
end
return Sync
