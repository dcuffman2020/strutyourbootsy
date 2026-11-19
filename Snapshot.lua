-- DEV-02 read-only, ballot-free registration snapshots.
-- Pure Lua; intentionally not wired to network until chunking and receipts exist.
local _,ns=...
ns=ns or {}
local Snapshot={}
ns.Snapshot=Snapshot
local function token(s,min,max)
 return type(s)=="string" and #s>=min and #s<=max and s:match("^[%w%-]+$")~=nil
end
local function positiveInt(n)
 return type(n)=="number" and n%1==0 and n>=1 and n<=2147483647
end
local function copyEntries(entries)
 local out={}
 for i,item in ipairs(entries) do
  out[i]={guid=item.guid,role=item.role}
 end
 return out
end
-- Produces a fresh, minimal value object; no ballots, scores, player names
-- or internal coordinator references can escape through this projection.
function Snapshot.FromHost(host)
 if type(host)~="table" or type(host.state)~="table" then return nil,"invalid_host" end
 if host.state.phase~="registration" then return nil,"unsupported_phase" end
 local list={}
 for guid,role in pairs(host.guids or {}) do
  if not token(guid,1,128) or (role~="contestant" and role~="spectator") then
   return nil,"invalid_registration"
  end
  list[#list+1]={guid=guid,role=role}
 end
 table.sort(list,function(a,b) return a.guid<b.guid end)
 local snap={session=host.id,adminGuid=host.adminGuid,version=host.state.version,
  rounds=host.rounds,phase="registration",registrations=list}
 local ok,reason=Snapshot.Validate(snap)
 if not ok then return nil,reason end
 return snap
end
function Snapshot.Validate(s)
 if type(s)~="table" or not token(s.session,8,64) or not token(s.adminGuid,1,128) then return false,"invalid_identity" end
 if not positiveInt(s.version) then return false,"invalid_version" end
 if not positiveInt(s.rounds) or s.rounds>5 or s.phase~="registration" then return false,"invalid_phase" end
 if type(s.registrations)~="table" or #s.registrations>39 then return false,"invalid_entries" end
 local seen,last={},nil
 for i,item in ipairs(s.registrations) do
  if type(item)~="table" or not token(item.guid,1,128) or (item.role~="contestant" and item.role~="spectator") then
   return false,"invalid_entry"
  end
  if seen[item.guid] or (last and item.guid<=last) or item.guid==s.adminGuid then return false,"invalid_order" end
  seen[item.guid]=true;last=item.guid
 end
 return true
end
function Snapshot.NewReplica(session,adminGuid)
 assert(token(session,8,64) and token(adminGuid,1,128))
 return {session=session,adminGuid=adminGuid,version=0,snapshot=nil,conflicted=false}
end
-- Adapter MUST resolve sender GUID and current raid leader before calling.
-- An equal-version, nonidentical snapshot is a conflict, not a replacement.
function Snapshot.Apply(replica,sourceGuid,isCurrentLeader,s)
 if replica.conflicted then return false,"replica_conflicted" end
 if sourceGuid~=replica.adminGuid or isCurrentLeader~=true then return false,"untrusted_source" end
 local ok,reason=Snapshot.Validate(s)
 if not ok then return false,reason end
 if s.session~=replica.session or s.adminGuid~=replica.adminGuid then return false,"wrong_session" end
 if s.version<replica.version then return false,"stale_snapshot" end
 if s.version==replica.version then
  local prior=replica.snapshot
  if not prior or prior.rounds~=s.rounds or prior.phase~=s.phase
     or #prior.registrations~=#s.registrations then
   replica.conflicted=true
   return false,"version_conflict"
  end
  for i,item in ipairs(s.registrations) do
   local old=prior.registrations[i]
   if old.guid~=item.guid or old.role~=item.role then
    replica.conflicted=true
    return false,"version_conflict"
   end
  end
  return true,"unchanged"
 end
 if replica.version>0 and s.version>replica.version+1 then
  return false,"version_gap"
 end
 replica.version=s.version
 replica.snapshot={session=s.session,adminGuid=s.adminGuid,version=s.version,
  rounds=s.rounds,phase=s.phase,registrations=copyEntries(s.registrations)}
 return true
end
return Snapshot
