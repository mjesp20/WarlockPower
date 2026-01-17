-- Curse rotation list (display names)
WP_CurseList = {
    "Curse of Recklessness",
    "Curse of Shadow",
    "Curse of the Elements",
    "Curse of Weakness",
    "Curse of Tongues",
}

-- Assignment table: [warlockName] = curseIndex
WP_Assignments = {}

-- UI button references
WP_Buttons = {}

-- Macro-visible variable (exact spell name for casting)
WP_Curse = "Curse of Shadow" -- default

-- Saved variable
WarlockPower_SavedCurse = nil

-- Track previous warlock state for change detection. idk if this is needed/there might be a better way to do this
WP_PreviousWarlocks = {}


-- Utility

function WarlockPower_IsWarlock(unit)
    if not UnitExists(unit) then return false end
    local _, class = UnitClass(unit)
    return class == "WARLOCK"
end

-- Gather warlocks in group / raid with subgroup info

function WarlockPower_GetWarlocks()
    local list = {}

    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid"..i
            if WarlockPower_IsWarlock(unit) then
                tinsert(list, (UnitName(unit)))
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
        -- In party, everyone is effectively in the same "group"
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

-- Check if warlock composition changed

function WarlockPower_WarlocksChanged()
    local current = WarlockPower_GetWarlocksWithSubgroup()
    
    -- Check if any warlock was added, removed, or changed subgroup
    for name, subgroup in pairs(current) do
        if not WP_PreviousWarlocks[name] or WP_PreviousWarlocks[name] ~= subgroup then
            WP_PreviousWarlocks = current
            return true
        end
    end
    
    for name, subgroup in pairs(WP_PreviousWarlocks) do
        if not current[name] then
            WP_PreviousWarlocks = current
            return true
        end
    end
    
    return false
end


-- Broadcast your assignment

function WarlockPower_BroadcastMyAssignment()
    local playerName = UnitName("player")
    local myIndex = WP_Assignments[playerName]
    
    -- If we have no assignment yet, use saved curse or default to 1
    if not myIndex then
        myIndex = WarlockPower_SavedCurse or 1
        WP_Assignments[playerName] = myIndex
        WP_Curse = WP_CurseList[myIndex].."()"
    end
    
    WarlockPower_SendAssign(playerName, myIndex)
end


-- UI creation

function WarlockPower_CreateButton(index)
    local btn = CreateFrame(
        "Button",
        "WarlockPowerButton"..index,
        WarlockPowerFrame,
        "UIPanelButtonTemplate"
    )

    btn:SetWidth(200)
    btn:SetHeight(22)

    btn:SetPoint(
        "TOP",
        WarlockPowerFrame,
        "TOP",
        0,
        -40 - (index - 1) * 24
    )

    btn:SetScript("OnClick", function()
        WarlockPower_CycleCurse(this.warlock)
    end)

    WP_Buttons[index] = btn
    return btn
end


-- Update UI

function WarlockPower_UpdateWarlocks()
    local warlocks = WarlockPower_GetWarlocks()

    -- Hide old buttons
    for i = 1, table.getn(WP_Buttons) do
        WP_Buttons[i]:Hide()
    end

    -- Create/update buttons
    for i = 1, table.getn(warlocks) do
        local name = warlocks[i]
        local btn = WP_Buttons[i] or WarlockPower_CreateButton(i)

        btn.warlock = name

        local curseIndex = WP_Assignments[name] or 1
        local curseName = WP_CurseList[curseIndex]

        btn:SetText(name.." - "..curseName)
        btn:Show()
    end
end


-- Curse cycling

function WarlockPower_CycleCurse(warlock)
    local index = WP_Assignments[warlock] or 1
    index = index + 1
    if index > table.getn(WP_CurseList) then
        index = 1
    end

    WP_Assignments[warlock] = index

    -- Update locally if this is YOU
    if warlock == UnitName("player") then
        WP_Curse = WP_CurseList[index].."()"
        WarlockPower_SavedCurse = index  -- Save to persistent variable
        DEFAULT_CHAT_FRAME:AddMessage("WP: Your curse is now "..WP_CurseList[index])
    end

    -- Send assignment to group
    WarlockPower_SendAssign(warlock, index)

    WarlockPower_UpdateWarlocks()
end

function WarlockPower_SendAssign(warlock, index)
    local msg = "ASSIGN "..warlock.." "..tostring(index)
    
    --DEFAULT_CHAT_FRAME:AddMessage("WP: Attempting to send: "..msg)

    if UnitInRaid("player") then
        --DEFAULT_CHAT_FRAME:AddMessage("WP: Sending to RAID")
        SendAddonMessage("WP", msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        --DEFAULT_CHAT_FRAME:AddMessage("WP: Sending to PARTY")
        SendAddonMessage("WP", msg, "PARTY")
    else
        --DEFAULT_CHAT_FRAME:AddMessage("WP: ERROR - Not in group!")
    end
end

function WarlockPower_ParseMessage(prefix, msg, channel, sender)
    if prefix ~= "WP" then 
        --DEFAULT_CHAT_FRAME:AddMessage("  -> Wrong prefix, ignoring")
        return 
    end
    
    -- Filter out own messages (sender comparison)
    local playerName = UnitName("player")
    --DEFAULT_CHAT_FRAME:AddMessage("  My name: "..playerName)
    
    if sender == playerName then 
        --DEFAULT_CHAT_FRAME:AddMessage("  -> Message from self, ignoring")
        return 
    end

    -- Parse ASSIGN messages
    local _, _, name, indexStr = string.find(msg, "^ASSIGN ([^ ]+) ([0-9]+)")
    
    --DEFAULT_CHAT_FRAME:AddMessage("  Parsed name: "..(name or "nil"))
    --DEFAULT_CHAT_FRAME:AddMessage("  Parsed index: "..(indexStr or "nil"))
    
    if not name or not indexStr then 
        DEFAULT_CHAT_FRAME:AddMessage("  -> Failed to parse, ignoring")
        return 
    end

    local index = tonumber(indexStr)
    if not index then 
        DEFAULT_CHAT_FRAME:AddMessage("  -> Invalid index number")
        return 
    end

    WP_Assignments[name] = index
    --DEFAULT_CHAT_FRAME:AddMessage("  -> Assignment saved: "..name.." = "..index)

    -- If THIS MESSAGE IS FOR YOU, update macro variable and save
    if name == playerName then
        WP_Curse = WP_CurseList[index].."()"
        WarlockPower_SavedCurse = index  -- Save to persistent variable
        DEFAULT_CHAT_FRAME:AddMessage("WP: You have been assigned "..WP_CurseList[index])
    else
        --DEFAULT_CHAT_FRAME:AddMessage("  -> Not for me (name mismatch)")
    end

    WarlockPower_UpdateWarlocks()
end

-- Frame lifecycle (called from XML)

function WarlockPower_OnEvent(event)
    
    if event == "CHAT_MSG_ADDON" then
        WarlockPower_ParseMessage(arg1, arg2, arg3, arg4)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Initialize previous warlock list
        WP_PreviousWarlocks = WarlockPower_GetWarlocksWithSubgroup()
        
        -- Broadcast our saved assignment if we're in a group
        if UnitInRaid("player") or GetNumPartyMembers() > 0 then
            WarlockPower_BroadcastMyAssignment()
        end
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        -- Check if warlock composition changed
        if WarlockPower_WarlocksChanged() then
            WarlockPower_BroadcastMyAssignment()
        end
        
        -- Update UI if visible
        if WarlockPowerFrame:IsShown() then
            WarlockPower_UpdateWarlocks()
        end
    end
end

function WarlockPower_OnLoad()
    --DEFAULT_CHAT_FRAME:AddMessage("WP: OnLoad called!")
    
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("RAID_ROSTER_UPDATE")
    this:RegisterEvent("PARTY_MEMBERS_CHANGED")
    this:RegisterEvent("CHAT_MSG_ADDON")
    
    --DEFAULT_CHAT_FRAME:AddMessage("WP: Events registered")
    
    -- Add close button
    local closeBtn = CreateFrame("Button", "WarlockPowerCloseButton", WarlockPowerFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", WarlockPowerFrame, "TOPRIGHT", -5, -5)
    
    -- Add title
    local title = WarlockPowerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", WarlockPowerFrame, "TOP", 0, -15)
    title:SetText("Warlock Power")
    
    -- Make frame draggable
    WarlockPowerFrame:RegisterForDrag("LeftButton")
    WarlockPowerFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    WarlockPowerFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- Load saved curse assignment
    local playerName = UnitName("player")
    if WarlockPower_SavedCurse then
        WP_Assignments[playerName] = WarlockPower_SavedCurse
        WP_Curse = WP_CurseList[WarlockPower_SavedCurse].."()"
        DEFAULT_CHAT_FRAME:AddMessage("WP: Loaded saved curse: "..WP_CurseList[WarlockPower_SavedCurse])
    else
        -- Initialize with default curse
        WarlockPower_SavedCurse = 1
        WP_Assignments[playerName] = 1
        WP_Curse = WP_CurseList[1].."()"
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("WP: Addon loaded successfully!")
end

--------------------------------------------------
-- Slash command
--------------------------------------------------

SLASH_WARLOCKPOWER1 = "/wp"

SlashCmdList["WARLOCKPOWER"] = function()
    if WarlockPowerFrame:IsShown() then
        WarlockPowerFrame:Hide()
    else
        WarlockPower_UpdateWarlocks()
        WarlockPowerFrame:Show()
    end
end