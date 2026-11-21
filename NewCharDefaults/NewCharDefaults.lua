-- NewCharDefaults
-- Applies a standard UI setup the first time each character logs in.
-- Template values were taken from the character Moonica-Starfall.
--   /ncd         re-apply now
--   /ncd reset   forget that this character was set up (applies on next login)

local ADDON = "NewCharDefaults"

local EDIT_MODE_LAYOUT = "Mine"
local WINDOW_ALPHA = 203 / 255      -- background opacity for both tabs

-- Options that are stored as per-character CVars.
local CVARS = {
    enableMultiActionBars = 15,     -- action bars 2-5
    damageMeterEnabled = 1,         -- Advanced Options: Damage Meter
    cooldownViewerEnabled = 1,      -- Advanced Options: Cooldown Manager
}

local GENERAL_GROUPS = {
    "SYSTEM", "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING", "GUILD", "OFFICER",
    "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
    "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "ERRORS", "AFK", "DND",
    "IGNORED", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "COMBAT_FACTION_CHANGE",
    "SKILL", "LOOT", "MONEY", "CHANNEL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
    "BN_WHISPER", "BN_WHISPER_INFORM", "BN_CONVERSATION", "BN_INLINE_TOAST_ALERT",
    "CURRENCY", "BN_WHISPER_PLAYER_OFFLINE", "PET_BATTLE_INFO", "INSTANCE_CHAT",
    "INSTANCE_CHAT_LEADER", "GUILD_ITEM_LOOTED", "COMBAT_XP_GAIN",
    "COMBAT_HONOR_GAIN", "PING", "ENCOUNTER_EVENT", "GUILD_DISCORD",
    "COLLECTED_APPEARANCE",
}

local SPAM_NAME = "Spam"
local SPAM_FONT_SIZE = 18
local SPAM_GROUPS = {
    "SAY", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "GUILD", "CHANNEL", "BN_WHISPER",
}
-- Channels that live on the Spam tab instead of General. Only General and
-- LocalDefense exist at first; the rest are joined in cities, so they are
-- picked up whenever they appear (see ProcessChannels).
local SPAM_CHANNELS = {
    general = true, trade = true, localdefense = true,
    services = true, tradelocal = true, ooc = true,
}

local function Print(msg)
    print("|cff33ccff" .. ADDON .. "|r: " .. msg)
end

-- pcall wrapper that reports failures instead of hiding them.
local function Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Print(label .. " failed: " .. tostring(err)) end
    return ok
end

---------------------------------------------------------------------------
-- CVars (action bars, damage meter, cooldown manager)
-- Only CVars are set here. Calling SetActionBarToggles / MultiActionBar_Update
-- from addon code taints Blizzard's action bar and Edit Mode code ("blocked
-- from an action only available to the Blizzard UI"), so they are avoided. A UI
-- reload makes the changes show up (see the reload popup).
---------------------------------------------------------------------------
local function ApplyCVars()
    for name, value in pairs(CVARS) do
        Try("SetCVar " .. name, SetCVar, name, value)
    end
end

---------------------------------------------------------------------------
-- Minimap tracking
---------------------------------------------------------------------------
local TRACKING = {
    "Auctioneer", "Banker", "Innkeeper", "Mailbox",
    "Class Trainer", "Profession Trainers", "Repair", "Flight Master",
}

local function GetTrackingCount()
    if C_Minimap and C_Minimap.GetNumTrackingTypes then return C_Minimap.GetNumTrackingTypes() end
    if GetNumTrackingTypes then return GetNumTrackingTypes() end
    return 0
end

-- Returns name, active for a tracking index, whichever API shape this client has.
local function GetTrackingEntry(i)
    if C_Minimap and C_Minimap.GetTrackingInfo then
        local info, _, active = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" then return info.name, info.active end
        return info, active
    end
    if GetTrackingInfo then
        local name, _, active = GetTrackingInfo(i)
        return name, active
    end
end

local function SetTrackingEntry(i, on)
    if C_Minimap and C_Minimap.SetTracking then
        C_Minimap.SetTracking(i, on)
    else
        SetTracking(i, on)
    end
end

local trackingRetried = false

local function ApplyTracking()
    local wanted = {}
    for _, name in ipairs(TRACKING) do wanted[name:lower()] = name end

    local count = GetTrackingCount()
    if count == 0 then return false end
    for i = 1, count do
        local name, active = GetTrackingEntry(i)
        local key = name and name:lower()
        if key and wanted[key] then
            wanted[key] = nil
            if not active then Try("tracking " .. name, SetTrackingEntry, i, true) end
        end
    end

    local missing = {}
    for _, original in pairs(wanted) do table.insert(missing, original) end
    if #missing > 0 then
        Print("tracking not found: " .. table.concat(missing, ", "))
    end
    return true
end

StaticPopupDialogs["NEWCHARDEFAULTS_RELOAD"] = {
    text = "NewCharDefaults: default UI setup applied.\n\nReload now to show the action bars, damage meter and cooldown manager?",
    button1 = "Reload UI",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Edit Mode layout
---------------------------------------------------------------------------
local function FindLayoutIndex(name)
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local info = C_EditMode.GetLayouts()
    if not (info and info.layouts) then return nil end
    local presets = 2
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        presets = #EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    end
    for i, layout in ipairs(info.layouts) do
        if layout.layoutName == name then
            return i + presets, info.activeLayout, presets
        end
    end
    return nil, info.activeLayout, presets
end

local function ApplyEditMode(onlyIfPreset)
    local index, active, presets = FindLayoutIndex(EDIT_MODE_LAYOUT)
    if not index then
        return false, ("Edit Mode layout '%s' not found"):format(EDIT_MODE_LAYOUT)
    end
    if active == index then return true end
    if onlyIfPreset and active and active > presets then return true end
    if InCombatLockdown() then return false, "in combat" end
    local ok, err = pcall(C_EditMode.SetActiveLayout, index)
    return ok, err
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
local function FindChatFrameByName(name)
    for i = 1, NUM_CHAT_WINDOWS do
        local winName = GetChatWindowInfo(i)
        if winName == name then return _G["ChatFrame" .. i] end
    end
end

local function SetMessageGroups(frame, groups)
    ChatFrame_RemoveAllMessageGroups(frame)
    for _, g in ipairs(groups) do
        pcall(ChatFrame_AddMessageGroup, frame, g)   -- unknown groups are fine
    end
end

local function BaseChannelName(name)
    return (name:match("^(.-)%s+%-%s+") or name):lower()
end

local function AddChannelTo(frame, name)
    if ChatFrame_AddChannel then
        return pcall(ChatFrame_AddChannel, frame, name)
    end
    return pcall(AddChatWindowChannel, frame:GetID(), name)
end

local function RemoveChannelFrom(frame, name)
    if ChatFrame_RemoveChannel then
        return pcall(ChatFrame_RemoveChannel, frame, name)
    end
    return pcall(RemoveChatWindowChannel, frame:GetID(), name)
end

-- Moves each wanted channel to the Spam tab, once per character. Runs after
-- setup and whenever channels change, so channels that only appear in a city
-- (Trade, Services, TradeLocal, OOC) are picked up on first arrival.
local function ProcessChannels()
    local db = NewCharDefaultsDB
    if not (db and db.applied and db.movedChannels) then return end
    if InCombatLockdown() then return end
    local spam = FindChatFrameByName(SPAM_NAME)
    if not spam then return end

    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = list[i + 1]
        local base = name and BaseChannelName(name)
        if base and SPAM_CHANNELS[base] and not db.movedChannels[base] then
            local okAdd, errAdd = AddChannelTo(spam, name)
            local okRemove, errRemove = RemoveChannelFrom(ChatFrame1, name)
            if okAdd then
                db.movedChannels[base] = true
                Print("moved " .. name .. " to " .. SPAM_NAME .. ".")
            else
                Print("could not add " .. name .. " to " .. SPAM_NAME .. ": " .. tostring(errAdd))
            end
            if not okRemove then
                Print("could not remove " .. name .. " from General: " .. tostring(errRemove))
            end
        end
    end
end

local processQueued = false
local function QueueProcessChannels()
    if processQueued then return end
    processQueued = true
    C_Timer.After(0.5, function()
        processQueued = false
        ProcessChannels()
    end)
end

local function ApplyChat()
    -- General tab
    SetMessageGroups(ChatFrame1, GENERAL_GROUPS)
    Try("General opacity", FCF_SetWindowAlpha, ChatFrame1, WINDOW_ALPHA)

    -- Spam tab
    local spam = FindChatFrameByName(SPAM_NAME)
    if not spam then
        local ok, frame = pcall(FCF_OpenNewWindow, SPAM_NAME)
        if ok then spam = frame else Print("FCF_OpenNewWindow failed: " .. tostring(frame)) end
        spam = spam or FindChatFrameByName(SPAM_NAME)
    end
    if not spam then return false, "could not create Spam tab" end

    SetMessageGroups(spam, SPAM_GROUPS)
    Try("Spam font size", FCF_SetChatWindowFontSize, nil, spam, SPAM_FONT_SIZE)
    Try("Spam opacity", FCF_SetWindowAlpha, spam, WINDOW_ALPHA)
    Try("Spam lock", FCF_SetLocked, spam, 1)
    return true
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
-- New characters play an intro cutscene that hides or closes dialogs, so the
-- reload popup waits until it is over.
local function IsCutscenePlaying()
    if InCinematic and InCinematic() then return true end
    if IsInCinematicScene and IsInCinematicScene() then return true end
    if MovieFrame and MovieFrame:IsShown() then return true end
    if CinematicFrame and CinematicFrame:IsShown() then return true end
    return false
end

local reloadPending = false
local reloadTicker

local function ShowReloadPopupWhenReady()
    if not reloadPending then return end
    if IsCutscenePlaying() then
        -- Fallback in case the end-of-cutscene events don't fire.
        if not reloadTicker then
            reloadTicker = C_Timer.NewTicker(2, ShowReloadPopupWhenReady)
        end
        return
    end
    reloadPending = false
    if reloadTicker then reloadTicker:Cancel(); reloadTicker = nil end
    C_Timer.After(1, function()
        StaticPopup_Show("NEWCHARDEFAULTS_RELOAD")
    end)
end

local function ApplyAll()
    if InCombatLockdown() then return false end
    ApplyCVars()
    -- The tracking list can load late on a new character; retry once when it updates.
    trackingRetried = false
    if not ApplyTracking() then trackingRetried = true end
    local okLayout, layoutErr = ApplyEditMode(false)
    local okChat, chatErr = ApplyChat()

    NewCharDefaultsDB.applied = true
    NewCharDefaultsDB.movedChannels = {}
    ProcessChannels()

    local problems = {}
    if not okLayout then table.insert(problems, tostring(layoutErr)) end
    if not okChat then table.insert(problems, tostring(chatErr)) end
    if #problems == 0 then
        Print("default UI setup applied.")
    else
        Print("applied with problems: " .. table.concat(problems, "; "))
    end
    Print("click Reload UI (or type /reload) to finish setup.")
    reloadPending = true
    ShowReloadPopupWhenReady()
    return true
end

local pending = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("CHANNEL_UI_UPDATE")
frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
-- Cutscene-end events; guarded in case this client lacks one.
for _, ev in ipairs({ "CINEMATIC_STOP", "STOP_MOVIE", "MINIMAP_UPDATE_TRACKING" }) do
    pcall(frame.RegisterEvent, frame, ev)
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            NewCharDefaultsDB = NewCharDefaultsDB or {}
            Print(NewCharDefaultsDB.applied and "loaded (this character is already set up; /ncd to re-apply)."
                or "loaded (first-time setup will run shortly).")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not NewCharDefaultsDB then return end
        if NewCharDefaultsDB.applied then
            QueueProcessChannels()
            return
        end
        -- Give Edit Mode and the chat windows a moment to finish loading.
        C_Timer.After(2, function()
            if NewCharDefaultsDB.applied then return end
            local ok, result = xpcall(ApplyAll, function(e) return tostring(e) end)
            if not ok then
                Print("setup hit an error: " .. result)
            elseif not result then
                pending = true
                Print("in combat; setup will run when combat ends.")
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending and not NewCharDefaultsDB.applied then
            pending = false
            ApplyAll()
        else
            QueueProcessChannels()
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 ~= "player" then return end
        -- A new spec starts on a preset layout; move it to ours as well.
        if NewCharDefaultsDB and NewCharDefaultsDB.applied then
            C_Timer.After(2, function() ApplyEditMode(true) end)
        end
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        if trackingRetried then
            trackingRetried = false
            ApplyTracking()
        end
    elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        if reloadPending then C_Timer.After(1, ShowReloadPopupWhenReady) end
    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
        QueueProcessChannels()
    end
end)

SLASH_NEWCHARDEFAULTS1 = "/ncd"
SlashCmdList["NEWCHARDEFAULTS"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        NewCharDefaultsDB.applied = nil
        NewCharDefaultsDB.movedChannels = nil
        Print("reset. The setup will be applied again on next login.")
    elseif InCombatLockdown() then
        Print("can't apply in combat.")
    else
        ApplyAll()
    end
end
