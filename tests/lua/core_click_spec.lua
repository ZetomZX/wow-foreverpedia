local root = ...

local frames = {}
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
        return true
    end
    function frame:SetScript(kind, callback)
        self.scripts[kind] = callback
    end
    frames[#frames + 1] = frame
    return frame
end

local modifiedHook
hooksecurefunc = function(name, callback)
    assert(name == "HandleModifiedItemClick")
    modifiedHook = callback
end
HandleModifiedItemClick = function() end

local altDown = true
IsAltKeyDown = function() return altDown end
local now = 10
GetTime = function() return now end
GetBuildInfo = function() return nil, nil, nil, 16001 end
SlashCmdList = {}

local deferred = {}
C_Timer = {
    After = function(_, callback)
        deferred[#deferred + 1] = callback
    end,
}
local function runDeferred()
    local callbacks = deferred
    deferred = {}
    for _, callback in ipairs(callbacks) do callback() end
end

local ownerHovered = true
ProfessionsFrame = {}
local tooltipPostCall
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, callback)
        assert(kind == Enum.TooltipDataType.Item)
        tooltipPostCall = callback
    end,
}
local owner = {
    IsMouseOver = function() return ownerHovered end,
    GetParent = function() return ProfessionsFrame end,
}
GameTooltip = {
    lines = {},
    IsShown = function() return true end,
    GetOwner = function() return owner end,
    GetItem = function() return "Льняной материал", "|cff9d9d9d|Hitem:2589::::::::|h[Льняной материал]|h|r" end,
    AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
    NumLines = function(self) return #self.lines end,
    Show = function() end,
}

local bagButton = {
    buttonContext = "ButtonContext_ContainerFrameItemButton",
    GetBagID = function() return 0 end,
    GetID = function() return 4 end,
}
C_Container = {
    GetContainerItemInfo = function(bagID, slotID)
        assert(bagID == 0 and slotID == 4)
        return {
            itemID = 2589,
            hyperlink = "|cff9d9d9d|Hitem:2589::::::::|h[Льняной материал]|h|r",
        }
    end,
}

ForeverpediaDB = nil
local opened = {}
local searchOpenCount = 0
local namespace = {
    DataProvider = {
        Initialize = function() return true end,
        GetItemID = function(_, value)
            return tonumber(tostring(value):match("item:(%d+)")) or tonumber(value)
        end,
    },
    UI = {
        OpenSearch = function()
            searchOpenCount = searchOpenCount + 1
        end,
        OpenItem = function(_, link, itemID)
            opened[#opened + 1] = { link = link, itemID = itemID }
        end,
    },
}

assert(loadfile(root .. "/Foreverpedia/Config.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Util.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Localization.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Storage.lua"))("Foreverpedia", namespace)
local core = assert(loadfile(root .. "/Foreverpedia/Core.lua"))
core("Foreverpedia", namespace)
assert(#frames == 2)
assert(frames[1].events.ADDON_LOADED)
frames[1].scripts.OnEvent(frames[1], "ADDON_LOADED", "Foreverpedia")
assert(ForeverpediaDB.craftTreeEnabled == nil)
assert(type(tooltipPostCall) == "function")
assert(type(SlashCmdList.FOREVERPEDIA) == "function")
SlashCmdList.FOREVERPEDIA("")
assert(searchOpenCount == 1, "/fp without arguments must open manual search")

tooltipPostCall(GameTooltip)
assert(GameTooltip.lines[#GameTooltip.lines] == namespace.L("alt_open"))
local tooltipLineCount = #GameTooltip.lines
tooltipPostCall(GameTooltip)
assert(#GameTooltip.lines == tooltipLineCount, "tooltip hint must not be duplicated")

assert(frames[2].events.GLOBAL_MOUSE_DOWN)
assert(type(frames[2].scripts.OnEvent) == "function")
frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#opened == 0, "opening must be deferred outside Blizzard's input path")
runDeferred()
assert(#opened == 1)
assert(opened[1].itemID == 2589)

frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "RightButton")
assert(#opened == 1)

modifiedHook("|Hitem:2589|h[Льняной материал]|h")
runDeferred()
assert(#opened == 1, "the mouse and modified-click paths must be debounced")

now = 10.3
ownerHovered = false
frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#opened == 1, "a stale tooltip whose owner is not hovered must be ignored")

ownerHovered = true
frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "LeftButton")
runDeferred()
assert(#opened == 2)

owner.GetParent = function() return nil end
now = 10.6
frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "LeftButton")
runDeferred()
assert(#opened == 2, "merchant and other non-profession tooltips must be ignored")

altDown = false
now = 10.9
frames[2].scripts.OnEvent(frames[2], "GLOBAL_MOUSE_DOWN", "LeftButton")
runDeferred()
assert(#opened == 2)

print("Core profession reagent click spec: OK")
