local root = ...
unpack = unpack or table.unpack

CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:SetHeight() end
    function frame:SetWidth() end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:Show() end
    function frame:CreateFontString()
        return {
            SetAllPoints = function() end,
            SetJustifyH = function() end,
            SetText = function() end,
        }
    end
    function frame:CreateTexture()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
        }
    end
    return frame
end

local callbacks = {}
C_Timer = {
    After = function(_, callback) callbacks[#callbacks + 1] = callback end,
}

local mapShown, mapOnHide = false, nil
WorldMapFrame = {
    IsShown = function() return mapShown end,
    SetMapID = function() error("SetMapID must not run in Gamepad UI") end,
    Raise = function() end,
    HookScript = function(_, kind, callback)
        assert(kind == "OnHide")
        mapOnHide = callback
    end,
}
ToggleWorldMap = function() error("OpenWorldMap must be preferred") end
C_Map = {
    OpenWorldMap = function(mapID)
        assert(mapID == 12)
        mapShown = true
        return true
    end,
    GetMapInfo = function(mapID)
        return mapID == 12 and { name = "Test Zone", mapType = 3 } or nil
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function() end,
}
UiMapPoint = { CreateFromCoordinates = function() return {} end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }

local focusCount = 0
local namespace = {
    L = function(key, ...)
        local value = key == "coordinates" and "Coordinates: %.1f, %.1f" or key
        if select("#", ...) > 0 then return string.format(value, ...) end
        return value
    end,
    Theme = {
        colors = {
            gold = { 1, 0.8, 0.2 },
            muted = { 0.7, 0.7, 0.7 },
            normal = { 1, 1, 1 },
        },
        SetBackdrop = function() end,
    },
    Gamepad = {
        IsLayoutActive = function() return true end,
        OnWindowOpened = function() focusCount = focusCount + 1 end,
    },
}

assert(loadfile(root .. "/Foreverpedia/UI.lua"))("Foreverpedia", namespace)
local ui = namespace.UI
local showCount, hideCount = 0, 0
local content = {
    usedButtons = 0,
    buttons = {},
    GetWidth = function() return 400 end,
}
ui.frame = {
    IsShown = function() return true end,
    Show = function() showCount = showCount + 1 end,
    Hide = function() hideCount = hideCount + 1 end,
    Raise = function() end,
    details = { content = content },
}
ui.detailCursorY = 0

ui:DetailCoordinateButton({ areaID = 12, x = 25, y = 50, zone = "Test Zone" })
content.buttons[1].scripts.OnClick()
assert(hideCount == 1, "Foreverpedia must hide while the map is open")
assert(mapOnHide, "the map close hook must be installed")

mapShown = false
mapOnHide()
assert(showCount == 0,
    "Foreverpedia must not reopen inside Blizzard's protected map OnHide chain")

for _, callback in ipairs(callbacks) do callback() end
assert(showCount == 1, "Foreverpedia must reopen on the next frame")
assert(focusCount == 1, "Foreverpedia must restore its own focus after the map closes")

print("UI deferred map reopen spec: OK")
