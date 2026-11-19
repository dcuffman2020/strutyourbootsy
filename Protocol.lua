-- DEV-02 strict bounded protocol: no executable deserialization.
local _, ns = ...
ns=ns or {}
local P={}
ns.Protocol=P
P.PREFIX="StrutYourBootsy"
P.MAX_BYTES=255
local kinds={HELLO=true,ANNOUNCE=true,REGISTER=true,REG_ACK=true,SNAP_REQ=true,SNAP_PART=true,SNAP_ACK=true,BALLOT=true,
 START=true,BEGIN_RUNWAY=true,BEGIN_VOTING=true,CLOSE_VOTING=true,
 NEXT_ROUND=true,PAUSE=true,RESUME=true,END=true}
local function safe(s,pattern,min,max)
 return type(s)=="string" and #s>=min and #s<=max and s:match(pattern)~=nil
end
function P.Encode(kind,session,seq,payload)
 if not kinds[kind] then return nil,"unknown_command" end
 if not safe(session,"^[%w%-]+$",1,64) then return nil,"invalid_session" end
 if type(seq)~="number" or seq%1~=0 or seq<1 or seq>2147483647 then return nil,"invalid_sequence" end
 payload=payload or ""
 if not safe(payload,"^[%w%._%-]*$",0,180) then return nil,"invalid_payload" end
 local wire=table.concat({"SYB1",kind,session,tostring(seq),payload},"|")
 if #wire>P.MAX_BYTES then return nil,"message_too_long" end
 return wire
end
function P.Decode(wire)
 if type(wire)~="string" or #wire>P.MAX_BYTES or #wire<12 or wire:find("%z") then return nil,"invalid_wire" end
 local kind,session,seq,payload=wire:match("^SYB1|([^|]+)|([^|]+)|([^|]+)|([^|]*)$")
 if not kind then return nil,"invalid_wire" end
 if not seq:match("^[1-9]%d*$") or #seq>10 then return nil,"invalid_sequence" end
 local number=tonumber(seq)
 local normalized,reason=P.Encode(kind,session,number,payload)
 if not normalized then return nil,reason end
 if normalized~=wire then return nil,"noncanonical_wire" end
 return {kind=kind,session=session,seq=number,payload=payload}
end
return P
