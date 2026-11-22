local _, ns = ...
local function copyVisual(visual)
    return {appearanceID=visual.appearanceID or 0,
        secondaryAppearanceID=visual.secondaryAppearanceID or 0,illusionID=visual.illusionID or 0}
end

local Outfits = {entries={}, models={}, complete=0}
ns.Outfits=Outfits

local function unitFor(guid)
    if not guid then return end
    local function matches(unit)
        local id=UnitGUID(unit)
        return not (issecretvalue and issecretvalue(id)) and id==guid
    end
    if matches("player") then return "player" end
    if IsInRaid() then
        for i=1,GetNumGroupMembers() do
            local unit="raid"..i
            if matches(unit) and UnitIsConnected(unit) and UnitIsVisible(unit) then return unit end
        end
    end
end

-- Use the same scene preset as Retail's Dressing Room when available. The
-- adapter does not open Blizzard's UI or modify anyone's selected target.
local function modernModel()
    if not CAMERA_TRANSITION_TYPE_IMMEDIATE or not CAMERA_MODIFICATION_TYPE_DISCARD then return end
    local scene=CreateFrame("ModelScene",nil,UIParent,"NoCameraControlModelSceneMixinTemplate")
    scene:SetAlpha(0);scene:Hide()
    scene:TransitionToModelSceneID(596,CAMERA_TRANSITION_TYPE_IMMEDIATE,CAMERA_MODIFICATION_TYPE_DISCARD,true)
    local actor=scene:GetPlayerActor() or scene:GetActorByTag("player")
    if not actor or type(actor.GetItemTransmogInfoList)~="function" or type(actor.SetItemTransmogInfo)~="function"
        or type(actor.SetAutoDress)~="function" or type(actor.IsGeoReady)~="function" then return end
    local adapter={}
    for _,method in ipairs({"Hide","Show","SetAlpha","SetParent","ClearAllPoints","SetPoint","SetSize","EnableMouse","SetFrameLevel"}) do
        adapter[method]=function(_,...) return scene[method](scene,...) end
    end
    function adapter:SetUnit(unit) return actor:SetModelByUnit(unit,false,true,false,true) end
    function adapter:IsGeoReady() return actor:IsGeoReady() end
    function adapter:ClearModel() actor:ClearModel() end
    function adapter:GetItemTransmogInfoList() return actor:GetItemTransmogInfoList() end
    function adapter:SetItemTransmogInfo(info,slot,ignoreChild) actor:SetItemTransmogInfo(info,slot,ignoreChild) end
    function adapter:SetAutoDress(value) actor:SetAutoDress(value) end
    function adapter:SetRotation(angle) actor:SetYaw(angle) end
    function adapter:SetKeepModelOnHide() end
    function adapter:SetPortraitZoom() end
    function adapter:FreezeAnimation()
        if actor.SetPaused then actor:SetPaused(true) end
    end
    return adapter
end

function Outfits:Reset(key)
    if self.key==key then return end
    self.key,self.active,self.complete=key,nil,0
    self.entries={}
    self:HideModel()
    for _,model in pairs(self.models) do
        model:Hide()
        pcall(model.ClearModel,model)
    end
end

-- Never update a model from the raid unit once we have frozen its appearance list.
-- A missing/unsupported model is not a substitute for a saved runway look.
function Outfits:TryCapture(entry,index)
    if entry.loading or entry.model or entry.attempts and entry.attempts>=3 then return end
    entry.attempts=(entry.attempts or 0)+1
    local ok,unit=pcall(unitFor,entry.guid)
    if not ok or not unit then return end
    local model=self.models[index]
    if not model then
        local created,result=pcall(modernModel)
        if not created or not result then
            created,result=pcall(CreateFrame,"DressUpModel",nil,UIParent)
        end
        if not created or not result then return end
        model=result
        self.models[index]=model
    end
    if type(model.SetUnit)~="function" or type(model.SetKeepModelOnHide)~="function"
        or type(model.GetItemTransmogInfoList)~="function" or type(model.SetAutoDress)~="function"
        or type(model.SetItemTransmogInfo)~="function" or type(model.IsGeoReady)~="function" then return end
    local key=self.key
    local function stillActive() return self.key==key and self.active==index and self.entries[index]==entry end
    entry.loading=true
    local bound,accepted=pcall(function()
        model:Hide()
        model:SetParent(UIParent)
        model:ClearAllPoints()
        model:SetPoint("CENTER")
        model:SetSize(120,180)
        model:EnableMouse(false)
        model:SetKeepModelOnHide(true)
        model:SetAlpha(0)
        model:ClearModel()
        model:SetAutoDress(true)
        local result=model:SetUnit(unit,false)
        if result==true then model:Show() end
        return result==true
    end)
    if not bound or not accepted then entry.loading=nil;model:Hide();return end
    local function finish(tries)
        -- A reused model belongs to the new session after a reset.
        if self.key~=key then return end
        if not stillActive() then entry.loading=nil;model:Hide();return end
        local checked,ready=pcall(model.IsGeoReady,model)
        if checked and not ready and tries<5 and C_Timer and C_Timer.After then
            C_Timer.After(.2,function() finish(tries+1) end)
            return
        end
        local captured,valid=pcall(function()
            if not ready or unitFor(entry.guid)~=unit then return false end
            local slots=model:GetItemTransmogInfoList()
            if type(slots)~="table" or not next(slots) then return false end
            local saved={}
            for slot,visual in pairs(slots) do
                if type(slot)=="number" and type(visual)=="table" then
                    saved[slot]=copyVisual(visual)
                end
            end
            if not next(saved) then return false end
            model:SetAutoDress(false)
            for slot,appearance in pairs(saved) do model:SetItemTransmogInfo(appearance,slot,true) end
            model:SetPortraitZoom(0)
            model:SetRotation(.10,false)
            model:FreezeAnimation(0,0,0)
            entry.saved=saved
            return true
        end)
        model:Hide()
        entry.loading=nil
        if captured and valid then entry.model=model end
    end
    if C_Timer and C_Timer.After then C_Timer.After(.2,function() finish(1) end) else finish(5) end
end

function Outfits:Observe(p)
    local session=p.sessionId
    self:Reset(session and (session..":"..(p.round or 1)) or nil)
    self.active=nil
    if p.phase=="runway" and p.runway then
        local r=p.runway
        self.complete=math.max(self.complete,r.index-1)
        self.active=r.index
        local e=self.entries[r.index]
        if not e and r.current and r.current~="Contestant unavailable" then
            e={name=r.current,guid=r.currentGuid or (p.runwayGuids and p.runwayGuids[r.current])}
            self.entries[r.index]=e
        end
        if e and not p.practice then self:TryCapture(e,r.index) end
    elseif p.phase=="runway_complete" and p.runway then
        self.complete=p.runway.total
    elseif not p.practice and p.voteTotal then
        self.complete=p.voteTotal
    elseif p.practice and (p.phase=="voting" or p.phase=="round_results") then
        self.complete=#(p.runwayOrder or {})
    end
    for i,name in ipairs(p.runwayOrder or {}) do
        if not self.entries[i] then self.entries[i]={name=name,guid=p.runwayGuids and p.runwayGuids[name]} end
    end
end

function Outfits:RememberRows(rows)
    for _,row in ipairs(rows or {}) do
        if row.name and row.index<=self.complete and not self.entries[row.index] then
            self.entries[row.index]={name=row.name,guid=row.guid}
        end
    end
end

function Outfits:Get(index)
    if index>=1 and index<=self.complete then return self.entries[index] end
end

function Outfits:HideModel()
    if self.shown then self.shown:Hide(); self.shown=nil end
end

function Outfits:ShowModel(entry,parent,width,height)
    local model=entry and entry.model
    if not model then self:HideModel();return false end
    if self.shown~=model or self.modelParent~=parent then self:HideModel() end
    local ok,ready=pcall(function()
        if not model:IsGeoReady() then return false end
        local slots=model:GetItemTransmogInfoList()
        if type(slots)~="table" then return false end
        for slot,saved in pairs(entry.saved) do
            if not slots[slot] then return false end
            local visual=copyVisual(slots[slot])
            if visual.appearanceID~=saved.appearanceID or visual.secondaryAppearanceID~=saved.secondaryAppearanceID
                or visual.illusionID~=saved.illusionID then return false end
        end
        return true
    end)
    if not ok or not ready then self:HideModel();return false end
    local shown=pcall(function()
        model:SetParent(parent)
        model:SetFrameLevel(parent:GetFrameLevel()+1)
        model:ClearAllPoints()
        model:SetPoint("CENTER",parent,"CENTER",0,0)
        model:SetSize(width,height)
        model:SetAlpha(1)
        model:Show()
    end)
    if shown then self.shown,self.modelParent=model,parent else model:Hide() end
    return shown
end
