-- DEV-02 bounded registration snapshot fragmentation; pure Lua, no WoW APIs.
-- Fragments are integrity-checked, not cryptographically authenticated.
local _,ns=...
ns=ns or {}
local C={}
ns.SnapshotCodec=C
C.CHUNK_BYTES=120
C.MAX_CHUNKS=64
C.MAX_BYTES=C.CHUNK_BYTES*C.MAX_CHUNKS
local function integer(n,min,max)
 return type(n)=="number" and n%1==0 and n>=min and n<=max
end
local function check(s,min,max)
 return type(s)=="string" and #s>=min and #s<=max and s:match("^[%w%-]+$")~=nil
end
local function checksum(str)
 local a,b=1,0
 for i=1,#str do a=(a+str:byte(i))%65521;b=(b+a)%65521 end
 return b*65536+a
end
function C.Serialize(s,Snapshot)
 local ok,reason=Snapshot.Validate(s)
 if not ok then return nil,reason end
 local parts={tostring(s.version),tostring(s.rounds)}
 for _,entry in ipairs(s.registrations) do
  parts[#parts+1]=entry.guid.."_"..(entry.role=="contestant" and "c" or "s")
 end
 local wire=table.concat(parts,".")
 if #wire>C.MAX_BYTES then return nil,"snapshot_too_large" end
 return wire
end
function C.Deserialize(wire,session,adminGuid,Snapshot)
 if type(wire)~="string" or #wire>C.MAX_BYTES then return nil,"invalid_snapshot" end
 local fields={}
 for field in (wire.."."):gmatch("(.-)%.") do
  if field=="" then return nil,"empty_field" end
  fields[#fields+1]=field
  if #fields>41 then return nil,"too_many_fields" end
 end
 if #fields<2 then return nil,"short_snapshot" end
 local version,rounds=tonumber(fields[1]),tonumber(fields[2])
 if not integer(version,1,2147483647) or tostring(version)~=fields[1] or not integer(rounds,1,5) or tostring(rounds)~=fields[2] then
  return nil,"invalid_header"
 end
 local registrations={}
 for i=3,#fields do
  local guid,role=fields[i]:match("^([%w%-]+)_([cs])$")
  if not guid then return nil,"invalid_registration" end
  registrations[#registrations+1]={guid=guid,role=role=="c" and "contestant" or "spectator"}
 end
 local snapshot={session=session,adminGuid=adminGuid,version=version,rounds=rounds,phase="registration",registrations=registrations}
 local ok,reason=Snapshot.Validate(snapshot)
 if not ok then return nil,reason end
 return snapshot
end
function C.Fragment(serialized)
 if type(serialized)~="string" or #serialized==0 or #serialized>C.MAX_BYTES then return nil,"invalid_serialized" end
 local total=math.ceil(#serialized/C.CHUNK_BYTES)
 if total>C.MAX_CHUNKS then return nil,"too_many_chunks" end
 local digest=tostring(checksum(serialized))
 local out={}
 for i=1,total do
  local piece=serialized:sub((i-1)*C.CHUNK_BYTES+1,i*C.CHUNK_BYTES)
  out[i]=digest.."_"..i.."_"..total.."_"..piece
  if #out[i]>180 then return nil,"frame_too_long" end
 end
 return out
end
function C.NewAssembler()
 return {digest=nil,total=nil,parts={},count=0}
end
function C.Accept(assembly,frame)
 if type(frame)~="string" or #frame>180 then return false,"invalid_frame" end
 local digest,index,total,piece=frame:match("^(%d+)_(%d+)_(%d+)_(.+)$")
 digest,index,total=tonumber(digest),tonumber(index),tonumber(total)
 if not integer(digest,1,4294967295) or not integer(index,1,C.MAX_CHUNKS) or not integer(total,1,C.MAX_CHUNKS) or index>total
  or not piece or #piece>C.CHUNK_BYTES or not piece:match("^[%w%._%-]+$") then
  return false,"invalid_fragment"
 end
 if assembly.digest and (assembly.digest~=digest or assembly.total~=total) then return false,"mixed_transfer" end
 assembly.digest=digest;assembly.total=total
 local prior=assembly.parts[index]
 if prior then
  if prior~=piece then return false,"conflicting_fragment" end
  return true,"duplicate"
 end
 assembly.parts[index]=piece;assembly.count=assembly.count+1
 if assembly.count~=total then return true,"pending" end
 local serialized=table.concat(assembly.parts)
 if #serialized>C.MAX_BYTES or checksum(serialized)~=digest then return false,"checksum_mismatch" end
 return true,serialized
end
return C
