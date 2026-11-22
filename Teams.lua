local _,ns=...
local Teams={}
ns.Teams=Teams

function Teams.ValidSize(size)
    return type(size)=="number" and size%1==0 and size>=2 and size<=5
end

function Teams.Name(value)
    if type(value)~="string" then return end
    value=value:match("^ *(.-) *$")
    if #value>24 or not value:match("^[%a][%w '-]*$") then return end
    return value
end

function Teams.New(size)
    if Teams.ValidSize(size) then return {size=size,revision=1,span=0,rows={},byMember={}} end
end

function Teams.Apply(t,who,action,slot,other,text)
    local own=t.byMember[who]
    local team=own and t.rows[own]
    local affected=own
    if action=="create" or action=="rename" then
        local name=Teams.Name(text)
        if not name then return false,"team_name_invalid" end
        if action=="create" and own then return false,"team_already_joined" end
        if action=="rename" and (not team or team.lead~=who) then return false,"not_team_leader" end
        for id,row in pairs(t.rows) do
            if id~=own and row.name:lower()==name:lower() then return false,"team_name_taken" end
        end
        if action=="create" then
            for i=1,39 do if not t.rows[i] then affected=i;break end end
            if not affected then return false,"team_full" end
            t.rows[affected]={id=affected,name=name,lead=who,members={who}}
            t.byMember[who]=affected
            t.span=math.max(t.span,affected)
        else team.name=name end
    elseif action=="join" then
        if own then return false,"team_already_joined" end
        local target=t.rows[slot or 0]
        if not target then return false,"team_not_found" end
        if #target.members>=t.size then return false,"team_full" end
        target.members[#target.members+1]=who
        t.byMember[who]=slot
        affected=slot
    elseif action=="leave" or action=="spectate" then
        if not team and action=="leave" then return false,"team_not_found" end
        if team and team.lead==who and #team.members>1 then return false,"team_transfer_before_leave" end
        if team then
            for i,guid in ipairs(team.members) do
                if guid==who then table.remove(team.members,i);break end
            end
            t.byMember[who]=nil
            if team.nominee==who then team.nominee,team.nomination=nil,nil end
            if #team.members==0 then t.rows[own]=nil
            elseif team.lead==who then team.lead=team.members[1] end
        end
    elseif action=="nominate" then
        if not team or team.lead~=who then return false,"not_team_leader" end
        if #team.members<2 or other==who or t.byMember[other or ""]~=own then return false,"team_invalid_nominee" end
        if team.nominee then return false,"team_nomination_pending" end
        team.nominee,team.nomination=other,t.revision+1
    elseif action=="accept" or action=="decline" then
        if not team or team.nominee~=who or team.nomination~=slot then return false,"team_no_nomination" end
        if action=="accept" then team.lead=who end
        team.nominee,team.nomination=nil,nil
    else return false,"unknown_command" end
    t.revision=t.revision+1
    return true,nil,affected
end

function Teams.Readiness(t,roster)
    local count,unassigned,ready=0,0,true
    for _,row in pairs(t.rows) do
        if #row.members==t.size then count=count+1 else ready=false end
    end
    for _,m in pairs(roster) do
        if m.role=="contestant" and not t.byMember[m.guid] then unassigned=unassigned+1 end
    end
    if unassigned>0 then return false,"team_unassigned",count,unassigned end
    if count<3 then return false,"team_need_three",count,unassigned end
    if not ready then return false,"team_incomplete",count,unassigned end
    return true,nil,count,unassigned
end

function Teams.Entry(id) return "Team-"..id end
function Teams.EntryID(value)
    if type(value)=="string" then return tonumber(value:match("^Team%-(%d+)$")) end
end
