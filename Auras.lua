local _, addon = ...

-- Default aura entries per class (used to seed the DB on first run)
function addon:GetClassAuraDefaults(class)
    return nil
end

-- Default item entries (used to seed the DB on first run)
function addon:GetItemDefaults()
    return {
        ["188152"] = {
            color = {
                r = 0.5,
                g = 0.5,
                b = 1
            }
        }
    }
end
