-- Strut Your Bootsy multiplayer transport and roster adapter (Retail).
-- All WoW APIs are injected. This keeps validation deterministic in headless tests.
local addonName, ns = ...
ns = ns or {}

local Teams = ns.Teams
local Network = {}
Network.__index = Network
ns.Network = Network

Network.PREFIX = "SYBDEV02"
Network.SCHEMA = 9
Network.CAPABILITY = "raid-comms-v9"
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
Network.AUTHORITY_TIMEOUT = 300
Network.DISCOVERY_SECONDS = 10
Network.MAX_RECENT_COMMANDS = 128
Network.SEND_BURST = 8
Network.SEND_WINDOW = 5

local knownTypes = { HELLO=true, WELCOME=true, STATE=true, CMD=true, ACK=true, REJECT=true, PING=true, PAGE_REQ=true, PAGE=true, TREQ=true, TDATA=true }
local adminActions = { START=true, BEGIN_RUNWAY=true, PAUSE=true, RESUME=true, ADVANCE=true, END=true, BEGIN_VOTING=true, CLOSE_VOTING=true, NEXT_ROUND=true, OPEN_AWARDS=true, CONFIRM_AWARDS=true, REVEAL_AWARD=true }
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
    team_name_invalid=true,team_already_joined=true,team_name_taken=true,team_full=true,team_not_found=true,
    not_team_leader=true,team_invalid_nominee=true,team_nomination_pending=true,team_no_nomination=true,
    team_transfer_before_leave=true,team_unassigned=true,team_need_three=true,team_incomplete=true,
    invalid_roll=true,rolls_required=true,reroll_required=true,not_finished=true,
    voting_closed=true, not_eligible=true, admin_cannot_vote=true, self_vote=true,
    ballot_already_submitted=true, invalid_ballot=true, empty_ballot=true,
    registration_closed=true, minimum_five_contestants=true, registration_pending=true,
    invalid_runway_order=true, preparation_unavailable=true, preparation_running=true,
}
local pausablePhases={preparation=true,runway=true,runway_complete=true,voting=true,round_results=true}
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
    WELCOME={session_id=true, version=true, phase=true, leader_guid=true, role=true, late=true, theme=true, prep_ends=true, pos=true, total=true, cur=true, nxt=true, run_ends=true, vote_ends=true, vote_total=true, vv=true, pp=true, why=true, rn=true, rc=true, ac=true, rv=true, cf=true, voted=true, sz=true, tr=true, tc=true},
    STATE={session_id=true, version=true, phase=true, theme=true, prep_ends=true, pos=true, total=true, cur=true, nxt=true, run_ends=true, vote_ends=true, vote_total=true, vv=true, pp=true, why=true, rn=true, rc=true, ac=true, rv=true, cf=true, sz=true, tr=true, tc=true},
    CMD={session_id=true, command_id=true, expected_version=true, action=true, role=true, ratings=true, op=true, slot=true, other=true, txt=true},
    TREQ={sid=true,i=true}, TDATA={sid=true,i=true,tr=true,tc=true,d=true},
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
    return type(x) == "string" and x~="-" and #x <= 32 and x:match("^[%w%-]+$") ~= nil
end

local function validateFields(message)
    local allowed = allowedFields[message.type]
    if not allowed then return false, "unknown_command" end
    for key, value in pairs(message) do
        if key ~= "type" and key ~= "schema" and not allowed[key] then return false, "malformed_payload" end
        if type(value) == "string" and #value > (key=="rows" and (Network.VOTE_PAGE_SIZE*41-1) or key=="d" and 200 or 80) then return false, "malformed_payload" end
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
            local pos, total = integer(message.pos,1), integer(message.total,message.sz and 3 or 5)
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
        local final=message.phase=="final_results"
        local summary=voting or message.phase=="round_results" or final
        local rn,rc=integer(message.rn or 1,0),integer(message.rc or 1,1)
        if not rn or not rc or rc>5 or rn>rc or (final and rn~=rc) then return false,"malformed_payload" end
        local paused=message.phase=="paused"
        if paused then
            if not pausablePhases[message.pp] or (message.why~="host" and message.why~="contestant" and message.why~="authority") then
                return false,"malformed_payload"
            end
        elseif message.pp or message.why then return false,"malformed_payload" end
        local vv=message.vv and integer(message.vv,1)
        if message.vv and (not vv or vv>tonumber(message.version) or not (voting or (paused and message.pp=="voting"))) then
            return false,"malformed_payload"
        end
        if final then
            local ac,rv=integer(message.ac,0),integer(message.rv,0)
            if not ac or ac>4 or not rv or rv>math.min(3,ac) or (message.cf and message.cf~="1")
                or (rv>0 and not message.cf) then return false,"malformed_payload" end
        elseif message.ac or message.rv or message.cf then return false,"malformed_payload" end
        if summary then
            local total=integer(message.vote_total,message.sz and 3 or 5)
            if not total or total>39 or (voting and not integer(message.vote_ends,1))
                or (not voting and message.vote_ends) or (message.voted and message.voted~="1") then
                return false,"malformed_payload"
            end
        elseif message.vote_total or message.vote_ends or (message.voted and not (paused and message.pp=="voting" and message.voted=="1")) then
            return false,"malformed_payload"
        end
    end
    if message.type=="PAGE" or message.type=="PAGE_REQ" then
        local page=integer(message.page,1)
        if not page or page>math.ceil(39/Network.VOTE_PAGE_SIZE) or not message.session_id
            or not integer(message.version,1) or (message.type=="PAGE" and not message.rows) then
            return false,"malformed_payload"
        end
    end
    if message.sz or message.tr and (message.type=="WELCOME" or message.type=="STATE") then
        if not Teams or not Teams.ValidSize(tonumber(message.sz)) or not integer(message.tr,1)
            or not integer(message.tc,0) or tonumber(message.tc)>39 then return false,"malformed_payload" end
    end
    if message.type=="TREQ" or message.type=="TDATA" then
        if not message.sid or not integer(message.i,1) or tonumber(message.i)>39 then return false,"malformed_payload" end
        if message.type=="TDATA" and (not integer(message.tr,1) or not integer(message.tc,0)
            or tonumber(message.tc)>39 or not message.d) then return false,"malformed_payload" end
    end
    if message.type=="CMD" and message.action~="TEAM" and (message.op or message.slot or message.other or message.txt) then
        return false,"malformed_payload"
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
    if self.sessionId and self.phase~="ended" and self.originalLeader==leader and newAuthority then
        if not newAuthority.connected then
            if not self.authorityLostAt then
                local session=self.sessionId
                self.authorityLostAt=self:_now()
                if self.api.after then self.api.after(Network.AUTHORITY_TIMEOUT,function()
                    if self.sessionId==session and self.authorityLostAt then self:RefreshRoster() end
                end) end
            elseif self:_now()-self.authorityLostAt>=Network.AUTHORITY_TIMEOUT then
                self:EndSession("authority_timeout")
                self.authorityLostAt=nil
            end
        else
            local returning=self.authorityLostAt~=nil
            self.authorityLostAt=nil
            if self:IsAuthority() and pausablePhases[self.phase] and
                (returning or (self.phase~="round_results" and self:RunwayBlocked())) then
                local ok=self:_handleCommand({action="PAUSE",command_id="auto-pause-"..self.version,
                    session_id=self.sessionId,expected_version=self.version,
                    pauseCause=returning and "authority" or "contestant"},self.leader)
                if ok then
                    local session,version=self.sessionId,self.version
                    if not self:BroadcastContest() and self.api.after then
                        self.api.after(Network.SEND_WINDOW+.25,function()
                            if self.sessionId==session and self.version==version then self:BroadcastContest() end
                        end)
                    end
                end
            end
        end
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

function Network:SetRounds(rounds)
    if not self:IsAuthority() or self.originalLeader~=self.leader then return false,"not_raid_leader" end
    if not self.sessionId or self.phase~="registration" then return false,"wrong_phase" end
    if type(rounds)~="number" or not integer(rounds,1) or rounds>5 then return false,"invalid_setting" end
    self.rounds=rounds
    return true
end

function Network:StartContest(commandId)
    return self:AdminCommand("START", commandId)
end

local function stateFields(self, msg)
    msg.rn,msg.rc=self.round or 0,self.rounds or 1
    if self.phase=="paused" then
        msg.pp,msg.why=self.pausedPhase,self.pauseCause
        if self.pausedPhase=="voting" and self.voting then msg.vv=self.voting.version end
    end
    if self.awards and self.phase=="final_results" then
        msg.ac,msg.rv,msg.cf=math.min(4,#self.awards.results),self.awards.revealed,self.awards.confirmed and 1 or nil
    end
    if self.teams then msg.sz,msg.tr,msg.tc=self.teams.size,self.teams.revision,self.teams.span end
    if self.voting and (self.phase=="voting" or self.phase=="round_results" or self.phase=="final_results") then
        msg.vote_total=self.voting.total
        if self.phase=="voting" then msg.vote_ends,msg.vv=self.voting.endsAt,self.voting.version end
    end
    local prep, r
    if self.phase~="paused" then prep,r=self.preparation,self.runway end
    msg.theme, msg.prep_ends = prep and prep.theme, prep and prep.endsAt
    if r then msg.pos,msg.total,msg.cur,msg.nxt,msg.run_ends=r.index,r.total,r.current,r.upcoming,r.endsAt end
    return msg
end

-- A single leader-authored raid update avoids a per-client reveal burst.
-- Poll/WELCOME provides eventual recovery if this packet is missed.
function Network:BroadcastContest()
    if not self:IsAuthority() or self.originalLeader ~= self.leader then return false, "not_authority" end
    if not self.preparation and not self.runway and not self.voting and self.phase~="paused" and self.phase~="ended" then return false, "wrong_phase" end
    return self:Send(stateFields(self,{type="STATE", session_id=self.sessionId, version=self.version, phase=self.phase}), "RAID")
end

function Network:Poll()
    local leader = self.leader and self.roster[self.leader]
    if not leader or not leader.connected or self:IsAuthority() then return end
    return self:Send({type="HELLO", capability=Network.CAPABILITY}, "WHISPER", self.leader)
end

function Network:StartSession(sessionId, teamSize, rounds)
    if not self:IsAuthority() then return false, "not_raid_leader" end
    if self.incompleteRoster then return false, "discovery_pending" end
    if not self.registered then return false, "not_registered" end
    if self.sessionId and self.phase ~= "ended" then return false, "session_active" end
    if type(sessionId) ~= "string" or sessionId == "" or #sessionId > 40 then return false, "invalid_session" end
    if teamSize~=nil and (not Teams or not Teams.ValidSize(teamSize)) then return false,"invalid_role" end
    if rounds~=nil and (type(rounds)~="number" or not integer(rounds,1) or rounds>5) then return false,"invalid_setting" end
    self.teams=Teams and Teams.New(teamSize)
    self.teamSent={}
    self.sessionId, self.version, self.phase = sessionId, 1, "registration"
    self.originalLeader = self.leader
    self.discoveryStarted, self.lastRejected, self.preparation, self.runway, self.contestantGuids = nil, nil, nil, nil, nil
    self.voting,self.votePages,self.voted,self.sentVotePages,self.galleryOrder=nil,{},nil,{},nil
    self.round,self.rounds,self.awards=0,rounds or 1,nil
    self.pausedPhase,self.pauseCause,self.pauseRemaining,self.authorityLostAt=nil,nil,nil,nil
    self.awardCount,self.awardRevealed,self.awardsConfirmed=nil,nil,nil
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
    self.awards,self.awardCount,self.awardRevealed,self.awardsConfirmed=nil,nil,nil,nil
    self.pausedPhase,self.pauseCause,self.pauseRemaining,self.authorityLostAt=nil,nil,nil,nil
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
    message.session_id, message.expected_version = self.sessionId,
        action=="VOTE" and self.voting and self.voting.version or self.version
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
    if message.action=="TEAM" then
        local m=self.roster[sender]
        if not self.teams or self.phase~="registration" then return self:_reject(sender,id,"wrong_phase") end
        if sender==self.leader or m.role~="contestant" or m.joinedAfterStart then return self:_reject(sender,id,"not_eligible") end
        if not expected or expected>self.version then return self:_reject(sender,id,"snapshot_mismatch") end
        local ok,why,changed=Teams.Apply(self.teams,m.guid,message.op,integer(message.slot,1),message.other,message.txt)
        if not ok then return self:_reject(sender,id,why) end
        if message.op=="spectate" then m.role="spectator" end
        self:_remember(replayKey,{ok=true,version=self.version,vote=true})
        self:_confirmVote(sender,id,self.version)
        self:BroadcastTeam(changed or 1,true)
        if message.op=="spectate" then
            local welcome=stateFields(self,{type="WELCOME",session_id=self.sessionId,version=self.version,
                phase=self.phase,leader_guid=self.roster[self.leader].guid,role=m.role})
            if not self:Send(welcome,"WHISPER",sender) and self.api.after then
                local session=self.sessionId
                self.api.after(Network.SEND_WINDOW+.25,function()
                    if self.sessionId==session and self:IsAuthority() and self.phase=="registration" then
                        self:Send(welcome,"WHISPER",sender)
                    end
                end)
            end
        end
        self:_emit("team_changed",{})
        return true
    end
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
        if expected~=(vote.version or self.version) then return self:_reject(sender,id,"snapshot_mismatch") end
        local wire=message.ratings
        if type(wire)~="string" or #wire~=vote.total or wire:find("[^0-5]") then return self:_reject(sender,id,"invalid_ballot") end
        local ratings={}
        for i,name in ipairs(vote.order) do
            local value=tonumber(wire:sub(i,i))
            if value>0 then
                if name==sender or (self.teams and Teams.EntryID(name)==self.teams.byMember[member.guid]) then
                    return self:_reject(sender,id,"self_vote")
                end
                ratings[name]=value
            end
        end
        if not next(ratings) then return self:_reject(sender,id,"empty_ballot") end
        local ok,reason=self.callbacks.onCommand("VOTE",sender,{ratings=ratings})
        if not ok then return self:_reject(sender,id,reason) end
        vote.accepted[member.guid]=true
        local voteVersion=vote.version or self.version
        self:_remember(replayKey,{ok=true,version=voteVersion,vote=true})
        self:_confirmVote(sender,id,voteVersion)
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
    if (action == "PAUSE" and not pausablePhases[self.phase]) or
       (action == "RESUME" and self.phase ~= "paused") or (action == "ADVANCE" and self.phase ~= "runway") then
        return self:_reject(sender, id, "wrong_phase")
    end
    if action=="RESUME" and self:RunwayBlocked() then return self:_reject(sender,id,"disconnected") end
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
    if action=="NEXT_ROUND" then
        if self.phase~="round_results" or (self.round or 1)>=(self.rounds or 1) then return self:_reject(sender,id,"wrong_phase") end
        if self:RunwayBlocked() then return self:_reject(sender,id,"disconnected") end
    end
    if action=="OPEN_AWARDS" and (self.phase~="round_results" or self.round~=self.rounds) then return self:_reject(sender,id,"not_finished") end
    if (action=="CONFIRM_AWARDS" or action=="REVEAL_AWARD") and self.phase~="final_results" then return self:_reject(sender,id,"wrong_phase") end
    if action=="END" and (self.phase~="final_results" or not self.awards or not self.awards.confirmed
        or self.awards.revealed<math.min(3,#self.awards.results)) then return self:_reject(sender,id,"wrong_phase") end
    local preparation, frozen
    if action=="START" or action=="NEXT_ROUND" then
        local theme = self.callbacks.chooseTheme and self.callbacks.chooseTheme(action=="START" and 1 or self.round+1)
        local startedAt = self.api.serverNow and integer(self.api.serverNow(), 1)
        if not validTheme(theme) or not startedAt then return self:_reject(sender, id, "preparation_unavailable") end
        preparation = {theme=theme, endsAt=startedAt + (self.preparationSeconds or Network.PREPARATION_SECONDS)}
        if action=="START" then
            frozen = {}
            for name, member in pairs(self.roster) do
                if member.role == "contestant" then
                    if not validGuid(member.guid) then return self:_reject(sender,id,"invalid_runway_order") end
                    frozen[name] = member.guid
                end
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
        self.round=1
        self.galleryOrder=turn
    elseif action=="NEXT_ROUND" then
        self.round=self.round+1
        self.phase,self.preparation,self.runway,self.galleryOrder="preparation",preparation,nil,turn
        self.voting,self.votePages,self.voted,self.sentVotePages=nil,{},false,{}
    elseif action=="OPEN_AWARDS" or action=="CONFIRM_AWARDS" or action=="REVEAL_AWARD" then
        self.phase,self.awards,self.votePages,self.sentVotePages="final_results",turn,{},{}
    elseif action=="END" then
        self.phase,self.voting,self.votePages,self.voted="ended",nil,{},nil
        self.awards,self.awardCount,self.awardRevealed,self.awardsConfirmed=nil,nil,nil,nil
    elseif action=="PAUSE" then
        self.pausedPhase,self.pauseCause=self.phase,message.pauseCause or "host"
        local timer=(self.phase=="preparation" and self.preparation) or (self.phase=="runway" and self.runway)
            or (self.phase=="voting" and self.voting)
        self.pauseRemaining=timer and timer.endsAt and math.max(0,timer.endsAt-self.api.serverNow()) or nil
        self.phase,self.votePages="paused",{}
    elseif action=="RESUME" then
        self.phase=self.pausedPhase
        local timer=(self.phase=="preparation" and self.preparation) or (self.phase=="runway" and self.runway)
            or (self.phase=="voting" and self.voting)
        if timer and self.pauseRemaining then timer.endsAt=self.api.serverNow()+self.pauseRemaining end
        self.pausedPhase,self.pauseCause,self.pauseRemaining=nil,nil,nil
    elseif action=="BEGIN_VOTING" then
        local eligible={}
        for name,m in pairs(self.roster) do
            if name~=self.leader and m.role and not m.joinedAfterStart then eligible[name]=m.guid end
        end
        for name,m in pairs(self.absent) do
            if name~=self.leader and m.role and not m.joinedAfterStart then eligible[name]=m.guid end
        end
        self.phase,self.runway="voting",nil
        self.voting={endsAt=self.api.serverNow()+Network.VOTING_SECONDS,total=#turn,order=turn,
            eligible=eligible,accepted={},version=self.version+1}
        self.votePages,self.voted,self.sentVotePages={},false,{}
    elseif action=="CLOSE_VOTING" then
        self.phase="round_results"
        self.voting.results=turn
        self.votePages={}
    elseif action == "BEGIN_RUNWAY" or action == "ADVANCE" then
        local function guid(name) return name and (self.teams and name or self.contestantGuids[name]) or nil end
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

local pagePhases={runway=true,runway_complete=true,voting=true,round_results=true,final_results=true}

function Network:GetVotePage(page)
    if not pagePhases[self.phase] or self.authorityLostAt then return nil end
    local vote=self.voting or (self.runway and self.galleryOrder and {
        total=self.runway.index-(self.phase=="runway" and 1 or 0),order=self.galleryOrder})
    if not self:IsAuthority() then return (self.votePages or {})[page] end
    if not vote then return nil end
    if self.phase=="final_results" then
        if page~=1 or not self.awards then return nil end
        local a=self.awards
        local podium=math.min(3,#a.results)
        local out={}
        for i=1,math.min(4,#a.results) do
            local revealed=a.confirmed and ((i<=podium and i>podium-a.revealed) or (i==4 and a.revealed==podium))
            local name=revealed and a.results[i].name
            out[i]={guid=name and (self.teams and name or self.contestantGuids[name]) or "-",index=i}
        end
        return #out>0 and out or nil
    end
    local result={}
    local first=(page-1)*Network.VOTE_PAGE_SIZE+1
    for i=first,math.min(first+Network.VOTE_PAGE_SIZE-1,vote.total) do
        local item=vote.results and vote.results[i]
        local name=item and item.name or vote.order[i]
        result[#result+1]={guid=self.teams and name or self.contestantGuids[name],index=i,score=item and item.score,cumulative=item and item.cumulative}
    end
    return #result>0 and result or nil
end

function Network:RequestVotePage(page)
    if not pagePhases[self.phase] or self.authorityLostAt or not self.sessionId then return false end
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
    for _,r in ipairs(rows) do parts[#parts+1]=r.guid..":"..(r.score and tostring(r.score) or "0")..":"..(r.cumulative and tostring(r.cumulative) or "0") end
    local ok=self:Send({type="PAGE",session_id=self.sessionId,version=self.version,page=page,rows=table.concat(parts,",")},"RAID")
    if ok then self.sentVotePages[key]=self:_now() end
    return ok
end

function Network:BroadcastTeam(index,force)
    if not self.teams or not self:IsAuthority() or self.originalLeader~=self.leader then return false end
    local t=self.teams
    local now=self:_now()
    local key=t.revision..":"..index
    self.teamSent=self.teamSent or {}
    if not force and self.teamSent[key] and now-self.teamSent[key]<2 then return true end
    local row=t.rows[index]
    local data="-"
    if row then
        local tokens={row.name,"0","0",tostring(row.nomination or 0)}
        for i,member in ipairs(row.members) do
            if member==row.lead then tokens[2]=tostring(i) end
            if member==row.nominee then tokens[3]=tostring(i) end
            tokens[#tokens+1]=member
        end
        data=table.concat(tokens,";")
    end
    local ok=self:Send({type="TDATA",sid=self.sessionId,i=index,tr=t.revision,tc=t.span,d=data},"RAID")
    if ok then self.teamSent[key]=now end
    if force and not ok and self.api.after then
        local session,revision=self.sessionId,t.revision
        self.api.after(Network.SEND_WINDOW+.25,function()
            if self.sessionId==session and self.teams and self.teams.revision==revision then self:BroadcastTeam(index) end
        end)
    end
    return ok
end

function Network:RequestTeam(index)
    if not self.teams or not self.sessionId then return false end
    return self:Send({type="TREQ",sid=self.sessionId,i=index},"WHISPER",self.leader)
end

local function syncTeams(self,size,revision,count,fresh)
    if not size then self.teams=nil;return end
    if fresh or not self.teams or self.teams.size~=size then
        self.teams=Teams.New(size)
        self.teams.revision,self.teams.span=revision,count
    elseif revision>self.teams.revision then
        self.teams.revision,self.teams.span=revision,count
        self.teams.rows,self.teams.byMember,self.teams.known={},{},{}
    end
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
    local raidPrepUpdate = channel == "RAID" and message.type == "STATE" and (message.phase == "preparation" or message.phase == "runway" or message.phase == "runway_complete" or message.phase=="voting" or message.phase=="round_results" or message.phase=="final_results" or message.phase=="paused" or message.phase=="ended")
    if message.type ~= "HELLO" and channel ~= "WHISPER" and not raidPrepUpdate and message.type~="PAGE" and message.type~="TDATA" then
        return self:_reject(sender, message.type == "CMD" and message.command_id or nil, "wrong_channel")
    end
    if message.type=="TREQ" or message.type=="TDATA" then
        if not self.teams or message.sid~=self.sessionId then return false,"stale_session" end
        local index=tonumber(message.i)
        if message.type=="TREQ" then
            if index>self.teams.span then return false,"malformed_payload" end
            return self:BroadcastTeam(index)
        end
        if sender~=self.leader or sender~=self.originalLeader then return false,"unauthorized_sender" end
        if self:IsAuthority() then return true end
        local t=self.teams
        local revision,count=tonumber(message.tr),tonumber(message.tc)
        if revision<t.revision or (index>count and message.d~="-") then return false,"stale_version" end
        local row
        if message.d~="-" then
            local tokens={}
            for part in (message.d..";"):gmatch("(.-);") do tokens[#tokens+1]=part end
            local name,lead,nominee=Teams.Name(tokens[1]),integer(tokens[2],1),integer(tokens[3],0)
            local token=integer(tokens[4],0)
            local size=#tokens-4
            if not name or size<1 or size>t.size or not lead or lead>size or not nominee or nominee>size or lead==nominee or not token or (nominee>0)~=(token>0) or token>revision then
                return false,"malformed_payload"
            end
            local members,seen={},{}
            for j=5,#tokens do
                local id=tokens[j]
                if not validGuid(id) or seen[id] then return false,"malformed_payload" end
                members[#members+1]=id;seen[id]=true
            end
            row={id=index,name=name,lead=members[lead],nominee=members[nominee],nomination=token>0 and token or nil,members=members}
        end
        if revision>t.revision+1 then t.rows,t.known={},{} end
        t.revision,t.span=revision,count
        t.rows[index]=row
        t.known=t.known or {}; t.known[index]=true
        t.byMember={}
        for id,x in pairs(t.rows) do for _,guid in ipairs(x.members) do t.byMember[guid]=id end end
        self:_emit("team_changed",{})
        return true
    end
    local preparation, runway, voting
    if message.vote_total then
        local endsAt=tonumber(message.vote_ends)
        if endsAt and (not self.api.serverNow or endsAt>self.api.serverNow()+Network.VOTING_SECONDS+5) then
            return self:_reject(sender,nil,"malformed_payload")
        end
        voting={endsAt=endsAt,total=tonumber(message.vote_total),version=tonumber(message.vv) or tonumber(message.version)}
    end
    if message.type=="PAGE" or message.type=="PAGE_REQ" then
        if not pagePhases[self.phase] or self.authorityLostAt then return false,"wrong_phase" end
        local runwayPhase=self.phase=="runway" or self.phase=="runway_complete"
        local total=self.voting and self.voting.total or runwayPhase and self.runway and
            (self.runway.index-(self.phase=="runway" and 1 or 0))
        if self.phase=="final_results" then total=self.awardCount or self.awards and math.min(4,#self.awards.results) end
        if not total or self.sessionId~=message.session_id or self.version~=tonumber(message.version) then return false,"stale_session" end
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
            local guid,score,cumulative=part:match("^([%w%-]+):(%d+):(%d+)$")
            score,cumulative=tonumber(score),tonumber(cumulative)
            local final=self.phase=="final_results"
            if (not validGuid(guid) and not (guid=="-" and final)) or (guid~="-" and seen[guid]) or not score or not cumulative
                or (score~=0 and (score<100 or score>500)) or (cumulative~=0 and (cumulative<100 or cumulative>500))
                or (self.phase~="round_results" and (score~=0 or cumulative~=0)) then return false,"malformed_payload" end
            if final then
                local slot=first+#result
                local podium=math.min(3,self.awardCount or 0)
                local visible=self.awardsConfirmed and ((slot<=podium and slot>podium-(self.awardRevealed or 0)) or
                    (slot==4 and self.awardRevealed==podium))
                if (guid~="-")~=(visible==true) then return false,"malformed_payload" end
            end
            seen[guid]=true
            result[#result+1]={guid=guid,index=first+#result,score=score~=0 and score or nil,cumulative=cumulative~=0 and cumulative or nil}
        end
        if #result~=math.min(Network.VOTE_PAGE_SIZE,total-first+1) then return false,"malformed_payload" end
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
                voted=self.voting and self.voting.accepted[member.guid] and
                    (self.phase=="voting" or self.phase=="round_results" or self.phase=="final_results" or
                        (self.phase=="paused" and self.pausedPhase=="voting")) and 1 or nil }), "WHISPER", sender)
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
        if self.sessionId~=message.session_id or version~=self.version then self.votePages={} end
        self.round,self.rounds=tonumber(message.rn) or 1,tonumber(message.rc) or 1
        self.awardCount,self.awardRevealed,self.awardsConfirmed=tonumber(message.ac),tonumber(message.rv),message.cf=="1"
        self.voted=message.voted=="1"
        self.pausedPhase,self.pauseCause=message.pp,message.why
        self.hostVoteVersion=tonumber(message.vv)
        syncTeams(self,tonumber(message.sz),tonumber(message.tr),tonumber(message.tc),self.sessionId~=message.session_id)
        self.voting=voting
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
        if pending.message.action=="VOTE" or pending.message.action=="TEAM" then
            if not version or not expectedVersion or version<expectedVersion or (message.type=="ACK" and pending.message.action=="VOTE" and version~=expectedVersion) then
                return self:_reject(sender,nil,"invalid_result_version")
            end
            if pending.status~="pending" then return self:_reject(sender,nil,"duplicate_result") end
            local accepted=message.type=="ACK" or message.reason=="ballot_already_submitted"
            if accepted and pending.message.action=="VOTE" and (self.phase=="voting" or self.pausedPhase=="voting")
                and expectedVersion==(self.voting and self.voting.version or self.hostVoteVersion or self.version) then self.voted=true end
            if accepted and pending.message.action=="TEAM" and pending.message.op=="spectate" then
                local me=self.roster[self.api.playerName()]
                if me then me.role="spectator" end
            end
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
        syncTeams(self,tonumber(message.sz),tonumber(message.tr),tonumber(message.tc),false)
        local nextRound=tonumber(message.rn) or 1
        if nextRound~=(self.round or 0) or (message.phase=="voting" and self.phase~="voting" and self.pausedPhase~="voting") then
            self.voted=false
        end
        self.pausedPhase,self.pauseCause=message.pp,message.why
        self.hostVoteVersion=tonumber(message.vv)
        self.round,self.rounds=nextRound,tonumber(message.rc) or 1
        self.awardCount,self.awardRevealed,self.awardsConfirmed=tonumber(message.ac),tonumber(message.rv),message.cf=="1"
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
    elseif not self.teams and contestants < 5 then lobby = "insufficient_contestants"
    elseif missingContestants > 0 then lobby = "disconnected"
    elseif counts.addon_pending + counts.unknown + missingResponses > 0 then lobby = "pending_addon_users"
    elseif not self.sessionId or self.phase ~= "registration" then lobby = "wrong_phase"
    elseif not discoveryComplete then
        lobby = "discovery_pending"
    else lobby = "ready_to_start" end
    local complete,unassigned
    if self.teams and self:IsAuthority() and self.phase=="registration" then
        local ok,reason
        ok,reason,complete,unassigned=Teams.Readiness(self.teams,self.roster)
        if lobby=="ready_to_start" and not ok then lobby=reason end
    end
    local r
    if self.runway then
        local function name(guid)
            if not guid then return nil end
            if self.teams then
                local id=Teams.EntryID(guid)
                local team=id and self.teams.rows[id]
                return team and team.name or (id and ("Team "..id) or "Team unavailable")
            end
            for _, member in ipairs(members) do if member.guid == guid then return member.name end end
            return "Contestant unavailable"
        end
        r = {index=self.runway.index,total=self.runway.total,current=name(self.runway.current),currentGuid=self.runway.current,upcoming=name(self.runway.upcoming),endsAt=self.runway.endsAt}
    end
    local phase=self.authorityLostAt and self.phase~="registration" and "paused" or self.phase
    return { sessionId=self.sessionId, version=self.version, phase=phase, leader=self.leader,
        pauseCause=self.authorityLostAt and "authority" or self.pauseCause,
        pausePhase=self.authorityLostAt and self.phase or self.pausedPhase,
        authorityRemaining=self.authorityLostAt and math.max(0,Network.AUTHORITY_TIMEOUT-(self:_now()-self.authorityLostAt)),
        canResume=self:IsAuthority() and self.phase=="paused" and not self:RunwayBlocked(),
        round=self.round or 0,rounds=self.rounds or 1,
        awardCount=self.awards and math.min(4,#self.awards.results) or self.awardCount,
        awardRevealed=self.awards and self.awards.revealed or self.awardRevealed,
        awardsConfirmed=self.awards and self.awards.confirmed or self.awardsConfirmed,
        isLeader=self:IsAuthority() == true, presence=counts, contestants=contestants, spectators=spectators,
        pendingResponses=counts.addon_pending + missingResponses,
        discoveryComplete=discoveryComplete, members=members, localRole=localMember and localMember.role, lobbyState=lobby,
        preparation=self.preparation and copy(self.preparation), runway=r, runwayBlocked=self:RunwayBlocked(), lastRejected=self.lastRejected,
        teams=self.teams,localGuid=localMember and localMember.guid, completeTeams=complete, unassigned=unassigned }
end
