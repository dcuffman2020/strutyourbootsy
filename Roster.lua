-- DEV-02 WoW roster resolver. The sender field is a transport identity,
-- not a GUID; resolve it against the live raid roster before authorization.
local _, ns = ...
ns=ns or {}
local R={}
ns.Roster=R
local function canonical(name)
 if type(name)~="string" then return nil end
 return name:lower():gsub("%s+","")
end
function R.Build(previous)
 local roster,byName={},{}
 if not IsInRaid() then return roster,byName end
 local n=GetNumGroupMembers()
 for i=1,n do
  local unit="raid"..i
  if UnitExists(unit) then
   local guid=UnitGUID(unit)
   local name,realm=UnitFullName(unit)
   if guid and name and name~="" then
    local full=name.."-"..((realm and realm~="") and realm or GetRealmName())
    local prior=previous and previous[guid]
    roster[guid]={name=full,leader=UnitIsGroupLeader(unit) and true or false,
      addon=prior and prior.addon==true or false}
    byName[canonical(full)]=guid
    -- Some game events omit a same-realm suffix. Only resolve such names
    -- when unambiguous; ambiguous short names are deliberately rejected.
    local short=canonical(name)
    if byName[short] and byName[short]~=guid then byName[short]=false
    elseif byName[short]~=false then byName[short]=guid end
   end
  end
 end
 return roster,byName
end
function R.Resolve(byName,sender)
 local guid=byName and byName[canonical(sender)]
 if type(guid)=="string" then return guid end
 return nil
end
return R
