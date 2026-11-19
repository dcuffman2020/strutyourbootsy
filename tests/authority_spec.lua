local ns = {}
assert(loadfile("Authority.lua"))("StrutYourBootsy", ns)
local A = assert(ns.Authority)
local ctx = A.New("session-12345", "admin-guid")
local roster = {
 ["admin-guid"]={addon=true,leader=true},
 ["player-guid"]={addon=true,leader=false},
 ["observer-guid"]={addon=false,leader=false},
}
local function msg(kind,seq,session)
 return {kind=kind,seq=seq,session=session or "session-12345",payload=""}
end
local function reject(g,m,reason)
 local ok,why=A.Validate(ctx,roster,g,m)
 assert(not ok and why==reason, tostring(why).." expected "..reason)
end
assert(A.Validate(ctx,roster,"admin-guid",msg("START",1)))
reject("player-guid",msg("START",1),"not_authorized_admin")
reject("unknown",msg("HELLO",1),"not_in_raid")
reject("observer-guid",msg("HELLO",1),"addon_not_confirmed")
reject("player-guid",msg("BALLOT",1,"other-session"),"wrong_session")
reject("admin-guid",msg("BALLOT",1),"admin_cannot_vote")
reject("admin-guid",msg("REGISTER",1),"admin_cannot_register")
reject("player-guid",msg("BOGUS",1),"unknown_command")
reject("player-guid",msg("HELLO",0),"invalid_sequence")
assert(A.Validate(ctx,roster,"player-guid",msg("HELLO",1)))
A.Accept(ctx,"player-guid",msg("HELLO",1))
reject("player-guid",msg("HELLO",1),"replayed_message")
reject("player-guid",msg("HELLO",0),"invalid_sequence")
assert(A.IsLeaderStillAuthorized(ctx,roster))
roster["admin-guid"].leader=false
reject("admin-guid",msg("PAUSE",2),"not_authorized_admin")
assert(not A.IsLeaderStillAuthorized(ctx,roster))
print("Authority spec passed")
