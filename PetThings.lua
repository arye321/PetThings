--[[
    PetThings - Hunter Pet Management AddOn
    Compatibility: WoW Forever / Classic Beta (Interface 16001) / Midnight / Classic
]]--

local ADDON_NAME, AddonTable = ...
local PetThings = CreateFrame("Frame", "PetThingsCoreFrame", UIParent)

-- =========================================================================
-- 1. Default Settings (SavedVariablesPerCharacter: PetThingsDB)
-- =========================================================================
local DEFAULT_CONFIG = {
    locked = false,
    testMode = false,
    minimap = {
        hide = false,
        angle = 215,
    },
    buffs = {
        enabled = true,
        iconSize = 30,
        spacing = 4,
        perRow = 8,
        growth = "RIGHT", -- "RIGHT", "LEFT", "UP", "DOWN"
        showDuration = true,
        showCount = true,
        point = "CENTER",
        x = -150,
        y = 50,
    },
    debuffs = {
        enabled = true,
        iconSize = 32,
        spacing = 4,
        perRow = 8,
        growth = "RIGHT",
        showDuration = true,
        showCount = true,
        point = "CENTER",
        x = -150,
        y = 10,
    },
    feedReminder = {
        enabled = true,
        size = 48,
        remindAtContent = true, -- Also warn at Content (2) or only Unhappy (1)
        playSound = true,
        showText = true,
        point = "CENTER",
        x = 0,
        y = 140,
    }
}

-- Ensure table copy / merge helper
local function CopyDefaults(src, dst)
    if type(src) ~= "table" then return {} end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- =========================================================================
-- 2. Utility & Compatibility Helpers
-- =========================================================================
local function CreateBackdropFrame(frameType, name, parent, template)
    local templates = template or ""
    if BackdropTemplateMixin and not string.find(templates, "BackdropTemplate") then
        templates = (templates == "" and "BackdropTemplate" or templates .. ",BackdropTemplate")
    end
    return CreateFrame(frameType, name, parent, templates)
end

local function ApplyStandardBackdrop(frame, r, g, b, a, edgeR, edgeG, edgeB, edgeA)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.12, a or 0.85)
        frame:SetBackdropBorderColor(edgeR or 0.3, edgeG or 0.3, edgeB or 0.4, edgeA or 0.9)
    end
end

local DEBUFF_COLORS = DebuffTypeColor or {
    ["Magic"]   = { r = 0.20, g = 0.60, b = 1.00 },
    ["Curse"]   = { r = 0.60, g = 0.00, b = 1.00 },
    ["Disease"] = { r = 0.60, g = 0.40, b = 0.10 },
    ["Poison"]  = { r = 0.00, g = 0.60, b = 0.10 },
    ["none"]    = { r = 0.80, g = 0.10, b = 0.10 },
    [""]        = { r = 0.80, g = 0.10, b = 0.10 },
}

local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 3600 then
        return string.format("%dh", math.floor(seconds / 3600 + 0.5))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60 + 0.5))
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    else
        return string.format("%.1f", seconds)
    end
end

-- Universal Aura Fetcher for "pet"
local function GetPetAura(index, filter)
    -- Modern C_UnitAuras API
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex("pet", index, filter)
        if aura then
            return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.auraInstanceID
        end
    end
    if filter == "HARMFUL" and C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        local aura = C_UnitAuras.GetDebuffDataByIndex("pet", index)
        if aura then
            return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.auraInstanceID
        end
    elseif filter == "HELPFUL" and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local aura = C_UnitAuras.GetBuffDataByIndex("pet", index)
        if aura then
            return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.auraInstanceID
        end
    end

    -- Classic UnitAura / UnitBuff / UnitDebuff API
    if UnitAura then
        local name, icon, count, debuffType, duration, expirationTime = UnitAura("pet", index, filter)
        if name then
            return name, icon, count, debuffType, duration, expirationTime, index
        end
    end
    if filter == "HELPFUL" and UnitBuff then
        local name, icon, count, debuffType, duration, expirationTime = UnitBuff("pet", index)
        if name then
            return name, icon, count, debuffType, duration, expirationTime, index
        end
    elseif filter == "HARMFUL" and UnitDebuff then
        local name, icon, count, debuffType, duration, expirationTime = UnitDebuff("pet", index)
        if name then
            return name, icon, count, debuffType, duration, expirationTime, index
        end
    end

    return nil
end

-- =========================================================================
-- 3. Movable Anchor Frame Factory
-- =========================================================================
local AnchorFrames = {}

local function CreateMovableAnchor(name, titleText, dbKey, defaultWidth, defaultHeight)
    local anchor = CreateBackdropFrame("Frame", name, UIParent)
    anchor:SetSize(defaultWidth or 120, defaultHeight or 36)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:SetClampedToScreen(true)

    ApplyStandardBackdrop(anchor, 0.1, 0.3, 0.6, 0.6, 0.2, 0.7, 1.0, 0.9)

    local title = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    title:SetText("|cff33ccff" .. titleText .. "|r")
    anchor.title = title

    anchor:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not PetThingsDB.locked then
            self:StartMoving()
            self.isMoving = true
        end
    end)

    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            local point, _, _, x, y = self:GetPoint()
            if PetThingsDB and PetThingsDB[dbKey] then
                PetThingsDB[dbKey].point = point or "CENTER"
                PetThingsDB[dbKey].x = math.floor(x + 0.5)
                PetThingsDB[dbKey].y = math.floor(y + 0.5)
            end
        end
    end)

    function anchor:UpdateLockVisual()
        if PetThingsDB.locked then
            anchor:EnableMouse(false)
            if anchor.SetBackdropColor then
                anchor:SetBackdropColor(0, 0, 0, 0)
                anchor:SetBackdropBorderColor(0, 0, 0, 0)
            end
            anchor.title:Hide()
        else
            anchor:EnableMouse(true)
            ApplyStandardBackdrop(anchor, 0.1, 0.3, 0.6, 0.6, 0.2, 0.7, 1.0, 0.9)
            anchor.title:Show()
        end
    end

    function anchor:RestorePosition()
        local cfg = PetThingsDB and PetThingsDB[dbKey]
        if cfg and cfg.point then
            self:ClearAllPoints()
            self:SetPoint(cfg.point, UIParent, cfg.point, cfg.x or 0, cfg.y or 0)
        end
    end

    table.insert(AnchorFrames, anchor)
    return anchor
end

-- =========================================================================
-- 4. Pet Buffs & Debuffs Display
-- =========================================================================
local BuffFrameAnchor = CreateMovableAnchor("PetThingsBuffAnchor", "Pet Buffs", "buffs", 160, 36)
local DebuffFrameAnchor = CreateMovableAnchor("PetThingsDebuffAnchor", "Pet Debuffs", "debuffs", 160, 36)

local function CreateAuraContainer(anchor, filter, dbKey)
    local container = CreateFrame("Frame", nil, anchor)
    container:SetAllPoints(anchor)
    container.buttons = {}
    container.filter = filter
    container.dbKey = dbKey

    local function CreateAuraButton(index)
        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(32, 32)
        btn:EnableMouse(true)

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints(btn)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints(btn)
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        btn.count = count

        local duration = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
        duration:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        btn.duration = duration

        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
        border:Hide()
        btn.border = border

        btn:SetScript("OnEnter", function(self)
            if not self.auraIndex then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            if self.isTest then
                GameTooltip:SetText(self.testName or "Sample Aura", 1, 1, 1)
                GameTooltip:AddLine(self.testDesc or "Test aura description for PetThings frame layout preview.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
                return
            end
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and self.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
                GameTooltip:SetUnitAuraByAuraInstanceID("pet", self.auraInstanceID)
            elseif filter == "HELPFUL" and GameTooltip.SetUnitBuff then
                GameTooltip:SetUnitBuff("pet", self.auraIndex)
            elseif filter == "HARMFUL" and GameTooltip.SetUnitDebuff then
                GameTooltip:SetUnitDebuff("pet", self.auraIndex)
            elseif GameTooltip.SetUnitAura then
                GameTooltip:SetUnitAura("pet", self.auraIndex, filter)
            end
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return btn
    end

    function container:GetButton(index)
        if not self.buttons[index] then
            self.buttons[index] = CreateAuraButton(index)
        end
        return self.buttons[index]
    end

    function container:UpdateLayout()
        local cfg = PetThingsDB[self.dbKey]
        local size = cfg.iconSize or 30
        local spacing = cfg.spacing or 4
        local perRow = math.max(1, cfg.perRow or 8)
        local growth = cfg.growth or "RIGHT"

        for i, btn in ipairs(self.buttons) do
            btn:SetSize(size, size)
            btn:ClearAllPoints()
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)

            local offsetX, offsetY = 0, 0
            if growth == "RIGHT" then
                offsetX = col * (size + spacing)
                offsetY = -row * (size + spacing + 12)
                btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", offsetX, offsetY)
            elseif growth == "LEFT" then
                offsetX = -col * (size + spacing)
                offsetY = -row * (size + spacing + 12)
                btn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", offsetX, offsetY)
            elseif growth == "UP" then
                offsetX = row * (size + spacing + 12)
                offsetY = col * (size + spacing)
                btn:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", offsetX, offsetY)
            else -- DOWN
                offsetX = row * (size + spacing + 12)
                offsetY = -col * (size + spacing)
                btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", offsetX, offsetY)
            end
        end
    end

    function container:Refresh()
        local cfg = PetThingsDB[self.dbKey]
        if not cfg.enabled then
            for _, btn in pairs(self.buttons) do btn:Hide() end
            return
        end

        local isPetActive = UnitExists("pet")
        local isTest = PetThingsDB.testMode

        if not isPetActive and not isTest then
            for _, btn in pairs(self.buttons) do btn:Hide() end
            return
        end

        self:UpdateLayout()

        if isTest then
            -- Display test auras
            local dummyCount = 4
            for i = 1, dummyCount do
                local btn = self:GetButton(i)
                btn.isTest = true
                btn.auraIndex = i
                btn.auraInstanceID = nil
                btn.testName = (self.filter == "HELPFUL" and "Pet Buff " or "Pet Debuff ") .. i
                btn.testDesc = "Sample aura to adjust icon size and positioning."

                if self.filter == "HELPFUL" then
                    btn.icon:SetTexture(i == 1 and 132155 or (i == 2 and 132144 or 132111))
                    btn.border:Hide()
                else
                    btn.icon:SetTexture(i == 1 and 136071 or (i == 2 and 136126 or 136067))
                    local color = DEBUFF_COLORS[i == 1 and "Poison" or (i == 2 and "Magic" or "Disease")] or DEBUFF_COLORS["none"]
                    btn.border:SetVertexColor(color.r, color.g, color.b)
                    btn.border:Show()
                end

                btn.count:SetText(i > 1 and tostring(i) or "")
                btn.duration:SetText(cfg.showDuration and (i * 15 .. "s") or "")
                btn:Show()
            end
            for i = dummyCount + 1, #self.buttons do
                self.buttons[i]:Hide()
            end
            return
        end

        -- Actual Pet Auras
        local btnIndex = 1
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, auraInstanceID = GetPetAura(i, self.filter)
            if not name then break end

            local btn = self:GetButton(btnIndex)
            btn.isTest = false
            btn.auraIndex = i
            btn.auraInstanceID = auraInstanceID
            btn.icon:SetTexture(icon)

            if cfg.showCount and count and count > 1 then
                btn.count:SetText(count)
            else
                btn.count:SetText("")
            end

            if duration and duration > 0 and expirationTime and expirationTime > 0 then
                if btn.cooldown then
                    btn.cooldown:SetCooldown(expirationTime - duration, duration)
                    btn.cooldown:Show()
                end
                btn.expirationTime = expirationTime
            else
                if btn.cooldown then btn.cooldown:Hide() end
                btn.expirationTime = nil
                btn.duration:SetText("")
            end

            if self.filter == "HARMFUL" then
                local color = DEBUFF_COLORS[debuffType or "none"] or DEBUFF_COLORS["none"]
                btn.border:SetVertexColor(color.r, color.g, color.b)
                btn.border:Show()
            else
                btn.border:Hide()
            end

            btn:Show()
            btnIndex = btnIndex + 1
        end

        for i = btnIndex, #self.buttons do
            self.buttons[i]:Hide()
        end
    end

    return container
end

local BuffContainer = CreateAuraContainer(BuffFrameAnchor, "HELPFUL", "buffs")
local DebuffContainer = CreateAuraContainer(DebuffFrameAnchor, "HARMFUL", "debuffs")

-- OnUpdate handler to update duration strings smoothly
local function AurasOnUpdate(self, elapsed)
    self.timeSinceLast = (self.timeSinceLast or 0) + elapsed
    if self.timeSinceLast < 0.2 then return end
    self.timeSinceLast = 0

    local now = GetTime()
    local function UpdateDurations(container, cfg)
        if not cfg.enabled or not cfg.showDuration or PetThingsDB.testMode then return end
        for _, btn in ipairs(container.buttons) do
            if btn:IsShown() and btn.expirationTime and btn.expirationTime > now then
                btn.duration:SetText(FormatTime(btn.expirationTime - now))
            elseif btn:IsShown() and btn.expirationTime then
                btn.duration:SetText("")
            end
        end
    end

    UpdateDurations(BuffContainer, PetThingsDB.buffs)
    UpdateDurations(DebuffContainer, PetThingsDB.debuffs)
end

-- =========================================================================
-- 5. Pet Happiness & Feed Reminder
-- =========================================================================
local FeedAnchor = CreateMovableAnchor("PetThingsFeedAnchor", "Pet Feed Alert", "feedReminder", 64, 64)

local FeedReminderFrame = CreateFrame("Button", "PetThingsFeedFrame", FeedAnchor, "SecureActionButtonTemplate")
FeedReminderFrame:SetAllPoints(FeedAnchor)
FeedReminderFrame:RegisterForClicks("AnyUp", "AnyDown")

-- Secure feed pet action: click to feed pet out of combat
FeedReminderFrame:SetAttribute("type", "spell")
FeedReminderFrame:SetAttribute("spell", "Feed Pet")

local feedIcon = FeedReminderFrame:CreateTexture(nil, "BACKGROUND")
feedIcon:SetAllPoints(FeedReminderFrame)
feedIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
feedIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
FeedReminderFrame.icon = feedIcon

local feedGlow = FeedReminderFrame:CreateTexture(nil, "OVERLAY")
feedGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
feedGlow:SetBlendMode("ADD")
feedGlow:SetAllPoints(FeedReminderFrame)
FeedReminderFrame.glow = feedGlow

local feedText = FeedReminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
feedText:SetPoint("TOP", FeedReminderFrame, "BOTTOM", 0, -4)
feedText:SetJustifyH("CENTER")
FeedReminderFrame.text = feedText

local lastHappinessAlert = nil

function FeedReminderFrame:UpdateSize()
    local size = PetThingsDB.feedReminder.size or 48
    FeedAnchor:SetSize(size, size)
    FeedReminderFrame:SetSize(size, size)
end

function FeedReminderFrame:CheckHappiness()
    local cfg = PetThingsDB.feedReminder
    if not cfg.enabled then
        self:Hide()
        return
    end

    if PetThingsDB.testMode then
        self:UpdateSize()
        self.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
        if cfg.showText then
            self.text:SetText("|cffff3333FEED PET!|r\n|cffffff00(Test Mode)|r")
            self.text:Show()
        else
            self.text:Hide()
        end
        self:Show()
        return
    end

    if not UnitExists("pet") then
        self:Hide()
        lastHappinessAlert = nil
        return
    end

    local happiness = nil
    if GetPetHappiness then
        happiness = GetPetHappiness()
    end

    -- If happiness API is unavailable (e.g. non-classic pet), hide frame
    if not happiness then
        self:Hide()
        return
    end

    -- happiness: 1 = Unhappy (red, 75% or 50% dmg), 2 = Content (yellow, 100% dmg), 3 = Happy (green, 125% dmg)
    local shouldWarn = false
    local statusText = ""
    local iconTex = "Interface\\Icons\\Ability_Hunter_BeastTraining"

    if happiness == 1 then
        shouldWarn = true
        statusText = "|cffff2020Unhappy!|r\n|cffff6666Feed Pet (50% DMG)|r"
        iconTex = "Interface\\Icons\\INV_Misc_Food_09"
    elseif happiness == 2 and cfg.remindAtContent then
        shouldWarn = true
        statusText = "|cffffff00Content|r\n|cffffcc00Feed for +25% DMG|r"
        iconTex = "Interface\\Icons\\Ability_Hunter_BeastTraining"
    end

    if shouldWarn then
        self:UpdateSize()
        self.icon:SetTexture(iconTex)
        if cfg.showText then
            self.text:SetText(statusText)
            self.text:Show()
        else
            self.text:Hide()
        end
        self:Show()

        -- Sound alert trigger
        if cfg.playSound and lastHappinessAlert ~= happiness then
            PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
            lastHappinessAlert = happiness
        end
    else
        self:Hide()
        lastHappinessAlert = happiness
    end
end

-- Pulsing animation for feed glow
local glowTimer = 0
FeedReminderFrame:SetScript("OnUpdate", function(self, elapsed)
    if not self:IsShown() then return end
    glowTimer = (glowTimer + elapsed * 3) % (math.pi * 2)
    local alpha = 0.3 + 0.5 * (math.sin(glowTimer) * 0.5 + 0.5)
    feedGlow:SetAlpha(alpha)
end)

FeedReminderFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("|cff33ff99PetThings: Feed Reminder|r", 1, 1, 1)
    GameTooltip:AddLine("Your pet is hungry! Feed it to increase loyalty & damage.", 1, 0.8, 0, true)
    GameTooltip:AddLine("Left-Click: Cast Feed Pet (out of combat)", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

FeedReminderFrame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- =========================================================================
-- 6. Minimap Button
-- =========================================================================
local MinimapButton = CreateFrame("Button", "PetThingsMinimapButton", Minimap)
MinimapButton:SetSize(31, 31)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-Button-Highlight")
MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
MinimapButton:RegisterForDrag("LeftButton")

local minimapIcon = MinimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("CENTER", 0, 0)
minimapIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
minimapIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local minimapBorder = MinimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetSize(53, 53)
minimapBorder:SetPoint("TOPLEFT", MinimapButton, "TOPLEFT", 0, 0)
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdateMinimapButtonPosition()
    local angle = math.rad(PetThingsDB.minimap.angle or 215)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if PetThingsDB.minimap.hide then
        MinimapButton:Hide()
    else
        MinimapButton:Show()
    end
end

MinimapButton:SetScript("OnDragStart", function(self)
    self.isDragging = true
    self:LockHighlight()
end)

MinimapButton:SetScript("OnDragStop", function(self)
    self.isDragging = false
    self:UnlockHighlight()
end)

MinimapButton:SetScript("OnUpdate", function(self)
    if not self.isDragging then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end
    PetThingsDB.minimap.angle = angle
    UpdateMinimapButtonPosition()
end)

MinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff33ff99PetThings|r", 1, 1, 1)
    GameTooltip:AddLine("Hunter Pet Manager & Aura Monitor", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("|cffffffffLeft-Click:|r", "Open Options", 0.2, 1, 0.2, 1, 1, 1)
    GameTooltip:AddDoubleLine("|cffffffffRight-Click:|r", PetThingsDB.locked and "Unlock Frames" or "Lock Frames", 0.2, 1, 0.2, 1, 1, 1)
    GameTooltip:AddDoubleLine("|cffffffffDrag:|r", "Move Minimap Icon", 0.2, 1, 0.2, 1, 1, 1)
    GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Forward declaration of ToggleOptions
local ToggleOptions

MinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        ToggleOptions()
    elseif button == "RightButton" then
        PetThingsDB.locked = not PetThingsDB.locked
        PetThings:UpdateLockState()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r Frames are now " .. (PetThingsDB.locked and "|cffff3333LOCKED|r" or "|cff33ff33UNLOCKED|r"))
    end
end)

-- =========================================================================
-- 7. Standalone Options GUI
-- =========================================================================
local OptionsFrame = CreateBackdropFrame("Frame", "PetThingsOptionsFrame", UIParent)
OptionsFrame:SetSize(420, 560)
OptionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
OptionsFrame:SetMovable(true)
OptionsFrame:EnableMouse(true)
OptionsFrame:SetClampedToScreen(true)
OptionsFrame:SetFrameStrata("HIGH")
OptionsFrame:Hide()

ApplyStandardBackdrop(OptionsFrame, 0.08, 0.08, 0.12, 0.95, 0.2, 0.6, 0.9, 1.0)

-- Header / Title Bar
local titleBar = CreateFrame("Frame", nil, OptionsFrame)
titleBar:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 6, -6)
titleBar:SetPoint("TOPRIGHT", OptionsFrame, "TOPRIGHT", -6, -6)
titleBar:SetHeight(28)
titleBar:EnableMouse(true)

local optTitle = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
optTitle:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
optTitle:SetText("|cff33ff99PetThings|r |cffffffffOptions|r")

local closeBtn = CreateFrame("Button", nil, OptionsFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", OptionsFrame, "TOPRIGHT", -2, -2)

titleBar:SetScript("OnMouseDown", function()
    OptionsFrame:StartMoving()
    OptionsFrame.isMoving = true
end)
titleBar:SetScript("OnMouseUp", function()
    OptionsFrame:StopMovingOrSizing()
    OptionsFrame.isMoving = false
end)

-- UI Control Helpers
local function CreateUICheckbox(parent, label, getVal, setVal)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb.text = text

    cb:SetScript("OnClick", function(self)
        setVal(self:GetChecked())
    end)
    cb.Refresh = function(self)
        self:SetChecked(getVal())
    end
    return cb
end

local function CreateUISlider(parent, label, minVal, maxVal, step, getVal, setVal)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetWidth(170)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local title = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
    title:SetText(label)
    slider.title = title

    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 4)
    slider.valText = valText

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        self.valText:SetText(tostring(value))
        setVal(value)
    end)

    slider.Refresh = function(self)
        local val = getVal()
        self:SetValue(val)
        self.valText:SetText(tostring(val))
    end
    return slider
end

local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, yOffset)
    header:SetText("|cff33ccff" .. text .. "|r")

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    line:SetColorTexture(0.2, 0.4, 0.6, 0.5)
    return header
end

-- Build Settings Controls inside OptionsFrame
local uiWidgets = {}

-- 1. General Section
CreateSectionHeader(OptionsFrame, "General Settings", -40)

local cbLock = CreateUICheckbox(OptionsFrame, "Lock Frame Positions",
    function() return PetThingsDB.locked end,
    function(val)
        PetThingsDB.locked = val
        PetThings:UpdateLockState()
    end
)
cbLock:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -62)
table.insert(uiWidgets, cbLock)

local cbTest = CreateUICheckbox(OptionsFrame, "Test Mode (Show dummy preview)",
    function() return PetThingsDB.testMode end,
    function(val)
        PetThingsDB.testMode = val
        PetThings:RefreshAll()
    end
)
cbTest:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -62)
table.insert(uiWidgets, cbTest)

local cbMinimap = CreateUICheckbox(OptionsFrame, "Show Minimap Button",
    function() return not PetThingsDB.minimap.hide end,
    function(val)
        PetThingsDB.minimap.hide = not val
        UpdateMinimapButtonPosition()
    end
)
cbMinimap:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -90)
table.insert(uiWidgets, cbMinimap)

-- 2. Buffs Section
CreateSectionHeader(OptionsFrame, "Pet Buffs Frame", -122)

local cbBuffs = CreateUICheckbox(OptionsFrame, "Enable Buffs Display",
    function() return PetThingsDB.buffs.enabled end,
    function(val)
        PetThingsDB.buffs.enabled = val
        BuffContainer:Refresh()
    end
)
cbBuffs:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -144)
table.insert(uiWidgets, cbBuffs)

local cbBuffTimer = CreateUICheckbox(OptionsFrame, "Show Durations",
    function() return PetThingsDB.buffs.showDuration end,
    function(val)
        PetThingsDB.buffs.showDuration = val
        BuffContainer:Refresh()
    end
)
cbBuffTimer:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -144)
table.insert(uiWidgets, cbBuffTimer)

local slBuffSize = CreateUISlider(OptionsFrame, "Buff Icon Size", 16, 64, 1,
    function() return PetThingsDB.buffs.iconSize end,
    function(val)
        PetThingsDB.buffs.iconSize = val
        BuffContainer:Refresh()
    end
)
slBuffSize:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -190)
table.insert(uiWidgets, slBuffSize)

local slBuffSpacing = CreateUISlider(OptionsFrame, "Buff Spacing", 0, 20, 1,
    function() return PetThingsDB.buffs.spacing end,
    function(val)
        PetThingsDB.buffs.spacing = val
        BuffContainer:Refresh()
    end
)
slBuffSpacing:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 215, -190)
table.insert(uiWidgets, slBuffSpacing)

local slBuffPerRow = CreateUISlider(OptionsFrame, "Buffs Per Row", 1, 16, 1,
    function() return PetThingsDB.buffs.perRow end,
    function(val)
        PetThingsDB.buffs.perRow = val
        BuffContainer:Refresh()
    end
)
slBuffPerRow:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -235)
table.insert(uiWidgets, slBuffPerRow)

-- 3. Debuffs Section
CreateSectionHeader(OptionsFrame, "Pet Debuffs Frame", -270)

local cbDebuffs = CreateUICheckbox(OptionsFrame, "Enable Debuffs Display",
    function() return PetThingsDB.debuffs.enabled end,
    function(val)
        PetThingsDB.debuffs.enabled = val
        DebuffContainer:Refresh()
    end
)
cbDebuffs:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -292)
table.insert(uiWidgets, cbDebuffs)

local cbDebuffTimer = CreateUICheckbox(OptionsFrame, "Show Durations",
    function() return PetThingsDB.debuffs.showDuration end,
    function(val)
        PetThingsDB.debuffs.showDuration = val
        DebuffContainer:Refresh()
    end
)
cbDebuffTimer:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -292)
table.insert(uiWidgets, cbDebuffTimer)

local slDebuffSize = CreateUISlider(OptionsFrame, "Debuff Icon Size", 16, 64, 1,
    function() return PetThingsDB.debuffs.iconSize end,
    function(val)
        PetThingsDB.debuffs.iconSize = val
        DebuffContainer:Refresh()
    end
)
slDebuffSize:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -338)
table.insert(uiWidgets, slDebuffSize)

local slDebuffSpacing = CreateUISlider(OptionsFrame, "Debuff Spacing", 0, 20, 1,
    function() return PetThingsDB.debuffs.spacing end,
    function(val)
        PetThingsDB.debuffs.spacing = val
        DebuffContainer:Refresh()
    end
)
slDebuffSpacing:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 215, -338)
table.insert(uiWidgets, slDebuffSpacing)

local slDebuffPerRow = CreateUISlider(OptionsFrame, "Debuffs Per Row", 1, 16, 1,
    function() return PetThingsDB.debuffs.perRow end,
    function(val)
        PetThingsDB.debuffs.perRow = val
        DebuffContainer:Refresh()
    end
)
slDebuffPerRow:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -383)
table.insert(uiWidgets, slDebuffPerRow)

-- 4. Happiness & Feed Reminder Section
CreateSectionHeader(OptionsFrame, "Feed Reminder & Happiness Alert", -418)

local cbFeedEnable = CreateUICheckbox(OptionsFrame, "Enable Feed Alert",
    function() return PetThingsDB.feedReminder.enabled end,
    function(val)
        PetThingsDB.feedReminder.enabled = val
        FeedReminderFrame:CheckHappiness()
    end
)
cbFeedEnable:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -440)
table.insert(uiWidgets, cbFeedEnable)

local cbFeedContent = CreateUICheckbox(OptionsFrame, "Warn on Content",
    function() return PetThingsDB.feedReminder.remindAtContent end,
    function(val)
        PetThingsDB.feedReminder.remindAtContent = val
        FeedReminderFrame:CheckHappiness()
    end
)
cbFeedContent:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -440)
table.insert(uiWidgets, cbFeedContent)

local slFeedSize = CreateUISlider(OptionsFrame, "Alert Icon Size", 24, 96, 2,
    function() return PetThingsDB.feedReminder.size end,
    function(val)
        PetThingsDB.feedReminder.size = val
        FeedReminderFrame:UpdateSize()
    end
)
slFeedSize:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -485)
table.insert(uiWidgets, slFeedSize)

local cbFeedSound = CreateUICheckbox(OptionsFrame, "Play Sound Alert",
    function() return PetThingsDB.feedReminder.playSound end,
    function(val)
        PetThingsDB.feedReminder.playSound = val
    end
)
cbFeedSound:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -475)
table.insert(uiWidgets, cbFeedSound)

local cbFeedText = CreateUICheckbox(OptionsFrame, "Show Status Text",
    function() return PetThingsDB.feedReminder.showText end,
    function(val)
        PetThingsDB.feedReminder.showText = val
        FeedReminderFrame:CheckHappiness()
    end
)
cbFeedText:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 210, -500)
table.insert(uiWidgets, cbFeedText)

-- Bottom Reset Buttons
local btnResetPos = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
btnResetPos:SetSize(120, 24)
btnResetPos:SetPoint("BOTTOMLEFT", OptionsFrame, "BOTTOMLEFT", 20, 14)
btnResetPos:SetText("Reset Positions")
btnResetPos:SetScript("OnClick", function()
    PetThingsDB.buffs.point = DEFAULT_CONFIG.buffs.point
    PetThingsDB.buffs.x = DEFAULT_CONFIG.buffs.x
    PetThingsDB.buffs.y = DEFAULT_CONFIG.buffs.y

    PetThingsDB.debuffs.point = DEFAULT_CONFIG.debuffs.point
    PetThingsDB.debuffs.x = DEFAULT_CONFIG.debuffs.x
    PetThingsDB.debuffs.y = DEFAULT_CONFIG.debuffs.y

    PetThingsDB.feedReminder.point = DEFAULT_CONFIG.feedReminder.point
    PetThingsDB.feedReminder.x = DEFAULT_CONFIG.feedReminder.x
    PetThingsDB.feedReminder.y = DEFAULT_CONFIG.feedReminder.y

    PetThings:RestoreAllPositions()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r Frame positions reset to defaults.")
end)

local btnResetAll = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
btnResetAll:SetSize(120, 24)
btnResetAll:SetPoint("BOTTOMRIGHT", OptionsFrame, "BOTTOMRIGHT", -20, 14)
btnResetAll:SetText("Reset All Settings")
btnResetAll:SetScript("OnClick", function()
    PetThingsDB = CopyDefaults(DEFAULT_CONFIG, {})
    PetThings:UpdateLockState()
    PetThings:RestoreAllPositions()
    PetThings:RefreshAll()
    OptionsFrame:RefreshControls()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r All settings reset to defaults.")
end)

function OptionsFrame:RefreshControls()
    for _, widget in ipairs(uiWidgets) do
        if widget.Refresh then
            widget:Refresh()
        end
    end
end

ToggleOptions = function()
    if OptionsFrame:IsShown() then
        OptionsFrame:Hide()
    else
        OptionsFrame:RefreshControls()
        OptionsFrame:Show()
    end
end

-- =========================================================================
-- 8. Core Event Handling & Lifecycle
-- =========================================================================
function PetThings:UpdateLockState()
    for _, anchor in ipairs(AnchorFrames) do
        anchor:UpdateLockVisual()
    end
    if OptionsFrame:IsShown() then
        OptionsFrame:RefreshControls()
    end
end

function PetThings:RestoreAllPositions()
    for _, anchor in ipairs(AnchorFrames) do
        anchor:RestorePosition()
    end
end

function PetThings:RefreshAll()
    BuffContainer:Refresh()
    DebuffContainer:Refresh()
    FeedReminderFrame:CheckHappiness()
    UpdateMinimapButtonPosition()
end

PetThings:RegisterEvent("ADDON_LOADED")
PetThings:RegisterEvent("PLAYER_ENTERING_WORLD")
PetThings:RegisterEvent("UNIT_PET")
PetThings:RegisterEvent("PET_UI_UPDATE")
PetThings:RegisterEvent("UNIT_AURA")
PetThings:RegisterEvent("UNIT_HAPPINESS")

PetThings:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        PetThingsDB = CopyDefaults(DEFAULT_CONFIG, PetThingsDB)
        self:RestoreAllPositions()
        self:UpdateLockState()
        UpdateMinimapButtonPosition()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:RestoreAllPositions()
        self:RefreshAll()
    elseif event == "UNIT_AURA" then
        if arg1 == "pet" then
            BuffContainer:Refresh()
            DebuffContainer:Refresh()
        end
    elseif event == "UNIT_HAPPINESS" or event == "PET_UI_UPDATE" or (event == "UNIT_PET" and arg1 == "player") then
        self:RefreshAll()
    end
end)

PetThings:SetScript("OnUpdate", AurasOnUpdate)

-- =========================================================================
-- 9. Slash Commands
-- =========================================================================
SLASH_PETTHINGS1 = "/petthings"
SLASH_PETTHINGS2 = "/pt"
SlashCmdList["PETTHINGS"] = function(msg)
    local cmd = string.lower(string.trim and string.trim(msg) or string.gsub(msg, "^%s*(.-)%s*$", "%1"))
    if cmd == "lock" or cmd == "unlock" then
        PetThingsDB.locked = not PetThingsDB.locked
        PetThings:UpdateLockState()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r Frames are now " .. (PetThingsDB.locked and "|cffff3333LOCKED|r" or "|cff33ff33UNLOCKED|r"))
    elseif cmd == "test" then
        PetThingsDB.testMode = not PetThingsDB.testMode
        PetThings:RefreshAll()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r Test Mode " .. (PetThingsDB.testMode and "|cff33ff33ENABLED|r" or "|cffff3333DISABLED|r"))
    elseif cmd == "reset" then
        PetThingsDB = CopyDefaults(DEFAULT_CONFIG, {})
        PetThings:UpdateLockState()
        PetThings:RestoreAllPositions()
        PetThings:RefreshAll()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99PetThings:|r Settings reset to default.")
    else
        ToggleOptions()
    end
end
