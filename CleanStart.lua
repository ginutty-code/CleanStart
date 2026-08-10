-- CleanStart - Filter addon messages from chat

local ADDON_NAME = "!CleanStart"
-- Read from the .toc instead of a second hardcoded constant, so it can't drift.
local ADDON_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "unknown"

if not CleanStartDB then CleanStartDB = {} end
local db = CleanStartDB

local originalAddMessage = DEFAULT_CHAT_FRAME.AddMessage
local originalPrint = print

local captureActive = true
local capturedMessages = {}
local hookedFrames = {}
local playerLoginFired = false  -- guards against PLAYER_LOGIN double-firing

local MSG_ADDON = "addon"      -- no ID = addon message (blocked by default)
local MSG_SYSTEM = "system"    -- has ID = system/player message (user choice)

-- ─── Database Defaults ─────────────────────────────────────────────────────────

local function EnsureDefaults()
    if db.enabled == nil then db.enabled = true end
    if db.debug == nil then db.debug = false end
    if db.blockWindow == nil then db.blockWindow = 3 end
    if not db.customFilters then db.customFilters = {} end
    if not db.whitelist then db.whitelist = {} end
    if not db.blockedMessageIds then db.blockedMessageIds = {} end
end

-- ─── Filter Matching Functions ─────────────────────────────────────────────────

local function MatchesCustomFilter(msg)
    if type(msg) ~= "string" then return false end
    if not db.customFilters then return false end
    local msgLower = string.lower(msg)
    for _, filter in ipairs(db.customFilters) do
        local filterText = filter
        local matchType = "contains"  -- default
        
        if string.sub(filter, 1, 1) == "^" then
            matchType = "starts"
            filterText = string.sub(filter, 2)
        elseif string.sub(filter, 1, 1) == "=" then
            matchType = "exact"
            filterText = string.sub(filter, 2)
        end
        
        local filterLower = string.lower(filterText)
        
        if matchType == "contains" then
            if string.find(msgLower, filterLower, 1, true) then
                return true, filter
            end
        elseif matchType == "starts" then
            if string.sub(msgLower, 1, #filterLower) == filterLower then
                return true, filter
            end
        elseif matchType == "exact" then
            if msgLower == filterLower then
                return true, filter
            end
        end
    end
    return false
end

local function IsWhitelisted(msg)
    if type(msg) ~= "string" then return false end
    if not db.whitelist then return false end
    local msgLower = string.lower(msg)
    for _, entry in ipairs(db.whitelist) do
        if string.find(msgLower, string.lower(entry), 1, true) then
            return true
        end
    end
    return false
end

local function IsMessageIdBlocked(msgId)
    if not msgId or type(msgId) ~= "number" then return false end
    if not db.blockedMessageIds then return false end
    for _, blockedId in ipairs(db.blockedMessageIds) do
        if blockedId == msgId then
            return true
        end
    end
    return false
end

-- ─── Message Capture System ─────────────────────────────────────────────────────

local function CaptureMessage(msg, msgId, r, g, b)
    if type(msg) ~= "string" then return end
    if string.find(msg, "CleanStart", 1, true) then return end

    
    local hasMessageId = msgId and type(msgId) == "number"
    local msgType = hasMessageId and MSG_SYSTEM or MSG_ADDON
    local defaultAction = (msgType == MSG_ADDON) and "blocked" or "allowed"

    local userAction = nil
    local filterType = nil
    if msgType == MSG_SYSTEM then
        if IsMessageIdBlocked(msgId) then
            userAction = "blocked"
            filterType = "id"
        elseif db.customFilters then
            local msgLower = string.lower(msg)
            for _, filter in ipairs(db.customFilters) do
                if string.sub(filter, 1, 1) == "=" then
                    local filterTextLower = string.lower(string.sub(filter, 2))
                    if msgLower == filterTextLower then
                        userAction = "blocked"
                        filterType = "exact"
                        break
                    end
                elseif string.sub(filter, 1, 1) == "^" then
                    local pattern = string.lower(string.sub(filter, 2))
                    if string.sub(msgLower, 1, #pattern) == pattern then
                        userAction = "blocked"
                        filterType = "starts"
                        break
                    end
                else
                    local pattern = string.lower(filter)
                    if string.find(msgLower, pattern, 1, true) then
                        userAction = "blocked"
                        filterType = "contains"
                        break
                    end
                end
            end
        end
    end
    
    table.insert(capturedMessages, {
        text = msg,
        id = msgId,
        msgType = msgType,
        defaultAction = defaultAction,
        userAction = userAction,
        filterType = filterType,
        r = r,
        g = g,
        b = b,
        index = #capturedMessages + 1
    })
    
    if db and db.debug then
        originalPrint("|cFF00AAFFCleanStart:|r Captured [" .. msgType .. "] " .. 
            (hasMessageId and ("ID:" .. msgId .. " ") or "") .. "\"" .. msg .. "\"")
    end
end

-- ─── Main Filter Logic ─────────────────────────────────────────────────────────

local function ShouldFilter(msg, msgId)
    if not db or not db.enabled then return false end
    if type(msg) ~= "string" then return false end

    if string.find(msg, "CleanStart", 1, true) then
        return false
    end

    if IsWhitelisted(msg) then
        if db and db.debug then
            originalPrint("|cFF00AAFFCleanStart:|r Whitelisted: \"" .. msg .. "\"")
        end
        return false
    end
    
    if IsMessageIdBlocked(msgId) then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Blocked by ID: " .. tostring(msgId))
        end
        return true
    end
    
    local matched, word = MatchesCustomFilter(msg)
    if matched then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Custom filter blocked: \"" .. msg .. "\"")
        end
        return true
    end

    local hasMessageId = msgId and type(msgId) == "number"

    -- Only reached during the capture window (hooks are removed once it closes).
    if captureActive then
        return not hasMessageId
    end

    return false
end

-- ─── Chat Frame Hooks ──────────────────────────────────────────────────────────

local function ProcessCapturedMessage(msg, msgId, r, g, b)
    if not captureActive then return false end
    CaptureMessage(msg, msgId, r, g, b)
    return ShouldFilter(msg, msgId)
end

-- Fail-open: an error here must never eat a real chat message. Forward it to
-- the normal error handler (so BugGrabber etc. still catch it) and let the
-- message through instead of silently dropping it.
local function ShouldBlockMessage(msg, msgId, r, g, b)
    local ok, blockOrErr = pcall(ProcessCapturedMessage, msg, msgId, r, g, b)
    if not ok then
        geterrorhandler()(blockOrErr)
        return false
    end
    return blockOrErr
end

local function HookChatFrame(frame)
    if frame and frame.AddMessage and not hookedFrames[frame] then
        local orig = frame.AddMessage
        hookedFrames[frame] = orig
        frame.AddMessage = function(self, msg, r, g, b, id, ...)
            if ShouldBlockMessage(msg, id, r, g, b) then return end
            orig(self, msg, r, g, b, id, ...)
        end
    end
end

local function UnhookAllFrames()
    -- Unhooking while in combat can taint the chat frames, so defer until combat ends.
    if InCombatLockdown() then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Cannot unhook frames while in combat, will retry later.")
        end
        C_Timer.After(1, function()
            if InCombatLockdown() then
                C_Timer.After(1, UnhookAllFrames)
            else
                UnhookAllFrames()
            end
        end)
        return
    end

    for frame, orig in pairs(hookedFrames) do
        if frame then
            frame.AddMessage = orig
        end
    end
    hookedFrames = {}

    DEFAULT_CHAT_FRAME.AddMessage = originalAddMessage
    print = originalPrint

    if db and db.debug then
        originalPrint("|cFF00FF00CleanStart:|r Hooks removed, addon inactive.")
    end
end

-- Hooked immediately at file load, before PLAYER_LOGIN, so nothing during the
-- capture window is missed.
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg, r, g, b, id, ...)
    if ShouldBlockMessage(msg, id, r, g, b) then return end
    originalAddMessage(self, msg, r, g, b, id, ...)
end
hookedFrames[DEFAULT_CHAT_FRAME] = originalAddMessage

-- Same fail-open contract as ShouldBlockMessage.
local function ShouldBlockPrint(...)
    if not captureActive then return false end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    local msg = table.concat(parts, " ")
    CaptureMessage(msg, nil, 1, 1, 1)
    return ShouldFilter(msg, nil)
end

print = function(...)
    local ok, block = pcall(ShouldBlockPrint, ...)
    if not ok then
        geterrorhandler()(block)
    elseif block then
        return
    end
    originalPrint(...)
end

-- ─── GUI System ────────────────────────────────────────────────────────────────

local guiFrame = nil
local scrollFrame = nil
local scrollChild = nil
local messageRows = {}
local editDialog = nil
local filtersListFrame = nil

-- ─── ESC Key Handling ──────────────────────────────────────────────────────────

-- Proxy frame that closes our windows one at a time on Escape (topmost first).
-- Must be defined before the GUI functions that reference it.
local escProxyFrame = CreateFrame("Frame", "CleanStartEscProxy", UIParent)
escProxyFrame:Hide()
escProxyFrame:SetScript("OnHide", function(self)
    local hasEdit = editDialog and editDialog:IsShown()
    local hasFilters = filtersListFrame and filtersListFrame:IsShown()
    local hasGui = guiFrame and guiFrame:IsShown()

    if hasEdit then
        editDialog:Hide()
        self:Show()
    elseif hasFilters then
        filtersListFrame:Hide()
        self:Show()
    elseif hasGui then
        guiFrame:Hide()
    end
end)

table.insert(UISpecialFrames, "CleanStartEscProxy")

-- Keeps escProxyFrame in sync with our windows. Without this, closing a
-- window via its "Close" button (instead of Escape) leaves escProxyFrame
-- registered as shown, so the *next unrelated* Escape press gets silently
-- swallowed by it instead of closing whatever the player actually meant to.
local function SyncEscProxy()
    local anyShown = (guiFrame and guiFrame:IsShown())
        or (filtersListFrame and filtersListFrame:IsShown())
        or (editDialog and editDialog:IsShown())
    if anyShown then
        escProxyFrame:Show()
    else
        escProxyFrame:Hide()
    end
end

local function CreateGUI()
    if guiFrame then return end

    guiFrame = CreateFrame("Frame", "CleanStartGUI", UIParent, "BasicFrameTemplateWithInset")
    guiFrame:SetSize(600, 500)
    guiFrame:SetPoint("CENTER")
    guiFrame:SetMovable(true)
    guiFrame:EnableMouse(true)
    guiFrame:SetResizable(true)
    if guiFrame.SetResizeBounds then
        local maxW = UIParent:GetWidth() or 1920
        local maxH = UIParent:GetHeight() or 1080
        guiFrame:SetResizeBounds(400, 300, maxW - 16, maxH - 16)
    end
    guiFrame:RegisterForDrag("LeftButton")
    guiFrame:SetScript("OnDragStart", guiFrame.StartMoving)
    guiFrame:SetScript("OnDragStop", guiFrame.StopMovingOrSizing)
    guiFrame:SetClampedToScreen(true)
    guiFrame:Hide()
    guiFrame:HookScript("OnHide", SyncEscProxy)

    guiFrame.title = guiFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guiFrame.title:SetPoint("TOP", guiFrame, "TOP", 0, -5)
    guiFrame.title:SetText("CleanStart - Captured Messages")

    local resizeHandle = CreateFrame("Button", nil, guiFrame)
    resizeHandle:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -5, 5)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function()
        guiFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        guiFrame:StopMovingOrSizing()
    end)

    guiFrame:SetScript("OnSizeChanged", function()
        if scrollChild and scrollFrame then
            scrollChild:SetWidth(scrollFrame:GetWidth() - 20)
            if guiFrame:IsShown() and #capturedMessages > 0 then
                CleanStart_RefreshMessageList()
            end
        end
    end)

    local buttonFrame = CreateFrame("Frame", nil, guiFrame)
    buttonFrame:SetPoint("BOTTOMLEFT", guiFrame, "BOTTOMLEFT", 10, 30)
    buttonFrame:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -10, 30)
    buttonFrame:SetHeight(25)

    local filtersListButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    filtersListButton:SetPoint("LEFT", buttonFrame, "LEFT", 0, 0)
    filtersListButton:SetSize(90, 25)
    filtersListButton:SetText("Filters List")
    filtersListButton:SetScript("OnClick", function()
        CleanStart_ToggleFiltersList()
    end)

    local clearFiltersButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    clearFiltersButton:SetPoint("LEFT", filtersListButton, "RIGHT", 10, 0)
    clearFiltersButton:SetSize(90, 25)
    clearFiltersButton:SetText("Clear Filters")
    clearFiltersButton:SetScript("OnClick", function()
        db.customFilters = {}
        db.blockedMessageIds = {}
        CleanStart_RefreshMessageList()
        originalPrint("|cFF00FF00CleanStart:|r All filters cleared.")
    end)

    local closeButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    closeButton:SetPoint("RIGHT", buttonFrame, "RIGHT", -20, 0)
    closeButton:SetSize(70, 25)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() guiFrame:Hide() end)

    scrollFrame = CreateFrame("ScrollFrame", "CleanStartScrollFrame", guiFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", guiFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -30, 60)

    scrollChild = CreateFrame("Frame", "CleanStartScrollChild", scrollFrame)
    scrollChild:SetSize(560, 1)
    scrollFrame:SetScrollChild(scrollChild)

    guiFrame.statusText = guiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guiFrame.statusText:SetPoint("BOTTOMLEFT", guiFrame, "BOTTOMLEFT", 15, 10)
    guiFrame.statusText:SetText("")
end

local function CreateEditDialog()
    if editDialog then return end

    editDialog = CreateFrame("Frame", "CleanStartEditDialog", UIParent, "BasicFrameTemplateWithInset")
    editDialog:SetSize(500, 400)
    editDialog:SetPoint("CENTER")
    editDialog:SetMovable(true)
    editDialog:EnableMouse(true)
    editDialog:RegisterForDrag("LeftButton")
    editDialog:SetScript("OnDragStart", editDialog.StartMoving)
    editDialog:SetScript("OnDragStop", editDialog.StopMovingOrSizing)
    editDialog:SetClampedToScreen(true)
    editDialog:Hide()
    editDialog:HookScript("OnHide", SyncEscProxy)
    editDialog:SetFrameStrata("DIALOG")

    editDialog.title = editDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editDialog.title:SetPoint("TOP", editDialog, "TOP", 0, -5)
    editDialog.title:SetText("Custom Filter")

    editDialog.instructions = editDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editDialog.instructions:SetPoint("TOP", editDialog, "TOP", 15, -30)
    editDialog.instructions:SetText("Edit the filter text.\n Add prefix ^ for starts-with match, or no prefix for contains match")

    editDialog.blockByIdCheckbox = CreateFrame("CheckButton", "CleanStartBlockByIdCheck", editDialog, "ChatConfigCheckButtonTemplate")
    editDialog.blockByIdCheckbox:SetPoint("BOTTOMLEFT", editDialog, "BOTTOMLEFT", 15, 60)
    editDialog.blockByIdCheckbox.Text = editDialog.blockByIdCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editDialog.blockByIdCheckbox.Text:SetPoint("LEFT", editDialog.blockByIdCheckbox, "RIGHT", 5, 0)
    editDialog.blockByIdCheckbox.Text:SetText("Block by Message ID (blocks all messages with this system ID)")
    editDialog.blockByIdCheckbox:SetHitRectInsets(0, -editDialog.blockByIdCheckbox.Text:GetStringWidth(), 0, 0)

    local scrollFrameEdit = CreateFrame("ScrollFrame", "CleanStartEditScrollFrame", editDialog, "UIPanelScrollFrameTemplate")
    scrollFrameEdit:SetPoint("TOPLEFT", editDialog, "TOPLEFT", 15, -90)
    scrollFrameEdit:SetPoint("BOTTOMRIGHT", editDialog, "BOTTOMRIGHT", -35, 90)

    local editBox = CreateFrame("EditBox", "CleanStartEditBox", scrollFrameEdit)
    editBox:SetSize(450, 200)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlight)
    editBox:SetScript("OnEscapePressed", function() editDialog:Hide() end)
    scrollFrameEdit:SetScrollChild(editBox)
    editDialog.editBox = editBox

    local cancelBtn = CreateFrame("Button", nil, editDialog, "UIPanelButtonTemplate")
    cancelBtn:SetPoint("BOTTOMRIGHT", editDialog, "BOTTOMRIGHT", -10, 10)
    cancelBtn:SetSize(70, 25)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() editDialog:Hide() end)

    local okBtn = CreateFrame("Button", nil, editDialog, "UIPanelButtonTemplate")
    okBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    okBtn:SetSize(70, 25)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", function()
        if editDialog.onConfirm then
            editDialog.onConfirm(editDialog.editBox:GetText(), editDialog.blockByIdCheckbox:GetChecked())
        end
        editDialog:Hide()
    end)
end

local function ShowEditDialog(msgText, msgId, onConfirm)
    if not editDialog then
        CreateEditDialog()
    end
    
    editDialog.editBox:SetText(msgText)
    editDialog.editBox:HighlightText()
    editDialog.editBox:SetFocus()
    editDialog.onConfirm = onConfirm

    if msgId and type(msgId) == "number" then
        editDialog.blockByIdCheckbox:Show()
        editDialog.blockByIdCheckbox:SetChecked(false)
        editDialog.blockByIdCheckbox.msgId = msgId
    else
        editDialog.blockByIdCheckbox:Hide()
        editDialog.blockByIdCheckbox.msgId = nil
    end
    
    editDialog:Show()
    escProxyFrame:Show()
end

function CleanStart_RefreshMessageList()
    if not scrollChild then return end

    for _, row in ipairs(messageRows) do
        if row.frame then
            row.frame:Hide()
            row.frame:SetParent(nil)
        end
    end
    messageRows = {}

    local addonCount = 0
    local systemCount = 0
    local blockedCount = 0
    local allowedCount = 0

    for _, msg in ipairs(capturedMessages) do
        if msg.msgType == MSG_ADDON then
            addonCount = addonCount + 1
        else
            systemCount = systemCount + 1
            if msg.userAction == "blocked" then
                blockedCount = blockedCount + 1
            elseif msg.userAction == "allowed" then
                allowedCount = allowedCount + 1
            end
        end
    end

    guiFrame.statusText:SetText(string.format(
        "Addon: %d (blocked during login) | System: %d (Blocked: %d)",
        addonCount, systemCount, blockedCount))

    local yOffset = -5
    local rowHeight = 75
    local maxDisplay = 100  -- cap for render performance

    local messagesToShow = #capturedMessages
    local startIndex = math.max(1, messagesToShow - maxDisplay + 1)

    for i = startIndex, messagesToShow do
        local msg = capturedMessages[i]
        local rowIndex = i - startIndex + 1

        local rowFrame = CreateFrame("Frame", "CleanStartRow" .. rowIndex, scrollChild)
        rowFrame:SetHeight(rowHeight)
        rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        rowFrame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 10, yOffset)

        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        if msg.msgType == MSG_ADDON then
            rowFrame.bg:SetColorTexture(0.4, 0.2, 0.2, 0.3)
        else
            rowFrame.bg:SetColorTexture(0.2, 0.4, 0.2, 0.3)
        end

        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        if msg.msgType == MSG_ADDON then
            typeText:SetText("|cFFFF6666[ADDON]|r ID: none")
        else
            typeText:SetText("|cFF66FF66[SYSTEM]|r ID: " .. tostring(msg.id))
        end

        local msgText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        msgText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -20)
        msgText:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -25, 30)
        msgText:SetJustifyH("LEFT")
        msgText:SetJustifyV("TOP")
        msgText:SetWordWrap(true)
        local displayText = msg.text
        if #displayText > 500 then
            displayText = string.sub(displayText, 1, 497) .. "..."
        end
        msgText:SetText(displayText)

        if msg.msgType == MSG_SYSTEM then
            local statusText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -5, -3)
            local isBlocked = false
            local blockType = nil

            if IsMessageIdBlocked(msg.id) then
                isBlocked = true
                blockType = "id"
            else
                local msgTextLower = string.lower(msg.text)
                for _, filter in ipairs(db.customFilters) do
                    if string.sub(filter, 1, 1) == "=" then
                        if string.lower(string.sub(filter, 2)) == msgTextLower then
                            isBlocked = true
                            blockType = "exact"
                            break
                        end
                    elseif string.sub(filter, 1, 1) == "^" then
                        local pattern = string.lower(string.sub(filter, 2))
                        if string.sub(msgTextLower, 1, #pattern) == pattern then
                            isBlocked = true
                            blockType = "starts"
                            break
                        end
                    else
                        local pattern = string.lower(filter)
                        if string.find(msgTextLower, pattern, 1, true) then
                            isBlocked = true
                            blockType = "contains"
                            break
                        end
                    end
                end
            end

            if isBlocked then
                statusText:SetText("|cFFFF0000BLOCKED (" .. blockType .. ")|r")
                msg.userAction = "blocked"
                msg.filterType = blockType
            else
                statusText:SetText("|cFFAAAAAADefault: allowed|r")
                msg.userAction = nil
                msg.filterType = nil
            end

            -- Rightmost: Custom, then Block, then Allow.
            local customBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            customBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -5, 5)
            customBtn:SetSize(70, 22)
            customBtn:SetText("Custom")
            customBtn:SetScript("OnClick", function()
                ShowEditDialog(msg.text, msg.id, function(filterText, blockById)
                    if blockById and msg.id then
                        local alreadyBlocked = false
                        for _, blockedId in ipairs(db.blockedMessageIds) do
                            if blockedId == msg.id then
                                alreadyBlocked = true
                                break
                            end
                        end
                        if not alreadyBlocked then
                            table.insert(db.blockedMessageIds, msg.id)
                        end
                        msg.userAction = "blocked"
                        msg.filterType = "id"
                        if db.debug then
                            originalPrint("|cFFFF6600CleanStart:|r Blocked by ID: " .. msg.id)
                        end
                    elseif filterText and filterText ~= "" then
                        local alreadyBlocked = false
                        for _, filter in ipairs(db.customFilters) do
                            if filter == filterText then
                                alreadyBlocked = true
                                break
                            end
                        end
                        if not alreadyBlocked then
                            table.insert(db.customFilters, filterText)
                        end
                        msg.userAction = "blocked"
                        if string.sub(filterText, 1, 1) == "=" then
                            msg.filterType = "exact"
                        elseif string.sub(filterText, 1, 1) == "^" then
                            msg.filterType = "starts"
                        else
                            msg.filterType = "contains"
                        end
                        if db.debug then
                            originalPrint("|cFFFF6600CleanStart:|r Blocked (custom): \"" .. filterText .. "\"")
                        end
                    end
                    CleanStart_RefreshMessageList()
                end)
            end)

            local blockBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            blockBtn:SetPoint("RIGHT", customBtn, "LEFT", -5, 0)
            blockBtn:SetSize(70, 22)
            blockBtn:SetText("Block")
            blockBtn:SetScript("OnClick", function()
                local filterText = "=" .. msg.text
                local alreadyBlocked = false
                for _, filter in ipairs(db.customFilters) do
                    if filter == filterText then
                        alreadyBlocked = true
                        break
                    end
                end
                if not alreadyBlocked then
                    table.insert(db.customFilters, filterText)
                end
                msg.userAction = "blocked"
                msg.filterType = "exact"
                CleanStart_RefreshMessageList()
                if db.debug then
                    originalPrint("|cFFFF6600CleanStart:|r Blocked (exact): \"" .. msg.text .. "\"")
                end
            end)

            local allowBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            allowBtn:SetPoint("RIGHT", blockBtn, "LEFT", -5, 0)
            allowBtn:SetSize(70, 22)
            allowBtn:SetText("Allow")
            allowBtn:SetScript("OnClick", function()
                local msgTextLower = string.lower(msg.text)
                for j = #db.customFilters, 1, -1 do
                    local filter = db.customFilters[j]
                    if string.sub(filter, 1, 1) == "=" then
                        if string.lower(string.sub(filter, 2)) == msgTextLower then
                            table.remove(db.customFilters, j)
                        end
                    elseif string.sub(filter, 1, 1) == "^" then
                        local pattern = string.lower(string.sub(filter, 2))
                        if string.sub(msgTextLower, 1, #pattern) == pattern then
                            table.remove(db.customFilters, j)
                        end
                    else
                        local pattern = string.lower(filter)
                        if string.find(msgTextLower, pattern, 1, true) then
                            table.remove(db.customFilters, j)
                        end
                    end
                end
                if msg.id then
                    for j = #db.blockedMessageIds, 1, -1 do
                        if db.blockedMessageIds[j] == msg.id then
                            table.remove(db.blockedMessageIds, j)
                        end
                    end
                end
                msg.userAction = nil
                msg.filterType = nil
                CleanStart_RefreshMessageList()
                if db.debug then
                    originalPrint("|cFF00FF00CleanStart:|r Allowed message: \"" .. msg.text .. "\"")
                end
            end)
        else
            local statusText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -5, -3)
            statusText:SetText("|cFFFF6666Blocked by default|r")
        end

        table.insert(messageRows, {frame = rowFrame, msg = msg})
        yOffset = yOffset - rowHeight - 2
    end

    local totalHeight = math.abs(yOffset) + 5
    scrollChild:SetHeight(math.max(totalHeight, 1))
end

function CleanStart_ToggleGUI()
    if not guiFrame then
        CreateGUI()
    end
    
    if guiFrame:IsShown() then
        guiFrame:Hide()
    else
        CleanStart_RefreshMessageList()
        guiFrame:Show()
        escProxyFrame:Show()  -- Enable ESC handling
    end
end

-- ─── Filters List Window ───────────────────────────────────────────────────────

local filtersListScrollFrame = nil
local filtersListScrollChild = nil
local filterRows = {}

local function RefreshFiltersList()
    if not filtersListScrollChild then return end

    for _, row in ipairs(filterRows) do
        if row.frame then
            row.frame:Hide()
            row.frame:SetParent(nil)
        end
    end
    filterRows = {}
    
    local yOffset = -5
    local rowHeight = 75

    for i, filter in ipairs(db.customFilters) do
        local filterType = "contains"
        local displayText = filter
        if string.sub(filter, 1, 1) == "=" then
            filterType = "exact"
            displayText = string.sub(filter, 2)
        elseif string.sub(filter, 1, 1) == "^" then
            filterType = "starts"
            displayText = string.sub(filter, 2)
        end

        local rowFrame = CreateFrame("Frame", "CleanStartFilterRow" .. i, filtersListScrollChild)
        rowFrame:SetHeight(rowHeight)
        rowFrame:SetPoint("TOPLEFT", filtersListScrollChild, "TOPLEFT", 0, yOffset)
        rowFrame:SetPoint("TOPRIGHT", filtersListScrollChild, "TOPRIGHT", 10, yOffset)

        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        rowFrame.bg:SetColorTexture(0.2, 0.3, 0.5, 0.3)

        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        typeText:SetText("|cFF00AAFF[" .. string.upper(filterType) .. " FILTER]|r")

        local filterTextWidget = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        filterTextWidget:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -20)
        filterTextWidget:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -25, 30)
        filterTextWidget:SetJustifyH("LEFT")
        filterTextWidget:SetJustifyV("TOP")
        filterTextWidget:SetWordWrap(true)
        local displayTextTruncated = displayText
        if #displayTextTruncated > 500 then
            displayTextTruncated = string.sub(displayTextTruncated, 1, 497) .. "..."
        end
        filterTextWidget:SetText(displayTextTruncated)

        local editBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -5, 5)
        editBtn:SetSize(70, 22)
        editBtn:SetText("Edit")
        editBtn:SetScript("OnClick", function()
            ShowEditDialog(displayText, nil, function(newFilterText, blockById)
                if newFilterText and newFilterText ~= "" then
                    db.customFilters[i] = newFilterText
                    RefreshFiltersList()
                    CleanStart_RefreshMessageList()
                    originalPrint("|cFF00FF00CleanStart:|r Filter updated.")
                end
            end)
        end)

        local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        removeBtn:SetPoint("RIGHT", editBtn, "LEFT", -5, 0)
        removeBtn:SetSize(70, 22)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            table.remove(db.customFilters, i)
            RefreshFiltersList()
            CleanStart_RefreshMessageList()
            originalPrint("|cFF00FF00CleanStart:|r Filter removed.")
        end)

        table.insert(filterRows, {frame = rowFrame, filter = filter, filterType = "text", index = i})
        yOffset = yOffset - rowHeight - 2
    end

    for i, msgId in ipairs(db.blockedMessageIds) do
        local rowFrame = CreateFrame("Frame", "CleanStartBlockedIdRow" .. i, filtersListScrollChild)
        rowFrame:SetHeight(rowHeight)
        rowFrame:SetPoint("TOPLEFT", filtersListScrollChild, "TOPLEFT", 0, yOffset)
        rowFrame:SetPoint("TOPRIGHT", filtersListScrollChild, "TOPRIGHT", 10, yOffset)

        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        rowFrame.bg:SetColorTexture(0.5, 0.3, 0.2, 0.3)

        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        typeText:SetText("|cFFFF6600[BLOCKED MESSAGE ID]|r")

        local filterTextWidget = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        filterTextWidget:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -20)
        filterTextWidget:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -25, 30)
        filterTextWidget:SetJustifyH("LEFT")
        filterTextWidget:SetJustifyV("TOP")
        filterTextWidget:SetWordWrap(true)
        filterTextWidget:SetText("Message ID: " .. tostring(msgId) .. "\n\nThis blocks all system messages with this ID.")

        -- Edit is disabled: ID filters have nothing to edit, only remove.
        local editBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -125, 5)
        editBtn:SetSize(70, 22)
        editBtn:SetText("Edit")
        editBtn:Disable()

        local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        removeBtn:SetPoint("LEFT", editBtn, "RIGHT", 5, 0)
        removeBtn:SetSize(70, 22)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            table.remove(db.blockedMessageIds, i)
            RefreshFiltersList()
            CleanStart_RefreshMessageList()
            originalPrint("|cFF00FF00CleanStart:|r Blocked ID removed.")
        end)

        table.insert(filterRows, {frame = rowFrame, filterId = msgId, filterType = "id", index = i})
        yOffset = yOffset - rowHeight - 2
    end

    if #db.customFilters == 0 and #db.blockedMessageIds == 0 then
        local noFiltersText = filtersListScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noFiltersText:SetPoint("TOP", filtersListScrollChild, "TOP", 0, -20)
        noFiltersText:SetText("|cFFAAAAAANo filters configured.|r\n\nUse the Block/Custom buttons on messages to create filters.")
    end

    local totalHeight = math.abs(yOffset) + 5
    filtersListScrollChild:SetHeight(math.max(totalHeight, 1))
end

local function CreateFiltersListWindow()
    if filtersListFrame then return end

    filtersListFrame = CreateFrame("Frame", "CleanStartFiltersListGUI", UIParent, "BasicFrameTemplateWithInset")
    filtersListFrame:SetSize(600, 500)
    filtersListFrame:SetPoint("CENTER")
    filtersListFrame:SetMovable(true)
    filtersListFrame:EnableMouse(true)
    filtersListFrame:SetResizable(true)
    if filtersListFrame.SetResizeBounds then
        local maxW = UIParent:GetWidth() or 1920
        local maxH = UIParent:GetHeight() or 1080
        filtersListFrame:SetResizeBounds(400, 300, maxW - 16, maxH - 16)
    end
    filtersListFrame:RegisterForDrag("LeftButton")
    filtersListFrame:SetScript("OnDragStart", filtersListFrame.StartMoving)
    filtersListFrame:SetScript("OnDragStop", filtersListFrame.StopMovingOrSizing)
    filtersListFrame:SetClampedToScreen(true)
    filtersListFrame:SetFrameStrata("HIGH")
    filtersListFrame:Hide()
    filtersListFrame:HookScript("OnHide", SyncEscProxy)

    filtersListFrame.title = filtersListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    filtersListFrame.title:SetPoint("TOP", filtersListFrame, "TOP", 0, -5)
    filtersListFrame.title:SetText("CleanStart - Filters List")

    local resizeHandle = CreateFrame("Button", nil, filtersListFrame)
    resizeHandle:SetPoint("BOTTOMRIGHT", filtersListFrame, "BOTTOMRIGHT", -5, 5)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function()
        filtersListFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        filtersListFrame:StopMovingOrSizing()
    end)

    filtersListFrame:SetScript("OnSizeChanged", function()
        if filtersListScrollChild and filtersListScrollFrame then
            filtersListScrollChild:SetWidth(filtersListScrollFrame:GetWidth() - 20)
            if filtersListFrame:IsShown() and (#db.customFilters > 0 or #db.blockedMessageIds > 0) then
                RefreshFiltersList()
            end
        end
    end)

    local buttonFrame = CreateFrame("Frame", nil, filtersListFrame)
    buttonFrame:SetPoint("BOTTOMLEFT", filtersListFrame, "BOTTOMLEFT", 10, 30)
    buttonFrame:SetPoint("BOTTOMRIGHT", filtersListFrame, "BOTTOMRIGHT", -10, 30)
    buttonFrame:SetHeight(25)

    local closeButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    closeButton:SetPoint("RIGHT", buttonFrame, "RIGHT", -20, 0)
    closeButton:SetSize(70, 25)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() filtersListFrame:Hide() end)

    filtersListFrame.statusText = filtersListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filtersListFrame.statusText:SetPoint("BOTTOMLEFT", filtersListFrame, "BOTTOMLEFT", 15, 10)
    filtersListFrame.statusText:SetText("")

    filtersListScrollFrame = CreateFrame("ScrollFrame", "CleanStartFiltersListScrollFrame", filtersListFrame, "UIPanelScrollFrameTemplate")
    filtersListScrollFrame:SetPoint("TOPLEFT", filtersListFrame, "TOPLEFT", 10, -30)
    filtersListScrollFrame:SetPoint("BOTTOMRIGHT", filtersListFrame, "BOTTOMRIGHT", -30, 60)

    filtersListScrollChild = CreateFrame("Frame", "CleanStartFiltersListScrollChild", filtersListScrollFrame)
    filtersListScrollChild:SetSize(560, 1)
    filtersListScrollFrame:SetScrollChild(filtersListScrollChild)
end

function CleanStart_ToggleFiltersList()
    if not filtersListFrame then
        CreateFiltersListWindow()
    end

    if filtersListFrame:IsShown() then
        filtersListFrame:Hide()
    else
        filtersListFrame.statusText:SetText(string.format(
            "Text Filters: %d | Blocked IDs: %d",
            #db.customFilters, #db.blockedMessageIds))
        RefreshFiltersList()
        filtersListFrame:Show()
        escProxyFrame:Show()
    end
end

-- ─── Event Handler ─────────────────────────────────────────────────────────────

local function CloseCaptureWindow()
    captureActive = false
    UnhookAllFrames()
    if db.debug then
        originalPrint("|cFF00FF00CleanStart:|r Capture window closed.")
        originalPrint("|cFF00FF00CleanStart:|r Captured " .. #capturedMessages .. " messages. Use /cs to review.")
    end
end

-- Starts the login capture window, deferring the close by 1s at a time while
-- the player is in combat so UnhookAllFrames doesn't have to fight taint.
local function StartCaptureWindowTimer()
    if InCombatLockdown() then
        if db.debug then
            originalPrint("|cFFFF6600CleanStart:|r In combat, delaying capture window close.")
        end
        C_Timer.After(1, function()
            if InCombatLockdown() then
                C_Timer.After(1, CloseCaptureWindow)
            else
                CloseCaptureWindow()
            end
        end)
    else
        C_Timer.After(db.blockWindow, CloseCaptureWindow)
    end
end

local frame = CreateFrame("Frame", "CleanStartFrame")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Prevent double-init on reload
        if playerLoginFired then return end
        playerLoginFired = true

        capturedMessages = {}

        -- A /reload mid-instance isn't a real login - no login spam to catch,
        -- and Blizzard restricts chat history access while instanced. Skip
        -- the capture window instead of briefly filtering live chat.
        if IsInInstance() then
            captureActive = false
            UnhookAllFrames()
            if db.debug then
                originalPrint("|cFF00FF00CleanStart:|r Reload detected inside an instance, capture skipped.")
            end
            return
        end

        -- DEFAULT_CHAT_FRAME and print were already hooked at file load.
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            HookChatFrame(_G["ChatFrame" .. i])
        end

        StartCaptureWindowTimer()

    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME or name == "CleanStart" then
            db = CleanStartDB
            EnsureDefaults()
            SLASH_CLEANSTART1 = "/cleanstart"
            SLASH_CLEANSTART2 = "/cs"
            SlashCmdList["CLEANSTART"] = SlashCommandHandler
            if db.debug then
                originalPrint("|cFF00FF00CleanStart:|r Debug mode is ON")
            end
        end
    end
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")

-- ─── Slash Commands ────────────────────────────────────────────────────────────

function SlashCommandHandler(input)
    input = input:trim()
    local cmd, arg = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "on" then
        db.enabled = true
        originalPrint("|cFF00FF00CleanStart:|r Filtering enabled.")

    elseif cmd == "off" then
        db.enabled = false
        originalPrint("|cFF00FF00CleanStart:|r Filtering disabled.")

    elseif cmd == "status" then
        originalPrint("|cFF00FF00CleanStart v" .. ADDON_VERSION .. ":|r")
        originalPrint("  Filtering    : " .. (db.enabled and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
        originalPrint("  Debug        : " .. (db.debug and "|cFF00FF00On|r" or "|cFFFF0000Off|r"))
        originalPrint("  Capture window : " .. db.blockWindow .. "s")
        originalPrint("  Custom filters : " .. #db.customFilters)
        originalPrint("  Whitelist entries : " .. #db.whitelist)
        originalPrint("  Captured messages : " .. #capturedMessages)

    elseif cmd == "debug" then
        db.debug = not db.debug
        originalPrint("|cFF00FF00CleanStart:|r Debug " .. (db.debug and "enabled" or "disabled") .. ".")

    elseif cmd == "window" then
        local secs = tonumber(arg)
        if secs and secs > 0 then
            db.blockWindow = secs
            originalPrint("|cFF00FF00CleanStart:|r Capture window set to " .. secs .. "s.")
        else
            originalPrint("|cFF00FF00CleanStart:|r Usage: /cs window <seconds>  (current: " .. db.blockWindow .. "s)")
        end

    elseif cmd == "list" then
        if #db.customFilters == 0 then
            originalPrint("|cFF00FF00CleanStart:|r No custom filters.")
        else
            originalPrint("|cFF00FF00CleanStart:|r Custom filters (" .. #db.customFilters .. "):")
            for i, v in ipairs(db.customFilters) do
                local filterType = "contains"
                local displayText = v
                if string.sub(v, 1, 1) == "=" then
                    filterType = "exact"
                    displayText = string.sub(v, 2)
                elseif string.sub(v, 1, 1) == "^" then
                    filterType = "starts"
                    displayText = string.sub(v, 2)
                end
                originalPrint("  " .. i .. ". [" .. filterType .. "] \"" .. displayText .. "\"")
            end
        end

    elseif cmd == "add" then
        if arg ~= "" then
            table.insert(db.customFilters, arg)
            originalPrint("|cFF00FF00CleanStart:|r Filter added: \"" .. arg .. "\"")
        else
            originalPrint("|cFF00FF00CleanStart:|r Usage: /cs add <text> (prefix with ^ for starts-with, = for exact)")
        end

    elseif cmd == "remove" or cmd == "rm" then
        if arg ~= "" then
            local index = tonumber(arg)
            if index and db.customFilters[index] then
                originalPrint("|cFF00FF00CleanStart:|r Removed: \"" .. table.remove(db.customFilters, index) .. "\"")
            else
                for i, v in ipairs(db.customFilters) do
                    if v == arg then
                        table.remove(db.customFilters, i)
                        originalPrint("|cFF00FF00CleanStart:|r Removed: \"" .. arg .. "\"")
                        return
                    end
                end
                originalPrint("|cFF00FF00CleanStart:|r Not found: \"" .. arg .. "\"")
            end
        else
            originalPrint("|cFF00FF00CleanStart:|r Usage: /cs remove <# or text>")
        end

    elseif cmd == "clearfilters" then
        db.customFilters = {}
        originalPrint("|cFF00FF00CleanStart:|r All custom filters cleared.")

    elseif cmd == "whitelist" then
        local sub, warg = arg:match("^(%S+)%s*(.*)$")
        sub = sub and sub:lower() or ""
        if sub == "add" and warg ~= "" then
            table.insert(db.whitelist, warg)
            originalPrint("|cFF00FF00CleanStart:|r Whitelisted: \"" .. warg .. "\"")
        elseif (sub == "remove" or sub == "rm") and warg ~= "" then
            local idx = tonumber(warg)
            if idx and db.whitelist[idx] then
                originalPrint("|cFF00FF00CleanStart:|r Removed whitelist: \"" .. table.remove(db.whitelist, idx) .. "\"")
            else
                for i, v in ipairs(db.whitelist) do
                    if v == warg then
                        table.remove(db.whitelist, i)
                        originalPrint("|cFF00FF00CleanStart:|r Removed whitelist: \"" .. warg .. "\"")
                        return
                    end
                end
                originalPrint("|cFF00FF00CleanStart:|r Not found: \"" .. warg .. "\"")
            end
        elseif sub == "list" then
            if #db.whitelist == 0 then
                originalPrint("|cFF00FF00CleanStart:|r Whitelist is empty.")
            else
                originalPrint("|cFF00FF00CleanStart:|r Whitelist:")
                for i, v in ipairs(db.whitelist) do
                    originalPrint("  " .. i .. ". \"" .. v .. "\"")
                end
            end
        else
            originalPrint("|cFF00FF00CleanStart:|r Usage: /cs whitelist add | remove | list <text>")
        end

    elseif cmd == "help" then
        originalPrint("|cFF00FF00CleanStart v" .. ADDON_VERSION .. " Commands:|r")
        originalPrint("  /cs              - Toggle captured messages window")
        originalPrint("  /cs on|off       - Enable/disable filtering")
        originalPrint("  /cs status       - Show current status")
        originalPrint("  /cs window <secs>- Set capture window duration")
        originalPrint("  /cs list         - List all custom filters")
        originalPrint("  /cs add <text>   - Add filter (^starts, =exact)")
        originalPrint("  /cs remove <#>   - Remove a filter by number")
        originalPrint("  /cs clearfilters - Clear all filters")
        originalPrint("  /cs whitelist add | remove | list <text> - Manage whitelist")
        originalPrint("  /cs debug        - Toggle debug output")

    else
        CleanStart_ToggleGUI()
    end
end
