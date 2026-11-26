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

local secureHooks = {}
hooksecurefunc = function(name, callback)
    assert(name == "HandleModifiedItemClick" or name == "SetItemRef")
    secureHooks[name] = callback
end
HandleModifiedItemClick = function() end
SetItemRef = function() end

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
assert(type(secureHooks.HandleModifiedItemClick) == "function")
assert(type(secureHooks.SetItemRef) == "function")
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

secureHooks.HandleModifiedItemClick("|Hitem:2589|h[Льняной материал]|h")
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

local itemPayload = "item:2589::::::::"
local itemText = "|cff9d9d9d|H" .. itemPayload .. "|h[Linen Cloth]|h|r"
local itemRefHook = secureHooks.SetItemRef
itemRefHook(itemPayload, itemText, "LeftButton")
assert(#deferred == 0, "ordinary chat item clicks must be ignored")

altDown = true
itemRefHook(itemPayload, itemText, "RightButton")
itemRefHook("player:Example", "|Hplayer:Example|h[Example]|h", "LeftButton")
assert(#deferred == 0, "right clicks and non-item chat links must be ignored")

itemRefHook(itemPayload, itemText, "LeftButton")
assert(#opened == 2, "opening must be deferred outside Blizzard's click path")
runDeferred()
assert(#opened == 3, "Alt-left chat clicks must open even without HandleModifiedItemClick")
assert(opened[3].itemID == 2589 and opened[3].link == itemText)

now = 11.2
itemRefHook("item:2592::::::::", "[Wool Cloth]", "LeftButton")
runDeferred()
assert(#opened == 4 and opened[4].itemID == 2592, "the raw payload must work without full link text")

now = 11.5
secureHooks.HandleModifiedItemClick(itemText)
itemRefHook(itemPayload, itemText, "LeftButton")
runDeferred()
assert(#opened == 5, "a click dispatched through both hooks must open exactly once")

now = 11.8
secureHooks.HandleModifiedItemClick(itemText)
runDeferred()
assert(#opened == 6, "the standalone modified item click path must still open")

print("Core chat and profession click spec: OK")
