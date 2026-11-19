local ns={}
assert(loadfile("Snapshot.lua"))("StrutYourBootsy",ns)
assert(loadfile("SnapshotCodec.lua"))("StrutYourBootsy",ns)
local S,C=ns.Snapshot,ns.SnapshotCodec
local list={}
for i=1,39 do list[#list+1]={guid="Player-"..string.format("%03d",i),role=i%2==0 and "spectator" or "contestant"} end
local snap={session="session-54321",adminGuid="admin-guid",version=15,rounds=5,phase="registration",registrations=list}
local encoded=assert(C.Serialize(snap,S))
local chunks=assert(C.Fragment(encoded))
assert(#chunks>1)
local assembler=C.NewAssembler()
local finished
for i=#chunks,1,-1 do
 local ok,value=C.Accept(assembler,chunks[i])
 assert(ok,value)
 if value~="pending" and value~="duplicate" then finished=value end
end
assert(finished==encoded)
local decoded=assert(C.Deserialize(finished,"session-54321","admin-guid",S))
assert(decoded.version==15 and #decoded.registrations==39)
assert(decoded.registrations[39].guid=="Player-039")
local dup=C.NewAssembler()
assert(C.Accept(dup,chunks[1]))
local ok,why=C.Accept(dup,chunks[1])
assert(ok and why=="duplicate")
local corrupt=C.NewAssembler()
for i=1,#chunks-1 do assert(C.Accept(corrupt,chunks[i])) end
local last=chunks[#chunks]
local changed=last:sub(1,-2)..(last:sub(-1)=="z" and "a" or "z")
local accepted,reason=C.Accept(corrupt,changed)
assert(not accepted and reason=="checksum_mismatch")
local mixed=C.NewAssembler()
assert(C.Accept(mixed,chunks[1]))
assert(not C.Accept(mixed,"123_1_2_payload"))
assert(C.Deserialize("1.2.bad_extra","session-54321","admin-guid",S)==nil)
assert(C.Deserialize("01.2","session-54321","admin-guid",S)==nil)
print("Snapshot codec spec passed")
