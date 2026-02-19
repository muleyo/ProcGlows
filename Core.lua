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
local activeGlows = {}
local GLOW_KEY = "ProcGlows"
local allGlowingButtons = {}
local spellButtonCache = {}
local itemAnchorCache = {}
local spellAnchorCache = {}
local cdmSpellFrameCache = {}
local spellCacheDirty = true
local itemCacheDirty = true
local stackTexts = {}
local LSM = LibStub("LibSharedMedia-3.0")
local BUTTON_PREFIXES = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
                         "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
                         "MultiBar8Button"}
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

    -- Bartender4  (LibActionButton buttons named BT4Button1 … BT4Button120)
    if _G["Bartender4"] then
        for i = 1, 120 do
            local btn = _G["BT4Button" .. i]
            if btn then
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    -- Dominos  (LibActionButton buttons named DominosActionButton1 … DominosActionButton168)
    if _G["Dominos"] then
        for i = 1, 168 do
            local btn = _G["DominosActionButton" .. i]
            if btn then
                thirdPartyButtons[#thirdPartyButtons + 1] = btn
            end
        end
    end

    -- ElvUI  (buttons named ElvUI_Bar<1-10>Button<1-12>)
    if _G["ElvUI"] then
        for bar = 1, 10 do
            for slot = 1, 12 do
                local btn = _G["ElvUI_Bar" .. bar .. "Button" .. slot]
                if btn then
                    thirdPartyButtons[#thirdPartyButtons + 1] = btn
                end
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
    if not count or count < 2 then
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

function addon:ShowProcGlow(button, r, g, b, soundKey)
    local opts = {
        startAnim = true,
        key = GLOW_KEY
    }
    if r then
        opts.color = {r, g, b, 1}
    end
    LCG.ProcGlow_Start(button, opts)
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

function addon:HideProcGlow(button)
    LCG.ProcGlow_Stop(button, GLOW_KEY)
    allGlowingButtons[button] = nil
    addon:HideStackCount(button)
end

function addon:HideAllGlows()
    for button in pairs(allGlowingButtons) do
        LCG.ProcGlow_Stop(button, GLOW_KEY)
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
            LCG.ProcGlow_Stop(button, GLOW_KEY)
            allGlowingButtons[button] = nil
            activeGlows[button] = nil
        end
    end
end

function addon:HasProcGlow(button)
    return button["_ProcGlow" .. GLOW_KEY] ~= nil
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
                            addon:ShowProcGlow(aura, nil, nil, nil, iconGlowData.procSound)
                        else
                            addon:ShowProcGlow(aura, iconGlowData.color.r, iconGlowData.color.g, iconGlowData.color.b,
                                iconGlowData.procSound)
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
            local stackCount = tonumber(aura.Applications.Applications:GetText())

            -- Per-entry: action bar buttons and CDM spell frames
            for _, auraData in ipairs(entries) do
                local buttons = auraData.buttons
                if buttons then
                    for _, button in ipairs(buttons) do
                        if aura.Cooldown:IsShown() and not suppressed then
                            if not addon:HasProcGlow(button) then
                                if auraData.useDefaultColor then
                                    addon:ShowProcGlow(button, nil, nil, nil, auraData.procSound)
                                else
                                    addon:ShowProcGlow(button, auraData.color.r, auraData.color.g, auraData.color.b,
                                        auraData.procSound)
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
                            if aura.Cooldown:IsShown() and not suppressed then
                                if not activeGlows[frame] or not addon:HasProcGlow(frame) then
                                    activeGlows[frame] = true
                                    if auraData.useDefaultColor then
                                        addon:ShowProcGlow(frame, nil, nil, nil, auraData.procSound)
                                    else
                                        addon:ShowProcGlow(frame, auraData.color.r, auraData.color.g, auraData.color.b,
                                            auraData.procSound)
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
                if not suppressed and GetItemCount(item.itemID) > 0 and C_Item.IsUsableItem(item.itemID) and
                    (not button.cooldown:IsShown()) then
                    if not addon:HasProcGlow(button) then
                        if item.useDefaultColor then
                            addon:ShowProcGlow(button, nil, nil, nil, item.procSound)
                        else
                            addon:ShowProcGlow(button, item.color.r, item.color.g, item.color.b, item.procSound)
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

    for spellID, spellData in pairs(addon.Spells) do
        local buttons = spellAnchorCache[spellID]
        if buttons then
            local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
            for _, button in ipairs(buttons) do
                local onCooldown = button.cooldown:IsShown() and not cooldownInfo.isOnGCD
                local shouldGlow = not suppressed and C_Spell.IsSpellUsable(spellID) and not onCooldown

                if shouldGlow then
                    if not activeGlows[button] or not addon:HasProcGlow(button) then
                        activeGlows[button] = true
                        if spellData.useDefaultColor then
                            addon:ShowProcGlow(button, nil, nil, nil, spellData.procSound)
                        else
                            addon:ShowProcGlow(button, spellData.color.r, spellData.color.g, spellData.color.b,
                                spellData.procSound)
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
    end

    -- Glow spell icons in EssentialCooldownViewer (CooldownManager)
    for spellID, spellData in pairs(addon.Spells) do
        if spellData.glowCooldownManager then
            local cdmFrames = cdmSpellFrameCache[spellID]
            if cdmFrames then
                local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
                for _, frame in ipairs(cdmFrames) do
                    local onCooldown =
                        frame.Cooldown and frame.Cooldown:IsShown() and frame.cooldownChargesCount < 1 and
                            not cooldownInfo.isOnGCD
                    local shouldGlow = not suppressed and C_Spell.IsSpellUsable(spellID) and not onCooldown

                    if shouldGlow then
                        if not activeGlows[frame] or not addon:HasProcGlow(frame) then
                            activeGlows[frame] = true
                            if spellData.useDefaultColor then
                                addon:ShowProcGlow(frame, nil, nil, nil, spellData.procSound)
                            else
                                addon:ShowProcGlow(frame, spellData.color.r, spellData.color.g, spellData.color.b,
                                    spellData.procSound)
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
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIONBAR_SLOT_CHANGED" or
        event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_BONUS_ACTIONBAR" or
        event == "UPDATE_VEHICLE_ACTIONBAR" then
        addon:InvalidateAllCaches()
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
        addon:CheckItemCooldowns()
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        addon:CheckSpellCooldowns()
        return
    end
    addon:CheckItemCooldowns()
end)

BuffIconCooldownViewer:HookScript("OnUpdate", addon.CheckAuras)
