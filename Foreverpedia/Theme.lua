local _, ns = ...

local Theme = {
    colors = {
        overlay = { 0.01, 0.008, 0.006, 0.72 },
        background = { 0.045, 0.035, 0.025, 0.98 },
        craftBackground = { 0.045, 0.035, 0.025, 0.995 },
        panel = { 0.085, 0.065, 0.040, 0.98 },
        node = { 0.075, 0.058, 0.038, 0.99 },
        border = { 0.56, 0.40, 0.18, 1 },
        gold = { 0.95, 0.72, 0.27, 1 },
        muted = { 0.70, 0.66, 0.57, 1 },
        normal = { 0.93, 0.89, 0.80, 1 },
    },
}
ns.Theme = Theme

-- SmartNavigation hooks CreateFrame calls that already carry a parent and may
-- treat addon controls as a new gamepad window. Creating first and parenting
-- second keeps Foreverpedia out of that protected focus/binding stack.
function ns.CreateDetachedFrame(frameType, name, parent, template)
    local frame = CreateFrame(frameType, name, nil, template)
    if parent then frame:SetParent(parent) end
    return frame
end

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Theme.SetBackdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(background or Theme.colors.background))
    frame:SetBackdropBorderColor(unpack(border or Theme.colors.border))
end
