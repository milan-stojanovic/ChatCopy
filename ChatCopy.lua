local ADDON_NAME = ...

local function ChatCopy_Print(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ChatCopy|r: " .. tostring(message))
	else
		print("ChatCopy: " .. tostring(message))
	end
end

local function ChatCopy_GetCharacterKey()
	local name, realm = UnitFullName("player")
	if not name then
		name = UnitName("player")
	end
	if not realm or realm == "" then
		realm = GetRealmName and GetRealmName() or "UnknownRealm"
	end
	return tostring(name) .. "-" .. tostring(realm)
end

local function ChatCopy_InitDB()
	ChatCopyDB = ChatCopyDB or {}
	ChatCopyDB.version = ChatCopyDB.version or 1
	ChatCopyDB.profiles = ChatCopyDB.profiles or {}
	if ChatCopyDB.debug == nil then
		ChatCopyDB.debug = false
	end
end

local function ChatCopy_Debug(message)
	if ChatCopyDB and ChatCopyDB.debug then
		ChatCopy_Print("[debug] " .. tostring(message))
	end
end

local function ChatCopy_ListChatWindowIds()
	local ids = {}
	local seen = {}

	-- Retail maintains CHAT_FRAMES (array of global frame names) for windows that exist.
	-- IMPORTANT: do not rely on frame:GetID() being populated; use the frame name (ChatFrameN) when possible.
	if type(CHAT_FRAMES) == "table" then
		for _, frameName in ipairs(CHAT_FRAMES) do
			if type(frameName) == "string" then
				local parsedId = tonumber(frameName:match("^ChatFrame(%d+)$"))
				if parsedId and parsedId > 0 and not seen[parsedId] then
					seen[parsedId] = true
					table.insert(ids, parsedId)
				else
					local frame = _G[frameName]
					if frame and frame.GetID then
						local id = frame:GetID()
						if type(id) == "number" and id > 0 and not seen[id] then
							seen[id] = true
							table.insert(ids, id)
						end
					end
				end
			end
		end
	end

	-- Fallback: scan numeric frames.
	if #ids == 0 then
		for i = 1, (NUM_CHAT_WINDOWS or 20) do
			local frame = _G["ChatFrame" .. i]
			local name = GetChatWindowInfo(i)
			if frame and name ~= nil then
				table.insert(ids, i)
			end
		end
	end

	table.sort(ids)
	return ids
end

local function ChatCopy_PersistChatChanges(desiredCount)
	for i = 1, desiredCount do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame then
			if type(FCF_SavePositionAndDimensions) == "function" then
				pcall(FCF_SavePositionAndDimensions, chatFrame)
			end
			if type(FCF_SaveChatWindow) == "function" then
				pcall(FCF_SaveChatWindow, chatFrame)
			end
		end
	end
	if type(FCF_SaveDock) == "function" then
		pcall(FCF_SaveDock)
	end
	if type(FCF_SaveChatWindows) == "function" then
		pcall(FCF_SaveChatWindows)
	end
end

local function ChatCopy_ReadWindow(windowId)
	local name = GetChatWindowInfo(windowId)
	if not name then
		return nil
	end

	local messageGroups = {}
	if type(GetChatWindowMessages) == "function" then
		local groups = { GetChatWindowMessages(windowId) }
		for _, groupToken in ipairs(groups) do
			if type(groupToken) == "string" and groupToken ~= "" then
				table.insert(messageGroups, groupToken)
			end
		end
	end

	local channels = {}
	if type(GetChatWindowChannels) == "function" then
		local ch = { GetChatWindowChannels(windowId) }
		for idx = 1, #ch, 2 do
			local a = ch[idx]
			local b = ch[idx + 1]
			local channelName
			if type(b) == "string" and b ~= "" then
				channelName = b
			elseif type(a) == "string" and a ~= "" then
				channelName = a
			end
			if channelName then
				table.insert(channels, channelName)
			end
		end
	end

	return {
		windowId = windowId,
		name = name,
		messageGroups = messageGroups,
		channels = channels,
	}
end

local function ChatCopy_IsPlaceholderName(name)
	name = tostring(name or "")
	return name:match("^Chat%s+%d+$") ~= nil
end

local function ChatCopy_ShouldIncludeWindow(windowData)
	if type(windowData) ~= "table" then
		return false
	end
	if windowData.name == "Voice" then
		return false
	end
	local groupsCount = type(windowData.messageGroups) == "table" and #windowData.messageGroups or 0
	local channelsCount = type(windowData.channels) == "table" and #windowData.channels or 0
	if groupsCount == 0 and channelsCount == 0 and ChatCopy_IsPlaceholderName(windowData.name) then
		return false
	end
	if groupsCount == 0 and channelsCount == 0 then
		return false
	end
	return true
end

local function ChatCopy_GetChatFrameByWindowId(windowId)
	if type(FCF_GetChatFrameByID) == "function" then
		local ok, frame = pcall(FCF_GetChatFrameByID, windowId)
		if ok and frame then
			return frame
		end
	end
	local direct = _G["ChatFrame" .. tostring(windowId)]
	if direct then
		return direct
	end
	if type(CHAT_FRAMES) == "table" then
		for _, frameName in ipairs(CHAT_FRAMES) do
			local frame = _G[frameName]
			if frame and frame.GetID and frame:GetID() == windowId then
				return frame
			end
		end
	end
	return nil
end

local function ChatCopy_ApplyToFrame(chatFrame, windowData)
	if not chatFrame or type(windowData) ~= "table" then
		return
	end

	if type(ChatFrame_RemoveAllMessageGroups) == "function" then
		pcall(ChatFrame_RemoveAllMessageGroups, chatFrame)
	end
	if type(ChatFrame_RemoveAllChannels) == "function" then
		pcall(ChatFrame_RemoveAllChannels, chatFrame)
	end

	if type(ChatFrame_AddMessageGroup) == "function" and type(windowData.messageGroups) == "table" then
		for _, groupToken in ipairs(windowData.messageGroups) do
			if type(groupToken) == "string" and groupToken ~= "" then
				pcall(ChatFrame_AddMessageGroup, chatFrame, groupToken)
			end
		end
	end

	if type(ChatFrame_AddChannel) == "function" and type(windowData.channels) == "table" then
		for _, channelName in ipairs(windowData.channels) do
			if type(channelName) == "string" and channelName ~= "" then
				local channelId = 0
				if type(GetChannelName) == "function" then
					channelId = GetChannelName(channelName) or 0
				end
				if (not channelId or channelId == 0) and type(JoinChannelByName) == "function" then
					pcall(JoinChannelByName, channelName)
				end
				pcall(ChatFrame_AddChannel, chatFrame, channelName)
			end
		end
	end
end

local function ChatCopy_SnapshotCurrentCharacter()
	ChatCopy_InitDB()

	local profileKey = ChatCopy_GetCharacterKey()
	local windowIds = ChatCopy_ListChatWindowIds()

	local snapshot = {
		key = profileKey,
		windowCount = 0,
		windowIds = windowIds,
		windows = {},
		updatedAt = time and time() or nil,
	}

	for _, windowId in ipairs(windowIds) do
		local data = ChatCopy_ReadWindow(windowId)
		if data and ChatCopy_ShouldIncludeWindow(data) then
			table.insert(snapshot.windows, data)
		end
	end
	snapshot.windowCount = #snapshot.windows

	ChatCopyDB.profiles[profileKey] = snapshot
end

local function ChatCopy_CloseExtraWindows(desiredCount)
	local currentCount = #ChatCopy_ListChatWindowIds()
	if currentCount <= desiredCount then
		return
	end

	ChatCopy_Debug("Closing extra windows: have=" .. tostring(currentCount) .. " want=" .. tostring(desiredCount))

	for i = currentCount, desiredCount + 1, -1 do
		if i ~= 1 then
			local chatFrame = ChatCopy_GetChatFrameByWindowId(i)
			if chatFrame then
				if type(FCF_Close) == "function" then
					pcall(FCF_Close, chatFrame)
				elseif type(FCF_CloseWindow) == "function" then
					pcall(FCF_CloseWindow, chatFrame)
				end
			end
		end
	end
end

local function ChatCopy_EnsureWindowCount(desiredCount)
	local currentCount = #ChatCopy_ListChatWindowIds()
	while currentCount < desiredCount do
		local newName = "Window " .. tostring(currentCount + 1)
		if type(FCF_OpenNewWindow) == "function" then
			ChatCopy_Debug("Creating window: " .. newName)
			pcall(FCF_OpenNewWindow, newName)
		else
			break
		end
		currentCount = #ChatCopy_ListChatWindowIds()
	end
end

local function ChatCopy_SetWindowName(i, name)
	local chatFrame = ChatCopy_GetChatFrameByWindowId(i)
	if not chatFrame or type(name) ~= "string" then
		return
	end
	if type(FCF_SetWindowName) == "function" then
		pcall(FCF_SetWindowName, chatFrame, name)
	elseif type(SetChatWindowName) == "function" then
		pcall(SetChatWindowName, i, name)
	end
end

local function ChatCopy_ApplyWindow(i, windowData)
	local chatFrame = ChatCopy_GetChatFrameByWindowId(i)
	if not chatFrame then
		ChatCopy_Debug("ChatFrame" .. tostring(i) .. " missing; skipping")
		return
	end

	ChatCopy_Debug("Applying window #" .. tostring(i) .. ": name='" .. tostring(windowData.name) .. "' groups=" .. tostring(type(windowData.messageGroups) == "table" and #windowData.messageGroups or 0) .. " channels=" .. tostring(type(windowData.channels) == "table" and #windowData.channels or 0))

	ChatCopy_SetWindowName(i, windowData.name)

	ChatCopy_ApplyToFrame(chatFrame, windowData)
end

local function ChatCopy_ApplySnapshot(sourceKey)
	ChatCopy_InitDB()

	if InCombatLockdown and InCombatLockdown() then
		ChatCopy_Print("Cannot apply in combat.")
		return false
	end

	if type(sourceKey) ~= "string" or sourceKey == "" then
		ChatCopy_Print("Select a character in 'Copy From'.")
		return false
	end

	local snapshot = ChatCopyDB.profiles and ChatCopyDB.profiles[sourceKey]
	if type(snapshot) ~= "table" or type(snapshot.windows) ~= "table" then
		ChatCopy_Print("No saved chat settings found for: " .. tostring(sourceKey))
		return false
	end

	ChatCopy_Debug("Apply from: " .. tostring(sourceKey))
	ChatCopy_Debug("Snapshot windowIds: " .. tostring(type(snapshot.windowIds) == "table" and table.concat(snapshot.windowIds, ",") or "(none)"))
	ChatCopy_Debug("Current windowIds: " .. table.concat(ChatCopy_ListChatWindowIds(), ","))

	local desiredCount = tonumber(snapshot.windowCount) or 0
	if desiredCount < 1 then
		ChatCopy_Print("Saved settings look empty for: " .. tostring(sourceKey))
		return false
	end

	ChatCopy_Debug("Desired window count: " .. tostring(desiredCount))

	-- Recreate custom windows (tabs) so they become visible on the target character.
	-- Keep ChatFrame1 (General) and ChatFrame2 (Combat Log) but overwrite their filters.
	local currentIds = ChatCopy_ListChatWindowIds()
	local maxId = currentIds[#currentIds] or 0
	for windowId = maxId, 3, -1 do
		local name = GetChatWindowInfo(windowId)
		if name and name ~= "" and name ~= "Voice" and not ChatCopy_IsPlaceholderName(name) then
			local frame = ChatCopy_GetChatFrameByWindowId(windowId)
			if frame and type(FCF_Close) == "function" then
				ChatCopy_Debug("Closing existing tab windowId=" .. tostring(windowId) .. " name='" .. tostring(name) .. "'")
				pcall(FCF_Close, frame)
			elseif frame and type(FCF_CloseWindow) == "function" then
				ChatCopy_Debug("Closing existing tab windowId=" .. tostring(windowId) .. " name='" .. tostring(name) .. "'")
				pcall(FCF_CloseWindow, frame)
			end
		end
	end

	-- Apply General/Log to windowIds 1 and 2, then create remaining windows in order.
	local baseIds = { 1, 2 }
	for baseIndex, baseWindowId in ipairs(baseIds) do
		local data = snapshot.windows[baseIndex]
		if type(data) == "table" then
			ChatCopy_ApplyWindow(baseWindowId, data)
		end
	end

	for idx = 3, desiredCount do
		local data = snapshot.windows[idx]
		if type(data) == "table" then
			local ok, newFrame = pcall(FCF_OpenNewWindow, tostring(data.name))
			if ok and newFrame then
				ChatCopy_Debug("Created new tab: '" .. tostring(data.name) .. "'")
				ChatCopy_ApplyToFrame(newFrame, data)
			else
				ChatCopy_Debug("Failed to create tab via FCF_OpenNewWindow for '" .. tostring(data.name) .. "'")
			end
		end
	end

	ChatCopy_PersistChatChanges(10)
	ChatCopy_Debug("After apply windowIds: " .. table.concat(ChatCopy_ListChatWindowIds(), ","))

	return true
end

-- UI
local selectedSourceKey

local function ChatCopy_ListProfileKeys()
	ChatCopy_InitDB()
	local keys = {}
	for k, v in pairs(ChatCopyDB.profiles or {}) do
		if type(k) == "string" and type(v) == "table" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

local function ChatCopy_CreateOptionsPanel()
	local panel = CreateFrame("Frame", "ChatCopyOptionsPanel", UIParent)
	panel.name = "ChatCopy"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ChatCopy")

	local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
	label:SetText("Copy From")

	local dropdown = CreateFrame("Frame", "ChatCopyCopyFromDropdown", panel, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -6)
	UIDropDownMenu_SetWidth(dropdown, 260)

	local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	applyBtn:SetSize(140, 24)
	applyBtn:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -10)
	applyBtn:SetText("Apply")
	applyBtn:SetScript("OnClick", function()
		if ChatCopy_ApplySnapshot(selectedSourceKey) then
			ChatCopy_Print("Applied. Reload UI to finalize?")
			if StaticPopup_Show then
				StaticPopup_Show("CHATCOPY_RELOAD_CONFIRM")
			else
				ChatCopy_Print("Type /reload to finalize.")
			end
		end
	end)

	local function Dropdown_OnClick(self)
		selectedSourceKey = self.value
		UIDropDownMenu_SetSelectedValue(dropdown, self.value)
	end

	UIDropDownMenu_Initialize(dropdown, function(_, level)
		local info = UIDropDownMenu_CreateInfo()
		info.func = Dropdown_OnClick

		local keys = ChatCopy_ListProfileKeys()
		for _, k in ipairs(keys) do
			info.text = k
			info.value = k
			info.checked = (k == selectedSourceKey)
			UIDropDownMenu_AddButton(info, level)
		end
	end)

	panel.refresh = function()
		local keys = ChatCopy_ListProfileKeys()
		if not selectedSourceKey or selectedSourceKey == "" then
			selectedSourceKey = keys[1]
		end
		UIDropDownMenu_SetSelectedValue(dropdown, selectedSourceKey)
		UIDropDownMenu_SetText(dropdown, selectedSourceKey or "")
	end

	panel.OnShow = function()
		if panel.refresh then
			panel.refresh()
		end
	end
	panel:SetScript("OnShow", panel.OnShow)

	return panel
end

local function ChatCopy_RegisterOptionsPanel(panel)
	-- Retail Settings API (Dragonflight+)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
		return
	end

	-- Legacy Interface Options
	if type(InterfaceOptions_AddCategory) == "function" then
		InterfaceOptions_AddCategory(panel)
	end
end

-- Bootstrap
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

local optionsPanel

eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ChatCopy_InitDB()
		if StaticPopupDialogs and not StaticPopupDialogs.CHATCOPY_RELOAD_CONFIRM then
			StaticPopupDialogs.CHATCOPY_RELOAD_CONFIRM = {
				text = "Reload the UI now to finalize chat settings?",
				button1 = "Reload",
				button2 = "Later",
				OnAccept = function()
					ReloadUI()
				end,
				timeout = 0,
				whileDead = 1,
				hideOnEscape = 1,
				preferredIndex = 3,
			}
		end
		optionsPanel = ChatCopy_CreateOptionsPanel()
		ChatCopy_RegisterOptionsPanel(optionsPanel)
		if optionsPanel.refresh then
			optionsPanel.refresh()
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Keep this quiet and minimal: snapshot so other characters can copy from it.
		pcall(ChatCopy_SnapshotCurrentCharacter)
	end
end)
