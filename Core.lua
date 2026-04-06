local _, addon = ...
_, addon.Class = UnitClass("player")

addon.events = CreateFrame("Frame")
addon.events:RegisterEvent("SPELL_UPDATE_USABLE")
addon.events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addon.events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addon.events:RegisterEvent("PLAYER_REGEN_ENABLED")
addon.events:RegisterEvent("PLAYER_REGEN_DISABLED")
addon.events:RegisterEvent("PLAYER_UNGHOST")
addon.events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
addon.events:RegisterEvent("PLAYER_TALENT_UPDATE")
addon.events:RegisterEvent("PLAYER_ENTERING_WORLD")
addon.events:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
addon.events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
addon.events:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")

local itemSlotCache = {}
local LCG = addon.LCG
local lcgWarnedOnce = false
local activeGlows = {}
local GLOW_KEY = "ProcGlows"
local allGlowingButtons = {}
local spellButtonCache = {}
local itemAnchorCache = {}
local spellAnchorCache = {}
local cdmSpellFrameCache = {}
local actionSlotSnapshot = {}
local spellCacheDirty = true
local itemCacheDirty = true
local stackTexts = {}
local LSM = LibStub("LibSharedMedia-3.0")
local BUTTON_PREFIXES = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
                         "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "MultiBar8Button"}
local MAX_ACTION_SLOT = 180

-- ─── Third-party action bar support (Bartender4, Dominos, ElvUI) ─────────────

-- Returns the action slot for both Blizzard (.action) and LAB-based (._state_action) buttons
local function GetButtonActionSlot(button)
    return button._state_action or button.action
end

local thirdPartyButtons = {}
local thirdPartyDirty = true

local function CollectThirdPartyButtons()
    wipe(thirdPartyButtons)
    local seen = {}

    -- LibActionButton-1.0 registry (catches Bartender4, Dominos, and any other LAB addon)
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB and LAB.GetAllButtons then
        for btn in pairs(LAB:GetAllButtons()) do
            if not seen[btn] then
                seen[btn] = true
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    -- Bartender4  (BT4Button1 … BT4Button180, up to 15 bars × 12 buttons)
    if _G["Bartender4"] then
        for i = 1, 180 do
            local btn = _G["BT4Button" .. i]
            if btn and not seen[btn] then
                seen[btn] = true
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    -- Dominos  (DominosActionButton1 … DominosActionButton168)
    if _G["Dominos"] then
        for i = 1, 168 do
            local btn = _G["DominosActionButton" .. i]
            if btn and not seen[btn] then
                seen[btn] = true
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    -- ElvUI  (ElvUI_Bar<1-15>Button<1-14>)
    if _G["ElvUI"] then
        for bar = 1, 15 do
            for slot = 1, 14 do
                local btn = _G["ElvUI_Bar" .. bar .. "Button" .. slot]
                if btn and not seen[btn] then
                    seen[btn] = true
                    thirdPartyButtons[#thirdPartyButtons + 1] = btn
                end
            end
        end
    end

    -- ElvUI LibActionButton-1.0-ElvUI fork
    local LAB_Elv = LibStub and LibStub("LibActionButton-1.0-ElvUI", true)
    if LAB_Elv and LAB_Elv.GetAllButtons then
        for btn in pairs(LAB_Elv:GetAllButtons()) do
            if not seen[btn] then
                seen[btn] = true
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    thirdPartyDirty = false
end

-- ─── Stack count overlay ─────────────────────────────────────────────────────
local STACK_FONT = "Fonts\\FRIZQT__.TTF"
local STACK_FONT_SIZE = 20
local STACK_FONT_FLAGS = "OUTLINE"

function addon:ShowStackCount(frame, count)
    if not count then
        addon:HideStackCount(frame)
        return
    end
    local text = stackTexts[frame]
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetFont(STACK_FONT, STACK_FONT_SIZE, STACK_FONT_FLAGS)
        text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        text:SetTextColor(1, 0, 0, 1)
        stackTexts[frame] = text
    end
    text:SetText(count)
    text:Show()
end

function addon:HideStackCount(frame)
    local text = stackTexts[frame]
    if text then
        text:Hide()
    end
end

function addon:ShowProcGlow(button, r, g, b, soundKey, entryGlowType)
    local glowType = entryGlowType and entryGlowType ~= "Default" and entryGlowType or (self.db and self.db.profile.glowType or "Proc Glow")
    local color = r and {r, g, b, 1} or nil

    if glowType == "Proc Glow" then
        if not LCG.ProcGlow_Start then
            if not lcgWarnedOnce then
                lcgWarnedOnce = true
                print("|cffff4444ProcGlows:|r LibCustomGlow did not fully initialize (ProcGlow_Start is missing). " ..
                          "This is likely caused by a conflicting addon or a WoW build incompatibility with " ..
                          "the embedded LibCustomGlow-1.0 (version " .. (LCG.minor or "?") .. "). " ..
                          "Glows will not display until this is resolved.")
            end
            return
        end
        local opts = {
            startAnim = true,
            key = GLOW_KEY
        }
        if color then
            opts.color = color
        end
        LCG.ProcGlow_Start(button, opts)
        local glowFrame = button["_ProcGlow" .. GLOW_KEY]
        if glowFrame then
            glowFrame.startAnim = false
        end
    elseif glowType == "Pixel Glow" then
        if LCG.PixelGlow_Start then
            LCG.PixelGlow_Start(button, color, nil, nil, nil, nil, nil, nil, nil, GLOW_KEY)
        end
    elseif glowType == "Autocast Shine" then
        if LCG.AutoCastGlow_Start then
            LCG.AutoCastGlow_Start(button, color, nil, nil, nil, nil, nil, GLOW_KEY)
        end
    elseif glowType == "Action Button Glow" then
        if LCG.ButtonGlow_Start then
            LCG.ButtonGlow_Start(button, color)
        end
    end

    if not allGlowingButtons[button] then
        -- Play per-entry proc sound
        if soundKey and soundKey ~= "None" then
            local soundFile = LSM:Fetch(LSM.MediaType.SOUND, soundKey, true)
            if soundFile then
                PlaySoundFile(soundFile, "Master")
            end
        end
    end
    allGlowingButtons[button] = true
end

local function StopAllGlowTypes(button)
    if LCG.ProcGlow_Stop then
        LCG.ProcGlow_Stop(button, GLOW_KEY)
    end
    if LCG.PixelGlow_Stop then
        LCG.PixelGlow_Stop(button, GLOW_KEY)
    end
    if LCG.AutoCastGlow_Stop then
        LCG.AutoCastGlow_Stop(button, GLOW_KEY)
    end
    if LCG.ButtonGlow_Stop then
        LCG.ButtonGlow_Stop(button)
    end
end

function addon:HideProcGlow(button)
    StopAllGlowTypes(button)
    allGlowingButtons[button] = nil
    addon:HideStackCount(button)
end

function addon:HideAllGlows()
    for button in pairs(allGlowingButtons) do
        StopAllGlowTypes(button)
        activeGlows[button] = nil
        addon:HideStackCount(button)
    end
    wipe(allGlowingButtons)
end

function addon:IsCombatOnly()
    return self.db and self.db.profile.combatOnly and not UnitAffectingCombat("player")
end

function addon:CleanupOrphanedGlows()
    -- Collect all buttons that are still in a cache
    local cached = {}
    if addon.Auras then
        for _, entries in pairs(addon.Auras) do
            for _, entry in ipairs(entries) do
                if entry.buttons then
                    for _, button in ipairs(entry.buttons) do
                        cached[button] = true
                    end
                end
            end
        end
    end
    for _, buttons in pairs(spellAnchorCache) do
        for _, button in ipairs(buttons) do
            cached[button] = true
        end
    end
    for _, buttons in pairs(itemAnchorCache) do
        for _, button in ipairs(buttons) do
            cached[button] = true
        end
    end
    for _, frames in pairs(cdmSpellFrameCache) do
        for _, frame in ipairs(frames) do
            cached[frame] = true
        end
    end
    -- Include BuffIconCooldownViewer aura frames that may have icon glows
    if BuffIconCooldownViewer and BuffIconCooldownViewer.itemFramePool then
        for aura in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
            if aura and aura.GetBaseSpellID then
                local spellID = aura:GetBaseSpellID()
                if spellID and addon.Auras and addon.Auras[spellID] then
                    cached[aura] = true
                end
            end
        end
    end
    -- Remove glows from buttons that are no longer in any cache
    for button in pairs(allGlowingButtons) do
        if not cached[button] then
            StopAllGlowTypes(button)
            allGlowingButtons[button] = nil
            activeGlows[button] = nil
        end
    end
end

function addon:HasProcGlow(button)
    return button["_ProcGlow" .. GLOW_KEY] ~= nil or button["_PixelGlow" .. GLOW_KEY] ~= nil or button["_AutoCastGlow" .. GLOW_KEY] ~= nil or
               button._ButtonGlow ~= nil
end

function addon:FindButtonsForSlot(slot)
    local result = {}
    local seen = {}
    if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            if not seen[button] and GetButtonActionSlot(button) == slot then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and not seen[button] and GetButtonActionSlot(button) == slot then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    -- Third-party action bar addons (Bartender4, Dominos, ElvUI)
    if thirdPartyDirty then
        CollectThirdPartyButtons()
    end
    for _, button in ipairs(thirdPartyButtons) do
        if not seen[button] and GetButtonActionSlot(button) == slot then
            seen[button] = true
            result[#result + 1] = button
        end
    end
    return result
end

function addon:LookupSpellButtons(spellID)
    local result = {}
    local seen = {}

    -- Collect all action slots for this spell (base + override)
    local allSlots = {}
    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if slots then
        for _, s in ipairs(slots) do
            allSlots[#allSlots + 1] = s
        end
    end
    if C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            slots = C_ActionBar.FindSpellActionButtons(overrideID)
            if slots then
                for _, s in ipairs(slots) do
                    allSlots[#allSlots + 1] = s
                end
            end
        end
    end

    -- For each slot, find every button that owns it
    for _, slot in ipairs(allSlots) do
        local buttons = addon:FindButtonsForSlot(slot)
        for _, button in ipairs(buttons) do
            if not seen[button] then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    return result
end

function addon:FindButtonsBySpellID(spellID)
    if spellCacheDirty then
        wipe(spellButtonCache)
        spellCacheDirty = false
    end
    if not spellButtonCache[spellID] then
        spellButtonCache[spellID] = addon:LookupSpellButtons(spellID)
    end
    return spellButtonCache[spellID]
end

function addon:InvalidateAllCaches()
    spellCacheDirty = true
    itemCacheDirty = true
    thirdPartyDirty = true
    addon:RebuildAuraAnchorCache()
    addon:RebuildSpellButtonCache()
    addon:RebuildItemButtonCache()
    addon:RebuildCDMSpellFrameCache()
    addon:CleanupOrphanedGlows()
end

function addon:ScanItemButtons()
    if InCombatLockdown() then
        itemCacheDirty = true
        return
    end
    wipe(itemSlotCache)
    for slot = 1, MAX_ACTION_SLOT do
        if HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "item" and id then
                if not itemSlotCache[id] then
                    itemSlotCache[id] = {}
                end
                itemSlotCache[id][#itemSlotCache[id] + 1] = slot
            end
        end
    end
    itemCacheDirty = false
end

function addon:FindButtonsByItemID(itemID)
    if itemCacheDirty and not InCombatLockdown() then
        addon:ScanItemButtons()
    end
    local slots = itemSlotCache[itemID]
    if not slots then
        return {}
    end
    local result = {}
    local seen = {}
    for _, slot in ipairs(slots) do
        local buttons = addon:FindButtonsForSlot(slot)
        for _, button in ipairs(buttons) do
            if not seen[button] then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    return result
end

function addon:RebuildAuraAnchorCache()
    if not addon.Auras then
        return
    end
    -- Force spell cache refresh so LookupSpellButtons gets fresh data
    spellCacheDirty = true
    for buffSpellID, entries in pairs(addon.Auras) do
        for _, entry in ipairs(entries) do
            entry.buttons = addon:FindButtonsBySpellID(entry.anchorSpellID)
        end
    end
end

function addon:RebuildItemButtonCache()
    wipe(itemAnchorCache)
    if not addon.Items then
        return
    end
    for key, item in pairs(addon.Items) do
        itemAnchorCache[item.itemID] = addon:FindButtonsByItemID(item.itemID)
    end
end

function addon:RebuildSpellButtonCache()
    wipe(spellAnchorCache)
    if not addon.Spells then
        return
    end
    -- Force spell cache refresh so LookupSpellButtons gets fresh data
    spellCacheDirty = true
    for spellID, _ in pairs(addon.Spells) do
        spellAnchorCache[spellID] = addon:FindButtonsBySpellID(spellID)
    end
end

-- Build a spellID -> {frames} cache from EssentialCooldownViewer's pool.
-- The pool is dynamic so we rebuild every check cycle.
function addon:RebuildCDMSpellFrameCache()
    wipe(cdmSpellFrameCache)
    if not EssentialCooldownViewer or not EssentialCooldownViewer.itemFramePool then
        return
    end
    for frame in EssentialCooldownViewer.itemFramePool:EnumerateActive() do
        if frame and frame.GetBaseSpellID then
            local spellID = frame:GetBaseSpellID()
            if spellID then
                if not cdmSpellFrameCache[spellID] then
                    cdmSpellFrameCache[spellID] = {}
                end
                cdmSpellFrameCache[spellID][#cdmSpellFrameCache[spellID] + 1] = frame
            end
        end
    end
end

function addon:CheckAuras()
    if not addon.Auras then
        return
    end

    local suppressed = addon:IsCombatOnly()

    for aura in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
        local spellID = aura:GetBaseSpellID()
        local entries = spellID and addon.Auras[spellID]
        if entries then
            -- shouldShow: hide aura if ALL entries say not to show
            local anyShow = false
            for _, auraData in ipairs(entries) do
                if auraData.shouldShow then
                    anyShow = true
                    break
                end
            end
            if not anyShow then
                aura:Hide()
            end

            -- Glow on the aura icon itself: use first entry with glowIcon
            local iconGlowData = nil
            for _, auraData in ipairs(entries) do
                if auraData.glowIcon then
                    iconGlowData = auraData
                    break
                end
            end
            if iconGlowData then
                if aura.Cooldown:IsShown() and not suppressed then
                    if not activeGlows[aura] or not addon:HasProcGlow(aura) then
                        activeGlows[aura] = true
                        if iconGlowData.useDefaultColor then
                            addon:ShowProcGlow(aura, nil, nil, nil, iconGlowData.procSound, iconGlowData.glowType)
                        else
                            addon:ShowProcGlow(aura, iconGlowData.color.r, iconGlowData.color.g, iconGlowData.color.b, iconGlowData.procSound,
                                iconGlowData.glowType)
                        end
                    end
                else
                    if activeGlows[aura] then
                        activeGlows[aura] = nil
                        addon:HideProcGlow(aura)
                    end
                end
            end

            -- Fetch stack count once per buff for all entries
            local stackCount = aura.Applications.Applications:GetText()

            -- Per-entry: action bar buttons and CDM spell frames
            for _, auraData in ipairs(entries) do
                local buttons = auraData.buttons
                if buttons then
                    for _, button in ipairs(buttons) do
                        if aura.Cooldown:IsShown() and not suppressed then
                            if not addon:HasProcGlow(button) then
                                if auraData.useDefaultColor then
                                    addon:ShowProcGlow(button, nil, nil, nil, auraData.procSound, auraData.glowType)
                                else
                                    addon:ShowProcGlow(button, auraData.color.r, auraData.color.g, auraData.color.b, auraData.procSound,
                                        auraData.glowType)
                                end
                            end
                            -- Show stack count on the action button
                            if auraData.showStacks then
                                addon:ShowStackCount(button, stackCount)
                            end
                        else
                            addon:HideProcGlow(button)
                        end
                    end
                end

                -- Glow matching spell icon in EssentialCooldownViewer (CooldownManager)
                if auraData.glowCooldownManager then
                    local cdmFrames = cdmSpellFrameCache[auraData.anchorSpellID]
                    if cdmFrames then
                        for _, frame in ipairs(cdmFrames) do
                            if aura.Cooldown:IsShown() and not suppressed and C_Spell.IsSpellUsable(auraData.anchorSpellID) then
                                if not activeGlows[frame] or not addon:HasProcGlow(frame) then
                                    activeGlows[frame] = true
                                    if auraData.useDefaultColor then
                                        addon:ShowProcGlow(frame, nil, nil, nil, auraData.procSound, auraData.glowType)
                                    else
                                        addon:ShowProcGlow(frame, auraData.color.r, auraData.color.g, auraData.color.b, auraData.procSound,
                                            auraData.glowType)
                                    end
                                end
                                -- Show stack count on the CDM spell frame
                                if auraData.showStacks then
                                    addon:ShowStackCount(frame, stackCount)
                                end
                            else
                                if activeGlows[frame] then
                                    activeGlows[frame] = nil
                                    addon:HideProcGlow(frame)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function addon:CheckItemCooldowns()
    if not addon.Items then
        return
    end

    local suppressed = addon:IsCombatOnly()

    for _, item in pairs(addon.Items) do
        local buttons = itemAnchorCache[item.itemID]

        if buttons then
            for _, button in ipairs(buttons) do
                if not suppressed and C_Item.GetItemCount(item.itemID) > 0 and C_Item.IsUsableItem(item.itemID) and (not button.cooldown:IsShown()) then
                    if not addon:HasProcGlow(button) then
                        if item.useDefaultColor then
                            addon:ShowProcGlow(button, nil, nil, nil, item.procSound, item.glowType)
                        else
                            addon:ShowProcGlow(button, item.color.r, item.color.g, item.color.b, item.procSound, item.glowType)
                        end
                    end
                else
                    addon:HideProcGlow(button)
                end
            end
        end
    end
end

function addon:CheckSpellCooldowns()
    if not addon.Spells then
        return
    end

    local suppressed = addon:IsCombatOnly()

    local onCooldown
    local shouldGlow

    for spellID, spellData in pairs(addon.Spells) do
        local buttons = spellAnchorCache[spellID]
        if buttons then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            for _, button in ipairs(buttons) do
                onCooldown = button.cooldown:IsShown() and not cdInfo.isOnGCD
                shouldGlow = not suppressed and C_Spell.IsSpellUsable(spellID) and not onCooldown

                if shouldGlow then
                    if not activeGlows[button] or not addon:HasProcGlow(button) then
                        activeGlows[button] = true
                        if spellData.useDefaultColor then
                            addon:ShowProcGlow(button, nil, nil, nil, spellData.procSound, spellData.glowType)
                        else
                            addon:ShowProcGlow(button, spellData.color.r, spellData.color.g, spellData.color.b, spellData.procSound,
                                spellData.glowType)
                        end
                    end
                else
                    if activeGlows[button] then
                        activeGlows[button] = nil
                        addon:HideProcGlow(button)
                    end
                end
            end
        end

    -- Glow spell icons in EssentialCooldownViewer (CooldownManager)
        if spellData.glowCooldownManager then
            local cdmFrames = cdmSpellFrameCache[spellID]
            if cdmFrames then
                for _, frame in ipairs(cdmFrames) do
                    if shouldGlow then
                        if not activeGlows[frame] or not addon:HasProcGlow(frame) then
                            activeGlows[frame] = true
                            if spellData.useDefaultColor then
                                addon:ShowProcGlow(frame, nil, nil, nil, spellData.procSound, spellData.glowType)
                            else
                                addon:ShowProcGlow(frame, spellData.color.r, spellData.color.g, spellData.color.b, spellData.procSound,
                                    spellData.glowType)
                            end
                        end
                    else
                        if activeGlows[frame] then
                            activeGlows[frame] = nil
                            addon:HideProcGlow(frame)
                        end
                    end
                end
            end
        end
    end
end

-- Hooks
addon.events:HookScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event ==
        "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_BONUS_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
        -- Rebuild the slot snapshot so ACTIONBAR_SLOT_CHANGED can detect real changes
        wipe(actionSlotSnapshot)
        for s = 1, MAX_ACTION_SLOT do
            if HasAction(s) then
                local aType, id = GetActionInfo(s)
                actionSlotSnapshot[s] = aType and (aType .. ":" .. (id or 0)) or nil
            end
        end
        addon:InvalidateAllCaches()
        return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = ...
        if slot == 0 then
            -- slot 0 means "all slots" – full rebuild
            wipe(actionSlotSnapshot)
            for s = 1, MAX_ACTION_SLOT do
                if HasAction(s) then
                    local aType, id = GetActionInfo(s)
                    actionSlotSnapshot[s] = aType and (aType .. ":" .. (id or 0)) or nil
                end
            end
            addon:InvalidateAllCaches()
        else
            local newKey
            if HasAction(slot) then
                local aType, id = GetActionInfo(slot)
                newKey = aType and (aType .. ":" .. (id or 0)) or nil
            end
            if actionSlotSnapshot[slot] ~= newKey then
                actionSlotSnapshot[slot] = newKey
                addon:InvalidateAllCaches()
            end
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: refresh all checks so glows appear immediately
        addon:CheckAuras()
        addon:CheckItemCooldowns()
        addon:CheckSpellCooldowns()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: if combat-only mode, hide all glows
        if addon.db and addon.db.profile.combatOnly then
            addon:HideAllGlows()
        end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        addon:CheckSpellCooldowns()
        return
    end
    addon:CheckItemCooldowns()
end)

BuffIconCooldownViewer:HookScript("OnEvent", addon.CheckAuras)
