-- Headless host Main.lua with the actual Network/Core/Teams modules.
-- WoW rendering and transport delivery are the mocked boundary.
local ns={}
for _,path in ipairs({"Core.lua","Teams.lua","Network.lua"}) do
    assert(loadfile(path))("StrutYourBootsy",ns)
end
local Network,Teams=ns.Network,ns.Teams
local base=1700000000
local now,roster,queue,warnings,timers=0,{},{},{},{}
local host,adapter,event
local names={"Host-Realm","Amber-Realm","Birch-Realm","Cedar-Realm","Dawn-Realm",
    "Ember-Realm","Fern-Realm","Viewer-Realm","Guest-Realm"}
local function advance(seconds) now=now+seconds end
local function window() advance(Network.SEND_WINDOW+1) end
local function packet(source,prefix,wire,channel,target)
    queue[#queue+1]={source=source,prefix=prefix,wire=wire,channel=channel,target=target,message=assert(Network.Decode(wire))}
end
local function receive(client,p)
    client:RefreshRoster()
    return client:Receive(p.prefix,p.wire,p.channel,p.source)
end
local function last(kind,source,target)
    for i=#queue,1,-1 do
        local p=queue[i]
        if p.message.type==kind and p.source==source and (not target or p.target==target) then return p end
    end
    error("missing "..kind.." from "..source)
end
local function reject(want,ok,why) assert(not ok and why==want,tostring(why).." ~= "..want) end
local function serverTime() return base+now end
GetTime=function() return now end
GetServerTime=serverTime
GetNormalizedRealmName=function() return "Realm" end
IsInRaid=function() return true end
GetNumGroupMembers=function() return #roster end
local function unitRow(unit)
    return roster[unit=="player" and 1 or tonumber(unit:match("^raid(%d+)$"))]
end
UnitFullName=function(unit) return unitRow(unit).name:match("^([^-]+)%-(.+)$") end
UnitGUID=function(unit) return unitRow(unit).guid end
GetRaidRosterInfo=function(i)
    local m=roster[i]
    return m.name,m.leader and 2 or 0,nil,nil,nil,nil,nil,m.connected
end
CreateFrame=function()
    return {RegisterEvent=function() end,SetScript=function(_,key,fn) assert(key=="OnEvent"); event=fn end}
end
C_Timer={After=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn} end}
Enum={SendAddonMessageResult={Success=0}}
C_ChatInfo={
    RegisterAddonMessagePrefix=function() end, IsAddonMessagePrefixRegistered=function() return true end,
    SendAddonMessage=function(...) packet(names[1],...); return 0 end,
    SendChatMessage=function(message,channel)
        assert(channel=="RAID_WARNING")
        warnings[#warnings+1]=message
        return true
    end,
}
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
ns.UI={Initialize=function(a) adapter=a end,Refresh=function() end}
local construct=Network.New
Network.New=function(...)
    host=construct(...)
    return host
end
local viewer,guest,entrant
local seq=0
local function id()
    seq=seq+1
    return "test-"..seq
end
local function command(action)
    window()
    local ok,why=host:AdminCommand(action,id())
    if ok then assert(host:BroadcastContest()) end
    return ok,why
end
local function client(index)
    local name=names[index]
    local c=construct({
        now=GetTime,serverNow=GetServerTime,playerName=function() return name end,
        getRoster=function() return roster end,registerPrefix=function() return true end,
        send=function(...) packet(name,...);return true end,
    },{})
    assert(c:Register())
    c:RefreshRoster()
    return c
end
local function sync(c,name)
    window()
    assert(c:Poll())
    assert(receive(host,last("HELLO",name)))
    assert(receive(c,last("WELCOME",names[1],name)))
end
local function member(name,fields,action,version)
    window()
    local wire=assert(Network.Encode({type="CMD",session_id=host.sessionId,expected_version=version or host.version,
        action=action or "ROLE",command_id=id(),role=fields.role,ratings=fields.ratings,op=fields.op,slot=fields.slot,txt=fields.txt}))
    return host:Receive(Network.PREFIX,wire,"WHISPER",name)
end
local function page(c,n)
    window()
    assert(host:BroadcastVotePage(n))
    assert(receive(c,last("PAGE",names[1])))
    return assert(c:GetVotePage(n))
end
local function init(size,count)
    now,queue,warnings,timers=0,{},{},{}
    SYBCharacterDB=nil
    host=nil
    roster={}
    local limit=9
    for j,n in ipairs(names) do
        if j<=limit and (size or j~=7) then
            roster[#roster+1]={name=n,guid=string.format("%032d",j),connected=true,leader=j==1}
        end
    end
    -- Recreate Main locals across independent sessions.
    assert(loadfile("Main.lua"))("StrutYourBootsy",ns)
    event(nil,"PLAYER_LOGIN")
    adapter.setContestFormat(size)
    adapter.openRegistration()
    assert(adapter.setLiveRounds(count))
    assert(host:GetProjection().rounds==count and not host:SetRounds(6))
    for j=2,limit do
        if size or j~=7 then assert(member(names[j],{role=j>=8 and "spectator" or "contestant"})) end
    end
    if size then
        for t=1,3 do
            assert(member(names[t*2],{op="create",txt="Team "..t},"TEAM"))
            assert(member(names[t*2+1],{op="join",slot=t},"TEAM"))
        end
    end
    viewer,entrant=client(8),client(2)
    guest=client(9)
    sync(viewer,names[8]); sync(entrant,names[2])
    if guest then sync(guest,names[9]) end
    assert(viewer.round==0 and viewer.rounds==count)
    assert(host:GetProjection().lobbyState=="ready_to_start")
    assert(command("START"))
    assert(not host:SetRounds(count==1 and 2 or 1))
    assert(host.round==1 and host.phase=="preparation")
end
local function reachVote(n,size)
    assert(host.round==n and host.phase=="preparation")
    reject("preparation_running",command("BEGIN_RUNWAY"))
    advance(host.preparation.endsAt-serverTime())
    assert(command("BEGIN_RUNWAY"))
    local seen={}
    for _=1,size do
        assert(host.runway.current and not seen[host.runway.current])
        seen[host.runway.current]=true
        assert(command("ADVANCE"))
    end
    assert(host.phase=="runway_complete")
    window()
    adapter.beginVoting()
    assert(host.phase=="voting")
    assert(host.voting.total==size and host.voting.endsAt==serverTime()+Network.VOTING_SECONDS)
end
local function ballot(ratings,order)
    local digits={}
    for i,k in ipairs(order or host.voting.order) do digits[i]=ratings[k] or 0 end
    return table.concat(digits)
end
local function entryRatings(values,size)
    local byEntry={}
    for i,score in ipairs(values) do
        byEntry[size and Teams.Entry(i) or names[i+1]]=score
    end
    return ballot(byEntry)
end
local function submit(c,name,ratings,deliverAck)
    assert(c:Request("VOTE",id(),{ratings=ratings}))
    local outgoing=last("CMD",name)
    assert(receive(host,outgoing))
    local reply=last("ACK",names[1],name)
    if deliverAck then assert(receive(c,reply)) end
    return outgoing,reply
end
local function voteTimer(deadline)
    local close
    for _,timer in ipairs(timers) do
        if timer.at==deadline-base then close=timer.fn end
    end
    return assert(close,"Main must schedule vote closure")
end
local function closeVote()
    local deadline=host.voting.endsAt
    assert(serverTime()<deadline)
    local close=voteTimer(deadline)
    advance(deadline-serverTime())
    close()
    assert(host.phase=="round_results")
end
local function namesByRank(c)
    local out={}
    for p=1,math.ceil(c.awardCount/Network.VOTE_PAGE_SIZE) do
        for _,r in ipairs(page(c,p)) do out[r.index]=r.guid end
    end
    return out
end

-- Two live solo rounds. Two voters in every round, second ballot partial.
init(nil,2)
local rounds = {
    {{5,4,3,2,1},{5,4,3,2,1}},
    {{3,5,2,1,5},{3,5,2,1,0}},
}
local stale,oldAck
for r=1,2 do
    reachVote(r,5)
    assert(receive(viewer,last("STATE",names[1])))
    assert(viewer.phase=="voting" and viewer.round==r and not viewer.voted)
    if r==2 then
        -- Both exact idempotent replay and a different old-revision packet:
        -- neither may populate the new round's accepted-voter map or client UI.
        reject("snapshot_mismatch",member(names[8],{ratings=entryRatings(rounds[r][1])},"VOTE",tonumber(stale.message.expected_version)))
        assert(receive(host,stale))
        assert(not host.voting.accepted["00000000000000000000000000000008"])
        receive(viewer,oldAck)
        assert(not viewer.voted)
    end
    window()
    local p,ack=submit(viewer,names[8],entryRatings(rounds[r][1]),r==2)
    if r==1 then stale,oldAck=p,ack else assert(viewer.voted) end
    sync(entrant,names[2])
    window()
    reject("self_vote",member(names[2],{ratings=entryRatings({1,5,5,5,0})},"VOTE"))

    sync(guest,names[9])
    window()
    submit(guest,names[9],entryRatings(rounds[r][2]),true)
    closeVote()
    assert(receive(viewer,last("STATE",names[1])))
    local rows=page(viewer,1)
    assert(rows[1].score==500 and rows[1].cumulative==(r==1 and 500 or 450))
    if r==1 then
        reject("not_finished",command("OPEN_AWARDS"))
        window(); adapter.nextRound()
    end
end
window(); adapter.openAwards()
assert(receive(viewer,last("STATE",names[1])))
assert(viewer.awardCount==4 and viewer.awardRevealed==0)
local ranks=namesByRank(viewer)
assert(table.concat(ranks,",")=="-,-,-,-")
for i=1,3 do
    window(); adapter.revealAward()
    assert(receive(viewer,last("STATE",names[1])) and viewer.awardRevealed==i)
    ranks=namesByRank(viewer)
    if i<3 then assert(ranks[1]=="-" and ranks[4]=="-") end
    if i==1 then assert(ranks[2]=="-" and ranks[3]==roster[4].guid) end
    if i==2 then assert(ranks[2]==roster[2].guid) end
end
assert(ranks[1]==roster[3].guid and ranks[2]==roster[2].guid and ranks[3]==roster[4].guid and ranks[4]==roster[5].guid)
local function warningCount(pattern)
    local n=0
    for _,line in ipairs(warnings) do if line:find(pattern,1,true) then n=n+1 end end
    return n
end
for r=1,2 do
    assert(warningCount("Round "..r.." voting is open")==1)
    assert(warningCount("Round "..r.." voting is closed")==1)
end
assert(warningCount("Third place: Cedar-Realm!") == 1)
assert(warningCount("Second place: Amber-Realm!") == 1)
assert(warningCount("First place: Birch-Realm! Honorable Mention: Dawn-Realm.") == 1)
window(); adapter.endContest()
assert(host.phase=="ended")

-- Team rounds preserve the matching entry IDs while reshuffling the runway.
-- Lockout applies to the entire voter team, not just its captain.
init(2,2)
for r=1,2 do
    reachVote(r,3)
    sync(entrant,names[2]); sync(viewer,names[8]); sync(guest,names[9])
    reject("self_vote",member(names[3],{ratings=entryRatings({5,1,1},true)},"VOTE"))
    window(); submit(viewer,names[8],entryRatings(r==1 and {5,3,1} or {3,5,1},true),true)
    window(); submit(guest,names[9],entryRatings(r==1 and {5,3,1} or {3,5,0},true),true)
    closeVote()
    assert(receive(viewer,last("STATE",names[1])))
    local all=page(viewer,1)
    assert(#all==3 and all[1].guid==Teams.Entry(r) and all[1].score==500)
    if r==1 then
        roster[2].connected=false
        host:RefreshRoster()
        assert(host:RunwayBlocked()); adapter.nextRound(); assert(host.round==1)
        roster[2].connected=true
        host:RefreshRoster()
        assert(not host:RunwayBlocked() and host.round==1)
        window(); adapter.nextRound()
    end
end
window(); adapter.openAwards()
assert(receive(viewer,last("STATE",names[1])))
assert(viewer.awardCount==2 and not viewer.awardsConfirmed)
adapter.revealAward(); assert(host.awards.revealed==0)
assert(adapter.recordRoll(Teams.Entry(1),20))
assert(adapter.recordRoll(Teams.Entry(2),90))
window(); adapter.confirmAwards()
window(); adapter.revealAward()
assert(receive(viewer,last("STATE",names[1])))
assert(namesByRank(viewer)[2]==Teams.Entry(1))
window(); adapter.revealAward()
assert(receive(viewer,last("STATE",names[1])))
assert(namesByRank(viewer)[1]==Teams.Entry(2))
-- The official cannot be promoted mid-contest by a roster change.
roster[1].leader,roster[2].leader=false,true
host:RefreshRoster(); viewer:RefreshRoster()
assert(host.phase=="ended" and viewer.phase=="ended" and not host.sessionId and not viewer.sessionId)
assert(not host:AdminCommand("OPEN_AWARDS",id()))

-- A paused vote must not close on its original timer or reset accepted
-- ballots. Contestant recovery is explicit, while an expired authority ends.
init(nil,1)
reachVote(1,5)
sync(viewer,names[8])
window()
submit(viewer,names[8],entryRatings({5,4,3,2,1}),true)
local deadline=host.voting.endsAt
local staleClose=voteTimer(deadline)
roster[2].connected=false
window(); host:RefreshRoster()
assert(host.phase=="paused" and host.pausedPhase=="voting" and host.pauseCause=="contestant")
assert(receive(viewer,last("STATE",names[1])) and viewer.voted and viewer.phase=="paused")
local left=host.pauseRemaining
assert(left>0 and left<Network.VOTING_SECONDS)
reject("voting_closed",member(names[9],{ratings=entryRatings({5,4,3,2,1})},"VOTE"))
adapter.resumeLive(); assert(host.phase=="paused")
advance(deadline-serverTime()+1)
staleClose(); assert(host.phase=="paused")
roster[2].connected=true
host:RefreshRoster()
assert(host.phase=="paused")
window(); adapter.resumeLive()
assert(host.phase=="voting" and host.voting.endsAt==serverTime()+left)
staleClose(); assert(host.phase=="voting")
assert(receive(viewer,last("STATE",names[1])) and viewer.voted)
reject("ballot_already_submitted",member(names[8],{ratings=entryRatings({5,4,3,2,1})},"VOTE"))
sync(guest,names[9])
window(); submit(guest,names[9],entryRatings({5,4,3,2,1}),true)
closeVote()
assert(host.voting.results[1].average==5 and warningCount("Round 1 voting is open")==1)
adapter.nextRound(); assert(host.phase=="round_results")
window(); adapter.openAwards()
assert(host.phase=="final_results" and #host.awards.results==5)
roster[1].connected=false
host:RefreshRoster()
assert(host:GetProjection().pauseCause=="authority" and not host:IsAuthority())
advance(Network.AUTHORITY_TIMEOUT)
host:RefreshRoster()
assert(host.phase=="ended")
print("Main/Network/Core live solo, team, single-round, and disconnect lifecycle passed")
