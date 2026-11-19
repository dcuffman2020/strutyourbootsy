-- DEV-02: Pure Lua validation of raid messages. No WoW API dependencies.
local _, ns = ...
ns = ns or {}
local Authority = {}
ns.Authority = Authority

local adminCommands = {
    START=true, BEGIN_RUNWAY=true, BEGIN_VOTING=true,
    CLOSE_VOTING=true, NEXT_ROUND=true, PAUSE=true, RESUME=true, END=true,
}
local participantCommands = { REGISTER=true, BALLOT=true, HELLO=true }
local MAX_PAYLOAD = 220

function Authority.New(sessionId, adminGuid)
    assert(type(sessionId) == "string" and #sessionId >= 8 and #sessionId <= 64)
    assert(type(adminGuid) == "string" and adminGuid ~= "")
    return { sessionId=sessionId, adminGuid=adminGuid, lastSequence={}, version=0 }
end

-- roster is indexed by GUID, with {name=..., addon=true/false, leader=true/false}.
-- senderGuid must be resolved from the live roster by the game adapter; never trust
-- an identity or GUID embedded in the received payload.
function Authority.Validate(ctx, roster, senderGuid, message)
    if type(roster) ~= "table" or type(senderGuid) ~= "string" then return false, "invalid_sender" end
    local member = roster[senderGuid]
    if not member or type(member) ~= "table" then return false, "not_in_raid" end
    if member.addon ~= true then return false, "addon_not_confirmed" end
    if type(message) ~= "table" then return false, "invalid_message" end
    if message.session ~= ctx.sessionId then return false, "wrong_session" end
    if type(message.kind) ~= "string" or not (adminCommands[message.kind] or participantCommands[message.kind]) then
        return false, "unknown_command"
    end
    if type(message.seq) ~= "number" or message.seq % 1 ~= 0 or message.seq < 1 or message.seq > 2147483647 then
        return false, "invalid_sequence"
    end
    if type(message.payload) ~= "string" or #message.payload > MAX_PAYLOAD then
        return false, "invalid_payload"
    end
    if adminCommands[message.kind] then
        if senderGuid ~= ctx.adminGuid or member.leader ~= true then return false, "not_authorized_admin" end
    elseif message.kind == "REGISTER" and senderGuid == ctx.adminGuid then
        return false, "admin_cannot_register"
    elseif message.kind == "BALLOT" and senderGuid == ctx.adminGuid then
        return false, "admin_cannot_vote"
    end
    if message.seq <= (ctx.lastSequence[senderGuid] or 0) then return false, "replayed_message" end
    return true
end

function Authority.Accept(ctx, senderGuid, message)
    -- Only call after Validate and successful domain application.
    ctx.lastSequence[senderGuid] = message.seq
end

function Authority.IsLeaderStillAuthorized(ctx, roster)
    local member = roster and roster[ctx.adminGuid]
    return member ~= nil and member.leader == true and member.addon == true
end

return Authority
