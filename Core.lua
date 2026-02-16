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
local auraAnchorCache = {}
local itemAnchorCache = {}
local spellAnchorCache = {}
local spellCacheDirty = true
local itemCacheDirty = true
local wasOnGCD = {}
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

function addon:ShowProcGlow(button, r, g, b)
    LCG.ProcGlow_Start(button, {
        color = {r, g, b, 1},
        startAnim = true,
        key = GLOW_KEY
    })
    allGlowingButtons[button] = true
end

function addon:HideProcGlow(button)
    LCG.ProcGlow_Stop(button, GLOW_KEY)
    allGlowingButtons[button] = nil
end

function addon:HideAllGlows()
    for button in pairs(allGlowingButtons) do
        LCG.ProcGlow_Stop(button, GLOW_KEY)
        activeGlows[button] = nil
    end
    wipe(allGlowingButtons)
end

function addon:IsCombatOnly()
    return self.db and self.db.profile.combatOnly and not UnitAffectingCombat("player")
end

function addon:CleanupOrphanedGlows()
    -- Collect all buttons that are still in a cache
    local cached = {}
    for _, buttons in pairs(auraAnchorCache) do
        for _, button in ipairs(buttons) do
            cached[button] = true
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
    wipe(auraAnchorCache)
    if not addon.Auras then
        return
    end
    -- Force spell cache refresh so LookupSpellButtons gets fresh data
    spellCacheDirty = true
    for buffSpellID, auraData in pairs(addon.Auras) do
        auraAnchorCache[buffSpellID] = addon:FindButtonsBySpellID(auraData.anchorSpellID)
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

function addon:CheckAuras()
    if not addon.Auras then
        return
    end

    local suppressed = addon:IsCombatOnly()

    for aura in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
        if aura and aura.GetBaseSpellID then
            local spellID = aura:GetBaseSpellID()
            if spellID and addon.Auras[spellID] then
                local auraData = addon.Auras[spellID]
                local buttons = auraAnchorCache[spellID]

                if not auraData.shouldShow then
                    aura:Hide()
                end

                -- Glow on the aura icon itself (delayed by 1 frame to avoid size pop)
                if auraData.glowIcon then
                    if aura.Cooldown:IsShown() and not suppressed then
                        if not addon:HasProcGlow(aura) and not aura._ProcGlowPending then
                            aura._ProcGlowPending = true
                            C_Timer.After(0, function()
                                aura._ProcGlowPending = nil
                                if aura.Cooldown:IsShown() and not addon:HasProcGlow(aura) then
                                    addon:ShowProcGlow(aura, auraData.color.r, auraData.color.g, auraData.color.b)
                                end
                            end)
                        end
                    else
                        aura._ProcGlowPending = nil
                        addon:HideProcGlow(aura)
                    end
                end

                if buttons then
                    for _, button in ipairs(buttons) do
                        if aura.Cooldown:IsShown() and not suppressed then
                            if not addon:HasProcGlow(button) then
                                addon:ShowProcGlow(button, auraData.color.r, auraData.color.g, auraData.color.b)
                            end
                        else
                            addon:HideProcGlow(button)
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
                        addon:ShowProcGlow(button, item.color.r, item.color.g, item.color.b)
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
                        addon:ShowProcGlow(button, spellData.color.r, spellData.color.g, spellData.color.b)
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
