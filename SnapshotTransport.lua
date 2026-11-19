-- DEV-02 registration-only snapshot delivery. Transport-independent; never stores ballots.
local _,ns=...
ns=ns or {}
local Snapshot,Codec=assert(ns.Snapshot),assert(ns.SnapshotCodec)
local T={}
ns.SnapshotTransport=T
function T.NewPeer(session,adminGuid)
 return {replica=Snapshot.NewReplica(session,adminGuid),assembly=Codec.NewAssembler(),
  lastPartAt=nil,lastRequestAt=nil,ackVersion=0}
end
function T.Build(host)
 local snapshot,reason=Snapshot.FromHost(host)
 if not snapshot then return nil,reason end
 local serialized
 serialized,reason=Codec.Serialize(snapshot,Snapshot)
 if not serialized then return nil,reason end
 local frames
 frames,reason=Codec.Fragment(serialized)
 if not frames then return nil,reason end
 return {version=snapshot.version,frames=frames,nextIndex=1}
end
function T.Next(outbound)
 if not outbound or outbound.nextIndex>#outbound.frames then return nil end
 return outbound.frames[outbound.nextIndex]
end
function T.Advance(outbound)
 outbound.nextIndex=outbound.nextIndex+1
end
function T.Receive(peer,sourceGuid,isLeader,message,now)
 if type(message)~="table" or message.kind~="SNAP_PART" or message.session~=peer.replica.session then
  return false,"invalid_message"
 end
 if sourceGuid~=peer.replica.adminGuid or isLeader~=true then return false,"unauthorized_source" end
 if type(now)~="number" or now<0 then return false,"invalid_time" end
 -- A stale incomplete transfer expires. A fresh request is needed for resync.
 if peer.lastPartAt and now-peer.lastPartAt>15 then peer.assembly=Codec.NewAssembler() end
 local ok,value=Codec.Accept(peer.assembly,message.payload)
 if not ok then
  peer.assembly=Codec.NewAssembler()
  return false,value
 end
 peer.lastPartAt=now
 if value=="pending" or value=="duplicate" then return true,value end
 local snapshot,reason=Codec.Deserialize(value,peer.replica.session,peer.replica.adminGuid,Snapshot)
 peer.assembly=Codec.NewAssembler()
 if not snapshot then return false,reason end
 local applied
 applied,reason=Snapshot.Apply(peer.replica,sourceGuid,isLeader,snapshot)
 if not applied then return false,reason end
 peer.ackVersion=snapshot.version
 return true,"completed"
end
function T.ShouldRequest(peer,now)
 if type(now)~="number" or now<0 then return false end
 return not peer.lastRequestAt or now-peer.lastRequestAt>=20
end
function T.Requested(peer,now)
 peer.lastRequestAt=now
end
function T.ResetForResync(peer)
 peer.replica=Snapshot.NewReplica(peer.replica.session,peer.replica.adminGuid)
 peer.assembly=Codec.NewAssembler()
 peer.lastPartAt=nil
end
return T
