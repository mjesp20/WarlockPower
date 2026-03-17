-- Curse rotation list (display names)
WP_CurseList = {
    "Curse of Recklessness",
    "Curse of Shadow",
    "Curse of the Elements",
    "Curse of Weakness",
    "Curse of Tongues",
}

-- Spell IDs for icon lookup
WP_CurseSpellIDs = {
    ["Curse of Recklessness"] = 11717,
    ["Curse of Shadow"]       = 17937,
    ["Curse of the Elements"] = 11722,
    ["Curse of Weakness"]     = 702,
    ["Curse of Tongues"]      = 11719,
}

function WarlockPower_GetCurseIcon(curseName)
    local id = WP_CurseSpellIDs[curseName]
    if not id then return "Interface\\Icons\\Temp" end
    local _, _, icon = SpellInfo(id)
    return icon
end

-- Assignment table: [warlockName] = curseIndex
WP_Assignments = {}

-- UI button references
WP_Buttons = {}

-- Macro-visible variable (exact spell name for casting)
WP_Curse = "Curse of Shadow"

-- Saved variable (persists across sessions via .toc SavedVariables)
WarlockPower_SavedCurse = nil

-- Track previous warlock state for change detection
WP_PreviousWarlocks = {}


--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function WarlockPower_IsWarlock(unit)
    if not UnitExists(unit) then return false end
    local _, class = UnitClass(unit)
    return class == "WARLOCK"
end

function WarlockPower_GetWarlocks()
    local list = {}
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid"..i
            if WarlockPower_IsWarlock(unit) then
                tinsert(list, (UnitName(unit)))  -- parens truncate to 1 return value
            end
        end
    else
        if WarlockPower_IsWarlock("player") then
            tinsert(list, (UnitName("player")))
        end
        for i = 1, GetNumPartyMembers() do
            local unit = "party"..i
            if WarlockPower_IsWarlock(unit) then
                tinsert(list, (UnitName(unit)))
            end
        end
    end
    return list
end
function WarlockPower_GetWarlocksWithSubgroup()
    local warlocks = {}
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
            if class == "WARLOCK" then
                warlocks[name] = subgroup
            end
        end
    else
        if WarlockPower_IsWarlock("player") then
            warlocks[UnitName("player")] = 1
        end
        for i = 1, GetNumPartyMembers() do
            local unit = "party"..i
            if WarlockPower_IsWarlock(unit) then
                warlocks[UnitName(unit)] = 1
            end
        end
    end
    return warlocks
end

function WarlockPower_WarlocksChanged()
    local current = WarlockPower_GetWarlocksWithSubgroup()
    for name, subgroup in pairs(current) do
        if not WP_PreviousWarlocks[name] or WP_PreviousWarlocks[name] ~= subgroup then
            WP_PreviousWarlocks = current
            return true
        end
    end
    for name, _ in pairs(WP_PreviousWarlocks) do
        if not current[name] then
            WP_PreviousWarlocks = current
            return true
        end
    end
    return false
end


--------------------------------------------------------------------------------
-- Messaging
-- Two message types:
--   HELLO <name> <index>  — "I just joined; here is my curse. Please reply with yours."
--   ASSIGN <name> <index> — "This warlock has this curse." (assignment update)
--------------------------------------------------------------------------------

function WarlockPower_SendMessage(msg)
    if UnitInRaid("player") then
        SendAddonMessage("WP", msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("WP", msg, "PARTY")
    end
end

-- Announce yourself when entering the world. Others will reply with their ASSIGN.
function WarlockPower_SendHello()
    local playerName = UnitName("player")
    local myIndex = WP_Assignments[playerName] or 1
    WarlockPower_SendMessage("HELLO "..playerName.." "..tostring(myIndex))
end

-- Broadcast a specific assignment (used for manual cycle changes)
function WarlockPower_SendAssign(warlock, index)
    WarlockPower_SendMessage("ASSIGN "..warlock.." "..tostring(index))
end

function WarlockPower_ParseMessage(prefix, msg, channel, sender)
    if prefix ~= "WP" then return end

    local playerName = UnitName("player")
    if sender == playerName then return end

    -- Handle HELLO: record their curse, then reply with ours so they learn it too
    local hName, hIndex = string.match(msg, "^HELLO ([^ ]+) ([0-9]+)")
    if hName and hIndex then
        local index = tonumber(hIndex)
        WP_Assignments[hName] = index
        -- Reply with our own assignment so the greeter populates their UI
        local myIndex = WP_Assignments[playerName] or 1
        WarlockPower_SendAssign(playerName, myIndex)
        WarlockPower_UpdateWarlocks()
        return
    end

    -- Handle ASSIGN: plain assignment update from another warlock
    local aName, aIndex = string.match(msg, "^ASSIGN ([^ ]+) ([0-9]+)")
    if aName and aIndex then
        local index = tonumber(aIndex)
        WP_Assignments[aName] = index

        -- If the raid leader assigned YOU a new curse, apply and save it
        if aName == playerName then
            WP_Curse = WP_CurseList[index]
            WarlockPower_SavedCurse = index
            DEFAULT_CHAT_FRAME:AddMessage("WP: You have been assigned "..WP_CurseList[index])
        end

        WarlockPower_UpdateWarlocks()
    end
end


--------------------------------------------------------------------------------
-- Curse cycling (manual click)
--------------------------------------------------------------------------------

function WarlockPower_CycleCurse(warlock)
    local index = WP_Assignments[warlock] or 1
    index = index + 1
    if index > table.getn(WP_CurseList) then index = 1 end

    WP_Assignments[warlock] = index

    if warlock == UnitName("player") then
        WP_Curse = WP_CurseList[index]
        WarlockPower_SavedCurse = index
        DEFAULT_CHAT_FRAME:AddMessage("WP: Your curse is now "..WP_CurseList[index])
    end

    WarlockPower_SendAssign(warlock, index)
    WarlockPower_UpdateWarlocks()
end


--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

function WarlockPower_CreateButton(index)
    local btn = CreateFrame(
        "Button",
        "WarlockPowerButton"..index,
        WarlockPowerFrame,
        "UIPanelButtonTemplate"
    )
    btn:SetWidth(200)
    btn:SetHeight(22)
    btn:SetPoint("TOP", WarlockPowerFrame, "TOP", 0, -40 - (index - 1) * 24)
    btn:SetScript("OnClick", function()
        WarlockPower_CycleCurse(this.warlock)
    end)
    WP_Buttons[index] = btn
    return btn
end

function WarlockPower_UpdateWarlocks()
    local warlocks = WarlockPower_GetWarlocks()

    for i = 1, table.getn(WP_Buttons) do
        WP_Buttons[i]:Hide()
    end

    for i = 1, table.getn(warlocks) do
        local name = warlocks[i]
        local btn = WP_Buttons[i] or WarlockPower_CreateButton(i)
        btn.warlock = name
        local curseIndex = WP_Assignments[name] or 1
        btn:SetText(name.." - "..WP_CurseList[curseIndex])
        btn:Show()
    end
end


--------------------------------------------------------------------------------
-- Frame lifecycle
--------------------------------------------------------------------------------

function WarlockPower_OnEvent(event)
        if event == "VARIABLES_LOADED" then
        local playerName = UnitName("player")
        if WarlockPower_SavedCurse and WP_CurseList[WarlockPower_SavedCurse] then
            WP_Assignments[playerName] = WarlockPower_SavedCurse
            WP_Curse = WP_CurseList[WarlockPower_SavedCurse]
            DEFAULT_CHAT_FRAME:AddMessage("WP: Loaded saved curse: "..WP_CurseList[WarlockPower_SavedCurse])
        else
            WarlockPower_SavedCurse = 1
            WP_Assignments[playerName] = 1
            WP_Curse = WP_CurseList[1]
        end
        return
    end
    if event == "CHAT_MSG_ADDON" then
        WarlockPower_ParseMessage(arg1, arg2, arg3, arg4)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        WP_PreviousWarlocks = WarlockPower_GetWarlocksWithSubgroup()

        -- Send HELLO to the group so others reply with their assignments.
        -- If nobody replies (solo / no WP users), we already loaded from
        -- SavedVariables in OnLoad, so WP_Curse is already correct.
        if UnitInRaid("player") or GetNumPartyMembers() > 0 then
            WarlockPower_SendHello()
        end
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        if WarlockPower_WarlocksChanged() then
            -- New warlocks joined; announce ourselves so they learn our curse
            WarlockPower_SendHello()
        end
        if WarlockPowerFrame:IsShown() then
            WarlockPower_UpdateWarlocks()
        end
    end
end

function WarlockPower_OnLoad()
    this:RegisterEvent("VARIABLES_LOADED")       -- add this
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("RAID_ROSTER_UPDATE")
    this:RegisterEvent("PARTY_MEMBERS_CHANGED")
    this:RegisterEvent("CHAT_MSG_ADDON")

    -- Close button
    local closeBtn = CreateFrame("Button", "WarlockPowerCloseButton", WarlockPowerFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", WarlockPowerFrame, "TOPRIGHT", -5, -5)

    -- Title
    local title = WarlockPowerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", WarlockPowerFrame, "TOP", 0, -15)
    title:SetText("Warlock Power")

    -- Draggable
    WarlockPowerFrame:RegisterForDrag("LeftButton")
    WarlockPowerFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    WarlockPowerFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- Load saved curse (WarlockPower_SavedCurse is populated by WoW from disk
    -- before OnLoad fires, because it's listed in ## SavedVariables in the .toc)
    local playerName = UnitName("player")
    if WarlockPower_SavedCurse and WP_CurseList[WarlockPower_SavedCurse] then
        WP_Assignments[playerName] = WarlockPower_SavedCurse
        WP_Curse = WP_CurseList[WarlockPower_SavedCurse]
        DEFAULT_CHAT_FRAME:AddMessage("WP: Loaded saved curse: "..WP_CurseList[WarlockPower_SavedCurse])
    else
        WarlockPower_SavedCurse = 1
        WP_Assignments[playerName] = 1
        WP_Curse = WP_CurseList[1]
    end

    DEFAULT_CHAT_FRAME:AddMessage("WP: Addon loaded successfully!")
end


--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

SLASH_WARLOCKPOWER1 = "/wp"

SlashCmdList["WARLOCKPOWER"] = function()
    if WarlockPowerFrame:IsShown() then
        WarlockPowerFrame:Hide()
    else
        WarlockPower_UpdateWarlocks()
        WarlockPowerFrame:Show()
    end
end
