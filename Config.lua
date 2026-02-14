local addonName, addon = ...

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

-- ─── Defaults ────────────────────────────────────────────────────────────────
local defaults = {
    profile = {
        auras = {
            -- keyed by string spellID of the buff/proc
            -- each entry: { anchorSpellID, color = {r,g,b}, shouldShow }
        },
        items = {
            -- keyed by string itemID
            -- each entry: { color = {r,g,b} }
        },
        spells = {
            -- keyed by string spellID
            -- each entry: { color = {r,g,b} }
        },
        hideAnimations = {
            castbar = true
        }
    }
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function SpellName(id)
    if not id or id == 0 then
        return ""
    end
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name or tostring(id)
end

local function ItemName(id)
    if not id or id == 0 then
        return ""
    end
    local name = C_Item.GetItemNameByID(id)
    if not name then
        -- Request item data so it's available on next call
        C_Item.RequestLoadItemDataByID(id)
        local itemInfo = C_Item.GetItemInfo(id)
        name = itemInfo and itemInfo.itemName
    end
    return name or tostring(id)
end

-- ─── Class info ──────────────────────────────────────────────────────────────
local CLASS_INFO = {{
    token = "DEATHKNIGHT",
    name = "Death Knight",
    color = "C41E3A"
}, {
    token = "DEMONHUNTER",
    name = "Demon Hunter",
    color = "A330C9"
}, {
    token = "DRUID",
    name = "Druid",
    color = "FF7C0A"
}, {
    token = "EVOKER",
    name = "Evoker",
    color = "33937F"
}, {
    token = "HUNTER",
    name = "Hunter",
    color = "AAD372"
}, {
    token = "MAGE",
    name = "Mage",
    color = "3FC7EB"
}, {
    token = "MONK",
    name = "Monk",
    color = "00FF98"
}, {
    token = "PALADIN",
    name = "Paladin",
    color = "F48CBA"
}, {
    token = "PRIEST",
    name = "Priest",
    color = "FFFFFF"
}, {
    token = "ROGUE",
    name = "Rogue",
    color = "FFF468"
}, {
    token = "SHAMAN",
    name = "Shaman",
    color = "0070DD"
}, {
    token = "WARLOCK",
    name = "Warlock",
    color = "8788EE"
}, {
    token = "WARRIOR",
    name = "Warrior",
    color = "C69B6D"
}}

local function ClassDisplayName(token)
    for _, info in ipairs(CLASS_INFO) do
        if info.token == token then
            return "|cff" .. info.color .. info.name .. "|r"
        end
    end
    return token
end

local function ClassOrder(token)
    for i, info in ipairs(CLASS_INFO) do
        if info.token == token then
            return i
        end
    end
    return 99
end

-- Rebuild the runtime tables that Core.lua reads
function addon:RebuildTables()
    -- Auras (nested by class)
    self.Auras = {}
    if self.db then
        for classToken, classAuras in pairs(self.db.profile.auras) do
            if type(classAuras) == "table" then
                for key, entry in pairs(classAuras) do
                    local spellID = tonumber(key)
                    if spellID and entry.color then
                        self.Auras[spellID] = {
                            anchorSpellID = entry.anchorSpellID,
                            color = {
                                r = entry.color.r,
                                g = entry.color.g,
                                b = entry.color.b
                            },
                            shouldShow = entry.shouldShow
                        }
                    end
                end
            end
        end
    end

    -- Items (flat)
    self.Items = {}
    if self.db then
        for key, entry in pairs(self.db.profile.items) do
            local itemID = tonumber(key)
            if itemID then
                self.Items[key] = {
                    itemID = itemID,
                    color = {
                        r = entry.color.r,
                        g = entry.color.g,
                        b = entry.color.b
                    }
                }
            end
        end
    end

    -- Spells (nested by class)
    self.Spells = {}
    if self.db then
        for classToken, classSpells in pairs(self.db.profile.spells) do
            if type(classSpells) == "table" then
                for key, entry in pairs(classSpells) do
                    local spellID = tonumber(key)
                    if spellID and entry.color then
                        self.Spells[spellID] = {
                            color = {
                                r = entry.color.r,
                                g = entry.color.g,
                                b = entry.color.b
                            }
                        }
                    end
                end
            end
        end
    end
end

-- ─── Import / Export helpers ─────────────────────────────────────────────────
local EXPORT_PREFIX = "!PG1!" -- versioned prefix so we can detect the format

local importExportState = {
    exportString = "",
    importString = ""
}

local function ExportProfile()
    local data = {
        auras = addon.db.profile.auras,
        items = addon.db.profile.items,
        spells = addon.db.profile.spells,
        hideAnimations = addon.db.profile.hideAnimations
    }
    local serialized = AceSerializer:Serialize(data)
    local compressed = LibDeflate:CompressDeflate(serialized, {
        level = 9
    })
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

local function ImportProfile(str)
    str = strtrim(str)
    if str == "" then
        return false, "Import string is empty."
    end
    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid import string (unrecognised format)."
    end
    local encoded = str:sub(#EXPORT_PREFIX + 1)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return false, "Failed to decode import string."
    end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Failed to decompress import string."
    end
    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok then
        return false, "Failed to deserialize import data."
    end
    if type(data) ~= "table" then
        return false, "Import data is not a valid profile."
    end

    -- Apply imported data
    if data.auras and type(data.auras) == "table" then
        wipe(addon.db.profile.auras)
        -- Detect old flat format vs new nested-by-class format
        local isFlat = false
        for _, v in pairs(data.auras) do
            if type(v) == "table" and v.anchorSpellID ~= nil then
                isFlat = true
            end
            break
        end
        if isFlat then
            addon.db.profile.auras[addon.Class] = {}
            for k, v in pairs(data.auras) do
                addon.db.profile.auras[addon.Class][k] = v
            end
        else
            for k, v in pairs(data.auras) do
                addon.db.profile.auras[k] = v
            end
        end
    end
    if data.items and type(data.items) == "table" then
        wipe(addon.db.profile.items)
        for k, v in pairs(data.items) do
            addon.db.profile.items[k] = v
        end
    end
    if data.spells and type(data.spells) == "table" then
        wipe(addon.db.profile.spells)
        -- Detect old flat format vs new nested-by-class format
        local isFlat = false
        for _, v in pairs(data.spells) do
            if type(v) == "table" and v.color ~= nil and v.color.r ~= nil then
                isFlat = true
            end
            break
        end
        if isFlat then
            addon.db.profile.spells[addon.Class] = {}
            for k, v in pairs(data.spells) do
                addon.db.profile.spells[addon.Class][k] = v
            end
        else
            for k, v in pairs(data.spells) do
                addon.db.profile.spells[k] = v
            end
        end
    end
    if data.hideAnimations and type(data.hideAnimations) == "table" then
        addon.db.profile.hideAnimations.castbar = data.hideAnimations.castbar and true or false
        addon.hideAnimConfig.castbar = addon.db.profile.hideAnimations.castbar
    end

    addon:RebuildTables()
    return true
end

-- ─── New-entry scratch state ─────────────────────────────────────────────────
local newAura = {
    buffSpellID = "",
    anchorSpellID = "",
    r = 1,
    g = 1,
    b = 0,
    shouldShow = true
}

-- Scan BuffIconCooldownViewer for available buff/proc spell IDs
local function GetCDMBuffValues()
    local values = {}
    if BuffIconCooldownViewer and BuffIconCooldownViewer.itemFramePool then
        for aura in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
            if aura and aura.GetBaseSpellID then
                local spellID = aura:GetBaseSpellID()
                if spellID and spellID ~= 0 then
                    local name = SpellName(spellID)
                    local icon = C_Spell.GetSpellTexture(spellID)
                    local prefix = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
                    values[tostring(spellID)] = prefix .. name .. " (" .. spellID .. ")"
                end
            end
        end
    end
    if not next(values) then
        values[""] = "|cff888888No CDM buffs active|r"
    end
    return values
end
local newItem = {
    itemID = "",
    r = 0.5,
    g = 0.5,
    b = 1
}
local newSpell = {
    spellID = "",
    r = 0,
    g = 1,
    b = 0
}

-- ─── Options table ───────────────────────────────────────────────────────────
local function GetOptions()
    local options = {
        type = "group",
        name = "|cff009cffmuleyo's|r |cffffd100ProcGlows|r",
        childGroups = "tab",
        args = {
            -- ── Auras tab ────────────────────────────────────────────────
            auras = {
                type = "group",
                name = "Auras",
                order = 1,
                childGroups = "tree",
                args = {
                    description = {
                        type = "description",
                        name = "Configure buff/proc auras. Each aura watches for a buff spell ID and highlights the action button that holds the target spell.\n\n|cffff8800Note:|r Only buffs tracked by the CooldownManager can be monitored.\n",
                        order = 0,
                        fontSize = "medium"
                    },
                    -- ── Add new aura group ──
                    addNew = {
                        type = "group",
                        name = "|cff00ff00+ Add New Aura|r",
                        order = 1,
                        inline = true,
                        args = {
                            buffSpellID = {
                                type = "select",
                                name = "Buff / Proc",
                                desc = "Select a buff or proc currently tracked by the CooldownManager.",
                                order = 1,
                                width = "double",
                                values = function()
                                    return GetCDMBuffValues()
                                end,
                                get = function()
                                    return newAura.buffSpellID
                                end,
                                set = function(_, v)
                                    newAura.buffSpellID = v
                                end
                            },
                            anchorSpellID = {
                                type = "input",
                                name = "Target Spell ID",
                                desc = "The spell ID on your action bar that should glow.",
                                order = 2,
                                width = "normal",
                                get = function()
                                    return newAura.anchorSpellID
                                end,
                                set = function(_, v)
                                    newAura.anchorSpellID = v
                                end
                            },
                            color = {
                                type = "color",
                                name = "Glow Color",
                                order = 3,
                                hasAlpha = false,
                                get = function()
                                    return newAura.r, newAura.g, newAura.b
                                end,
                                set = function(_, r, g, b)
                                    newAura.r = r
                                    newAura.g = g
                                    newAura.b = b
                                end
                            },
                            shouldShow = {
                                type = "toggle",
                                name = "Show Aura Icon in CDM",
                                desc = "Whether to keep the aura icon visible. If unchecked, the icon will be hidden and only the glow is shown.",
                                order = 4,
                                get = function()
                                    return newAura.shouldShow
                                end,
                                set = function(_, v)
                                    newAura.shouldShow = v
                                end
                            },
                            add = {
                                type = "execute",
                                name = "Add Aura",
                                order = 5,
                                width = "normal",
                                func = function()
                                    local buffID = tonumber(newAura.buffSpellID)
                                    local anchorID = tonumber(newAura.anchorSpellID)
                                    if not buffID or buffID == 0 then
                                        print("|cffff0000[ProcGlows]|r Invalid buff spell ID.")
                                        return
                                    end
                                    if not anchorID or anchorID == 0 then
                                        print("|cffff0000[ProcGlows]|r Invalid target spell ID.")
                                        return
                                    end
                                    local key = tostring(buffID)
                                    addon.db.profile.auras[addon.Class] = addon.db.profile.auras[addon.Class] or {}
                                    addon.db.profile.auras[addon.Class][key] = {
                                        anchorSpellID = anchorID,
                                        color = {
                                            r = newAura.r,
                                            g = newAura.g,
                                            b = newAura.b
                                        },
                                        shouldShow = newAura.shouldShow
                                    }
                                    addon:RebuildTables()
                                    -- reset
                                    newAura.buffSpellID = ""
                                    newAura.anchorSpellID = ""
                                    newAura.r = 1;
                                    newAura.g = 1;
                                    newAura.b = 0
                                    newAura.shouldShow = false
                                    print(
                                        "|cff00ff00[ProcGlows]|r Aura added: " .. SpellName(buffID) .. " (" .. buffID ..
                                            ")")
                                end
                            }
                        }
                    }
                }
            },

            -- ── Items tab ────────────────────────────────────────────────
            items = {
                type = "group",
                name = "Items",
                order = 2,
                childGroups = "tree",
                args = {
                    description = {
                        type = "description",
                        name = "Configure usable-item highlights. When an item becomes usable, its action button will glow.\n",
                        order = 0,
                        fontSize = "medium"
                    },
                    addNew = {
                        type = "group",
                        name = "|cff00ff00+ Add New Item|r",
                        order = 1,
                        inline = true,
                        args = {
                            itemID = {
                                type = "input",
                                name = "Item ID",
                                desc = "The item ID to watch.",
                                order = 1,
                                width = "normal",
                                get = function()
                                    return newItem.itemID
                                end,
                                set = function(_, v)
                                    newItem.itemID = v
                                end
                            },
                            color = {
                                type = "color",
                                name = "Glow Color",
                                order = 2,
                                hasAlpha = false,
                                get = function()
                                    return newItem.r, newItem.g, newItem.b
                                end,
                                set = function(_, r, g, b)
                                    newItem.r = r
                                    newItem.g = g
                                    newItem.b = b
                                end
                            },
                            add = {
                                type = "execute",
                                name = "Add Item",
                                order = 3,
                                width = "normal",
                                func = function()
                                    local id = tonumber(newItem.itemID)
                                    if not id or id == 0 then
                                        print("|cffff0000[ProcGlows]|r Invalid item ID.")
                                        return
                                    end
                                    local key = tostring(id)
                                    addon.db.profile.items[key] = {
                                        color = {
                                            r = newItem.r,
                                            g = newItem.g,
                                            b = newItem.b
                                        }
                                    }
                                    addon:RebuildTables()
                                    newItem.itemID = ""
                                    newItem.r = 0.5;
                                    newItem.g = 0.5;
                                    newItem.b = 1
                                    print("|cff00ff00[ProcGlows]|r Item added: " .. ItemName(id) .. " (" .. id .. ")")
                                end
                            }
                        }
                    }
                }
            },
            -- ── Spells tab ───────────────────────────────────────────────
            spells = {
                type = "group",
                name = "Spells",
                order = 3,
                childGroups = "tree",
                args = {
                    description = {
                        type = "description",
                        name = "Configure spell cooldown highlights. When a spell is off cooldown and usable, its action button will glow.\n",
                        order = 0,
                        fontSize = "medium"
                    },
                    addNew = {
                        type = "group",
                        name = "|cff00ff00+ Add New Spell|r",
                        order = 1,
                        inline = true,
                        args = {
                            spellID = {
                                type = "input",
                                name = "Spell ID",
                                desc = "The spell ID to watch. The button holding this spell will glow when it is off cooldown.",
                                order = 1,
                                width = "normal",
                                get = function()
                                    return newSpell.spellID
                                end,
                                set = function(_, v)
                                    newSpell.spellID = v
                                end
                            },
                            color = {
                                type = "color",
                                name = "Glow Color",
                                order = 2,
                                hasAlpha = false,
                                get = function()
                                    return newSpell.r, newSpell.g, newSpell.b
                                end,
                                set = function(_, r, g, b)
                                    newSpell.r = r
                                    newSpell.g = g
                                    newSpell.b = b
                                end
                            },
                            add = {
                                type = "execute",
                                name = "Add Spell",
                                order = 3,
                                width = "normal",
                                func = function()
                                    local id = tonumber(newSpell.spellID)
                                    if not id or id == 0 then
                                        print("|cffff0000[ProcGlows]|r Invalid spell ID.")
                                        return
                                    end
                                    local key = tostring(id)
                                    addon.db.profile.spells[addon.Class] = addon.db.profile.spells[addon.Class] or {}
                                    addon.db.profile.spells[addon.Class][key] = {
                                        color = {
                                            r = newSpell.r,
                                            g = newSpell.g,
                                            b = newSpell.b
                                        }
                                    }
                                    addon:RebuildTables()
                                    newSpell.spellID = ""
                                    newSpell.r = 0;
                                    newSpell.g = 1;
                                    newSpell.b = 0
                                    print("|cff00ff00[ProcGlows]|r Spell added: " .. SpellName(id) .. " (" .. id .. ")")
                                end
                            }
                        }
                    }
                }
            },
            -- ── Import / Export tab ─────────────────────────────────────
            importExport = {
                type = "group",
                name = "Import / Export",
                order = 5,
                args = {
                    descExport = {
                        type = "description",
                        name = "Copy the string below to share your settings with others, or paste an import string and click Import to load settings.\n",
                        order = 0,
                        fontSize = "medium"
                    },
                    generateExport = {
                        type = "execute",
                        name = "Generate Export String",
                        order = 1,
                        width = "normal",
                        func = function()
                            importExportState.exportString = ExportProfile()
                            -- refresh UI
                            local AceConfigReg = LibStub("AceConfigRegistry-3.0")
                            AceConfigReg:NotifyChange(addonName)
                            -- Scroll the export editbox back to the top after the UI rebuilds
                            C_Timer.After(0, function()
                                local openDialog =
                                    AceConfigDialog.OpenFrames[addonName] or AceConfigDialog.BlizOptions and
                                        AceConfigDialog.BlizOptions[addonName]
                                if openDialog then
                                    local status = openDialog:GetUserData("status") or openDialog.status
                                    -- Walk child widgets to find the export MultiLineEditBox
                                    if openDialog.children then
                                        for _, child in ipairs(openDialog.children) do
                                            if child.children then
                                                for _, w in ipairs(child.children) do
                                                    if w.type == "MultiLineEditBox" and w.editBox then
                                                        local eb = w.editBox
                                                        eb:SetCursorPosition(0)
                                                        eb:HighlightText(0, -1)
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end)
                            print("|cff00ff00[ProcGlows]|r Export string generated — copy it from the text box.")
                        end
                    },
                    exportBox = {
                        type = "input",
                        name = "Export String",
                        order = 2,
                        multiline = 6,
                        width = "full",
                        get = function()
                            return importExportState.exportString
                        end,
                        set = function()
                        end -- read-only
                    },
                    spacer = {
                        type = "description",
                        name = "\n",
                        order = 3,
                        width = "full"
                    },
                    importBox = {
                        type = "input",
                        name = "Import String",
                        order = 4,
                        multiline = 6,
                        width = "full",
                        get = function()
                            return importExportState.importString
                        end,
                        set = function(_, v)
                            importExportState.importString = v
                        end
                    },
                    importBtn = {
                        type = "execute",
                        name = "Import",
                        order = 5,
                        width = "normal",
                        confirm = true,
                        confirmText = "Importing will overwrite your current auras, items, spells, and animation settings. Continue?",
                        func = function()
                            local ok, err = ImportProfile(importExportState.importString)
                            if ok then
                                importExportState.importString = ""
                                local AceConfigReg = LibStub("AceConfigRegistry-3.0")
                                AceConfigReg:NotifyChange(addonName)
                                print("|cff00ff00[ProcGlows]|r Settings imported successfully.")
                            else
                                print("|cffff0000[ProcGlows]|r Import failed: " .. (err or "unknown error"))
                            end
                        end
                    }
                }
            },
            -- ── Animations tab ───────────────────────────────────────────
            animations = {
                type = "group",
                name = "Action Bar Animations",
                order = 4,
                args = {
                    description = {
                        type = "description",
                        name = "Toggle Blizzard action-bar overlay animations.\n",
                        order = 0,
                        fontSize = "medium"
                    },
                    castbar = {
                        type = "toggle",
                        name = "Hide Cast Animations",
                        desc = "Hide the spell-cast / interrupt / reticle animations on action buttons.\n\n|cffff8800Note:|r Enabling/Disabling requires a reload of the UI to take effect.",
                        order = 1,
                        width = "full",
                        get = function()
                            return addon.db.profile.hideAnimations.castbar
                        end,
                        set = function(_, v)
                            addon.db.profile.hideAnimations.castbar = v
                            addon.hideAnimConfig.castbar = v
                        end
                    }
                }
            },
            -- ── Profiles tab ─────────────────────────────────────────────
            profiles = AceDBOptions:GetOptionsTable(addon.db)
        }
    }
    options.args.profiles.order = 6

    -- ── Inject existing aura entries dynamically (grouped by class) ────────
    for _, classInfo in ipairs(CLASS_INFO) do
        local classToken = classInfo.token
        local classAuras = addon.db.profile.auras[classToken]
        local hasEntries = classAuras and next(classAuras)

        if hasEntries or classToken == addon.Class then
            local classGroup = {
                type = "group",
                name = "|cff" .. classInfo.color .. classInfo.name .. "|r",
                order = classToken == addon.Class and 2 or (10 + ClassOrder(classToken)),
                args = {}
            }

            if classAuras then
                local entryOrder = 1
                for key, entry in pairs(classAuras) do
                    local buffID = tonumber(key)
                    local icon = C_Spell.GetSpellTexture(buffID)
                    local iconStr = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
                    local label = iconStr .. SpellName(buffID) .. " (" .. key .. ")"

                    classGroup.args["aura_" .. key] = {
                        type = "group",
                        name = label,
                        order = entryOrder,
                        args = {
                            buffSpellID = {
                                type = "description",
                                name = "|cffffffffBuff Spell ID:|r " .. key,
                                order = 1,
                                fontSize = "medium"
                            },
                            anchorSpellID = {
                                type = "input",
                                name = "Target Spell ID",
                                order = 2,
                                width = "normal",
                                get = function()
                                    return tostring(entry.anchorSpellID or "")
                                end,
                                set = function(_, v)
                                    local id = tonumber(v)
                                    if id then
                                        entry.anchorSpellID = id
                                        addon:RebuildTables()
                                    end
                                end
                            },
                            color = {
                                type = "color",
                                name = "Glow Color",
                                order = 3,
                                hasAlpha = false,
                                get = function()
                                    return entry.color.r, entry.color.g, entry.color.b
                                end,
                                set = function(_, r, g, b)
                                    entry.color.r = r
                                    entry.color.g = g
                                    entry.color.b = b
                                    addon:RebuildTables()
                                end
                            },
                            shouldShow = {
                                type = "toggle",
                                name = "Show Aura Icon in CDM",
                                order = 4,
                                get = function()
                                    return entry.shouldShow
                                end,
                                set = function(_, v)
                                    entry.shouldShow = v
                                    addon:RebuildTables()
                                end
                            },
                            spacer = {
                                type = "description",
                                name = "",
                                order = 9,
                                width = "full"
                            },
                            remove = {
                                type = "execute",
                                name = "|cffff4444Remove|r",
                                order = 10,
                                width = "normal",
                                confirm = true,
                                confirmText = "Remove aura " .. label .. "?",
                                func = function()
                                    addon.db.profile.auras[classToken][key] = nil
                                    if not next(addon.db.profile.auras[classToken]) then
                                        addon.db.profile.auras[classToken] = nil
                                    end
                                    addon:RebuildTables()
                                    AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                                    AceConfigRegistry:NotifyChange(addonName)
                                    print("|cffff8800[ProcGlows]|r Aura removed: " .. label)
                                end
                            }
                        }
                    }
                    entryOrder = entryOrder + 1
                end
            end

            options.args.auras.args["class_" .. classToken] = classGroup
        end
    end

    -- ── Inject existing item entries dynamically ─────────────────────────────
    local itemOrder = 100
    for key, entry in pairs(addon.db.profile.items) do
        local id = tonumber(key)
        local icon = C_Item.GetItemIconByID(id)
        local iconStr = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
        local label = iconStr .. ItemName(id) .. " (" .. key .. ")"

        options.args.items.args["item_" .. key] = {
            type = "group",
            name = label,
            order = itemOrder,
            args = {
                itemID = {
                    type = "description",
                    name = "|cffffffffItem ID:|r " .. key,
                    order = 1,
                    fontSize = "medium"
                },
                color = {
                    type = "color",
                    name = "Glow Color",
                    order = 2,
                    hasAlpha = false,
                    get = function()
                        return entry.color.r, entry.color.g, entry.color.b
                    end,
                    set = function(_, r, g, b)
                        entry.color.r = r
                        entry.color.g = g
                        entry.color.b = b
                        addon:RebuildTables()
                    end
                },
                spacer = {
                    type = "description",
                    name = "",
                    order = 9,
                    width = "full"
                },
                remove = {
                    type = "execute",
                    name = "|cffff4444Remove|r",
                    order = 10,
                    width = "normal",
                    confirm = true,
                    confirmText = "Remove item " .. label .. "?",
                    func = function()
                        addon.db.profile.items[key] = nil
                        addon:RebuildTables()
                        AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                        AceConfigRegistry:NotifyChange(addonName)
                        print("|cffff8800[ProcGlows]|r Item removed: " .. label)
                    end
                }
            }
        }
        itemOrder = itemOrder + 1
    end

    -- ── Inject existing spell entries dynamically (grouped by class) ───────
    for _, classInfo in ipairs(CLASS_INFO) do
        local classToken = classInfo.token
        local classSpells = addon.db.profile.spells[classToken]
        local hasEntries = classSpells and next(classSpells)

        if hasEntries or classToken == addon.Class then
            local classGroup = {
                type = "group",
                name = "|cff" .. classInfo.color .. classInfo.name .. "|r",
                order = classToken == addon.Class and 2 or (10 + ClassOrder(classToken)),
                args = {}
            }

            if classSpells then
                local entryOrder = 1
                for key, entry in pairs(classSpells) do
                    local sid = tonumber(key)
                    local icon = C_Spell.GetSpellTexture(sid)
                    local iconStr = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
                    local label = iconStr .. SpellName(sid) .. " (" .. key .. ")"

                    classGroup.args["spell_" .. key] = {
                        type = "group",
                        name = label,
                        order = entryOrder,
                        args = {
                            spellID = {
                                type = "description",
                                name = "|cffffffffSpell ID:|r " .. key,
                                order = 1,
                                fontSize = "medium"
                            },
                            color = {
                                type = "color",
                                name = "Glow Color",
                                order = 2,
                                hasAlpha = false,
                                get = function()
                                    return entry.color.r, entry.color.g, entry.color.b
                                end,
                                set = function(_, r, g, b)
                                    entry.color.r = r
                                    entry.color.g = g
                                    entry.color.b = b
                                    addon:RebuildTables()
                                end
                            },
                            spacer = {
                                type = "description",
                                name = "",
                                order = 9,
                                width = "full"
                            },
                            remove = {
                                type = "execute",
                                name = "|cffff4444Remove|r",
                                order = 10,
                                width = "normal",
                                confirm = true,
                                confirmText = "Remove spell " .. label .. "?",
                                func = function()
                                    addon.db.profile.spells[classToken][key] = nil
                                    if not next(addon.db.profile.spells[classToken]) then
                                        addon.db.profile.spells[classToken] = nil
                                    end
                                    addon:RebuildTables()
                                    AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                                    AceConfigRegistry:NotifyChange(addonName)
                                    print("|cffff8800[ProcGlows]|r Spell removed: " .. label)
                                end
                            }
                        }
                    }
                    entryOrder = entryOrder + 1
                end
            end

            options.args.spells.args["class_" .. classToken] = classGroup
        end
    end

    return options
end

-- ─── Initialization ──────────────────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    -- Init DB
    addon.db = AceDB:New("muleyoProcGlowDB", defaults, true)

    -- Rebuild tables when profile changes
    addon.db.RegisterCallback(addon, "OnProfileChanged", function()
        addon.hideAnimConfig.castbar = addon.db.profile.hideAnimations.castbar
        addon:RebuildTables()
    end)
    addon.db.RegisterCallback(addon, "OnProfileCopied", function()
        addon.hideAnimConfig.castbar = addon.db.profile.hideAnimations.castbar
        addon:RebuildTables()
    end)
    addon.db.RegisterCallback(addon, "OnProfileReset", function()
        addon.hideAnimConfig.castbar = addon.db.profile.hideAnimations.castbar
        addon:RebuildTables()
    end)

    -- ── Migrate old flat auras/spells to nested-by-class format ──────────────
    local function MigrateFlat(tbl, classToken)
        local isFlat = false
        for k, v in pairs(tbl) do
            if type(v) == "table" and (v.anchorSpellID ~= nil or (v.color and v.color.r ~= nil)) then
                isFlat = true
                break
            end
        end
        if isFlat then
            local old = {}
            for k, v in pairs(tbl) do
                old[k] = v
            end
            wipe(tbl)
            tbl[classToken] = old
        end
    end
    MigrateFlat(addon.db.profile.auras, addon.Class)
    MigrateFlat(addon.db.profile.spells, addon.Class)

    if next(addon.db.profile.items) == nil then
        local itemDefaults = addon:GetItemDefaults()
        if itemDefaults then
            for k, v in pairs(itemDefaults) do
                addon.db.profile.items[tostring(k)] = v
            end
        end
    end

    -- Push saved animation settings to Hide_AB_Animations
    addon.hideAnimConfig.castbar = addon.db.profile.hideAnimations.castbar

    -- Build runtime tables
    addon:RebuildTables()

    -- Register options (use callback so dynamic entries refresh)
    AceConfig:RegisterOptionsTable(addonName, function()
        return GetOptions()
    end)
    AceConfigDialog:AddToBlizOptions(addonName, "ProcGlows")

    -- ── Support / Donate button on the config dialog ──────────────────────
    local DONATE_URL = "https://pay.muleyo.dev/?donation=true"

    -- Static popup to show the donation URL for copy-paste
    StaticPopupDialogs["PROCGLOWS_DONATE"] = {
        text = "Thank you for supporting ProcGlows!\n\nCopy the link below:",
        button1 = "Close",
        hasEditBox = true,
        editBoxWidth = 260,
        OnShow = function(self)
            self.EditBox:SetText(DONATE_URL)
            self.EditBox:HighlightText()
            self.EditBox:SetAutoFocus(true)
            self.EditBox:SetScript("OnKeyDown", function(editBox, key)
                if (IsControlKeyDown() or IsMetaKeyDown()) and key == "C" then
                    C_Timer.After(0, function()
                        self:Hide()
                    end)
                end
            end)
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    -- Hook AceConfigDialog:Open to attach the Support button
    hooksecurefunc(AceConfigDialog, "Open", function(_, appName)
        if appName ~= addonName then
            return
        end
        local frame = AceConfigDialog.OpenFrames[addonName]
        if not frame or frame.procGlowsSupportBtn then
            return
        end

        local btn = CreateFrame("Button", nil, frame.frame, "UIPanelButtonTemplate")
        btn:SetSize(100, 22)
        btn:SetPoint("TOPRIGHT", frame.frame, "TOPRIGHT", -25, -12)
        btn:SetFrameStrata("TOOLTIP")
        btn:SetFrameLevel(frame.frame:GetFrameLevel() + 10)
        btn:SetText("Donate")
        btn:SetScript("OnClick", function()
            StaticPopup_Show("PROCGLOWS_DONATE")
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Support Development", 1, 1, 1)
            GameTooltip:AddLine("Opens a link you can copy to donate.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        frame.procGlowsSupportBtn = btn
    end)

    -- Slash command
    SLASH_MULEYOPG1 = "/pg"
    SLASH_MULEYOPG2 = "/procglows"
    SlashCmdList["MULEYOPG"] = function()
        AceConfigDialog:Open(addonName)
        -- Auto-expand the current class group in the Auras tab
        AceConfigDialog:SelectGroup(addonName, "auras", "class_" .. addon.Class)
    end

    print("|cff009cffmuleyo's|r |cffffd100ProcGlows|r loaded — type |cff00ff00/pg|r to open config.")
end)
