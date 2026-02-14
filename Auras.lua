local _, addon = ...

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
