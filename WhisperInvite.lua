-- =========================================================================
-- WhisperInvite v1.3.0  (WotLK 3.3.5a, Interface 30300)
--
-- * Invites players who whisper the keyword (exact match by default).
-- * Auto-accepts party/raid invites from greenlighted (whitelisted) players.
-- * Movable minimap button (Shift+drag), Interface Options panel.
--
-- 3.3.5a notes: no C_Timer, no SetShown, no Ambiguate (guarded).
-- All UI beyond the frames themselves is configured lazily; nothing that
-- depends on saved variables runs before ADDON_LOADED.
-- =========================================================================

local addonName, WI = ...

-- -------------------------------------------------------------------------
-- Defaults & saved-variable merge
-- -------------------------------------------------------------------------
local DEFAULTS = {
    enabled    = false,        -- whisper-invite listener
    keyword    = "inv",
    autoReply  = true,         -- whisper the player back after inviting
    inviteScope = "greenlist", -- "greenlist": only whitelisted players can
                               -- trigger the keyword; "everyone": anyone can
    autoAccept = true,         -- auto-accept invites from whitelist
    whitelist  = {},           -- [lowername] = displayName
    minimapX   = nil,          -- free position, offsets from minimap center
    minimapY   = nil,          -- (nil = not placed yet; derived on first load)
}

WI.db = nil -- assigned on ADDON_LOADED

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- -------------------------------------------------------------------------
-- Forward local declarations (declared above every reader — house rule)
-- -------------------------------------------------------------------------
local UpdateMinimapButtonLook
local UpdateMinimapButtonPosition
local BuildOptionsPanel
local RefreshOptionsPanel
local RefreshWhitelistRows
local optionsPanel  -- set by BuildOptionsPanel

local mb -- minimap button, created below

-- -------------------------------------------------------------------------
-- Small helpers
-- -------------------------------------------------------------------------
local function CleanName(name)
    if not name then return nil end
    if Ambiguate then name = Ambiguate(name, "none") end
    name = name:match("^([^%-]+)") or name -- strip -Realm if present
    return name
end

local function Capitalize(name)
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

local function CanInvite()
    if GetNumRaidMembers() > 0 then
        return IsRaidLeader() or IsRaidOfficer()
    elseif GetNumPartyMembers() > 0 then
        return IsPartyLeader()
    end
    return true
end

local function GroupIsFull()
    if GetNumRaidMembers() > 0 then
        return GetNumRaidMembers() >= 40
    end
    return GetNumPartyMembers() >= 4
end

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99WhisperInvite:|r " .. text)
end

-- -------------------------------------------------------------------------
-- Core: whisper handling
-- -------------------------------------------------------------------------
local function OnWhisper(msg, sender)
    if not WI.db.enabled then return end
    sender = CleanName(sender)
    if not sender or sender == UnitName("player") then return end

    local kw   = string.lower(WI.db.keyword or "inv")
    local text = string.lower(strtrim(msg or ""))

    -- Matching is ALWAYS exact (case-insensitive, surrounding spaces
    -- trimmed): the whisper must be the keyword and nothing else. A
    -- "keyword anywhere in the sentence" mode existed until v1.2.1 and was
    -- removed as accident-prone by design decision — do not reintroduce it.
    if text ~= kw then return end

    -- Scope gate: in greenlist mode, only greenlighted players may trigger
    -- the keyword. Silent ignore for everyone else (no whisper, no spam).
    if WI.db.inviteScope ~= "everyone" and not WI.db.whitelist[string.lower(sender)] then
        return
    end

    if not CanInvite() then
        Msg(sender .. " whispered the keyword, but you cannot invite (not leader/assist).")
        return
    end
    if GroupIsFull() then
        Msg(sender .. " whispered the keyword, but the group is full.")
        if WI.db.autoReply then
            SendChatMessage("Sorry, the group is currently full.", "WHISPER", nil, sender)
        end
        return
    end

    InviteUnit(sender)
    if WI.db.autoReply then
        SendChatMessage("You have been automatically invited.", "WHISPER", nil, sender)
    end
end

-- -------------------------------------------------------------------------
-- Core: auto-accept invites from greenlighted players
-- -------------------------------------------------------------------------
local function OnPartyInvite(inviter)
    if not WI.db.autoAccept then return end
    inviter = CleanName(inviter)
    if not inviter then return end
    if WI.db.whitelist[string.lower(inviter)] then
        AcceptGroup()
        StaticPopup_Hide("PARTY_INVITE")
        Msg("Auto-accepted group invite from |cFF00FF00" .. inviter .. "|r.")
    end
end

-- -------------------------------------------------------------------------
-- Whitelist management
-- -------------------------------------------------------------------------
local function WhitelistAdd(name)
    name = CleanName(strtrim(name or ""))
    if not name or name == "" then
        Msg("Usage: /wi allow <playername>")
        return
    end
    local key = string.lower(name)
    if WI.db.whitelist[key] then
        Msg(Capitalize(name) .. " is already greenlighted.")
        return
    end
    WI.db.whitelist[key] = Capitalize(name)
    Msg("Greenlighted |cFF00FF00" .. Capitalize(name) .. "|r — their invites will be auto-accepted.")
    RefreshWhitelistRows()
end

local function WhitelistRemove(name)
    name = CleanName(strtrim(name or ""))
    if not name or name == "" then
        Msg("Usage: /wi disallow <playername>")
        return
    end
    local key = string.lower(name)
    if not WI.db.whitelist[key] then
        Msg(Capitalize(name) .. " is not on the greenlight list.")
        return
    end
    WI.db.whitelist[key] = nil
    Msg("Removed |cFFFF5555" .. Capitalize(name) .. "|r from the greenlight list.")
    RefreshWhitelistRows()
end

local function WhitelistSorted()
    local t = {}
    for _, display in pairs(WI.db.whitelist) do
        t[#t + 1] = display
    end
    table.sort(t)
    return t
end

-- -------------------------------------------------------------------------
-- Main event frame
-- -------------------------------------------------------------------------
local f = CreateFrame("Frame", "WhisperInviteFrame", UIParent)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= addonName then return end

        if type(WhisperInviteDB) ~= "table" then WhisperInviteDB = {} end
        WI.db = WhisperInviteDB
        MergeDefaults(WI.db, DEFAULTS)

        UpdateMinimapButtonLook()
        UpdateMinimapButtonPosition()
        BuildOptionsPanel()

        Msg("v1.3.0 loaded. /wi for commands, right-click the minimap button for options.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-anchor after minimap addons finish moving/scaling the map.
        UpdateMinimapButtonPosition()
    elseif event == "CHAT_MSG_WHISPER" then
        if not WI.db then return end
        local msg, sender = ...
        OnWhisper(msg, sender)
    elseif event == "PARTY_INVITE_REQUEST" then
        if not WI.db then return end
        local inviter = ...
        OnPartyInvite(inviter)
    end
end)

-- -------------------------------------------------------------------------
-- Minimap button
-- -------------------------------------------------------------------------
mb = CreateFrame("Button", "WhisperInviteMinimapButton", Minimap)
mb:SetWidth(31)
mb:SetHeight(31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Canonical minimap-button layout (LibDBIcon offsets): the TrackingBorder
-- texture's ring is drawn in the top-left area of its 53x53 canvas, so the
-- border anchors at TOPLEFT (0,0) and the icon/background are inset to sit
-- centered inside the visible ring.
local bg = mb:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetWidth(20)
bg:SetHeight(20)
bg:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -5)

local icon = mb:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\Spell_Nature_AstralRecal")
icon:SetWidth(17)
icon:SetHeight(17)
icon:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- trim square edges inside the round ring

local border = mb:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(53)
border:SetHeight(53)
border:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)

mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

UpdateMinimapButtonPosition = function()
    if not WI.db then return end
    -- Free-form position. If never placed (or migrating from the old angle
    -- format), seed a position from the stored/default angle once; after
    -- that, wherever the user drops the button is exactly where it stays.
    if WI.db.minimapX == nil or WI.db.minimapY == nil then
        local angle = math.rad(WI.db.minimapPos or 45)
        local radius = (Minimap:GetWidth() / 2) + 10
        WI.db.minimapX = math.cos(angle) * radius
        WI.db.minimapY = math.sin(angle) * radius
    end
    mb:ClearAllPoints()
    mb:SetPoint("CENTER", Minimap, "CENTER", WI.db.minimapX, WI.db.minimapY)
end

UpdateMinimapButtonLook = function()
    if WI.db and WI.db.enabled then
        icon:SetVertexColor(0, 1, 0)      -- green: listening
    else
        icon:SetVertexColor(1, 0.2, 0.2)  -- red: off
    end
end

local function RefreshMinimapTooltip(owner)
    if not GameTooltip:IsOwned(owner) then return end
    GameTooltip:ClearLines()
    GameTooltip:AddLine("WhisperInvite")
    GameTooltip:AddLine("Whisper-invite: " .. (WI.db.enabled and "|cFF00FF00Active|r" or "|cFFFF0000Off|r"))
    GameTooltip:AddLine("Keyword: |cFF00FFFF" .. WI.db.keyword .. "|r ("
        .. (WI.db.inviteScope ~= "everyone" and "greenlist only" or "everyone") .. ")")
    GameTooltip:AddLine("Auto-accept: " .. (WI.db.autoAccept and "|cFF00FF00On|r" or "|cFFFF0000Off|r")
        .. " |cFFC0C0C0(" .. #WhitelistSorted() .. " greenlighted)|r")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFFC0C0C0Left-Click:|r Toggle whisper-invite")
    GameTooltip:AddLine("|cFFC0C0C0Right-Click:|r Options")
    GameTooltip:AddLine("|cFFC0C0C0Shift + Drag:|r Move this button")
    GameTooltip:Show()
end

-- Drag: OnUpdate is attached only while dragging (not permanently).
local function DragUpdater(self)
    local xpos, ypos = GetCursorPosition()
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    xpos = xpos / scale
    ypos = ypos / scale
    local dx, dy = xpos - cx, ypos - cy
    -- Loose clamp so the button can sit on any ring/corner of any custom
    -- minimap but cannot be lost far off-screen.
    local limit = Minimap:GetWidth() + 60
    if dx > limit then dx = limit elseif dx < -limit then dx = -limit end
    if dy > limit then dy = limit elseif dy < -limit then dy = -limit end
    WI.db.minimapX = dx
    WI.db.minimapY = dy
    UpdateMinimapButtonPosition()
end

mb:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() and WI.db then
        self.isDragging = true
        self:SetScript("OnUpdate", DragUpdater)
    end
end)

mb:SetScript("OnMouseUp", function(self, button)
    if self.isDragging then
        self.isDragging = false
        self.suppressClick = true -- the release also fires OnClick; swallow it
        self:SetScript("OnUpdate", nil)
    end
end)

mb:SetScript("OnClick", function(self, button)
    if self.suppressClick then
        self.suppressClick = false
        return
    end
    if not WI.db then return end
    if button == "LeftButton" then
        WI.db.enabled = not WI.db.enabled
        UpdateMinimapButtonLook()
        RefreshOptionsPanel()
        RefreshMinimapTooltip(self)
        if WI.db.enabled then
            Msg("Whisper-invite |cFF00FF00enabled|r (keyword: |cFF00FFFF" .. WI.db.keyword .. "|r, exact match).")
        else
            Msg("Whisper-invite |cFFFF0000disabled|r.")
        end
    elseif button == "RightButton" then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
end)

mb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    RefreshMinimapTooltip(self)
end)

mb:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- -------------------------------------------------------------------------
-- Options panel (built lazily on ADDON_LOADED; ~390x390 budget)
-- -------------------------------------------------------------------------
local WL_ROWS       = 6
local WL_ROW_HEIGHT = 16
local wlRowButtons  = {}
local wlSelectedKey = nil

BuildOptionsPanel = function()
    if optionsPanel then return end

    local p = CreateFrame("Frame", "WhisperInviteOptionsPanel", UIParent)
    p.name = "WhisperInvite"
    optionsPanel = p

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("WhisperInvite")

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Keyword invites + auto-accept from greenlighted players.")

    -- --- Whisper-invite section -----------------------------------------
    local cbEnabled = CreateFrame("CheckButton", "WhisperInviteOptEnabled", p, "InterfaceOptionsCheckButtonTemplate")
    cbEnabled:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -8)
    _G[cbEnabled:GetName() .. "Text"]:SetText("Enable whisper-invite")
    cbEnabled:SetScript("OnClick", function(self)
        WI.db.enabled = self:GetChecked() and true or false
        UpdateMinimapButtonLook()
    end)

    local cbReply = CreateFrame("CheckButton", "WhisperInviteOptReply", p, "InterfaceOptionsCheckButtonTemplate")
    cbReply:SetPoint("TOPLEFT", cbEnabled, "BOTTOMLEFT", 0, -2)
    _G[cbReply:GetName() .. "Text"]:SetText("Whisper a confirmation back after inviting")
    cbReply:SetScript("OnClick", function(self)
        WI.db.autoReply = self:GetChecked() and true or false
    end)

    local kwLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    kwLabel:SetPoint("TOPLEFT", cbReply, "BOTTOMLEFT", 4, -10)
    kwLabel:SetText("Keyword:")

    local kwBox = CreateFrame("EditBox", "WhisperInviteOptKeyword", p, "InputBoxTemplate")
    kwBox:SetWidth(120)
    kwBox:SetHeight(20)
    kwBox:SetPoint("LEFT", kwLabel, "RIGHT", 12, 0)
    kwBox:SetAutoFocus(false)
    kwBox:SetMaxLetters(32)
    local function CommitKeyword(box)
        local text = strtrim(box:GetText() or "")
        if text == "" then
            box:SetText(WI.db.keyword)
        else
            WI.db.keyword = string.lower(text)
            box:SetText(WI.db.keyword)
            Msg("Keyword set to |cFF00FFFF" .. WI.db.keyword .. "|r.")
        end
        box:ClearFocus()
    end
    kwBox:SetScript("OnEnterPressed", CommitKeyword)
    kwBox:SetScript("OnEscapePressed", function(box)
        box:SetText(WI.db.keyword)
        box:ClearFocus()
    end)
    p.kwBox = kwBox

    local kwHint = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    kwHint:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", 0, -6)
    kwHint:SetTextColor(0.6, 0.6, 0.6)
    kwHint:SetText("The whisper must be exactly this word — keywords inside sentences never invite.")

    local cbScope = CreateFrame("CheckButton", "WhisperInviteOptScope", p, "InterfaceOptionsCheckButtonTemplate")
    cbScope:SetPoint("TOPLEFT", kwHint, "BOTTOMLEFT", -6, -6)
    _G[cbScope:GetName() .. "Text"]:SetText("Only greenlighted players can trigger the keyword")
    cbScope:SetScript("OnClick", function(self)
        WI.db.inviteScope = self:GetChecked() and "greenlist" or "everyone"
    end)

    -- --- Auto-accept section --------------------------------------------
    local cbAccept = CreateFrame("CheckButton", "WhisperInviteOptAccept", p, "InterfaceOptionsCheckButtonTemplate")
    cbAccept:SetPoint("TOPLEFT", cbScope, "BOTTOMLEFT", 0, -6)
    _G[cbAccept:GetName() .. "Text"]:SetText("Auto-accept invites from greenlighted players")
    cbAccept:SetScript("OnClick", function(self)
        WI.db.autoAccept = self:GetChecked() and true or false
    end)

    local addLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", cbAccept, "BOTTOMLEFT", 4, -10)
    addLabel:SetText("Player:")

    local addBox = CreateFrame("EditBox", "WhisperInviteOptAddName", p, "InputBoxTemplate")
    addBox:SetWidth(120)
    addBox:SetHeight(20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(12)

    local addBtn = CreateFrame("Button", "WhisperInviteOptAddBtn", p, "UIPanelButtonTemplate2")
    addBtn:SetWidth(80)
    addBtn:SetHeight(22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    addBtn:SetText("Greenlight")
    local function CommitAdd()
        local text = strtrim(addBox:GetText() or "")
        if text ~= "" then
            WhitelistAdd(text)
            addBox:SetText("")
        end
        addBox:ClearFocus()
    end
    addBtn:SetScript("OnClick", CommitAdd)
    addBox:SetScript("OnEnterPressed", CommitAdd)
    addBox:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)

    local remBtn = CreateFrame("Button", "WhisperInviteOptRemBtn", p, "UIPanelButtonTemplate2")
    remBtn:SetWidth(120)
    remBtn:SetHeight(22)
    remBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    remBtn:SetText("Remove selected")
    remBtn:SetScript("OnClick", function()
        if wlSelectedKey and WI.db.whitelist[wlSelectedKey] then
            WhitelistRemove(wlSelectedKey)
            wlSelectedKey = nil
        else
            Msg("Select a name in the list first.")
        end
    end)

    -- --- Whitelist scroll list ------------------------------------------
    local listBg = CreateFrame("Frame", "WhisperInviteOptListBg", p)
    listBg:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", -4, -10)
    listBg:SetWidth(220)
    listBg:SetHeight(WL_ROWS * WL_ROW_HEIGHT + 10)
    listBg:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)

    local scroll = CreateFrame("ScrollFrame", "WhisperInviteOptListScroll", listBg, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -26, 5)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, WL_ROW_HEIGHT, RefreshWhitelistRows)
    end)
    p.wlScroll = scroll

    for i = 1, WL_ROWS do
        local row = CreateFrame("Button", "WhisperInviteOptListRow" .. i, listBg)
        row:SetWidth(184)
        row:SetHeight(WL_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, 0)
        else
            row:SetPoint("TOPLEFT", wlRowButtons[i - 1], "BOTTOMLEFT", 0, 0)
        end
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 4, 0)
        row.text = fs
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:SetScript("OnClick", function(self)
            if self.key then
                wlSelectedKey = self.key
                RefreshWhitelistRows()
            end
        end)
        wlRowButtons[i] = row
    end

    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 4, -6)
    hint:SetText("Also: /wi allow <name>, /wi disallow <name>, /wi list")

    p:SetScript("OnShow", RefreshOptionsPanel)
    InterfaceOptions_AddCategory(p)
end

RefreshWhitelistRows = function()
    if not optionsPanel or not optionsPanel:IsVisible() then return end
    local names  = WhitelistSorted()
    local scroll = optionsPanel.wlScroll
    FauxScrollFrame_Update(scroll, #names, WL_ROWS, WL_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, WL_ROWS do
        local row  = wlRowButtons[i]
        local name = names[offset + i]
        if name then
            local key = string.lower(name)
            row.key = key
            if key == wlSelectedKey then
                row.text:SetText("|cFF00FF00> " .. name .. "|r")
            else
                row.text:SetText(name)
            end
            row:Show()
        else
            row.key = nil
            row.text:SetText("")
            row:Hide()
        end
    end
end

RefreshOptionsPanel = function()
    if not optionsPanel or not optionsPanel:IsVisible() or not WI.db then return end
    WhisperInviteOptEnabled:SetChecked(WI.db.enabled)
    WhisperInviteOptReply:SetChecked(WI.db.autoReply)
    WhisperInviteOptScope:SetChecked(WI.db.inviteScope ~= "everyone")
    WhisperInviteOptAccept:SetChecked(WI.db.autoAccept)
    optionsPanel.kwBox:SetText(WI.db.keyword or "inv")
    RefreshWhitelistRows()
end

-- -------------------------------------------------------------------------
-- Slash commands
-- -------------------------------------------------------------------------
SLASH_WHISPERINVITE1 = "/wi"
SLASH_WHISPERINVITE2 = "/whisperinvite"
SlashCmdList["WHISPERINVITE"] = function(input)
    if not WI.db then return end
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""

    if cmd == "" or cmd == "toggle" then
        WI.db.enabled = not WI.db.enabled
        UpdateMinimapButtonLook()
        RefreshOptionsPanel()
        Msg("Whisper-invite is now " .. (WI.db.enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r") .. ".")
    elseif cmd == "on" or cmd == "off" then
        WI.db.enabled = (cmd == "on")
        UpdateMinimapButtonLook()
        RefreshOptionsPanel()
        Msg("Whisper-invite is now " .. (WI.db.enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r") .. ".")
    elseif cmd == "keyword" or cmd == "kw" then
        if rest == "" then
            Msg("Current keyword: |cFF00FFFF" .. WI.db.keyword .. "|r (exact match). Usage: /wi keyword <word>")
        else
            WI.db.keyword = string.lower(strtrim(rest))
            RefreshOptionsPanel()
            Msg("Keyword set to |cFF00FFFF" .. WI.db.keyword .. "|r.")
        end
    elseif cmd == "scope" then
        rest = string.lower(strtrim(rest))
        if rest == "greenlist" or rest == "everyone" then
            WI.db.inviteScope = rest
            RefreshOptionsPanel()
            if rest == "greenlist" then
                Msg("Keyword invites restricted to |cFF00FF00greenlighted players only|r (" .. #WhitelistSorted() .. " on the list).")
            else
                Msg("Keyword invites open to |cFFFFFF00everyone|r.")
            end
        else
            Msg("Usage: /wi scope greenlist | everyone  (current: " .. WI.db.inviteScope .. ")")
        end
    elseif cmd == "allow" or cmd == "add" then
        WhitelistAdd(rest)
    elseif cmd == "disallow" or cmd == "remove" then
        WhitelistRemove(rest)
    elseif cmd == "list" then
        local names = WhitelistSorted()
        if #names == 0 then
            Msg("Greenlight list is empty. Add with /wi allow <name>.")
        else
            Msg("Greenlighted (" .. #names .. "): " .. table.concat(names, ", "))
        end
    elseif cmd == "accept" then
        WI.db.autoAccept = not WI.db.autoAccept
        RefreshOptionsPanel()
        Msg("Auto-accept is now " .. (WI.db.autoAccept and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r") .. ".")
    elseif cmd == "reply" then
        WI.db.autoReply = not WI.db.autoReply
        RefreshOptionsPanel()
        Msg("Invite confirmation whisper is now " .. (WI.db.autoReply and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r") .. ".")
    elseif cmd == "options" or cmd == "config" then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    elseif cmd == "status" then
        Msg("Whisper-invite: " .. (WI.db.enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r")
            .. " | Keyword: |cFF00FFFF" .. WI.db.keyword .. "|r (exact, "
            .. WI.db.inviteScope .. ")"
            .. " | Auto-accept: " .. (WI.db.autoAccept and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r")
            .. " | Greenlighted: " .. #WhitelistSorted())
    else
        Msg("Commands:")
        Msg("  /wi  or  /wi toggle  — toggle whisper-invite")
        Msg("  /wi on | off — set whisper-invite explicitly")
        Msg("  /wi keyword <word> — set the invite keyword")
        Msg("  /wi scope greenlist|everyone — who may trigger the keyword")
        Msg("  /wi allow <name> | disallow <name> | list — greenlight list")
        Msg("  /wi accept — toggle auto-accept | /wi reply — toggle reply whisper")
        Msg("  /wi status | options")
    end
end
