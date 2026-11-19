-- Strut Your Bootsy multiplayer transport and roster adapter (Retail).
-- All WoW APIs are injected. This keeps validation deterministic in headless tests.
local addonName, ns = ...
ns = ns or {}

local Network = {}
Network.__index = Network
ns.Network = Network

Network.PREFIX = "SYBDEV02"
Network.SCHEMA = 1
Network.MAX_BYTES = 255
Network.DISCOVERY_SECONDS = 10
Network.MAX_RECENT_COMMANDS = 128
Network.SEND_BURST = 8
Network.SEND_WINDOW = 5

local knownTypes = { HELLO=true, STATE=true, CMD=true, ACK=true, REJECT=true, PING=true }
local adminActions = { START=true, PAUSE=true, RESUME=true, ADVANCE=true, END=true }
local validPhases = { registration=true, preparation=true, runway=true, voting=true,
    round_results=true, final_results=true, paused=true, ended=true }

local function copy(source)
    local out = {}
    for k, v in pairs(source or {}) do out[k] = v end
    return out
end

local function escape(value)
    return tostring(value):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("=", "%%3D")
end

local function unescape(value)
    local checked = value:gsub("%%25", ""):gsub("%%7C", ""):gsub("%%3D", "")
    if checked:find("%%", 1, true) then return nil end
    return (value:gsub("%%3D", "="):gsub("%%7C", "|"):gsub("%%25", "%%"))
end

local function fullName(name, realm)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    if realm and realm ~= "" then return name .. "-" .. realm:gsub("%s", "") end
    return name
end

local function integer(value, minimum)
    local n = tonumber(value)
    if not n or n % 1 ~= 0 or n < (minimum or 0) then return nil end
    return n
end

function Network.Encode(message)
    local fields = { "t=" .. escape(message.type), "s=" .. escape(message.schema or Network.SCHEMA) }
    local keys = {}
    for key in pairs(message) do
        if key ~= "type" and key ~= "schema" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = message[key]
        if type(key) ~= "string" or not key:match("^[a-z][a-z0-9_]*$") or
           (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean") then
            return nil, "malformed_payload"
        end
        fields[#fields + 1] = key .. "=" .. escape(value == true and 1 or value == false and 0 or value)
    end
    local wire = table.concat(fields, "|")
    if #wire > Network.MAX_BYTES then return nil, "oversized_payload" end
    return wire
end

function Network.Decode(wire)
    if type(wire) ~= "string" then return nil, "malformed_payload" end
    if #wire > Network.MAX_BYTES then return nil, "oversized_payload" end
    local values = {}
    for part in (wire .. "|"):gmatch("(.-)|") do
        local key, raw = part:match("^([a-z][a-z0-9_]*)=(.*)$")
        if not key or values[key] ~= nil then return nil, "malformed_payload" end
        local value = unescape(raw)
        if not value then return nil, "malformed_payload" end
        values[key] = value
    end
    values.type, values.schema = values.t, integer(values.s, 1)
    values.t, values.s = nil, nil
    if values.schema ~= Network.SCHEMA then return nil, "unsupported_client" end
    if not knownTypes[values.type] then return nil, "unknown_command" end
    return values
end

local allowedFields = {
    HELLO={capability=true}, PING={},
    STATE={session_id=true, version=true, phase=true},
    CMD={session_id=true, command_id=true, expected_version=true, action=true, role=true},
    ACK={session_id=true, command_id=true, version=true, reason=true},
    REJECT={session_id=true, command_id=true, version=true, reason=true},
}

local function validateFields(message)
    local allowed = allowedFields[message.type]
    if not allowed then return false, "unknown_command" end
    for key, value in pairs(message) do
        if key ~= "type" and key ~= "schema" and not allowed[key] then return false, "malformed_payload" end
        if type(value) == "string" and #value > 80 then return false, "malformed_payload" end
    end
    if message.type == "HELLO" and message.capability ~= "raid-comms-v1" then return false, "unsupported_client" end
    if message.type == "STATE" and (not message.session_id or not message.version or not message.phase) then return false, "malformed_payload" end
    if message.type == "CMD" and (not message.session_id or not message.command_id or
       not message.expected_version or not message.action) then return false, "malformed_payload" end
    if (message.type == "ACK" or message.type == "REJECT") and
       (not message.session_id or not message.command_id or not message.version or not message.reason) then
        return false, "malformed_payload"
    end
    return true
end

function Network.New(api, callbacks)
    assert(type(api) == "table", "api required")
    local self = setmetatable({}, Network)
    self.api = api
    self.callbacks = callbacks or {}
    self.roster = {}
    self.sessionId = nil
    self.version = 0
    self.phase = "registration"
    self.leader = nil
    self.originalLeader = nil
    self.recentCommands = {}
    self.recentOrder = {}
    self.pending = {}
    self.sendTimes = {}
    self.discoveryStarted = nil
    self.lastRejected = nil
    self.registered = false
    return self
end

function Network:_now()
    return self.api.now and self.api.now() or 0
end

function Network:_emit(event, data)
    if self.callbacks.onEvent then self.callbacks.onEvent(event, data) end
end

function Network:Register()
    if self.registered then return true end
    if not self.api.registerPrefix or not self.api.registerPrefix(Network.PREFIX) then
        return false, "prefix_registration_failed"
    end
    self.registered = true
    return true
end

function Network:RefreshRoster()
    local nextRoster, leader = {}, nil
    local rows = self.api.getRoster and self.api.getRoster() or {}
    for _, row in ipairs(rows) do
        local name = fullName(row.name, row.realm)
        if name and row.guid and row.guid ~= "" then
            local previous = self.roster[name]
            nextRoster[name] = {
                name=name, guid=row.guid, connected=row.connected ~= false,
                leader=row.leader == true, presence=(previous and previous.presence) or "unknown",
                role=previous and previous.role,
                joinedAfterStart=(previous and previous.joinedAfterStart) or (self.sessionId ~= nil and previous == nil),
            }
            if row.leader then leader = name end
        end
    end
    local oldLeader = self.leader
    self.roster, self.leader = nextRoster, leader
    if self.sessionId and oldLeader and leader ~= oldLeader then
        self.phase = "paused"
        self:_emit("authority_changed", { previous=oldLeader, current=leader, policy="pause_then_end" })
        self:EndSession("authority_changed")
    end
    self:_emit("roster_changed", self:GetProjection())
    return nextRoster
end

function Network:BeginDiscovery()
    self.discoveryStarted = self:_now()
    for _, member in pairs(self.roster) do
        if member.name ~= self.leader then member.presence = "unknown" end
    end
    return self:Send({ type="HELLO", capability="raid-comms-v1" }, "RAID")
end

function Network:ClassifyDiscovery()
    if not self.discoveryStarted or self:_now() - self.discoveryStarted < Network.DISCOVERY_SECONDS then
        return false, "discovery_pending"
    end
    -- Silence remains unknown and blocks Start. It is not proof that an addon is absent.
    self:_emit("discovery_classified", self:GetProjection())
    return true
end

-- A higher-level roster workflow may confirm a passive observer only by matching
-- the current live GUID after discovery. Network silence alone never calls this.
function Network:ConfirmNoAddon(name, guid)
    local member = self.roster[name]
    if not self.discoveryStarted or self:_now() - self.discoveryStarted < Network.DISCOVERY_SECONDS then
        return false, "discovery_pending"
    end
    if not member or member.guid ~= guid then return false, "sender_not_in_raid" end
    if member.presence ~= "unknown" then return false, "presence_already_known" end
    member.presence = "no_addon"
    self:_emit("passive_observer_confirmed", {name=name, guid=guid})
    return true
end

function Network:StartSession(sessionId)
    if not self.leader or self.api.playerName() ~= self.leader then return false, "not_raid_leader" end
    if type(sessionId) ~= "string" or sessionId == "" or #sessionId > 40 then return false, "invalid_session" end
    self.sessionId, self.version, self.phase = sessionId, 1, "registration"
    self.originalLeader = self.leader
    self.recentCommands, self.recentOrder, self.pending = {}, {}, {}
    self:_emit("session_started", self:GetProjection())
    return true
end

function Network:EndSession(reason)
    if not self.sessionId then return false, "no_session" end
    self.phase = "ended"
    self.version = self.version + 1
    self:_emit("session_ended", { reason=reason, sessionId=self.sessionId, version=self.version })
    return true
end

function Network:_allowSend()
    local now, kept = self:_now(), {}
    for _, timestamp in ipairs(self.sendTimes) do
        if now - timestamp < Network.SEND_WINDOW then kept[#kept + 1] = timestamp end
    end
    self.sendTimes = kept
    if #kept >= Network.SEND_BURST then return false end
    kept[#kept + 1] = now
    return true
end

function Network:Send(message, channel, target)
    if not self.registered then return false, "not_registered" end
    if not self:_allowSend() then return false, "rate_limited" end
    local wire, reason = Network.Encode(message)
    if not wire then return false, reason end
    local ok = self.api.send(Network.PREFIX, wire, channel or "RAID", target)
    if not ok then return false, "transport_failed" end
    -- This means queued by transport only; state success still requires ACK/STATE.
    return true, "queued"
end

function Network:Request(action, commandId, fields)
    if not self.sessionId then return false, "no_session" end
    if type(commandId) ~= "string" or commandId == "" or #commandId > 40 then return false, "invalid_command_id" end
    local message = copy(fields)
    message.type, message.action, message.command_id = "CMD", action, commandId
    message.session_id, message.expected_version = self.sessionId, self.version
    local ok, reason = self:Send(message, "WHISPER", self.leader)
    if ok then self.pending[commandId] = { message=message, status="pending", attempts=1 } end
    return ok, reason
end

function Network:Retry(commandId)
    local pending = self.pending[commandId]
    if not pending then return false, "unknown_command_id" end
    local ok, reason = self:Send(pending.message, "WHISPER", self.leader)
    if ok then pending.attempts = pending.attempts + 1 end
    return ok, reason
end

function Network:_reject(sender, commandId, reason)
    self.lastRejected = reason
    self:_emit("command_rejected", { sender=sender, commandId=commandId, reason=reason })
    if commandId and self.roster[sender] then
        self:Send({ type="REJECT", session_id=self.sessionId or "-", command_id=commandId,
            reason=reason, version=self.version }, "WHISPER", sender)
    end
    return false, reason
end

function Network:_remember(commandId, result)
    self.recentCommands[commandId] = result
    self.recentOrder[#self.recentOrder + 1] = commandId
    if #self.recentOrder > Network.MAX_RECENT_COMMANDS then
        local expired = table.remove(self.recentOrder, 1)
        self.recentCommands[expired] = nil
    end
end

function Network:_handleCommand(message, sender)
    local id = message.command_id
    local replayKey = sender .. "\0" .. tostring(id)
    if type(id) ~= "string" or id == "" or #id > 40 then return self:_reject(sender, nil, "invalid_command_id") end
    if self.recentCommands[replayKey] then
        local prior = self.recentCommands[replayKey]
        self:Send({ type=prior.ok and "ACK" or "REJECT", session_id=self.sessionId,
            command_id=id, reason=prior.reason or "ok", version=self.version }, "WHISPER", sender)
        return prior.ok, prior.reason or "duplicate_replayed"
    end
    if message.session_id ~= self.sessionId then return self:_reject(sender, id, "stale_session") end
    local expected = integer(message.expected_version, 0)
    if expected ~= self.version then return self:_reject(sender, id, "snapshot_mismatch") end
    local action = message.action
    if not action or (not adminActions[action] and action ~= "ROLE") then return self:_reject(sender, id, "unknown_command") end
    if adminActions[action] and sender ~= self.leader then return self:_reject(sender, id, "not_raid_leader") end
    if action == "START" and self.phase ~= "registration" then return self:_reject(sender, id, "wrong_phase") end
    if (action == "PAUSE" and (self.phase == "paused" or self.phase == "ended")) or
       (action == "RESUME" and self.phase ~= "paused") or (action == "ADVANCE" and self.phase ~= "runway") then
        return self:_reject(sender, id, "wrong_phase")
    end
    if action == "ROLE" then
        if self.phase ~= "registration" then return self:_reject(sender, id, "wrong_phase") end
        if sender == self.leader then return self:_reject(sender, id, "admin_cannot_participate") end
        if message.role ~= "contestant" and message.role ~= "spectator" then return self:_reject(sender, id, "invalid_role") end
    end
    local ok, reason = true, nil
    if not self.callbacks.onCommand then return self:_reject(sender, id, "unsupported_command") end
    ok, reason = self.callbacks.onCommand(action, sender, copy(message))
    if not ok then self:_remember(replayKey, {ok=false, reason=reason or "rejected"}); return self:_reject(sender, id, reason or "rejected") end
    if action == "ROLE" then
        self.roster[sender].role = message.role
        self.roster[sender].presence = "addon_ready"
    end
    self.version = self.version + 1
    self:_remember(replayKey, {ok=true})
    self:Send({ type="ACK", session_id=self.sessionId, command_id=id, reason="ok", version=self.version }, "WHISPER", sender)
    self:_emit("command_acknowledged", { action=action, sender=sender, commandId=id, version=self.version })
    return true
end

function Network:Receive(prefix, wire, channel, sender)
    if prefix ~= Network.PREFIX then return false, "wrong_prefix" end
    sender = fullName(sender)
    local member = sender and self.roster[sender]
    if not member then return self:_reject(sender, nil, "sender_not_in_raid") end
    if not member.connected then return self:_reject(sender, nil, "disconnected") end
    local message, reason = Network.Decode(wire)
    if not message then return self:_reject(sender, nil, reason) end
    local valid, validationReason = validateFields(message)
    if not valid then return self:_reject(sender, message.command_id, validationReason) end
    if message.type == "HELLO" then
        member.presence = "addon_pending"
        self:_emit("addon_detected", { name=sender, guid=member.guid })
        return true
    elseif message.type == "CMD" then
        if self.api.playerName() ~= self.leader then return self:_reject(sender, message.command_id, "not_authority") end
        return self:_handleCommand(message, sender)
    elseif message.type == "ACK" or message.type == "REJECT" then
        if sender ~= self.leader or message.session_id ~= self.sessionId then return self:_reject(sender, message.command_id, "unauthorized_sender") end
        local pending = self.pending[message.command_id]
        if not pending then return self:_reject(sender, message.command_id, "unknown_command_id") end
        local version = integer(message.version, 0)
        if not version or version < self.version then return self:_reject(sender, message.command_id, "stale_version") end
        pending.status = message.type == "ACK" and "acknowledged" or "rejected"
        pending.reason, self.version = message.reason, version
        self:_emit("request_result", { commandId=message.command_id, status=pending.status, reason=pending.reason })
        return message.type == "ACK", message.reason
    elseif message.type == "STATE" then
        if sender ~= self.leader or message.session_id ~= self.sessionId then return self:_reject(sender, nil, "unauthorized_sender") end
        local version = integer(message.version, 0)
        if not version or version <= self.version or not validPhases[message.phase] then return self:_reject(sender, nil, "stale_version") end
        self.version, self.phase = version, message.phase
        self:_emit("state_confirmed", self:GetProjection())
        return true
    elseif message.type == "PING" then
        member.presence = "addon_ready"
        return true
    end
    return self:_reject(sender, nil, "unknown_command")
end

function Network:GetProjection()
    local counts = { addon_ready=0, addon_pending=0, no_addon=0, disconnected=0, late_joiner=0, unknown=0 }
    local contestants = 0
    for _, member in pairs(self.roster) do
        local key = member.connected and member.presence or "disconnected"
        if member.joinedAfterStart then key = "late_joiner" end
        counts[key] = (counts[key] or 0) + 1
        if member.connected and member.role == "contestant" and not member.joinedAfterStart then contestants = contestants + 1 end
    end
    local localName = self.api.playerName and self.api.playerName() or nil
    local localMember = self.roster[localName]
    local lobby
    if not self.leader then lobby = "insufficient_contestants"
    elseif localMember and not localMember.connected then lobby = "disconnected"
    elseif localName ~= self.leader and localMember and localMember.presence == "no_addon" then lobby = "passive_observer"
    elseif localMember and localMember.joinedAfterStart then lobby = "late_joiner"
    elseif localName ~= self.leader then lobby = "not_raid_leader"
    elseif contestants < 5 then lobby = "insufficient_contestants"
    elseif counts.addon_pending > 0 or counts.unknown > 0 then lobby = "pending_addon_users"
    else lobby = "ready_to_start" end
    return { sessionId=self.sessionId, version=self.version, phase=self.phase, leader=self.leader,
        isLeader=localName == self.leader, presence=counts, contestants=contestants,
        lobbyState=lobby, lastRejected=self.lastRejected }
end
