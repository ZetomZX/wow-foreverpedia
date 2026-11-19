local root = ...

local onUpdate
CreateFrame = function()
    return {
        SetScript = function(_, kind, callback)
            if kind == "OnUpdate" then onUpdate = callback end
        end,
    }
end
UIParent = {}
GameTooltip = nil
TooltipDataProcessor = nil
Enum = nil

local namespace = {
    L = function(key) return key end,
    Config = {
        gamepadHoldDuration = 0.70,
        gamepadHoldShowAfter = 0.15,
        gamepadTooltipMemory = 1.50,
    },
    Theme = {
        colors = { panel = { 0, 0, 0, 1 } },
        SetBackdrop = function() end,
    },
    UI = {},
}

assert(loadfile(root .. "/Foreverpedia/Gamepad.lua"))("Foreverpedia", namespace)
assert(type(namespace.Gamepad) == "table")
assert(not namespace.Gamepad:IsLayoutActive())
assert(type(onUpdate) == "function")

local reagentButton = {
    GetElementData = function()
        return {
            reagentSlotSchematic = {
                reagents = { { itemID = 2589 } },
            },
        }
    end,
}
assert(namespace.Gamepad:ResolveFrameItem(reagentButton) == 2589,
    "profession reagent slots must resolve their reagent item")

local outputButton = {
    GetElementData = function()
        return { recipeInfo = { recipeID = 77 } }
    end,
}
C_TradeSkillUI = {
    GetRecipeOutputItemData = function(recipeID)
        assert(recipeID == 77)
        return { itemID = 4242 }
    end,
}
assert(namespace.Gamepad:ResolveFrameItem(outputButton) == 4242,
    "profession recipe buttons must still resolve their output item")

local keyDown = true
local now = 1
local deferred
local opened
local nativeTapCalls = 0
Enum = {
    InputDeviceInterfaceType = { Gamepad = 1 },
}
C_InputInterfaceStyle = {
    GetCurrentStyle = function() return Enum.InputDeviceInterfaceType.Gamepad end,
}
IsKeyDown = function(key) return key == "PADRSTICK" and keyDown end
GetTime = function() return now end
SmartNavigation = {
    GetCurrentButton = function()
        return {
            GetBagID = function() return nil end,
            GetID = function() return 4 end,
            GetElementData = function()
                return { recipeInfo = { recipeID = 77 } }
            end,
        }
    end,
}
C_Container = {
    GetContainerItemLink = function()
        error("profession controls with a nil bag ID must not be queried as bags")
    end,
}
GameTooltip = {
    IsShown = function() return true end,
    GetItem = function()
        return "Огненный снеппер", "|Hitem:6291|h[Огненный снеппер]|h"
    end,
}
C_Timer = {
    After = function(delay, callback)
        assert(delay == 0)
        deferred = callback
    end,
}
namespace.UI.OpenItem = function(_, link, id)
    opened = { link = link, id = id }
end

assert(namespace.Gamepad:DeferNativeR3Tap(function()
    nativeTapCalls = nativeTapCalls + 1
end), "the profession R3 tap must be deferred while an item can be opened")
onUpdate()
now = 1.8
onUpdate()
assert(not opened and not deferred,
    "a completed hold must not open UI while R3 is still held")
keyDown = false
onUpdate()
assert(not opened and type(deferred) == "function",
    "opening must be deferred until after R3 is released")
deferred()
assert(opened and opened.id == 6291,
    "the visible profession reagent tooltip must win over recipe-output metadata")
assert(nativeTapCalls == 0,
    "a completed Foreverpedia hold must consume the native Set Amount tap")

opened, deferred = nil, nil
keyDown, now = true, 2
assert(namespace.Gamepad:DeferNativeR3Tap(function()
    nativeTapCalls = nativeTapCalls + 1
end))
onUpdate()
now = 2.05
keyDown = false
onUpdate()
assert(not opened and nativeTapCalls == 0 and type(deferred) == "function",
    "a short profession R3 press must wait until button-up")
deferred()
assert(nativeTapCalls == 1 and not opened,
    "a short profession R3 press must keep Blizzard's Set Amount action")

assert(loadfile(root .. "/Foreverpedia/GamepadNavigation.lua"))(
    "Foreverpedia", namespace)
assert(type(namespace.Gamepad.FocusWindow) == "function")
assert(type(namespace.Gamepad.Move) == "function")
assert(type(namespace.Gamepad.OnWindowOpened) == "function")

print("Gamepad runtime module load spec: OK")
