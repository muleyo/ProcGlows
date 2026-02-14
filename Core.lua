local _, addon = ...
_, addon.Class = UnitClass("player")

addon.events = CreateFrame("Frame")
addon.events:RegisterEvent("SPELL_UPDATE_USABLE")
addon.events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addon.events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addon.events:RegisterEvent("PLAYER_REGEN_ENABLED")

-- ─── Glow via LibCustomGlow ProcGlow (modern Blizzard flipbook proc glow) ───
local LCG = LibStub("LibCustomGlow-1.0")
local activeGlows = {}
local wasOnGCD = {}
local GLOW_KEY = "ProcGlows"

local function ShowProcGlow(button, r, g, b)
    LCG.ProcGlow_Start(button, {
        color = {r, g, b, 1},
        startAnim = true,
        key = GLOW_KEY
    })
end

local function HideProcGlow(button)
    LCG.ProcGlow_Stop(button, GLOW_KEY)
end

local function HasProcGlow(button)
    return button["_ProcGlow" .. GLOW_KEY] ~= nil
end

-- ─── Gather every action button we know about ───────────────────────────────
local BUTTON_PREFIXES = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
                         "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
                         "MultiBar8Button"}

-- ─── Find all buttons whose .action matches a given slot (inline compare) ───
-- IMPORTANT: We never store button.action in a variable.  In TWW it is a
-- "forbidden value" (secret number).  Storing it and passing it to any API
-- (HasAction, GetActionInfo, table index, …) taints the secure action-bar
-- execution path.  Direct comparison  button.action == <normal value>  returns
-- a clean boolean and is safe.
local function FindButtonsForSlot(slot)
    local result = {}
    local seen = {}
    if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            if not seen[button] and button.action == slot then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and not seen[button] and button.action == slot then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    return result
end

-- ─── Taint-free button lookup ───────────────────────────────────────────────
-- Uses C_ActionBar.FindSpellActionButtons (returns clean slot numbers) and
-- then matches those slots to buttons via inline comparison only.
function addon:FindButtonsBySpellID(spellID)
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
        local buttons = FindButtonsForSlot(slot)
        for _, button in ipairs(buttons) do
            if not seen[button] then
                seen[button] = true
                result[#result + 1] = button
            end
        end
    end
    return result
end

-- ─── Item button cache (scanned out of combat) ─────────────────────────────
-- We iterate known action slots (1–180) so we never need to read button.action
-- as a variable.  GetActionInfo(slot) with a plain number is taint-safe.
local MAX_ACTION_SLOT = 180
local itemButtonCache = {}
local itemCacheDirty = true

local function ScanItemButtons()
    if InCombatLockdown() then
        itemCacheDirty = true
        return
    end
    wipe(itemButtonCache)
    for slot = 1, MAX_ACTION_SLOT do
        if HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "item" and id then
                local buttons = FindButtonsForSlot(slot)
                if #buttons > 0 then
                    if not itemButtonCache[id] then
                        itemButtonCache[id] = {}
                    end
                    for _, btn in ipairs(buttons) do
                        itemButtonCache[id][#itemButtonCache[id] + 1] = btn
                    end
                end
            end
        end
    end
    itemCacheDirty = false
end

-- Initial scan (runs at load, out of combat)
ScanItemButtons()

function addon:FindButtonsByItemID(itemID)
    if itemCacheDirty and not InCombatLockdown() then
        ScanItemButtons()
    end
    return itemButtonCache[itemID] or {}
end

function addon:OnUpdate()
    if not addon.Auras then
        return
    end

    for aura in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
        if aura and aura.GetBaseSpellID then
            local spellID = aura:GetBaseSpellID()
            if spellID and addon.Auras[spellID] then
                local auraData = addon.Auras[spellID]
                local buttons = addon:FindButtonsBySpellID(auraData.anchorSpellID)
                local shouldShow = auraData.shouldShow

                if not shouldShow then
                    aura:Hide()
                end

                for _, button in ipairs(buttons) do
                    if aura.Cooldown:IsShown() then
                        if not HasProcGlow(button) then
                            ShowProcGlow(button, auraData.color.r, auraData.color.g, auraData.color.b)
                        end
                    else
                        HideProcGlow(button)
                    end
                end
            end
        end
    end
end

function addon:OnEvent()
    if not addon.Items then
        return
    end

    for _, item in pairs(addon.Items) do
        local buttons = addon:FindButtonsByItemID(item.itemID)

        for _, button in ipairs(buttons) do
            if C_Item.IsUsableItem(item.itemID) and not button.cooldown:IsShown() then
                if not HasProcGlow(button) then
                    ShowProcGlow(button, item.color.r, item.color.g, item.color.b)
                end
            else
                HideProcGlow(button)
            end
        end
    end
end

function addon:CheckSpellCooldowns()
    if not addon.Spells then
        return
    end

    for spellID, spellData in pairs(addon.Spells) do
        local buttons = addon:FindButtonsBySpellID(spellID)
        local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
        local isOnGCD = cooldownInfo and cooldownInfo.isOnGCD
        local justLeftGCD = wasOnGCD[spellID] and not isOnGCD
        wasOnGCD[spellID] = isOnGCD

        for _, button in ipairs(buttons) do
            -- Allow showing glows during GCD, skip hide on the frame GCD ends
            if C_Spell.IsSpellUsable(spellID) and (isOnGCD or justLeftGCD or not button.cooldown:IsShown()) then
                local alertMissing = activeGlows[button] and not HasProcGlow(button)
                if not activeGlows[button] or alertMissing then
                    activeGlows[button] = true
                    ShowProcGlow(button, spellData.color.r, spellData.color.g, spellData.color.b)
                end
            elseif not isOnGCD and not justLeftGCD then
                if activeGlows[button] then
                    activeGlows[button] = nil
                    HideProcGlow(button)
                end
            end
        end
    end
end

-- ─── Debug slash command ─────────────────────────────────────────────────────
SLASH_PGDEBUG1 = "/pgdebug"
SlashCmdList["PGDEBUG"] = function()
    print("|cff00ff00[ProcGlows Debug]|r Scanning action slots 1-180...")
    local buttonCount = 0
    for slot = 1, MAX_ACTION_SLOT do
        if HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            local buttons = FindButtonsForSlot(slot)
            if #buttons > 0 then
                local names = {}
                for _, btn in ipairs(buttons) do
                    names[#names + 1] = btn:GetName() or "unnamed"
                    buttonCount = buttonCount + 1
                end
                print("  slot=" .. slot .. "  " .. tostring(actionType) .. "/" .. tostring(id) .. "  buttons: " ..
                          table.concat(names, ", "))
            end
        end
    end
    print("  Total buttons matched: " .. buttonCount)

    if addon.Spells then
        print("|cff00ff00[ProcGlows]|r Tracked spells:")
        for spellID, _ in pairs(addon.Spells) do
            local buttons = addon:FindButtonsBySpellID(spellID)
            local spellName = C_Spell.GetSpellInfo(spellID)
            spellName = spellName and spellName.name or tostring(spellID)
            print("  Spell " .. spellID .. " (" .. spellName .. "): found " .. #buttons .. " buttons")
            for _, btn in ipairs(buttons) do
                print("    -> " .. (btn:GetName() or "unnamed"))
            end
        end
    end

    if addon.Auras then
        print("|cff00ff00[ProcGlows]|r Tracked auras:")
        for spellID, auraData in pairs(addon.Auras) do
            local buttons = addon:FindButtonsBySpellID(auraData.anchorSpellID)
            local spellName = C_Spell.GetSpellInfo(spellID)
            spellName = spellName and spellName.name or tostring(spellID)
            print("  Aura " .. spellID .. " (" .. spellName .. ") anchor=" .. auraData.anchorSpellID .. ": found " ..
                      #buttons .. " buttons")
            for _, btn in ipairs(buttons) do
                print("    -> " .. (btn:GetName() or "unnamed"))
            end
        end
    end

    if addon.Items then
        print("|cff00ff00[ProcGlows]|r Tracked items:")
        for key, item in pairs(addon.Items) do
            local buttons = addon:FindButtonsByItemID(item.itemID)
            print("  Item " .. item.itemID .. ": found " .. #buttons .. " buttons")
        end
    end
end

-- Hook BuffIconCooldownViewer to track auras 
BuffIconCooldownViewer:HookScript("OnUpdate", addon.OnUpdate)

addon.events:SetScript("OnEvent", function(self, event, ...)
    if event == "ACTIONBAR_SLOT_CHANGED" then
        itemCacheDirty = true
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if itemCacheDirty then
            ScanItemButtons()
        end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        addon:CheckSpellCooldowns()
        return
    end
    addon:OnEvent()
    addon:CheckSpellCooldowns()
end)
