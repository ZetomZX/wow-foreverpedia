local addonName, ns = ...
local L = ns.L

local VersionExchange = {}
ns.VersionExchange = VersionExchange

local PREFIX = "Foreverpedia"
local MESSAGE_TAG = "V"
local ANNOUNCE_DELAY = 2
local SEND_THROTTLE = 30

local frame
local initialized = false
local prefixRegistered = false
local announcePending = false
local updateNotified = false
local newestSeenVersion
local lastSent = {}
local repliedTo = {}

local function chatInfoMethod(name)
    local chatInfo = rawget(_G, "C_ChatInfo")
    if type(chatInfo) == "table" and type(chatInfo[name]) == "function" then
        return chatInfo[name]
    end
    return rawget(_G, name)
end

local function metadata(field)
    local addons = rawget(_G, "C_AddOns")
    local getter = type(addons) == "table" and addons.GetAddOnMetadata
        or rawget(_G, "GetAddOnMetadata")
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, addonName, field)
    if ok then return value end
    return nil
end

local function validVersion(version)
    return type(version) == "string"
        and #version <= 32
        and version:match("^%d+%.%d+%.%d+[%w%._%-]*$") ~= nil
end

local function isNewer(candidate, current)
    if not (validVersion(candidate) and validVersion(current)) then return false end
    return ns.Util.VersionAtLeast(candidate, current)
        and not ns.Util.VersionAtLeast(current, candidate)
end

local function playerName()
    if type(UnitName) ~= "function" then return nil end
    local ok, name = pcall(UnitName, "player")
    if ok then return name end
    return nil
end

local function isSelf(sender)
    if type(sender) ~= "string" then return true end
    local name = playerName()
    if not name then return false end
    if sender == name then return true end
    if type(Ambiguate) == "function" then
        local ok, shortName = pcall(Ambiguate, sender, "none")
        if ok and shortName == name then return true end
    end
    return false
end

local function now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function VersionExchange:GetLocalVersion()
    local version = metadata("Version")
    if validVersion(version) then return version end
    return nil
end

function VersionExchange:GetNewestSeenVersion()
    return newestSeenVersion
end

function VersionExchange:SendVersion(distribution, target, bypassThrottle)
    if not prefixRegistered then return false end
    local version = self:GetLocalVersion()
    if not version then return false end

    local key = tostring(distribution) .. ":" .. tostring(target or "")
    local timestamp = now()
    if not bypassThrottle and lastSent[key]
            and timestamp - lastSent[key] < SEND_THROTTLE then
        return false
    end

    local send = chatInfoMethod("SendAddonMessage")
    if type(send) ~= "function" then return false end
    local ok, sent = pcall(send, PREFIX, MESSAGE_TAG .. "\t" .. version,
        distribution, target)
    if not ok or sent == false then return false end
    lastSent[key] = timestamp
    return true
end

local function safeBooleanCall(callback, ...)
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback, ...)
    return ok and value and true or false
end

function VersionExchange:Announce()
    if not prefixRegistered then return end

    if safeBooleanCall(rawget(_G, "IsInGuild")) then
        self:SendVersion("GUILD")
    end

    local instanceCategory = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
    if instanceCategory ~= nil
            and safeBooleanCall(rawget(_G, "IsInGroup"), instanceCategory) then
        self:SendVersion("INSTANCE_CHAT")
    elseif safeBooleanCall(rawget(_G, "IsInRaid")) then
        self:SendVersion("RAID")
    elseif safeBooleanCall(rawget(_G, "IsInGroup")) then
        self:SendVersion("PARTY")
    end
end

function VersionExchange:ScheduleAnnounce(delay)
    if announcePending then return end
    announcePending = true
    local callback = function()
        announcePending = false
        self:Announce()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, delay or ANNOUNCE_DELAY, callback)
        if ok then return end
    end
    callback()
end

function VersionExchange:HandleMessage(prefix, message, distribution, sender)
    if prefix ~= PREFIX or isSelf(sender) or type(message) ~= "string" then return end
    local remoteVersion = message:match("^" .. MESSAGE_TAG .. "\t(.+)$")
    if not validVersion(remoteVersion) then return end

    local localVersion = self:GetLocalVersion()
    if not localVersion then return end

    if isNewer(remoteVersion, localVersion) then
        if not newestSeenVersion or isNewer(remoteVersion, newestSeenVersion) then
            newestSeenVersion = remoteVersion
            if ns.UI and ns.UI.SetAvailableUpdate then
                ns.UI:SetAvailableUpdate(newestSeenVersion)
            end
        end
        if not updateNotified then
            updateNotified = true
            print("|cffffa040Foreverpedia:|r "
                .. L("core_update_available", localVersion, remoteVersion))
        end
        return
    end

    if isNewer(localVersion, remoteVersion) and not repliedTo[sender] then
        repliedTo[sender] = true
        self:SendVersion("WHISPER", sender, true)
    end
end

function VersionExchange:Initialize()
    if initialized then return prefixRegistered end
    initialized = true

    local register = chatInfoMethod("RegisterAddonMessagePrefix")
    if type(register) ~= "function" then return false end
    local ok, registered = pcall(register, PREFIX)
    prefixRegistered = ok and registered ~= false
    if not prefixRegistered then return false end

    frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            self:HandleMessage(...)
        else
            self:ScheduleAnnounce(event == "PLAYER_LOGIN" and ANNOUNCE_DELAY or 1)
        end
    end)
    self:ScheduleAnnounce(ANNOUNCE_DELAY)
    return true
end

