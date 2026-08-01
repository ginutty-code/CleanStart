-- CleanStart - Filter addon messages from chat

local ADDON_NAME = "!CleanStart"
local ADDON_VERSION = "1.0.0"

if not CleanStartDB then CleanStartDB = {} end
local db = CleanStartDB

local originalAddMessage = DEFAULT_CHAT_FRAME.AddMessage
local originalPrint = print

-- Login window state
local captureActive = true
local capturedMessages = {}  -- Stores all messages during login window
local hookedFrames = {}  -- Track hooked frames for cleanup
local playerLoginFired = false  -- Track if PLAYER_LOGIN has fired to prevent double-init on reload

-- Message type constants
local MSG_ADDON = "addon"      -- No ID = addon message (blocked by default)
local MSG_SYSTEM = "system"    -- Has ID = system/player message (user choice)

-- ─── Database Defaults ─────────────────────────────────────────────────────────

local function EnsureDefaults()
    if db.enabled == nil then db.enabled = true end
    if db.debug == nil then db.debug = false end
    if db.blockWindow == nil then db.blockWindow = 1 end
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
    
    -- Determine default action
    local defaultAction = "none"
    if msgType == MSG_ADDON then
        defaultAction = "blocked"  -- Addon messages blocked by default
    else
        defaultAction = "allowed"  -- System messages allowed by default
    end
    
    -- Check if this message text is already in custom filters (blocked by user)
    local userAction = nil
    local filterType = nil
    if msgType == MSG_SYSTEM then
        -- Check if message ID is blocked
        if IsMessageIdBlocked(msgId) then
            userAction = "blocked"
            filterType = "id"
        elseif db.customFilters then
            -- Check text filters
            local msgLower = string.lower(msg)
            for _, filter in ipairs(db.customFilters) do
                if string.sub(filter, 1, 1) == "=" then
                    -- Exact match
                    local filterTextLower = string.lower(string.sub(filter, 2))
                    if msgLower == filterTextLower then
                        userAction = "blocked"
                        filterType = "exact"
                        break
                    end
                elseif string.sub(filter, 1, 1) == "^" then
                    -- Starts-with match
                    local pattern = string.lower(string.sub(filter, 2))
                    if string.sub(msgLower, 1, #pattern) == pattern then
                        userAction = "blocked"
                        filterType = "starts"
                        break
                    end
                else
                    -- Contains match
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
    
    -- Skip our own messages
    if string.find(msg, "CleanStart", 1, true) then
        return false
    end
    
    -- Check whitelist first
    if IsWhitelisted(msg) then
        if db and db.debug then
            originalPrint("|cFF00AAFFCleanStart:|r Whitelisted: \"" .. msg .. "\"")
        end
        return false
    end
    
    -- Check if message ID is blocked
    if IsMessageIdBlocked(msgId) then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Blocked by ID: " .. tostring(msgId))
        end
        return true
    end
    
    -- Custom text filters (only active during capture window)
    local matched, word = MatchesCustomFilter(msg)
    if matched then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Custom filter blocked: \"" .. msg .. "\"")
        end
        return true
    end
    
    local hasMessageId = msgId and type(msgId) == "number"
    
    -- During capture window: block addon messages (no ID)
    if captureActive then
        if not hasMessageId then
            return true  -- Block addon messages during login window
        end
        return false  -- Allow system messages during login window
    end
    
    -- After capture window: no filtering
    return false
end

-- ─── Chat Frame Hooks ──────────────────────────────────────────────────────────

local function HookChatFrame(frame)
    if frame and frame.AddMessage and not hookedFrames[frame] then
        local orig = frame.AddMessage
        hookedFrames[frame] = orig
        frame.AddMessage = function(self, msg, r, g, b, id, ...)
            -- Only process during capture window
            if captureActive then
                CaptureMessage(msg, id, r, g, b)
                if ShouldFilter(msg, id) then return end
            end
            orig(self, msg, r, g, b, id, ...)
        end
    end
end

local function UnhookAllFrames()
    -- Don't unhook during combat to prevent errors
    if InCombatLockdown() then
        if db and db.debug then
            originalPrint("|cFFFF6600CleanStart:|r Cannot unhook frames while in combat, will retry later.")
        end
        -- Schedule for after combat ends using C_Timer (doesn't require frame reference)
        C_Timer.After(1, function()
            if InCombatLockdown() then
                -- Still in combat, retry again
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
    
    -- Restore DEFAULT_CHAT_FRAME
    DEFAULT_CHAT_FRAME.AddMessage = originalAddMessage
    
    -- Restore print
    print = originalPrint
    
    if db and db.debug then
        originalPrint("|cFF00FF00CleanStart:|r Hooks removed, addon inactive.")
    end
end

-- Hook DEFAULT_CHAT_FRAME immediately at file load
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg, r, g, b, id, ...)
    if captureActive then
        CaptureMessage(msg, id, r, g, b)
        if ShouldFilter(msg, id) then return end
    end
    originalAddMessage(self, msg, r, g, b, id, ...)
end
-- Track that DEFAULT_CHAT_FRAME is already hooked to prevent double-hooking
hookedFrames[DEFAULT_CHAT_FRAME] = originalAddMessage

-- Hook print immediately at file load
print = function(...)
    if captureActive then
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        local msg = table.concat(parts, " ")
        CaptureMessage(msg, nil, 1, 1, 1)
        if ShouldFilter(msg, nil) then return end
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

-- Create a proxy frame for ESC handling that closes windows one at a time
-- This must be defined before the GUI functions that reference it
local escProxyFrame = CreateFrame("Frame", "CleanStartEscProxy", UIParent)
escProxyFrame:Hide()
escProxyFrame:SetScript("OnHide", function(self)
    -- Check which windows are visible before closing
    local hasEdit = editDialog and editDialog:IsShown()
    local hasFilters = filtersListFrame and filtersListFrame:IsShown()
    local hasGui = guiFrame and guiFrame:IsShown()
    
    -- Close windows one at a time, starting with the topmost (editDialog first)
    if hasEdit then
        editDialog:Hide()
        self:Show()  -- Re-show proxy for next ESC
    elseif hasFilters then
        filtersListFrame:Hide()
        self:Show()  -- Re-show proxy for next ESC
    elseif hasGui then
        guiFrame:Hide()
        -- Don't re-show - all windows closed
    end
end)

-- Register the proxy frame with UISpecialFrames
table.insert(UISpecialFrames, "CleanStartEscProxy")

local function CreateGUI()
    if guiFrame then return end
    
    -- Main frame
    guiFrame = CreateFrame("Frame", "CleanStartGUI", UIParent, "BasicFrameTemplateWithInset")
    guiFrame:SetSize(600, 500)
    guiFrame:SetPoint("CENTER")
    guiFrame:SetMovable(true)
    guiFrame:EnableMouse(true)
    guiFrame:SetResizable(true)
    -- Set resize bounds if available (retail API)
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
    
    -- Title
    guiFrame.title = guiFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guiFrame.title:SetPoint("TOP", guiFrame, "TOP", 0, -5)
    guiFrame.title:SetText("CleanStart - Captured Messages")
    
    -- Resize handle
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
    
    -- Update scroll child and rows on size change
    guiFrame:SetScript("OnSizeChanged", function()
        if scrollChild and scrollFrame then
            scrollChild:SetWidth(scrollFrame:GetWidth() - 20)
            -- Only refresh if GUI is shown and has messages
            if guiFrame:IsShown() and #capturedMessages > 0 then
                CleanStart_RefreshMessageList()
            end
        end
    end)
    
    -- Button container frame (positioned higher)
    local buttonFrame = CreateFrame("Frame", nil, guiFrame)
    buttonFrame:SetPoint("BOTTOMLEFT", guiFrame, "BOTTOMLEFT", 10, 30)
    buttonFrame:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -10, 30)
    buttonFrame:SetHeight(25)
    
    -- Filters List button (leftmost)
    local filtersListButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    filtersListButton:SetPoint("LEFT", buttonFrame, "LEFT", 0, 0)
    filtersListButton:SetSize(90, 25)
    filtersListButton:SetText("Filters List")
    filtersListButton:SetScript("OnClick", function()
        CleanStart_ToggleFiltersList()
    end)
    
    -- Clear Filters button
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
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    closeButton:SetPoint("RIGHT", buttonFrame, "RIGHT", -20, 0)
    closeButton:SetSize(70, 25)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() guiFrame:Hide() end)
    
    -- Scroll frame (ends higher to allow space for resize handle)
    scrollFrame = CreateFrame("ScrollFrame", "CleanStartScrollFrame", guiFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", guiFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -30, 60)
    
    -- Scroll child
    scrollChild = CreateFrame("Frame", "CleanStartScrollChild", scrollFrame)
    scrollChild:SetSize(560, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Status text
    guiFrame.statusText = guiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guiFrame.statusText:SetPoint("BOTTOMLEFT", guiFrame, "BOTTOMLEFT", 15, 10)
    guiFrame.statusText:SetText("")
end

-- Create Edit Dialog
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
    editDialog:SetFrameStrata("DIALOG")
    
    -- Title
    editDialog.title = editDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editDialog.title:SetPoint("TOP", editDialog, "TOP", 0, -5)
    editDialog.title:SetText("Custom Filter")
    
    -- Instructions
    editDialog.instructions = editDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editDialog.instructions:SetPoint("TOP", editDialog, "TOP", 15, -30)
    editDialog.instructions:SetText("Edit the filter text.\n Add prefix ^ for starts-with match, or no prefix for contains match")
    
    -- Block by ID checkbox (only shown for system messages with ID)
    editDialog.blockByIdCheckbox = CreateFrame("CheckButton", "CleanStartBlockByIdCheck", editDialog, "ChatConfigCheckButtonTemplate")
    editDialog.blockByIdCheckbox:SetPoint("BOTTOMLEFT", editDialog, "BOTTOMLEFT", 15, 60)
    editDialog.blockByIdCheckbox.Text = editDialog.blockByIdCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editDialog.blockByIdCheckbox.Text:SetPoint("LEFT", editDialog.blockByIdCheckbox, "RIGHT", 5, 0)
    editDialog.blockByIdCheckbox.Text:SetText("Block by Message ID (blocks all messages with this system ID)")
    editDialog.blockByIdCheckbox:SetHitRectInsets(0, -editDialog.blockByIdCheckbox.Text:GetStringWidth(), 0, 0)
    
    -- Multi-line edit box using ScrollFrame
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
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, editDialog, "UIPanelButtonTemplate")
    cancelBtn:SetPoint("BOTTOMRIGHT", editDialog, "BOTTOMRIGHT", -10, 10)
    cancelBtn:SetSize(70, 25)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() editDialog:Hide() end)
    
    -- OK button
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
    
    -- Show/hide block by ID checkbox based on whether message has an ID
    if msgId and type(msgId) == "number" then
        editDialog.blockByIdCheckbox:Show()
        editDialog.blockByIdCheckbox:SetChecked(false)
        editDialog.blockByIdCheckbox.msgId = msgId
    else
        editDialog.blockByIdCheckbox:Hide()
        editDialog.blockByIdCheckbox.msgId = nil
    end
    
    editDialog:Show()
    escProxyFrame:Show()  -- Enable ESC handling
end

function CleanStart_RefreshMessageList()
    if not scrollChild then return end
    
    -- Clear existing rows
    for _, row in ipairs(messageRows) do
        if row.frame then
            row.frame:Hide()
            row.frame:SetParent(nil)
        end
    end
    messageRows = {}
    
    -- Count by type
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
    
    -- Create rows
    local yOffset = -5
    local rowHeight = 75
    local maxDisplay = 100  -- Limit for performance
    
    local messagesToShow = #capturedMessages
    local startIndex = math.max(1, messagesToShow - maxDisplay + 1)
    
    for i = startIndex, messagesToShow do
        local msg = capturedMessages[i]
        local rowIndex = i - startIndex + 1
        
        -- Create row frame with dynamic width
        local rowFrame = CreateFrame("Frame", "CleanStartRow" .. rowIndex, scrollChild)
        rowFrame:SetHeight(rowHeight)
        rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        rowFrame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 10, yOffset)
        
        -- Background
        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        if msg.msgType == MSG_ADDON then
            rowFrame.bg:SetColorTexture(0.4, 0.2, 0.2, 0.3)  -- Reddish for addon
        else
            rowFrame.bg:SetColorTexture(0.2, 0.4, 0.2, 0.3)  -- Greenish for system
        end
        
        -- Message type indicator
        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        if msg.msgType == MSG_ADDON then
            typeText:SetText("|cFFFF6666[ADDON]|r ID: none")
        else
            typeText:SetText("|cFF66FF66[SYSTEM]|r ID: " .. tostring(msg.id))
        end
        
        -- Message text (full width, above buttons)
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
        
        -- Action buttons (only for system messages)
        if msg.msgType == MSG_SYSTEM then
            -- Current status indicator (top right)
            local statusText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -5, -3)
            -- Check if this message is blocked by any filter
            local isBlocked = false
            local blockType = nil
            
            -- Check if blocked by ID first
            if IsMessageIdBlocked(msg.id) then
                isBlocked = true
                blockType = "id"
            else
                -- Check text filters
                local msgTextLower = string.lower(msg.text)
                for _, filter in ipairs(db.customFilters) do
                    if string.sub(filter, 1, 1) == "=" then
                        -- Exact match
                        if string.lower(string.sub(filter, 2)) == msgTextLower then
                            isBlocked = true
                            blockType = "exact"
                            break
                        end
                    elseif string.sub(filter, 1, 1) == "^" then
                        -- Starts-with match
                        local pattern = string.lower(string.sub(filter, 2))
                        if string.sub(msgTextLower, 1, #pattern) == pattern then
                            isBlocked = true
                            blockType = "starts"
                            break
                        end
                    else
                        -- Contains match
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
            
            -- Custom button (opens edit dialog) - rightmost
            local customBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            customBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -5, 5)
            customBtn:SetSize(70, 22)
            customBtn:SetText("Custom")
            customBtn:SetScript("OnClick", function()
                -- Show edit dialog with the message text and ID
                ShowEditDialog(msg.text, msg.id, function(filterText, blockById)
                    if blockById and msg.id then
                        -- Block by message ID
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
                        -- Add the custom text filter
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
                        -- Determine filter type for display
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
            
            -- Block button (exact match)
            local blockBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            blockBtn:SetPoint("RIGHT", customBtn, "LEFT", -5, 0)
            blockBtn:SetSize(70, 22)
            blockBtn:SetText("Block")
            blockBtn:SetScript("OnClick", function()
                -- Add exact match filter
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
            
            -- Allow button (leftmost)
            local allowBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            allowBtn:SetPoint("RIGHT", blockBtn, "LEFT", -5, 0)
            allowBtn:SetSize(70, 22)
            allowBtn:SetText("Allow")
            allowBtn:SetScript("OnClick", function()
                -- Remove any filters related to this message
                local msgTextLower = string.lower(msg.text)
                for j = #db.customFilters, 1, -1 do
                    local filter = db.customFilters[j]
                    -- Check exact match filter
                    if string.sub(filter, 1, 1) == "=" then
                        if string.lower(string.sub(filter, 2)) == msgTextLower then
                            table.remove(db.customFilters, j)
                        end
                    -- Check starts-with filter - remove if message starts with the filter pattern
                    elseif string.sub(filter, 1, 1) == "^" then
                        local pattern = string.lower(string.sub(filter, 2))
                        if string.sub(msgTextLower, 1, #pattern) == pattern then
                            table.remove(db.customFilters, j)
                        end
                    else
                        -- Contains match
                        local pattern = string.lower(filter)
                        if string.find(msgTextLower, pattern, 1, true) then
                            table.remove(db.customFilters, j)
                        end
                    end
                end
                -- Remove blocked ID if present
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
            -- Addon message - show "blocked by default" at top right
            local statusText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -5, -3)
            statusText:SetText("|cFFFF6666Blocked by default|r")
        end
        
        table.insert(messageRows, {frame = rowFrame, msg = msg})
        yOffset = yOffset - rowHeight - 2
    end
    
    -- Update scroll child height
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
    
    -- Clear existing rows
    for _, row in ipairs(filterRows) do
        if row.frame then
            row.frame:Hide()
            row.frame:SetParent(nil)
        end
    end
    filterRows = {}
    
    local yOffset = -5
    local rowHeight = 75
    
    -- Text filters
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
        
        -- Background
        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        rowFrame.bg:SetColorTexture(0.2, 0.3, 0.5, 0.3)
        
        -- Filter type indicator
        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        typeText:SetText("|cFF00AAFF[" .. string.upper(filterType) .. " FILTER]|r")
        
        -- Filter text (full width, above buttons)
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
        
        -- Edit button (bottom right area)
        local editBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -5, 5)
        editBtn:SetSize(70, 22)
        editBtn:SetText("Edit")
        editBtn:SetScript("OnClick", function()
            -- Use the same edit dialog as the Custom button
            ShowEditDialog(displayText, nil, function(newFilterText, blockById)
                if newFilterText and newFilterText ~= "" then
                    db.customFilters[i] = newFilterText
                    RefreshFiltersList()
                    CleanStart_RefreshMessageList()
                    originalPrint("|cFF00FF00CleanStart:|r Filter updated.")
                end
            end)
        end)
        
        -- Remove button
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
    
    -- Blocked Message IDs
    for i, msgId in ipairs(db.blockedMessageIds) do
        local rowFrame = CreateFrame("Frame", "CleanStartBlockedIdRow" .. i, filtersListScrollChild)
        rowFrame:SetHeight(rowHeight)
        rowFrame:SetPoint("TOPLEFT", filtersListScrollChild, "TOPLEFT", 0, yOffset)
        rowFrame:SetPoint("TOPRIGHT", filtersListScrollChild, "TOPRIGHT", 10, yOffset)
        
        -- Background
        rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowFrame.bg:SetAllPoints()
        rowFrame.bg:SetColorTexture(0.5, 0.3, 0.2, 0.3)
        
        -- Filter type indicator
        local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -3)
        typeText:SetText("|cFFFF6600[BLOCKED MESSAGE ID]|r")
        
        -- Filter text (full width, above buttons)
        local filterTextWidget = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        filterTextWidget:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 5, -20)
        filterTextWidget:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -25, 30)
        filterTextWidget:SetJustifyH("LEFT")
        filterTextWidget:SetJustifyV("TOP")
        filterTextWidget:SetWordWrap(true)
        filterTextWidget:SetText("Message ID: " .. tostring(msgId) .. "\n\nThis blocks all system messages with this ID.")
        
        -- Edit button (disabled for ID filters)
        local editBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -125, 5)
        editBtn:SetSize(70, 22)
        editBtn:SetText("Edit")
        editBtn:Disable()
        
        -- Remove button
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
    
    -- No filters message
    if #db.customFilters == 0 and #db.blockedMessageIds == 0 then
        local noFiltersText = filtersListScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noFiltersText:SetPoint("TOP", filtersListScrollChild, "TOP", 0, -20)
        noFiltersText:SetText("|cFFAAAAAANo filters configured.|r\n\nUse the Block/Custom buttons on messages to create filters.")
    end
    
    -- Update scroll child height
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
    -- Set resize bounds if available (retail API)
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
    
    -- Title
    filtersListFrame.title = filtersListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    filtersListFrame.title:SetPoint("TOP", filtersListFrame, "TOP", 0, -5)
    filtersListFrame.title:SetText("CleanStart - Filters List")
    
    -- Resize handle
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
    
    -- Update scroll child and rows on size change
    filtersListFrame:SetScript("OnSizeChanged", function()
        if filtersListScrollChild and filtersListScrollFrame then
            filtersListScrollChild:SetWidth(filtersListScrollFrame:GetWidth() - 20)
            -- Only refresh if GUI is shown and has filters
            if filtersListFrame:IsShown() and (#db.customFilters > 0 or #db.blockedMessageIds > 0) then
                RefreshFiltersList()
            end
        end
    end)
    
    -- Button container frame (positioned higher)
    local buttonFrame = CreateFrame("Frame", nil, filtersListFrame)
    buttonFrame:SetPoint("BOTTOMLEFT", filtersListFrame, "BOTTOMLEFT", 10, 30)
    buttonFrame:SetPoint("BOTTOMRIGHT", filtersListFrame, "BOTTOMRIGHT", -10, 30)
    buttonFrame:SetHeight(25)
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
    closeButton:SetPoint("RIGHT", buttonFrame, "RIGHT", -20, 0)
    closeButton:SetSize(70, 25)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() filtersListFrame:Hide() end)
    
    -- Status text
    filtersListFrame.statusText = filtersListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filtersListFrame.statusText:SetPoint("BOTTOMLEFT", filtersListFrame, "BOTTOMLEFT", 15, 10)
    filtersListFrame.statusText:SetText("")
    
    -- Scroll frame (ends higher to allow space for resize handle)
    filtersListScrollFrame = CreateFrame("ScrollFrame", "CleanStartFiltersListScrollFrame", filtersListFrame, "UIPanelScrollFrameTemplate")
    filtersListScrollFrame:SetPoint("TOPLEFT", filtersListFrame, "TOPLEFT", 10, -30)
    filtersListScrollFrame:SetPoint("BOTTOMRIGHT", filtersListFrame, "BOTTOMRIGHT", -30, 60)
    
    -- Scroll child
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
        -- Update status text
        filtersListFrame.statusText:SetText(string.format(
            "Text Filters: %d | Blocked IDs: %d",
            #db.customFilters, #db.blockedMessageIds))
        RefreshFiltersList()
        filtersListFrame:Show()
        escProxyFrame:Show()  -- Enable ESC handling
    end
end

-- ─── Event Handler ─────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", "CleanStartFrame")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Prevent double-init on reload
        if playerLoginFired then return end
        playerLoginFired = true
        
        -- Clear captured messages from any previous session
        capturedMessages = {}
        
        -- Hook additional chat frames (DEFAULT_CHAT_FRAME and print already hooked at file load)
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            HookChatFrame(_G["ChatFrame" .. i])
        end
        
        -- Set up login window timer for capture
        -- Skip if player is in combat (will handle on next event or manual reload)
        if InCombatLockdown() then
            if db.debug then
                originalPrint("|cFFFF6600CleanStart:|r In combat, delaying capture window cleanup.")
            end
            -- Schedule for after combat ends using C_Timer
            C_Timer.After(1, function()
                if InCombatLockdown() then
                    -- Still in combat, retry again
                    C_Timer.After(1, function()
                        captureActive = false
                        UnhookAllFrames()
                        if db.debug then
                            originalPrint("|cFF00FF00CleanStart:|r Capture window closed (delayed due to combat).")
                            originalPrint("|cFF00FF00CleanStart:|r Captured " .. #capturedMessages .. " messages. Use /cs to review.")
                        end
                    end)
                else
                    captureActive = false
                    UnhookAllFrames()
                    if db.debug then
                        originalPrint("|cFF00FF00CleanStart:|r Capture window closed (delayed due to combat).")
                        originalPrint("|cFF00FF00CleanStart:|r Captured " .. #capturedMessages .. " messages. Use /cs to review.")
                    end
                end
            end)
        else
            C_Timer.After(db.blockWindow, function()
                captureActive = false
                -- Unhook all frames after capture window
                UnhookAllFrames()
                if db.debug then
                    originalPrint("|cFF00FF00CleanStart:|r Capture window closed (" .. db.blockWindow .. "s).")
                    originalPrint("|cFF00FF00CleanStart:|r Captured " .. #capturedMessages .. " messages. Use /cs to review.")
                end
            end)
        end

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
        -- Default: show GUI
        CleanStart_ToggleGUI()
    end
end
