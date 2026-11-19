local ns={}
assert(loadfile("Core.lua"))("StrutYourBootsy",ns)
assert(loadfile("Authority.lua"))("StrutYourBootsy",ns)
assert(loadfile("Session.lua"))("StrutYourBootsy",ns)
assert(loadfile("Snapshot.lua"))("StrutYourBootsy",ns)
local S=ns.Session
local P=ns.Snapshot
local host=S.New("session-54321","admin-guid","Admin-Realm",2)
local snap=assert(P.FromHost(host))
assert(snap.phase=="registration" and #snap.registrations==0)
local replica=P.NewReplica("session-54321","admin-guid")
assert(not P.Apply(replica,"other-guid",true,snap))
assert(P.Apply(replica,"admin-guid",true,snap))
assert(P.Apply(replica,"admin-guid",true,snap))
local roster={
 ["admin-guid"]={name="Admin-Realm",leader=true,addon=true},
 ["player-1"]={name="Player-Realm",leader=false,addon=true},
}
assert(S.Register(host,roster,"player-1",
 {kind="REGISTER",session="session-54321",seq=1,payload="contestant"}))
local nextSnap=assert(P.FromHost(host))
assert(P.Apply(replica,"admin-guid",true,nextSnap))
assert(replica.snapshot.registrations[1].role=="contestant")
nextSnap.registrations[1].role="spectator"
assert(replica.snapshot.registrations[1].role=="contestant")
assert(not P.Apply(replica,"admin-guid",true,nextSnap))
assert(replica.conflicted)
local fresh=P.NewReplica("session-54321","admin-guid")
local wrong=P.NewReplica("different-session","admin-guid")
assert(not P.Apply(wrong,"admin-guid",true,snap))
assert(P.Apply(fresh,"admin-guid",true,snap))
local gap={session="session-54321",adminGuid="admin-guid",
 version=4,rounds=2,phase="registration",registrations={}}
assert(not P.Apply(fresh,"admin-guid",true,gap))
local ballotLeak={session="session-54321",adminGuid="admin-guid",
 version=3,rounds=2,phase="voting",registrations={}}
assert(not P.Apply(P.NewReplica("session-54321","admin-guid"),"admin-guid",true,ballotLeak))
print("Snapshot spec passed")
