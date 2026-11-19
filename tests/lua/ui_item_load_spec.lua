local root = ...
unpack = unpack or table.unpack

local itemLoadFrame
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(kind, callback)
        self.scripts[kind] = callback
    end
    itemLoadFrame = itemLoadFrame or frame
    return frame
end

local tooltip = { lines = {}, shown = false }
GameTooltip = {
    SetOwner = function(_, owner) tooltip.owner = owner end,
    ClearLines = function() tooltip.lines = {} end,
    AddLine = function(_, value) tooltip.lines[#tooltip.lines + 1] = value end,
    SetHyperlink = function(_, value) tooltip.hyperlink = value end,
    Show = function() tooltip.shown = true end,
    Hide = function() tooltip.shown = false end,
    IsShown = function() return tooltip.shown end,
}

C_Item = {
    GetItemInfo = function() return nil end,
    GetItemIconByID = function(itemID)
        assert(itemID == 234006)
        return 1294913
    end,
}

local displayed = {}
local namespace = {
    L = function(key, ...)
        local values = {
            item_number = "Item #%d",
            loading_item = "Loading item data…",
            item_not_found = "Item not found in the database.",
            item_id = "Item ID: %d",
            footer = "ID %d / %s / %d / %d",
        }
        local value = values[key] or key
        if select("#", ...) > 0 then return string.format(value, ...) end
        return value
    end,
    GetItemName = function(itemID) return string.format("Item #%d", itemID) end,
    Theme = {
        colors = {
            gold = { 1, 0.8, 0.2 },
            muted = { 0.7, 0.7, 0.7 },
            normal = { 1, 1, 1 },
        },
        SetBackdrop = function() end,
    },
    DataProvider = {
        Get = function()
            return { sources = {}, uses = {} }
        end,
        GetManifest = function()
            return { dataset = "test" }
        end,
    },
}

assert(loadfile(root .. "/Foreverpedia/UI.lua"))("Foreverpedia", namespace)
local ui = namespace.UI
ui.currentItemID = 234006
ui.currentItemLink = "item:234006"
ui.frame = {
    IsShown = function() return true end,
    itemIcon = { SetTexture = function(_, value) displayed.icon = value end },
    itemName = {
        SetText = function(_, value) displayed.name = value end,
        SetTextColor = function() end,
    },
    itemMeta = { SetText = function(_, value) displayed.meta = value end },
    content = { SetHeight = function() end },
    footer = { SetText = function() end },
}
ui.UpdateCraftTreeButton = function() end
ui.ClearLines = function(self) self.cursorY = 0 end
ui.AddCategorizedSection = function() end

ui:Render()
assert(displayed.icon == 1294913, "the standalone item icon must be used while full data loads")
assert(displayed.meta == "Loading item data…")

assert(itemLoadFrame.events.GET_ITEM_INFO_RECEIVED)
itemLoadFrame.scripts.OnEvent(itemLoadFrame, "GET_ITEM_INFO_RECEIVED", 234006, false)
assert(displayed.icon == 1294913, "a failed item load must preserve the available icon")
assert(displayed.meta == "Item not found in the database.",
    "a failed item load must not remain in the loading state")

tooltip.hyperlink = nil
ui:ShowItemTooltip({}, 234006)
assert(not tooltip.hyperlink, "a known missing item must not invoke Blizzard's item hyperlink")
assert(tooltip.lines[2] == "Item not found in the database.")
assert(tooltip.lines[3] == "Item ID: 234006")
ui:HideItemTooltip()

itemLoadFrame.scripts.OnEvent(itemLoadFrame, "GET_ITEM_INFO_RECEIVED", 234006, true)
assert(displayed.meta == "Loading item data…",
    "a later successful notification must clear the previous failure")

