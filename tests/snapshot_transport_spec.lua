local ns={}
assert(loadfile("Snapshot.lua"))("StrutYourBootsy",ns)
assert(loadfile("SnapshotCodec.lua"))("StrutYourBootsy",ns)
assert(loadfile("SnapshotTransport.lua"))("StrutYourBootsy",ns)
local T=ns.SnapshotTransport
local host={id="session-12345",adminGuid="admin-guid",rounds=2,
 state={phase="registration",version=2},guids={["player-1"]="contestant"}}
local outbound=assert(T.Build(host))
assert(#outbound.frames>=1)
local peer=T.NewPeer(host.id,host.adminGuid)
local lastStatus
for i=1,#outbound.frames do
 local part=assert(T.Next(outbound))
 local ok,status=T.Receive(peer,"admin-guid",true,
  {kind="SNAP_PART",session=host.id,payload=part},i)
 assert(ok,status)
 lastStatus=status
 T.Advance(outbound)
end
assert(lastStatus=="completed" and peer.replica.version==2 and peer.ackVersion==2)
assert(T.Next(outbound)==nil)
assert(not T.Receive(peer,"fake-guid",true,
 {kind="SNAP_PART",session=host.id,payload=outbound.frames[1]},15))
assert(not T.Receive(peer,"admin-guid",false,
 {kind="SNAP_PART",session=host.id,payload=outbound.frames[1]},15))
assert(T.ShouldRequest(peer,20))
T.Requested(peer,20)
assert(not T.ShouldRequest(peer,30))
assert(T.ShouldRequest(peer,40))
T.ResetForResync(peer)
assert(peer.replica.version==0)
print("Snapshot transport spec passed")
