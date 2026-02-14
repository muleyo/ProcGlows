local _, addon = ...

-- Shared config table – values are overwritten by Config.lua after DB loads
addon.hideAnimConfig = addon.hideAnimConfig or {
    castbar = true
}

local config = addon.hideAnimConfig

local function hideSpellCastAnimFrame(button)
    if config and config.castbar then
        button.SpellCastAnimFrame:SetAlpha(0)
    end
end

local function hideInterruptDisplay(button)
    if config and config.castbar then
        button.InterruptDisplay:SetAlpha(0)
    end
end

local function hideTargetReticleAnimFrame(button)
    if config and config.castbar then
        button.TargetReticleAnimFrame:SetAlpha(0)
    end
end

-- Disable the CastBar within ActionButtons
local function hideCastAnimations(button)
    if config and config.castbar then
        button.cooldown:SetDrawBling(true)
    end

    hooksecurefunc(button, "PlaySpellCastAnim", hideSpellCastAnimFrame)
    hooksecurefunc(button, "PlaySpellInterruptedAnim", hideInterruptDisplay)
    hooksecurefunc(button, "PlayTargettingReticleAnim", hideTargetReticleAnimFrame)
end

-- Register known ActionButtons
for _, button in pairs(ActionBarButtonEventsFrame.frames) do
    hideCastAnimations(button)
end

-- and watch for any additional action buttons
hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
    hideCastAnimations(button)
end)

