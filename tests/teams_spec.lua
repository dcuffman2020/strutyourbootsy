local ns={}
assert(loadfile("Teams.lua"))("StrutYourBootsy",ns)
local Teams=ns.Teams
for size=2,5 do
    local t=assert(Teams.New(size))
    local roster={}
    local function add(guid) roster[guid]={guid=guid,role="contestant"} end
    for i=1,3 do
        local lead="lead"..i
        add(lead)
        assert(Teams.Apply(t,lead,"create",nil,nil,"Team "..i))
        for j=2,size do
            local friend="player"..i.."-"..j
            add(friend)
            assert(Teams.Apply(t,friend,"join",i))
        end
        if i<3 then
            local ok,why=Teams.Readiness(t,roster)
            assert(not ok and why=="team_need_three")
        end
    end
    assert(Teams.Readiness(t,roster))
    add("unassigned")
    local ok,why=Teams.Readiness(t,roster)
    assert(not ok and why=="team_unassigned")
    ok,why=Teams.Apply(t,"unassigned","join",1);assert(not ok and why=="team_full")
    ok,why=Teams.Apply(t,"player1-2","rename",nil,nil,"New name");assert(not ok and why=="not_team_leader")
    ok,why=Teams.Apply(t,"lead1","rename",nil,nil," team 2 ");assert(not ok and why=="team_name_taken")
    ok,why=Teams.Apply(t,"lead1","nominate",nil,"lead2");assert(not ok and why=="team_invalid_nominee")
    ok,why=Teams.Apply(t,"lead1","leave");assert(not ok and why=="team_transfer_before_leave")
    assert(Teams.Apply(t,"lead1","nominate",nil,"player1-2"))
    local first=t.rows[1].nomination
    ok,why=Teams.Apply(t,"unassigned","accept",first);assert(not ok and why=="team_no_nomination")
    assert(Teams.Apply(t,"player1-2","decline",first) and t.rows[1].lead=="lead1")
    assert(Teams.Apply(t,"lead1","nominate",nil,"player1-2"))
    ok,why=Teams.Apply(t,"player1-2","accept",first);assert(not ok and why=="team_no_nomination")
    assert(Teams.Apply(t,"player1-2","accept",t.rows[1].nomination))
    assert(t.rows[1].lead=="player1-2" and t.rows[1].name=="Team 1")
    ok,why=Teams.Apply(t,"lead1","rename",nil,nil,"New name");assert(not ok and why=="not_team_leader")
    assert(Teams.Apply(t,"player1-2","rename",nil,nil,"New name"))
    roster.unassigned.role="spectator"
    assert(Teams.Readiness(t,roster) and t.rows[1].name=="New name")
end
assert(not Teams.New(1) and not Teams.New(6) and not Teams.Name("|Tbad|t") and not Teams.Name(string.rep("X",25)))
print("Team rules, sizes, capacity, eligibility, and stale nominations passed")
