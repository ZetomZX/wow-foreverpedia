local root = ...

local frames = {}
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    frames[#frames + 1] = frame
    return frame
end

local sent = {}
local registeredPrefix
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        registeredPrefix = prefix
        return true
    end,
    SendAddonMessage = function(prefix, message, distribution, target)
        sent[#sent + 1] = {
            prefix = prefix,
            message = message,
            distribution = distribution,
            target = target,
        }
        return true
    end,
}
C_AddOns = {
    GetAddOnMetadata = function(addon, field)
        assert(addon == "Foreverpedia" and field == "Version")
        return "0.9.3"
    end,
}

local deferred = {}
C_Timer = {
    After = function(_, callback) deferred[#deferred + 1] = callback end,
}
GetTime = function() return 100 end
UnitName = function() return "LocalPlayer" end
Ambiguate = function(sender) return sender:match("^[^-]+") end
IsInGuild = function() return true end
IsInGroup = function() return true end
IsInRaid = function() return false end

local printed = {}
print = function(message) printed[#printed + 1] = message end
ForeverpediaDB = { language = "enUS", languageMode = "manual" }

local availableUpdate
local namespace = {
    UI = {
        SetAvailableUpdate = function(_, version) availableUpdate = version end,
    },
}
assert(loadfile(root .. "/Foreverpedia/Util.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Localization.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/VersionExchange.lua"))("Foreverpedia", namespace)

assert(namespace.VersionExchange:Initialize())
assert(registeredPrefix == "Foreverpedia")
assert(#frames == 1 and frames[1].events.CHAT_MSG_ADDON)
assert(#deferred == 1)
deferred[1]()
assert(#sent == 2, "login announcement should use guild and party")
assert(sent[1].message == "V\t0.9.3")

namespace.VersionExchange:HandleMessage(
    "Foreverpedia", "V\t0.9.4", "GUILD", "NewerPlayer-Realm")
assert(#printed == 1)
assert(printed[1]:find("0.9.3", 1, true))
assert(printed[1]:find("0.9.4", 1, true))
assert(availableUpdate == "0.9.4")

namespace.VersionExchange:HandleMessage(
    "Foreverpedia", "V\t0.9.5", "PARTY", "AnotherPlayer-Realm")
assert(#printed == 1, "update warning must appear once per session")
assert(availableUpdate == "0.9.5", "the banner should track the newest version")

namespace.VersionExchange:HandleMessage(
    "Foreverpedia", "V\t0.9.1", "GUILD", "OlderPlayer-Realm")
assert(#sent == 3)
assert(sent[3].distribution == "WHISPER")
assert(sent[3].target == "OlderPlayer-Realm")
assert(sent[3].message == "V\t0.9.3")

namespace.VersionExchange:HandleMessage(
    "Foreverpedia", "V\t0.9.1", "GUILD", "OlderPlayer-Realm")
assert(#sent == 3, "the same older sender should receive only one reply")

namespace.VersionExchange:HandleMessage(
    "Foreverpedia", "V\t999", "GUILD", "InvalidPlayer-Realm")
assert(#printed == 1 and #sent == 3, "invalid versions must be ignored")

