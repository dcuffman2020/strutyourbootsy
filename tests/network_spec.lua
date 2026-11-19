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

local leader, leaderSent = client("Leader-Realm")
local member, memberSent = client("Member-Realm")
assert(leader:StartSession("session-1"))
assert(member.leader == "Leader-Realm")
member.sessionId, member.version = "session-1", 1

-- Bounded codec and malformed input.
local hello = assert(Network.Encode({type="HELLO", capability="raid-comms-v1"}))
assert(leader:Receive(Network.PREFIX, hello, "RAID", "Member-Realm"))
assert(leader.roster["Member-Realm"].presence == "addon_pending")
local huge, hugeReason = Network.Encode({type="HELLO", capability=string.rep("x", 255)})
assert(huge == nil and hugeReason == "oversized_payload")
local decoded, malformedReason = Network.Decode("t=CMD|s=1|broken")
assert(decoded == nil and malformedReason == "malformed_payload")
local unknown, unknownReason = Network.Decode("t=EVIL|s=1")
assert(unknown == nil and unknownReason == "unknown_command")

-- Transport identity comes from sender metadata and must exist in the live roster.
local roleWire = assert(Network.Encode({type="CMD", action="ROLE", role="contestant",
    session_id="session-1", command_id="role-1", expected_version=1}))
local outsiderOK, outsiderReason = leader:Receive(Network.PREFIX, roleWire, "WHISPER", "Outsider-Realm")
assert(not outsiderOK and outsiderReason == "sender_not_in_raid")
assert(leader:Receive(Network.PREFIX, roleWire, "WHISPER", "Member-Realm"))
assert(leader.version == 2)

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

-- Requests remain pending after queueing and become successful only on leader ACK.
member.version = 2
assert(member:Request("ROLE", "member-command", {role="spectator"}))
assert(member.pending["member-command"].status == "pending")
assert(member:Retry("member-command"))
assert(member.pending["member-command"].attempts == 2)
local ack = assert(Network.Encode({type="ACK", session_id="session-1", command_id="member-command",
    reason="ok", version=3}))
assert(member:Receive(Network.PREFIX, ack, "WHISPER", "Leader-Realm"))
assert(member.pending["member-command"].status == "acknowledged" and member.version == 3)

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
assert(leader:BeginDiscovery())
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
