-- Strut Your Bootsy multiplayer transport and roster adapter (Retail).
-- All WoW APIs are injected. This keeps validation deterministic in headless tests.
local addonName, ns = ...
ns = ns or {}

local Network = {}
Network.__index = Network
ns.Network = Network

Network.PREFIX = "SYBDEV02"
Network.SCHEMA = 6
Network.CAPABILITY = "raid-comms-v6"
Network.PREPARATION_SECONDS = 120
Network.PREPARATION_OPTIONS = {120,180,240,300}
Network.PREPARATION_MAX = Network.PREPARATION_OPTIONS[#Network.PREPARATION_OPTIONS]

function Network.ValidPreparationSeconds(seconds)
    for _,value in ipairs(Network.PREPARATION_OPTIONS) do if seconds==value then return true end end
    return false
end
Network.RUNWAY_SECONDS = 120
Network.RUNWAY_OPTIONS = {30,60,120,180,300}

function Network.ValidRunwaySeconds(seconds)
    for _,value in ipairs(Network.RUNWAY_OPTIONS) do if seconds==value then return true end end
    return false
end
Network.MAX_BYTES = 255
Network.VOTING_SECONDS, Network.VOTE_PAGE_SIZE = 60, 4
Network.DISCOVERY_SECONDS = 10
Network.MAX_RECENT_COMMANDS = 128
Network.SEND_BURST = 8
Network.SEND_WINDOW = 5

local knownTypes = { HELLO=true, WELCOME=true, STATE=true, CMD=true, ACK=true, REJECT=true, PING=true, PAGE_REQ=true, PAGE=true }
local adminActions = { START=true, BEGIN_RUNWAY=true, PAUSE=true, RESUME=true, ADVANCE=true, END=true, BEGIN_VOTING=true, CLOSE_VOTING=true }
local rejectReasons = {
    admin_cannot_participate=true, already_registered=true, disconnected=true,
    duplicate_result=true, identity_mismatch=true, invalid_ack=true,
    invalid_command_id=true, invalid_player=true, invalid_reject=true,
    invalid_result_version=true, invalid_role=true, malformed_payload=true,
    no_session=true, not_authority=true, not_raid_leader=true,
    sender_not_in_raid=true, stale_version=true,
    snapshot_mismatch=true, stale_session=true, unsupported_command=true,
    unknown_command=true, unknown_command_id=true, unauthorized_sender=true,
    unsupported_client=true, wrong_channel=true, wrong_phase=true,
    late_joiner=true, pending_addon_users=true, insufficient_contestants=true, discovery_pending=true,
    voting_closed=true, not_eligible=true, admin_cannot_vote=true, self_vote=true,
    ballot_already_submitted=true, invalid_ballot=true, empty_ballot=true,
    registration_closed=true, minimum_five_contestants=true, registration_pending=true,
    invalid_runway_order=true, preparation_unavailable=true, preparation_running=true,
}
local validPhases = { registration=true, preparation=true, runway=true, runway_complete=true, voting=true,
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
    if checked:find("%", 1, true) then return nil end
    return (value:gsub("%%3D", "="):gsub("%%7C", "|"):gsub("%%25", "%%"))
end

local function fullName(name, realm)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    if realm and realm ~= "" then return name .. "-" .. realm:gsub("%s", "") end
    return name
end


function Network.NormalizeName(name, realm)
    return fullName(name, realm)
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
    HELLO={capability=true}, PING={session_id=true, version=true},
    WELCOME={session_id=true, version=true, phase=true, leader_guid=true, role=true, late=true, theme=true, prep_ends=true, pos=true, total=true, cur=true, nxt=true, run_ends=true, vote_ends=true, vote_total=true, voted=true},
    STATE={session_id=true, version=true, phase=true, theme=true, prep_ends=true, pos=true, total=true, cur=true, nxt=true, run_ends=true, vote_ends=true, vote_total=true},
    CMD={session_id=true, command_id=true, expected_version=true, action=true, role=true, ratings=true},
    PAGE_REQ={session_id=true,version=true,page=true},
    PAGE={session_id=true,version=true,page=true,rows=true},
    ACK={session_id=true, command_id=true, version=true, reason=true},
    REJECT={session_id=true, command_id=true, version=true, reason=true},
}

local function validTheme(value)
    -- Alpha theme names are bounded plain text, not WoW markup.
    return type(value) == "string" and #value <= 48 and value:match("^[%a][%w ,'-]*$") ~= nil
end

function Network.NormalizeCustomTheme(text)
    if type(text)~="string" then return nil end
    local trimmed=text:match("^ *(.-) *$")
    return validTheme(trimmed) and trimmed or nil
end

local function validGuid(x)
    return type(x) == "string" and #x <= 32 and x:match("^[%w%-]+$") ~= nil
end

local function validateFields(message)
    local allowed = allowedFields[message.type]
    if not allowed then return false, "unknown_command" end
    for key, value in pairs(message) do
        if key ~= "type" and key ~= "schema" and not allowed[key] then return false, "malformed_payload" end
        if type(value) == "string" and #value > (key=="rows" and 148 or 80) then return false, "malformed_payload" end
    end
    if message.type == "HELLO" and message.capability ~= Network.CAPABILITY then return false, "unsupported_client" end
    if message.type == "PING" and (not message.session_id or not message.version) then return false, "malformed_payload" end
    if message.type == "WELCOME" and
       ((message.role and message.role ~= "contestant" and message.role ~= "spectator") or
        (message.late and message.late ~= "1")) then return false, "malformed_payload" end
    if message.type == "WELCOME" and (not message.session_id or not message.version or
       not message.phase or not message.leader_guid) then return false, "malformed_payload" end
    if message.type == "STATE" and (not message.session_id or not message.version or not message.phase) then return false, "malformed_payload" end
    if message.type == "WELCOME" or message.type == "STATE" then
        if message.phase == "preparation" then
            if not validTheme(message.theme) or not integer(message.prep_ends, 1) then
                return false, "malformed_payload"
            end
        elseif message.theme or message.prep_ends then
            return false, "malformed_payload"
        end
        local runway = message.phase == "runway" or message.phase == "runway_complete"
        if runway then
            local pos, total = integer(message.pos,1), integer(message.total,5)
            if not pos or not total or total > 39 or pos > total then return false, "malformed_payload" end
            if message.phase == "runway" then
                if not integer(message.run_ends,1) or not validGuid(message.cur) or (pos < total and not validGuid(message.nxt)) or
                   (pos == total and message.nxt) or message.cur == message.nxt then
                    return false, "malformed_payload"
                end
            elseif pos ~= total or message.cur or message.nxt or message.run_ends then return false, "malformed_payload" end
        elseif message.pos or message.total or message.cur or message.nxt or message.run_ends then
            return false, "malformed_payload"
        end
    end
    if message.type=="WELCOME" or message.type=="STATE" then
        local voting=message.phase=="voting"
        local summary=voting or message.phase=="round_results"
        if summary then
            local total=integer(message.vote_total,5)
            if not total or total>39 or (voting and not integer(message.vote_ends,1))
                or (not voting and message.vote_ends) or (message.voted and message.voted~="1") then
                return false,"malformed_payload"
            end
        elseif message.vote_total or message.vote_ends or message.voted then return false,"malformed_payload" end
    end
    if message.type=="PAGE" or message.type=="PAGE_REQ" then
        local page=integer(message.page,1)
        if not page or page>math.ceil(39/Network.VOTE_PAGE_SIZE) or not message.session_id
            or not integer(message.version,1) or (message.type=="PAGE" and not message.rows) then
            return false,"malformed_payload"
        end
    end
    if message.type=="CMD" and (message.action=="VOTE")~=(message.ratings~=nil) then return false,"malformed_payload" end
    if message.type == "CMD" and (not message.session_id or not message.command_id or
       not message.expected_version or not message.action) then return false, "malformed_payload" end
    if (message.type == "ACK" or message.type == "REJECT") and
       (not message.session_id or not message.command_id or not message.version or not message.reason) then
        return false, "malformed_payload"
    end
    if message.type == "ACK" and message.reason ~= "ok" then return false, "invalid_ack" end
    if message.type == "REJECT" and not rejectReasons[message.reason] then return false, "invalid_reject" end
    return true
end

function Network.New(api, callbacks)
    assert(type(api) == "table", "api required")
    local self = setmetatable({}, Network)
    self.api = api
    self.callbacks = callbacks or {}
    self.roster = {}
    self.absent = {}
    self.incompleteRoster = false
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
    self.incompleteRoster = false
    local rows = self.api.getRoster and self.api.getRoster() or {}
    for _, row in ipairs(rows) do
        local localRealm = self.api.localRealm and self.api.localRealm() or nil
        local name = fullName(row.name, (row.realm and row.realm ~= "" and row.realm) or localRealm)
        if name and row.guid and row.guid ~= "" then
            local previous = self.roster[name] or self.absent[name]
            if previous and previous.guid ~= row.guid then previous = nil end
            self.absent[name] = nil
            nextRoster[name] = {
                name=name, guid=row.guid, connected=row.connected ~= false,
                leader=row.leader == true, presence=(previous and previous.presence) or "unknown",
                role=previous and previous.role,
                joinedAfterStart=(previous and previous.joinedAfterStart) or (self.sessionId ~= nil and previous == nil),
            }
            if row.leader then leader = name end
        else
            self.incompleteRoster = true
        end
    end
    if self.sessionId then
        for name, member in pairs(self.roster) do
            if not nextRoster[name] then self.absent[name] = member end
        end
    end
    local oldLeader = self.leader
    local oldAuthority = oldLeader and self.roster[oldLeader]
    local newAuthority = leader and nextRoster[leader]
    self.roster, self.leader = nextRoster, leader
    if self.sessionId and self.phase ~= "ended" and oldAuthority and
       (leader ~= oldLeader or not newAuthority or oldAuthority.guid ~= newAuthority.guid) then
        self.phase = "paused"
        self:_emit("authority_changed", { previous=oldLeader, current=leader, policy="pause_then_end" })
        self:EndSession("authority_changed")
        self.sessionId = nil
        self.pending = {}
    end
    self:_emit("roster_changed", self:GetProjection())
    return nextRoster
end

function Network:BeginDiscovery()
    if not self.sessionId or self.api.playerName() ~= self.leader then return false, "not_authority" end
    self.discoveryStarted = self:_now()
    for _, member in pairs(self.roster) do
        if member.name ~= self.leader and not member.role then member.presence = "unknown" end
    end
    return self:Send({ type="HELLO", capability=Network.CAPABILITY }, "RAID")
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
    if not self:IsAuthority() or self.phase ~= "registration" then return false, "not_authority" end
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

function Network:IsAuthority()
    local member = self.leader and self.roster[self.leader]
    return member and member.connected and self.api.playerName() == self.leader
end

function Network:AdminCommand(action, commandId)
    self:RefreshRoster()
    if not self:IsAuthority() then return false, "not_raid_leader" end
    if not self.sessionId or self.originalLeader ~= self.leader then return false, "no_session" end
    return self:_handleCommand({
        action=action, command_id=commandId, session_id=self.sessionId,
        expected_version=self.version,
    }, self.leader)
end

function Network:StartContest(commandId)
    return self:AdminCommand("START", commandId)
end

local function stateFields(self, msg)
    if self.voting and (self.phase=="voting" or self.phase=="round_results") then
        msg.vote_total=self.voting.total
        if self.phase=="voting" then msg.vote_ends=self.voting.endsAt end
    end
    local prep, r = self.preparation, self.runway
    msg.theme, msg.prep_ends = prep and prep.theme, prep and prep.endsAt
    if r then msg.pos,msg.total,msg.cur,msg.nxt,msg.run_ends=r.index,r.total,r.current,r.upcoming,r.endsAt end
    return msg
end

-- A single leader-authored raid update avoids a per-client reveal burst.
-- Poll/WELCOME provides eventual recovery if this packet is missed.
function Network:BroadcastContest()
    if not self:IsAuthority() or self.originalLeader ~= self.leader then return false, "not_authority" end
    if not self.preparation and not self.runway and not self.voting and self.phase~="ended" then return false, "wrong_phase" end
    return self:Send(stateFields(self,{type="STATE", session_id=self.sessionId, version=self.version, phase=self.phase}), "RAID")
end

function Network:Poll()
    local leader = self.leader and self.roster[self.leader]
    if not leader or not leader.connected or self:IsAuthority() then return end
    return self:Send({type="HELLO", capability=Network.CAPABILITY}, "WHISPER", self.leader)
end

function Network:StartSession(sessionId)
    if not self:IsAuthority() then return false, "not_raid_leader" end
    if self.incompleteRoster then return false, "discovery_pending" end
    if not self.registered then return false, "not_registered" end
    if self.sessionId and self.phase ~= "ended" then return false, "session_active" end
    if type(sessionId) ~= "string" or sessionId == "" or #sessionId > 40 then return false, "invalid_session" end
    self.sessionId, self.version, self.phase = sessionId, 1, "registration"
    self.originalLeader = self.leader
    self.discoveryStarted, self.lastRejected, self.preparation, self.runway, self.contestantGuids = nil, nil, nil, nil, nil
    self.voting,self.votePages,self.voted,self.sentVotePages=nil,{},nil,{}
    self.runwaySeconds=Network.RUNWAY_SECONDS
    self.preparationSeconds=Network.PREPARATION_SECONDS
    self.absent = {}
    for name, member in pairs(self.roster) do
        member.role, member.joinedAfterStart = nil, false
        member.presence = name == self.leader and "administrator" or "unknown"
    end
    self.recentCommands, self.recentOrder, self.pending = {}, {}, {}
    self:_emit("session_started", self:GetProjection())
    return true
end

function Network:CancelRegistration()
    self:RefreshRoster()
    if not self:IsAuthority() or self.originalLeader ~= self.leader then return false, "not_authority" end
    if self.phase ~= "registration" then return false, "wrong_phase" end
    return self:EndSession("cancelled")
end

function Network:EndSession(reason)
    if not self.sessionId then return false, "no_session" end
    self.phase, self.preparation, self.runway, self.contestantGuids = "ended", nil, nil, nil
    self.voting,self.votePages,self.voted=nil,{},nil
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

-- Votes do not bump the shared state revision. If simultaneous ballots fill
-- the transport budget, retry private confirmations on that same revision.
function Network:_confirmVote(sender,id,version)
    local session=self.sessionId
    local ack={type="ACK",session_id=session,command_id=id,reason="ok",version=version}
    if self:Send(ack,"WHISPER",sender) or not self.api.after then return end
    local queue=self.voteAckQueue
    if not queue or queue.session~=session then
        queue={session=session,items={}}
        self.voteAckQueue=queue
    end
    queue.items[sender]={ack=ack,sender=sender}
    if queue.scheduled then return end
    local function flush()
        if self.voteAckQueue~=queue or self.sessionId~=session or not self:IsAuthority() then return end
        for player,item in pairs(queue.items) do
            if self:Send(item.ack,"WHISPER",item.sender) then queue.items[player]=nil end
        end
        queue.attempts=(queue.attempts or 0)+1
        queue.scheduled=next(queue.items)~=nil and queue.attempts<6
        if queue.scheduled then self.api.after(Network.SEND_WINDOW+.25,flush)
        else self.voteAckQueue=nil end
    end
    queue.scheduled=true
    self.api.after(Network.SEND_WINDOW+.25,flush)
end

function Network:_handleCommand(message, sender)
    local id = message.command_id
    local replayKey = self.roster[sender].guid .. "\0" .. tostring(id)
    if type(id) ~= "string" or id == "" or #id > 40 then return self:_reject(sender, nil, "invalid_command_id") end
    if not self.sessionId or message.session_id ~= self.sessionId then return self:_reject(sender, id, "stale_session") end
    if self.recentCommands[replayKey] then
        local prior = self.recentCommands[replayKey]
        if prior.vote then self:_confirmVote(sender,id,prior.version)
        else
            self:Send({ type=prior.ok and "ACK" or "REJECT", session_id=self.sessionId,
                command_id=id, reason=prior.reason or "ok", version=prior.version }, "WHISPER", sender)
        end
        return prior.ok, prior.reason or "duplicate_replayed"
    end
    local expected = integer(message.expected_version, 0)
    if message.action=="VOTE" then
        if not self.callbacks.onCommand then return self:_reject(sender,id,"unsupported_command") end
        local vote=self.voting
        local member=self.roster[sender]
        if sender==self.leader then return self:_reject(sender,id,"admin_cannot_vote") end
        if not vote or self.phase~="voting" or not self.api.serverNow or self.api.serverNow()>=vote.endsAt then
            return self:_reject(sender,id,"voting_closed")
        end
        if vote.eligible[sender]~=member.guid then return self:_reject(sender,id,"not_eligible") end
        if vote.accepted[member.guid] then return self:_reject(sender,id,"ballot_already_submitted") end
        if expected~=self.version then return self:_reject(sender,id,"snapshot_mismatch") end
        local wire=message.ratings
        if type(wire)~="string" or #wire~=vote.total or wire:find("[^0-5]") then return self:_reject(sender,id,"invalid_ballot") end
        local ratings={}
        for i,name in ipairs(vote.order) do
            local value=tonumber(wire:sub(i,i))
            if value>0 then
                if name==sender then return self:_reject(sender,id,"self_vote") end
                ratings[name]=value
            end
        end
        if not next(ratings) then return self:_reject(sender,id,"empty_ballot") end
        local ok,reason=self.callbacks.onCommand("VOTE",sender,{ratings=ratings})
        if not ok then return self:_reject(sender,id,reason) end
        vote.accepted[member.guid]=true
        self:_remember(replayKey,{ok=true,version=self.version,vote=true})
        self:_confirmVote(sender,id,self.version)
        self:_emit("ballot_accepted",{})
        return true
    end
    if expected ~= self.version then return self:_reject(sender, id, "snapshot_mismatch") end
    local action = message.action
    if not action or (not adminActions[action] and action ~= "ROLE") then return self:_reject(sender, id, "unknown_command") end
    if adminActions[action] and sender ~= self.leader then return self:_reject(sender, id, "not_raid_leader") end
    if action == "START" then
        if self.phase ~= "registration" then return self:_reject(sender, id, "wrong_phase") end
        local readiness = self:GetProjection().lobbyState
        if readiness ~= "ready_to_start" then return self:_reject(sender, id, readiness) end
    end
    if action == "BEGIN_RUNWAY" or action == "ADVANCE" then
        if action == "BEGIN_RUNWAY" then
            if self.phase ~= "preparation" or not self.preparation then return self:_reject(sender,id,"wrong_phase") end
            if self.api.serverNow() < self.preparation.endsAt then return self:_reject(sender,id,"preparation_running") end
        end
        if self:RunwayBlocked() then return self:_reject(sender,id,"disconnected") end
    end
    if (action == "PAUSE" and (self.phase == "paused" or self.phase == "ended")) or
       (action == "RESUME" and self.phase ~= "paused") or (action == "ADVANCE" and self.phase ~= "runway") then
        return self:_reject(sender, id, "wrong_phase")
    end
    if action == "ROLE" then
        if self.phase ~= "registration" then return self:_reject(sender, id, "wrong_phase") end
        if sender == self.leader then return self:_reject(sender, id, "admin_cannot_participate") end
        if self.roster[sender].joinedAfterStart then return self:_reject(sender, id, "late_joiner") end
        if message.role ~= "contestant" and message.role ~= "spectator" then return self:_reject(sender, id, "invalid_role") end
    end
    if action=="BEGIN_VOTING" and (self.phase~="runway_complete" or not self.api.serverNow) then return self:_reject(sender,id,"wrong_phase") end
    if action=="CLOSE_VOTING" and (self.phase~="voting" or not self.voting or self.api.serverNow()<self.voting.endsAt) then
        return self:_reject(sender,id,"wrong_phase")
    end
    if action=="END" and self.phase~="round_results" then return self:_reject(sender,id,"wrong_phase") end
    local preparation, frozen
    if action == "START" then
        local theme = self.callbacks.chooseTheme and self.callbacks.chooseTheme()
        local startedAt = self.api.serverNow and integer(self.api.serverNow(), 1)
        if not validTheme(theme) or not startedAt then return self:_reject(sender, id, "preparation_unavailable") end
        preparation = {theme=theme, endsAt=startedAt + (self.preparationSeconds or Network.PREPARATION_SECONDS)}
        frozen = {}
        for name, member in pairs(self.roster) do
            if member.role == "contestant" then
                if not validGuid(member.guid) then return self:_reject(sender,id,"invalid_runway_order") end
                frozen[name] = member.guid
            end
        end
    end
    local ok, reason, turn
    if not self.callbacks.onCommand then return self:_reject(sender, id, "unsupported_command") end
    ok, reason, turn = self.callbacks.onCommand(action, sender, copy(message))
    if not ok then
        self:_remember(replayKey, {ok=false, reason=reason or "rejected", version=self.version})
        return self:_reject(sender, id, reason or "rejected")
    end
    if action == "ROLE" then
        self.roster[sender].role = message.role
        self.roster[sender].presence = "addon_ready"
    elseif action == "START" then
        self.phase, self.preparation, self.contestantGuids = "preparation", preparation, frozen
    elseif action=="END" then
        self.phase,self.voting,self.votePages,self.voted="ended",nil,{},nil
    elseif action=="BEGIN_VOTING" then
        local eligible={}
        for name,m in pairs(self.roster) do
            if name~=self.leader and m.role and not m.joinedAfterStart then eligible[name]=m.guid end
        end
        for name,m in pairs(self.absent) do
            if name~=self.leader and m.role and not m.joinedAfterStart then eligible[name]=m.guid end
        end
        self.phase,self.runway="voting",nil
        self.voting={endsAt=self.api.serverNow()+Network.VOTING_SECONDS,total=#turn,order=turn,eligible=eligible,accepted={}}
        self.votePages={}
    elseif action=="CLOSE_VOTING" then
        self.phase="round_results"
        self.voting.results=turn
        self.votePages={}
    elseif action == "BEGIN_RUNWAY" or action == "ADVANCE" then
        local function guid(name) return name and self.contestantGuids[name] or nil end
        self.phase, self.preparation = turn.current and "runway" or "runway_complete", nil
        self.runway = {index=turn.index,total=turn.total,current=guid(turn.current),upcoming=guid(turn.upcoming),
            endsAt=turn.current and self.api.serverNow()+self.runwaySeconds or nil}
    end
    self.version = self.version + 1
    self:_remember(replayKey, {ok=true, version=self.version})
    if sender ~= self.api.playerName() then
        self:Send({ type="ACK", session_id=self.sessionId, command_id=id, reason="ok", version=self.version }, "WHISPER", sender)
    end
    self:_emit("command_acknowledged", { action=action, sender=sender, commandId=id, version=self.version })
    return true
end

function Network:GetVotePage(page)
    local vote=self.voting
    if not vote then return nil end
    if not self:IsAuthority() then return (self.votePages or {})[page] end
    local result={}
    local first=(page-1)*Network.VOTE_PAGE_SIZE+1
    for i=first,math.min(first+Network.VOTE_PAGE_SIZE-1,vote.total) do
        local item=vote.results and vote.results[i]
        local name=item and item.name or vote.order[i]
        result[#result+1]={guid=self.contestantGuids[name],index=i,score=item and item.score}
    end
    return #result>0 and result or nil
end

function Network:RequestVotePage(page)
    if not self.voting or not self.sessionId then return false end
    return self:Send({type="PAGE_REQ",session_id=self.sessionId,version=self.version,page=page},"WHISPER",self.leader)
end

-- Pages contain only the contestant roster or public aggregates. Broadcasting each
-- requested page once serves simultaneous readers without one reply per voter.
function Network:BroadcastVotePage(page)
    local rows=self:GetVotePage(page)
    if not rows or not self:IsAuthority() or self.originalLeader~=self.leader then return false end
    local key=self.version..":"..page
    self.sentVotePages=self.sentVotePages or {}
    if self.sentVotePages[key] and self:_now()-self.sentVotePages[key]<2 then return true end
    local parts={}
    for _,r in ipairs(rows) do parts[#parts+1]=r.guid..":"..(r.score and tostring(r.score) or "0") end
    local ok=self:Send({type="PAGE",session_id=self.sessionId,version=self.version,page=page,rows=table.concat(parts,",")},"RAID")
    if ok then self.sentVotePages[key]=self:_now() end
    return ok
end

function Network:Receive(prefix, wire, channel, sender)
    if prefix ~= Network.PREFIX then return false, "wrong_prefix" end
    if channel ~= "RAID" and channel ~= "WHISPER" then return false, "wrong_channel" end
    sender = fullName(sender, self.api.localRealm and self.api.localRealm() or nil)
    local member = sender and self.roster[sender]
    if not member then return self:_reject(sender, nil, "sender_not_in_raid") end
    if not member.connected then return self:_reject(sender, nil, "disconnected") end
    local message, reason = Network.Decode(wire)
    if not message then return self:_reject(sender, nil, reason) end
    local valid, validationReason = validateFields(message)
    if not valid then return self:_reject(sender, message.type == "CMD" and message.command_id or nil, validationReason) end
    local raidPrepUpdate = channel == "RAID" and message.type == "STATE" and (message.phase == "preparation" or message.phase == "runway" or message.phase == "runway_complete" or message.phase=="voting" or message.phase=="round_results" or message.phase=="ended")
    if message.type ~= "HELLO" and channel ~= "WHISPER" and not raidPrepUpdate and message.type~="PAGE" then
        return self:_reject(sender, message.type == "CMD" and message.command_id or nil, "wrong_channel")
    end
    local preparation, runway, voting
    if message.vote_total then
        local endsAt=tonumber(message.vote_ends)
        if endsAt and (not self.api.serverNow or endsAt>self.api.serverNow()+Network.VOTING_SECONDS+5) then
            return self:_reject(sender,nil,"malformed_payload")
        end
        voting={endsAt=endsAt,total=tonumber(message.vote_total)}
    end
    if message.type=="PAGE" or message.type=="PAGE_REQ" then
        if (self.phase~="voting" and self.phase~="round_results") or not self.voting or self.sessionId~=message.session_id or self.version~=tonumber(message.version) then return false,"stale_session" end
        local page=tonumber(message.page)
        if message.type=="PAGE_REQ" then
            if not self:IsAuthority() or self.originalLeader~=self.leader then return false,"not_authority" end
            return self:BroadcastVotePage(page)
        end
        if sender~=self.leader or sender~=self.originalLeader then return false,"unauthorized_sender" end
        if self:IsAuthority() then return true end
        local result,seen={},{}
        local first=(page-1)*Network.VOTE_PAGE_SIZE+1
        for part in (message.rows..","):gmatch("(.-),") do
            local guid,score=part:match("^([%w%-]+):(%d+)$")
            score=tonumber(score)
            if not validGuid(guid) or seen[guid] or not score or (score~=0 and (score<100 or score>500))
                or (self.phase=="voting" and score~=0) then return false,"malformed_payload" end
            seen[guid]=true
            result[#result+1]={guid=guid,index=first+#result,score=score~=0 and score or nil}
        end
        if #result~=math.min(Network.VOTE_PAGE_SIZE,self.voting.total-first+1) then return false,"malformed_payload" end
        self.votePages=self.votePages or {}
        self.votePages[page]=result
        self:_emit("vote_page",{})
        return true
    end
    if message.pos then
        local endsAt=tonumber(message.run_ends)
        if endsAt and (not self.api.serverNow or endsAt>self.api.serverNow()+305) then
            return self:_reject(sender,nil,"malformed_payload")
        end
        runway = {index=tonumber(message.pos),total=tonumber(message.total),current=message.cur,
            upcoming=message.nxt,endsAt=endsAt}
    end
    if message.prep_ends then
        local endsAt = integer(message.prep_ends, 1)
        local serverTime = self.api.serverNow and self.api.serverNow()
        -- Tolerate modest server-clock skew, but not a countdown of arbitrary length.
        if not serverTime or endsAt > serverTime + Network.PREPARATION_MAX + 5 then
            return self:_reject(sender, nil, "malformed_payload")
        end
        preparation = {theme=message.theme, endsAt=endsAt}
    end
    if message.type == "HELLO" then
        if sender == self.api.playerName() then return true end
        member.presence = member.role and "addon_ready" or "addon_pending"
        self:_emit("addon_detected", { name=sender, guid=member.guid })
        if self:IsAuthority() and self.sessionId then
            return self:Send(stateFields(self,{ type="WELCOME", session_id=self.sessionId, version=self.version,
                phase=self.phase, leader_guid=self.roster[self.leader].guid, role=member.role,
                late=member.joinedAfterStart and 1 or nil,
                voted=self.voting and self.voting.accepted[member.guid] and 1 or nil }), "WHISPER", sender)
        elseif sender == self.leader then
            return self:Send({ type="HELLO", capability=Network.CAPABILITY }, "WHISPER", self.leader)
        end
        return true
    elseif message.type == "WELCOME" then
        if sender ~= self.leader then return self:_reject(sender, nil, "unauthorized_sender") end
        if member.guid ~= message.leader_guid then return self:_reject(sender, nil, "identity_mismatch") end
        local version = integer(message.version, 1)
        if not version or not validPhases[message.phase] then return self:_reject(sender, nil, "malformed_payload") end
        if self.sessionId and self.sessionId ~= message.session_id then
            if not self.api.newerSession or
               not self.api.newerSession(message.session_id, self.sessionId) then
                return self:_reject(sender, nil, "stale_session")
            end
            self.sessionId, self.pending = nil, {}
        end
        if self.sessionId and version < self.version then return self:_reject(sender, nil, "stale_version") end
        if self.sessionId~=message.session_id or version~=self.version then self.votePages,self.voted={},nil end
        self.voting=voting
        self.voted=self.voted or message.voted=="1"
        self.sessionId, self.version, self.phase = message.session_id, version, message.phase
        self.preparation, self.runway, self.originalLeader = preparation, runway, sender
        local me = self.roster[self.api.playerName()]
        if me then
            me.role = message.role
            me.joinedAfterStart = message.late == "1"
        end
        self:_emit("session_joined", self:GetProjection())
        return true
    elseif message.type == "CMD" then
        if not self:IsAuthority() then return self:_reject(sender, message.command_id, "not_authority") end
        return self:_handleCommand(message, sender)
    elseif message.type == "ACK" or message.type == "REJECT" then
        if sender ~= self.leader or message.session_id ~= self.sessionId then return self:_reject(sender, nil, "unauthorized_sender") end
        local pending = self.pending[message.command_id]
        if not pending then return self:_reject(sender, nil, "unknown_command_id") end
        local version = integer(message.version, 0)
        local expectedVersion = integer(pending.message.expected_version, 0)
        if pending.message.action=="VOTE" then
            if not version or not expectedVersion or version<expectedVersion or (message.type=="ACK" and version~=expectedVersion) then
                return self:_reject(sender,nil,"invalid_result_version")
            end
            if pending.status~="pending" then return self:_reject(sender,nil,"duplicate_result") end
            local accepted=message.type=="ACK" or message.reason=="ballot_already_submitted"
            if accepted then self.voted=true end
            pending.status,pending.reason=accepted and "acknowledged" or "rejected",message.reason
            self:_emit("request_result",{commandId=message.command_id,status=pending.status,reason=pending.reason})
            return accepted,message.reason
        end
        if message.type == "ACK" then
            if message.reason ~= "ok" then return self:_reject(sender, nil, "invalid_ack") end
            if not version or not expectedVersion or version ~= expectedVersion + 1 then
                return self:_reject(sender, nil, "invalid_result_version")
            end
        elseif message.reason == "ok" then return self:_reject(sender, nil, "invalid_reject") end
        if message.type == "REJECT" and (not version or not expectedVersion or
           (message.reason == "snapshot_mismatch" and version <= expectedVersion) or
           (message.reason ~= "snapshot_mismatch" and version ~= expectedVersion)) then
            return self:_reject(sender, nil, "invalid_result_version")
        end
        if pending.status ~= "pending" then return self:_reject(sender, nil, "duplicate_result") end
        pending.status = message.type == "ACK" and "acknowledged" or "rejected"
        pending.reason, pending.serverVersion = message.reason, version
        if message.type == "ACK" then
            self.version = math.max(self.version, version)
            local me = self.roster[self.api.playerName()]
            if me and pending.message.action == "ROLE" then me.role = pending.message.role end
        end
        self:_emit("request_result", { commandId=message.command_id, status=pending.status, reason=pending.reason })
        return message.type == "ACK", message.reason
    elseif message.type == "STATE" then
        if sender ~= self.leader or sender ~= self.originalLeader or message.session_id ~= self.sessionId then
            return self:_reject(sender, nil, "unauthorized_sender")
        end
        if sender == self.api.playerName() then return true end
        local version = integer(message.version, 0)
        if not version or version <= self.version or not validPhases[message.phase] then return self:_reject(sender, nil, "stale_version") end
        self.voting,self.votePages=voting,{}
        self.version, self.phase, self.preparation, self.runway = version, message.phase, preparation, runway
        self:_emit("state_confirmed", self:GetProjection())
        return true
    elseif message.type == "PING" then
        if message.session_id ~= self.sessionId or integer(message.version, 0) ~= self.version then
            return self:_reject(sender, nil, "snapshot_mismatch")
        end
        self:_emit("heartbeat", {name=sender, guid=member.guid})
        return true
    end
    return self:_reject(sender, nil, "unknown_command")
end

function Network:RunwayBlocked()
    for name, guid in pairs(self.contestantGuids or {}) do
        local m = self.roster[name]
        if not m or m.guid ~= guid or not m.connected then return true end
    end
    return false
end

function Network:GetProjection()
    local counts = { addon_ready=0, addon_pending=0, no_addon=0, disconnected=0, late_joiner=0, unknown=0 }
    local contestants, spectators, missingContestants, missingResponses = 0, 0, 0, 0
    local members = {}
    for name, member in pairs(self.roster) do
        if name ~= self.leader then
            local key = member.presence
            if not member.connected then key = "disconnected"
            elseif member.joinedAfterStart then key = "late_joiner" end
            counts[key] = (counts[key] or 0) + 1
            members[#members + 1] = {name=name, guid=member.guid, presence=key, role=member.role}
            if key == "addon_ready" and member.role == "contestant" then contestants = contestants + 1 end
            if key == "addon_ready" and member.role == "spectator" then spectators = spectators + 1 end
            if key == "disconnected" and not member.joinedAfterStart and member.presence == "addon_pending" then
                missingResponses = missingResponses + 1
            end
            if key == "disconnected" and member.role == "contestant" then
                missingContestants = missingContestants + 1
            end
        end
    end
    for name, member in pairs(self.absent) do
        counts.disconnected = counts.disconnected + 1
        if not member.joinedAfterStart and member.presence == "addon_pending" then
            missingResponses = missingResponses + 1
        end
        if member.role == "contestant" then missingContestants = missingContestants + 1 end
        members[#members + 1] = {name=name, guid=member.guid, presence="disconnected", role=member.role}
    end
    table.sort(members, function(a, b) return a.name < b.name end)
    local localName = self.api.playerName and self.api.playerName() or nil
    local localMember = self.roster[localName]
    local discoveryComplete = self.discoveryStarted ~= nil and self:_now() - self.discoveryStarted >= Network.DISCOVERY_SECONDS
    local lobby
    if not self.leader then lobby = "not_raid_leader"
    elseif localMember and not localMember.connected then lobby = "disconnected"
    elseif localName ~= self.leader and localMember and localMember.presence == "no_addon" then lobby = "passive_observer"
    elseif localMember and localMember.joinedAfterStart then lobby = "late_joiner"
    elseif not self:IsAuthority() then lobby = "not_raid_leader"
    elseif self.incompleteRoster then lobby = "discovery_pending"
    elseif contestants < 5 then lobby = "insufficient_contestants"
    elseif missingContestants > 0 then lobby = "disconnected"
    elseif counts.addon_pending + counts.unknown + missingResponses > 0 then lobby = "pending_addon_users"
    elseif not self.sessionId or self.phase ~= "registration" then lobby = "wrong_phase"
    elseif not discoveryComplete then
        lobby = "discovery_pending"
    else lobby = "ready_to_start" end
    local r
    if self.runway then
        local function name(guid)
            if not guid then return nil end
            for _, member in ipairs(members) do if member.guid == guid then return member.name end end
            return "Contestant unavailable"
        end
        r = {index=self.runway.index,total=self.runway.total,current=name(self.runway.current),upcoming=name(self.runway.upcoming),endsAt=self.runway.endsAt}
    end
    return { sessionId=self.sessionId, version=self.version, phase=self.phase, leader=self.leader,
        isLeader=self:IsAuthority() == true, presence=counts, contestants=contestants, spectators=spectators,
        pendingResponses=counts.addon_pending + missingResponses,
        discoveryComplete=discoveryComplete, members=members, localRole=localMember and localMember.role, lobbyState=lobby,
        preparation=self.preparation and copy(self.preparation), runway=r, runwayBlocked=self:RunwayBlocked(), lastRejected=self.lastRejected }
end
