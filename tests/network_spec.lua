-- Run with a Lua 5.1-compatible interpreter from the repository root:
--   lua tests/network_spec.lua
local namespace = {}
assert(loadfile("Network.lua"))("StrutYourBootsy", namespace)
local Network = assert(namespace.Network)

local now = 100
local roster = {
    {name="Leader-Realm", guid="Player-1", connected=true, leader=true},
    {name="Member-Realm", guid="Player-2", connected=true},
    {name="Quiet-Realm", guid="Player-3", connected=true},
}

local function client(name)
    local sent, events = {}, {}
    local instance = Network.New({
        now=function() return now end,
        serverNow=function() return 1700000000 + now end,
        playerName=function() return name end,
        getRoster=function() return roster end,
        registerPrefix=function(prefix) return prefix == Network.PREFIX end,
        send=function(prefix, message, channel, target)
            sent[#sent + 1] = {prefix=prefix, message=message, channel=channel, target=target}
            return true
        end,
    }, {
        onEvent=function(event, data) events[#events + 1] = {event=event, data=data} end,
        onCommand=function(action) return action ~= "END", "end_disabled_in_test" end,
    })
    assert(instance:Register())
    instance:RefreshRoster()
    return instance, sent, events
end

local function deliver(packet, receiver, sender)
    return receiver:Receive(packet.prefix, packet.message, packet.channel, sender)
end

local leader, leaderSent = client("Leader-Realm")
local member, memberSent = client("Member-Realm")
assert(leader:StartSession("session-1"))
assert(member.leader == "Leader-Realm")

-- End-to-end two-client bootstrap: the participant begins with no session state.
assert(member.sessionId == nil and member.version == 0)
assert(leader:BeginDiscovery())
assert(deliver(leaderSent[#leaderSent], member, "Leader-Realm")) -- leader HELLO -> participant HELLO
assert(deliver(memberSent[#memberSent], leader, "Member-Realm")) -- participant HELLO -> leader WELCOME
assert(deliver(leaderSent[#leaderSent], member, "Leader-Realm")) -- WELCOME initializes participant
assert(member.sessionId == "session-1" and member.version == 1 and member.phase == "registration")

-- Bounded codec and malformed input.
assert(leader.roster["Member-Realm"].presence == "addon_pending")
local huge, hugeReason = Network.Encode({type="HELLO", capability=string.rep("x", 255)})
assert(huge == nil and hugeReason == "oversized_payload")
local decoded, malformedReason = Network.Decode("t=CMD|s=2|broken")
assert(decoded == nil and malformedReason == "malformed_payload")
local unknown, unknownReason = Network.Decode("t=EVIL|s=2")
assert(unknown == nil and unknownReason == "unknown_command")

local old, oldReason = Network.Decode("t=HELLO|s=1|capability=raid-comms-v1")
assert(not old and oldReason == "unsupported_client")
assert(not leaderSent[#leaderSent].message:find("theme=", 1, true))

-- Transport identity comes from sender metadata and must exist in the live roster.
assert(member:Request("ROLE", "role-1", {role="contestant"}))
local rolePacket = memberSent[#memberSent]
local roleWire = rolePacket.message
local outsiderOK, outsiderReason = leader:Receive(Network.PREFIX, roleWire, "WHISPER", "Outsider-Realm")
assert(not outsiderOK and outsiderReason == "sender_not_in_raid")
assert(deliver(rolePacket, leader, "Member-Realm"))
assert(leader.version == 2)
assert(deliver(leaderSent[#leaderSent], member, "Leader-Realm"))
assert(member.version == 2 and member.pending["role-1"].status == "acknowledged")

-- Duplicate command IDs are idempotent and do not apply a second mutation.
local duplicateOK = leader:Receive(Network.PREFIX, roleWire, "WHISPER", "Member-Realm")
assert(duplicateOK and leader.version == 2)
local staleWire = assert(Network.Encode({type="CMD", action="ROLE", role="spectator",
    session_id="old-session", command_id="role-2", expected_version=2}))
local staleOK, staleReason = leader:Receive(Network.PREFIX, staleWire, "WHISPER", "Member-Realm")
assert(not staleOK and staleReason == "stale_session")

-- Spoofed and wrong-phase administrator actions fail closed.
local spoofed = assert(Network.Encode({type="CMD", action="START", session_id="session-1",
    command_id="start-1", expected_version=2}))
local spoofedOK, spoofedReason = leader:Receive(Network.PREFIX, spoofed, "WHISPER", "Member-Realm")
assert(not spoofedOK and spoofedReason == "not_raid_leader")
leader.phase = "voting"
local wrongPhase = assert(Network.Encode({type="CMD", action="START", session_id="session-1",
    command_id="start-2", expected_version=2}))
local phaseOK, phaseReason = leader:Receive(Network.PREFIX, wrongPhase, "WHISPER", "Leader-Realm")
assert(not phaseOK and phaseReason == "wrong_phase")

-- Requests remain pending after queueing and accept only the exact authoritative result version.
assert(member:Request("ROLE", "member-command", {role="spectator"}))
assert(member.pending["member-command"].status == "pending")
assert(member:Retry("member-command"))
assert(member.pending["member-command"].attempts == 2)
local ack = assert(Network.Encode({type="ACK", session_id="session-1", command_id="member-command",
    reason="ok", version=3}))
assert(member:Receive(Network.PREFIX, ack, "WHISPER", "Leader-Realm"))
assert(member.pending["member-command"].status == "acknowledged" and member.version == 3)
local arbitrary = assert(Network.Encode({type="ACK", session_id="session-1", command_id="bad-version",
    reason="ok", version=99}))
member.pending["bad-version"] = {message={expected_version=3}, status="pending", attempts=1}
local arbitraryOK, arbitraryReason = member:Receive(Network.PREFIX, arbitrary, "WHISPER", "Leader-Realm")
assert(not arbitraryOK and arbitraryReason == "invalid_result_version" and member.version == 3)

-- A preparation update is a leader-only, current-session reveal. Check that
-- invalid data does not mutate the registered client's view.
local function reveal(overrides, sender)
    local msg = {type="STATE", session_id="session-1", version=4,
        phase="preparation", theme="Royalty", prep_ends=1700000220}
    for k, v in pairs(overrides or {}) do msg[k] = v end
    return member:Receive(Network.PREFIX, assert(Network.Encode(msg)), "RAID", sender or "Leader-Realm")
end
local ok, reason = reveal({}, "Quiet-Realm")
assert(not ok and reason == "unauthorized_sender")
ok, reason = reveal({session_id="old-session"})
assert(not ok and reason == "unauthorized_sender")
ok, reason = reveal({phase="registration"})
assert(not ok and reason == "malformed_payload")
ok, reason = reveal({theme="|Tnot-markup|t"})
assert(not ok and reason == "malformed_payload")
ok, reason = reveal({prep_ends=1700000900})
assert(not ok and reason == "malformed_payload")
assert(member.phase == "registration" and member.version == 3 and not member:GetProjection().preparation)
assert(reveal())
assert(member.phase == "preparation" and member:GetProjection().preparation.theme == "Royalty")
assert(member:GetProjection().preparation.endsAt == 1700000220)
assert(not reveal({theme="Different"}))
assert(member:GetProjection().preparation.theme == "Royalty")

-- Canonical names cover same-realm, cross-realm, and connected-realm forms.
assert(Network.NormalizeName("Same", "Realm One") == "Same-RealmOne")
assert(Network.NormalizeName("Cross-OtherRealm", "Realm One") == "Cross-OtherRealm")
assert(Network.NormalizeName("Connected", "Connected Realm") == "Connected-ConnectedRealm")
local identityRoster = {{name="Same", guid="Same-GUID", connected=true, leader=true}}
local identity = Network.New({
    now=function() return now end, playerName=function() return "Same-RealmOne" end,
    localRealm=function() return "Realm One" end, getRoster=function() return identityRoster end,
    registerPrefix=function() return true end, send=function() return true end,
}, {})
assert(identity:Register()); identity:RefreshRoster()
assert(identity.roster["Same-RealmOne"].guid == "Same-GUID" and identity.leader == "Same-RealmOne")

-- A failed send creates no pending success state.
local failed = Network.New({
    now=function() return now end, playerName=function() return "Member-Realm" end,
    getRoster=function() return roster end, registerPrefix=function() return true end,
    send=function() return false end,
}, {})
assert(failed:Register()); failed:RefreshRoster(); failed.sessionId, failed.version = "session-1", 1
local sendOK, sendReason = failed:Request("ROLE", "failed-command", {role="spectator"})
assert(not sendOK and sendReason == "transport_failed" and failed.pending["failed-command"] == nil)

-- Silence stays unknown after timeout; an explicit live-GUID confirmation distinguishes a passive member.
leader.phase = "registration"
leader.discoveryStarted = now
assert(leader:GetProjection().lobbyState == "insufficient_contestants")
now = now + Network.DISCOVERY_SECONDS
assert(leader:ClassifyDiscovery())
assert(leader.roster["Quiet-Realm"].presence == "unknown")
assert(leader:GetProjection().presence.unknown > 0)
assert(leader:ConfirmNoAddon("Quiet-Realm", "Player-3"))
assert(leader.roster["Quiet-Realm"].presence == "no_addon")
local badPassive, badPassiveReason = leader:ConfirmNoAddon("Member-Realm", "spoofed-guid")
assert(not badPassive and badPassiveReason == "sender_not_in_raid")

-- Late joins and disconnects are explicit projections.
roster[#roster + 1] = {name="Late-Realm", guid="Player-4", connected=true}
leader:RefreshRoster()
assert(leader.roster["Late-Realm"].joinedAfterStart)
roster[2].connected = false
leader:RefreshRoster()
assert(leader:GetProjection().presence.disconnected == 1)

-- Leadership transfer pauses then ends; it never silently promotes authority.
roster[1].leader, roster[3].leader = false, true
leader:RefreshRoster()
assert(leader.phase == "ended")

-- No wire payload includes ballot details or voter-to-rating mappings.
for _, packet in ipairs(leaderSent) do
    assert(not packet.message:find("ballot", 1, true))
    assert(not packet.message:find("rating", 1, true))
end
for _, packet in ipairs(memberSent) do
    assert(not packet.message:find("ballot", 1, true))
    assert(not packet.message:find("rating", 1, true))
end

print("Network spec passed")
