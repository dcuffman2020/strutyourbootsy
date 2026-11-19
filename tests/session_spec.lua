local ns={}
assert(loadfile("Core.lua"))("StrutYourBootsy",ns)
assert(loadfile("Authority.lua"))("StrutYourBootsy",ns)
assert(loadfile("Session.lua"))("StrutYourBootsy",ns)
local S=ns.Session
local ctx=S.New("session-54321","admin-guid","Leader-Realm",2)
local roster={["admin-guid"]={name="Leader-Realm",addon=true,leader=true}}
for i=1,5 do
 roster["player-"..i]={name="Player"..i.."-Realm",addon=true,leader=false}
end
roster["observer"]={name="Observer-Realm",addon=false,leader=false}
assert(not S.CanStart(ctx,roster))
for i=1,5 do
 local guid="player-"..i
 local message={kind="REGISTER",session="session-54321",seq=1,payload="contestant"}
 assert(S.Register(ctx,roster,guid,message))
 assert(not S.Register(ctx,roster,guid,message))
end
assert(S.CanStart(ctx,roster))
-- Missing ACK may trigger a new request with a higher sequence.
assert(S.Register(ctx,roster,"player-1",{kind="REGISTER",session="session-54321",seq=2,payload="contestant"}))
assert(not S.Register(ctx,roster,"player-1",{kind="REGISTER",session="session-54321",seq=3,payload="spectator"}))
local forged={kind="REGISTER",session="session-54321",seq=2,payload="spectator"}
assert(not S.Register(ctx,roster,"observer",forged))
assert(not S.Register(ctx,roster,"admin-guid",forged))
local peer=S.NewPeer("session-54321","admin-guid",2)
local ack={kind="REG_ACK",session="session-54321",payload="player-1.contestant"}
assert(S.ApplyAck(peer,roster,"admin-guid",ack))
assert(peer.registrations["player-1"]=="contestant")
assert(not S.ApplyAck(peer,roster,"player-1",ack))
roster["admin-guid"].leader=false
assert(not S.CanStart(ctx,roster))
print("Session spec passed")
