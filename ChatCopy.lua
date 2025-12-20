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
	ChatCopyDB.enforceFontSizes = ChatCopyDB.enforceFontSizes or {}
	if ChatCopyDB.debug == nil then
		ChatCopyDB.debug = false
	end
end

local function ChatCopy_Debug(message)
	if ChatCopyDB and ChatCopyDB.debug then
		ChatCopy_Print("[debug] " .. tostring(message))
	end
end

-- Forward declarations (Lua local functions are not visible before declaration)
local ChatCopy_GetChatFrameByWindowId

local function ChatCopy_NormalizeFontSize(size)
	if type(size) ~= "number" then
		return nil
	end
	if size <= 0 then
		return nil
	end
	-- Most font sizes are effectively integers; round to avoid float noise.
	local rounded = math.floor(size + 0.5)
	if rounded <= 0 or rounded > 64 then
		return nil
	end
	return rounded
end

local function ChatCopy_GetEditBoxForChatFrame(chatFrame)
	if not chatFrame then
		return nil
	end
	if chatFrame.editBox then
		return chatFrame.editBox
	end
	if chatFrame.GetName then
		local frameName = chatFrame:GetName()
		if type(frameName) == "string" and frameName ~= "" then
			local bySuffix = _G[frameName .. "EditBox"]
			if bySuffix then
				return bySuffix
			end
			local id = tonumber(frameName:match("^ChatFrame(%d+)$"))
			if id then
				local byId = _G["ChatFrame" .. tostring(id) .. "EditBox"]
				if byId then
					return byId
				end
			end
		end
	end
	return _G.ChatFrame1EditBox
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


local function ChatCopy_PersistChatChanges()
	local ids = ChatCopy_ListChatWindowIds()
	for _, windowId in ipairs(ids) do
		local chatFrame = ChatCopy_GetChatFrameByWindowId(windowId)
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
	local name, infoFontSize = GetChatWindowInfo(windowId)
	if not name then
		return nil
	end

	local fontSize
	fontSize = ChatCopy_NormalizeFontSize(infoFontSize)
	local fcfFontSize
	local frameFontSize

	local chatFrame = ChatCopy_GetChatFrameByWindowId(windowId)
	local editBoxFontSize
	local editBox = ChatCopy_GetEditBoxForChatFrame(chatFrame) or _G["ChatFrame" .. tostring(windowId) .. "EditBox"]
	if editBox and editBox.GetFont then
		local _, size = editBox:GetFont()
		editBoxFontSize = ChatCopy_NormalizeFontSize(size)
	end
	if not fontSize and chatFrame and type(FCF_GetChatWindowFontSize) == "function" then
		-- Some clients accept a frame, others accept a windowId.
		local ok1, size1 = pcall(FCF_GetChatWindowFontSize, chatFrame)
		if ok1 then
			fcfFontSize = ChatCopy_NormalizeFontSize(size1)
		end
		if not fcfFontSize then
			local ok2, size2 = pcall(FCF_GetChatWindowFontSize, windowId)
			if ok2 then
				fcfFontSize = ChatCopy_NormalizeFontSize(size2)
			end
		end
		fontSize = fcfFontSize
	end
	if chatFrame and chatFrame.GetFont then
		local _, size = chatFrame:GetFont()
		frameFontSize = ChatCopy_NormalizeFontSize(size)
		fontSize = fontSize or frameFontSize
	end

	if ChatCopyDB and ChatCopyDB.debug then
		ChatCopy_Debug(
			"Capture font size: windowId="
				.. tostring(windowId)
				.. " name='"
				.. tostring(name)
				.. "' info="
				.. tostring(infoFontSize)
				.. " fcf="
				.. tostring(fcfFontSize)
				.. " frame="
				.. tostring(frameFontSize)
				.. " editBox="
				.. tostring(editBoxFontSize)
				.. " chosen="
				.. tostring(fontSize)
		)
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
		fontSize = fontSize,
		editBoxFontSize = editBoxFontSize,
		messageGroups = messageGroups,
		channels = channels,
	}
end

local function ChatCopy_ApplyEditBoxFontSize(chatFrame, fontSize)
	fontSize = ChatCopy_NormalizeFontSize(fontSize)
	if not chatFrame or not fontSize then
		return
	end

	local editBox = ChatCopy_GetEditBoxForChatFrame(chatFrame)
	if not editBox or not editBox.GetFont or not editBox.SetFont then
		return
	end

	local fontPath, _, flags = editBox:GetFont()
	if not fontPath then
		return
	end

	ChatCopy_Debug(
		"Setting input font size: frame='"
			.. tostring(chatFrame.GetName and chatFrame:GetName() or "?")
			.. "' size="
			.. tostring(fontSize)
	)
	pcall(editBox.SetFont, editBox, fontPath, fontSize, flags)

	if ChatCopyDB and ChatCopyDB.debug and editBox.GetFont then
		local _, appliedSize = editBox:GetFont()
		ChatCopy_Debug(
			"Input font size after set: frame='"
				.. tostring(chatFrame.GetName and chatFrame:GetName() or "?")
				.. "' size="
				.. tostring(appliedSize)
		)
	end
end

local function ChatCopy_ApplyFontSize(chatFrame, fontSize)
	fontSize = ChatCopy_NormalizeFontSize(fontSize)
	if not chatFrame or not fontSize then
		return
	end

	ChatCopy_Debug("Setting font size: frame='" .. tostring(chatFrame:GetName()) .. "' size=" .. tostring(fontSize))

	if type(FCF_SetChatWindowFontSize) == "function" then
		pcall(FCF_SetChatWindowFontSize, chatFrame, fontSize)
	end

	-- Some builds persist this via a windowId-based setter.
	if type(SetChatWindowFontSize) == "function" and chatFrame.GetID then
		local windowId = chatFrame:GetID()
		if type(windowId) == "number" and windowId > 0 then
			pcall(SetChatWindowFontSize, windowId, fontSize)
		end
	end

	-- Some builds are more reliable if we also set the font directly.
	if chatFrame.GetFont and chatFrame.SetFont then
		local fontPath, _, flags = chatFrame:GetFont()
		if fontPath then
			pcall(chatFrame.SetFont, chatFrame, fontPath, fontSize, flags)
		end
	end

	if type(FCF_SaveChatWindow) == "function" then
		pcall(FCF_SaveChatWindow, chatFrame)
	end

	if ChatCopyDB and ChatCopyDB.debug and chatFrame.GetFont then
		local _, appliedSize = chatFrame:GetFont()
		ChatCopy_Debug("Font size after set: frame='" .. tostring(chatFrame:GetName()) .. "' size=" .. tostring(appliedSize))
	end

	-- Extra safety: some settings only persist if saved after the frame has settled.
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if type(FCF_SaveChatWindow) == "function" then
				pcall(FCF_SaveChatWindow, chatFrame)
			end
			if type(FCF_SaveDock) == "function" then
				pcall(FCF_SaveDock)
			end
			if type(FCF_SaveChatWindows) == "function" then
				pcall(FCF_SaveChatWindows)
			end
		end)
	end
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


ChatCopy_GetChatFrameByWindowId = function(windowId)
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

	-- Apply font size last; some chat frame updates can reset it.
	ChatCopy_ApplyFontSize(chatFrame, windowData.fontSize)
	ChatCopy_ApplyEditBoxFontSize(chatFrame, windowData.editBoxFontSize or windowData.fontSize)
end

local function ChatCopy_ReapplyFontSizesFromSnapshot(sourceKey)
	ChatCopy_InitDB()
	local snapshot = ChatCopyDB.profiles and ChatCopyDB.profiles[sourceKey]
	if type(snapshot) ~= "table" or type(snapshot.windows) ~= "table" then
		return false
	end

	local currentIds = ChatCopy_ListChatWindowIds()
	local idByName = {}
	for _, windowId in ipairs(currentIds) do
		local name = GetChatWindowInfo(windowId)
		if type(name) == "string" and name ~= "" and not idByName[name] then
			idByName[name] = windowId
		end
	end

	for idx, data in ipairs(snapshot.windows) do
		if type(data) == "table" and (type(data.fontSize) == "number" or type(data.editBoxFontSize) == "number") then
			local targetId = idByName[data.name]
			-- Fallback: first two windows are always 1/2, and subsequent windows follow creation order.
			if not targetId then
				if idx == 1 then
					targetId = 1
				elseif idx == 2 then
					targetId = 2
				else
					targetId = idx
				end
			end
			local frame = ChatCopy_GetChatFrameByWindowId(targetId)
			if frame then
				ChatCopy_ApplyFontSize(frame, data.fontSize)
				ChatCopy_ApplyEditBoxFontSize(frame, data.editBoxFontSize)
			end
		end
	end

	ChatCopy_PersistChatChanges()
	return true
end

local function ChatCopy_ReapplyWindowDataFromSnapshot(sourceKey)
	ChatCopy_InitDB()
	local snapshot = ChatCopyDB.profiles and ChatCopyDB.profiles[sourceKey]
	if type(snapshot) ~= "table" or type(snapshot.windows) ~= "table" then
		return false
	end

	local currentIds = ChatCopy_ListChatWindowIds()
	local idByName = {}
	for _, windowId in ipairs(currentIds) do
		local name = GetChatWindowInfo(windowId)
		if type(name) == "string" and name ~= "" and not idByName[name] then
			idByName[name] = windowId
		end
	end

	for idx, data in ipairs(snapshot.windows) do
		if type(data) == "table" then
			local targetId = idByName[data.name]
			-- Fallback: first two windows are always 1/2, and subsequent windows follow creation order.
			if not targetId then
				if idx == 1 then
					targetId = 1
				elseif idx == 2 then
					targetId = 2
				else
					targetId = idx
				end
			end
			local frame = ChatCopy_GetChatFrameByWindowId(targetId)
			if frame then
				ChatCopy_SetWindowName(targetId, data.name)
				ChatCopy_ApplyToFrame(frame, data)
			end
		end
	end

	ChatCopy_PersistChatChanges()
	return true
end

local function ChatCopy_RecordApplyForTarget(targetKey, sourceKey)
	if type(targetKey) ~= "string" or targetKey == "" then
		return
	end
	ChatCopyDB.pendingApply = {
		targetKey = targetKey,
		sourceKey = sourceKey,
		createdAt = time and time() or nil,
	}
	ChatCopyDB.enforceFontSizes[targetKey] = true
end

local function ChatCopy_BuildApplyAllTargets()
	local targets = {}
	local keys = ChatCopy_ListProfileKeys()
	for _, key in ipairs(keys) do
		targets[key] = true
	end
	local currentKey = ChatCopy_GetCharacterKey()
	if type(currentKey) == "string" and currentKey ~= "" then
		targets[currentKey] = true
	end
	return targets
end

local function ChatCopy_MarkApplyAllComplete(pendingAll, targetKey)
	if type(pendingAll) ~= "table" or type(targetKey) ~= "string" then
		return
	end
	local targets = pendingAll.targets
	if type(targets) == "table" then
		targets[targetKey] = nil
		if not next(targets) then
			ChatCopyDB.pendingApplyAll = nil
		end
	end
end

local function ChatCopy_ApplySnapshotToAll(sourceKey)
	ChatCopy_InitDB()
	if type(sourceKey) ~= "string" or sourceKey == "" then
		ChatCopy_Print("Select a character in 'Copy From'.")
		return false
	end

	local currentKey = ChatCopy_GetCharacterKey()
	if sourceKey == currentKey then
		pcall(ChatCopy_SnapshotCurrentCharacter)
	end

	local snapshot = ChatCopyDB.profiles and ChatCopyDB.profiles[sourceKey]
	if type(snapshot) ~= "table" or type(snapshot.windows) ~= "table" then
		ChatCopy_Print("No saved chat settings found for: " .. tostring(sourceKey))
		return false
	end

	local ok = ChatCopy_ApplySnapshot(sourceKey)
	if not ok then
		return false
	end

	local targets = ChatCopy_BuildApplyAllTargets()
	ChatCopyDB.pendingApplyAll = {
		sourceKey = sourceKey,
		createdAt = time and time() or nil,
		targets = targets,
	}

	local targetKey = currentKey
	ChatCopy_RecordApplyForTarget(targetKey, sourceKey)
	ChatCopy_MarkApplyAllComplete(ChatCopyDB.pendingApplyAll, targetKey)
	return true
end

local function ChatCopy_HandlePendingApplyAll(currentKey)
	local pendingAll = ChatCopyDB and ChatCopyDB.pendingApplyAll
	if type(pendingAll) ~= "table" or type(pendingAll.sourceKey) ~= "string" then
		return false
	end
	local targets = pendingAll.targets
	if type(targets) == "table" and not targets[currentKey] then
		return false
	end
	if currentKey == pendingAll.sourceKey then
		ChatCopy_MarkApplyAllComplete(pendingAll, currentKey)
		return false
	end

	local function applyNow()
		local ok = ChatCopy_ApplySnapshot(pendingAll.sourceKey)
		if ok then
			ChatCopy_RecordApplyForTarget(currentKey, pendingAll.sourceKey)
			ChatCopy_MarkApplyAllComplete(pendingAll, currentKey)
			local function reapply()
				pcall(ChatCopy_ReapplyWindowDataFromSnapshot, pendingAll.sourceKey)
			end
			if C_Timer and C_Timer.After then
				C_Timer.After(0.5, reapply)
			else
				reapply()
			end
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(1, applyNow)
	else
		applyNow()
	end

	return true
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
			ChatCopy_Debug(
				"Snapshot windowId="
					.. tostring(windowId)
					.. " name='"
					.. tostring(data.name)
					.. "' fontSize="
					.. tostring(data.fontSize)
					.. " inputFontSize="
					.. tostring(data.editBoxFontSize)
			)
			table.insert(snapshot.windows, data)
		end
	end
	snapshot.windowCount = #snapshot.windows

	ChatCopyDB.profiles[profileKey] = snapshot
	ChatCopy_Debug("Snapshot saved: key=" .. tostring(profileKey) .. " windows=" .. tostring(snapshot.windowCount))
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

	local normalizedFont = ChatCopy_NormalizeFontSize(windowData.fontSize)
	ChatCopy_Debug(
		"Applying window #" .. tostring(i)
			.. ": name='" .. tostring(windowData.name)
			.. "' fontSize=" .. tostring(windowData.fontSize)
			.. " (normalized=" .. tostring(normalizedFont) .. ")"
			.. " groups=" .. tostring(type(windowData.messageGroups) == "table" and #windowData.messageGroups or 0)
			.. " channels=" .. tostring(type(windowData.channels) == "table" and #windowData.channels or 0)
	)

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

	if desiredCount > 2 and type(FCF_OpenNewWindow) ~= "function" then
		ChatCopy_Print("Cannot create chat tabs (FCF_OpenNewWindow missing).")
		return false
	end

	for idx = 3, desiredCount do
		local data = snapshot.windows[idx]
		if type(data) == "table" then
			local normalizedFont = ChatCopy_NormalizeFontSize(data.fontSize)
			if not normalizedFont then
				ChatCopy_Debug("Creating tab '" .. tostring(data.name) .. "' with no saved font size (fontSize=" .. tostring(data.fontSize) .. ")")
			end
			local ok, newFrame = pcall(FCF_OpenNewWindow, tostring(data.name))
			if ok and newFrame then
				ChatCopy_Debug("Created new tab: '" .. tostring(data.name) .. "'")
				ChatCopy_ApplyToFrame(newFrame, data)
				-- Reinforce font size after chat system finishes initializing the new frame.
				ChatCopy_ApplyFontSize(newFrame, data.fontSize)
				if C_Timer and C_Timer.After and type(data.fontSize) == "number" then
					C_Timer.After(0, function()
						ChatCopy_ApplyFontSize(newFrame, data.fontSize)
					end)
				end
			else
				ChatCopy_Debug("Failed to create tab via FCF_OpenNewWindow for '" .. tostring(data.name) .. "'")
			end
		end
	end

	ChatCopy_PersistChatChanges()
	ChatCopy_Debug("After apply windowIds: " .. table.concat(ChatCopy_ListChatWindowIds(), ","))

	-- Save a snapshot for the *target* character too, so we can reapply font sizes on future reloads if the client resets them.
	pcall(ChatCopy_SnapshotCurrentCharacter)

	return true
end

local function ChatCopy_GetAllMessageGroups()
	local groups = {}
	local ignore = {
		CHANNEL = true,
		CHANNEL_JOIN = true,
		CHANNEL_LEAVE = true,
		CHANNEL_NOTICE = true,
		CHANNEL_NOTICE_USER = true,
		IGNORED = true,
		DND = true,
		AFK = true,
	}

	if type(ChatTypeGroup) == "table" then
		for chatType in pairs(ChatTypeGroup) do
			if type(chatType) == "string" and not ignore[chatType] then
				groups[chatType] = true
			end
		end
	end

	-- Fallback: union of known groups from the chat config UI tables, if present.
	if next(groups) == nil and type(CHAT_CONFIG_CHAT_LEFT) == "table" then
		for _, entry in ipairs(CHAT_CONFIG_CHAT_LEFT) do
			if type(entry) == "table" and type(entry.type) == "string" and entry.type ~= "" then
				groups[entry.type] = true
			end
		end
	end

	local list = {}
	for k in pairs(groups) do
		table.insert(list, k)
	end
	table.sort(list)
	return list
end

local function ChatCopy_ApplyTemplate()
	ChatCopy_InitDB()

	if InCombatLockdown and InCombatLockdown() then
		ChatCopy_Print("Cannot apply in combat.")
		return false
	end

	local templateFontSize = 13
	local template = {
		-- window #1: General (everything)
		{
			name = "General",
			fontSize = templateFontSize,
			editBoxFontSize = templateFontSize,
			messageGroups = ChatCopy_GetAllMessageGroups(),
			channels = {},
		},
		-- window #2: Combat Log (do not change)
		{
			keep = true,
			name = "Log",
			fontSize = templateFontSize,
			editBoxFontSize = templateFontSize,
		},
		-- window #3: Whisper (only whispers)
		{
			name = "Whisper",
			fontSize = templateFontSize,
			editBoxFontSize = templateFontSize,
			messageGroups = {
				"WHISPER",
				"WHISPER_INFORM",
				"BN_WHISPER",
				"BN_WHISPER_INFORM",
			},
			channels = {},
		},
		-- window #4: Guild
		{
			name = "Guild",
			fontSize = templateFontSize,
			editBoxFontSize = templateFontSize,
			messageGroups = {
				"GUILD",
				"OFFICER",
				"GUILD_ACHIEVEMENT",
				"GUILD_ANNOUNCEMENT",
			},
			channels = {},
		},
		-- window #5: Party/Raid/Instance
		{
			name = "Party",
			fontSize = templateFontSize,
			editBoxFontSize = templateFontSize,
			messageGroups = {
				"PARTY",
				"PARTY_LEADER",
				"RAID",
				"RAID_LEADER",
				"RAID_WARNING",
				"INSTANCE_CHAT",
				"INSTANCE_CHAT_LEADER",
			},
			channels = {},
		},
	}

	ChatCopy_Debug("Applying built-in template")

	-- Remove existing custom tabs so the template tabs become visible.
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

	-- Apply General (1)
	ChatCopy_ApplyWindow(1, template[1])

	-- Combat Log (2): keep filters, but enforce name/font sizes.
	local combatLogData = template[2]
	local combatLogFrame = ChatCopy_GetChatFrameByWindowId(2)
	if type(combatLogData) == "table" then
		ChatCopy_SetWindowName(2, combatLogData.name)
		if combatLogFrame then
			ChatCopy_ApplyFontSize(combatLogFrame, combatLogData.fontSize)
			ChatCopy_ApplyEditBoxFontSize(combatLogFrame, combatLogData.editBoxFontSize)
		end
	end

	-- Create and configure Whisper/Guild/Party tabs
	for idx = 3, #template do
		local data = template[idx]
		if type(data) == "table" and type(data.name) == "string" then
			if type(FCF_OpenNewWindow) ~= "function" then
				ChatCopy_Print("Cannot create chat tabs (FCF_OpenNewWindow missing).")
				return false
			end
			local ok, newFrame = pcall(FCF_OpenNewWindow, tostring(data.name))
			if ok and newFrame then
				ChatCopy_Debug("Created template tab: '" .. tostring(data.name) .. "'")
				ChatCopy_ApplyToFrame(newFrame, data)
			else
				ChatCopy_Debug("Failed to create template tab via FCF_OpenNewWindow for '" .. tostring(data.name) .. "'")
			end
		end
	end

	ChatCopy_PersistChatChanges()
	pcall(ChatCopy_SnapshotCurrentCharacter)
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

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Copy chat tabs, filters, and font sizes between characters.")

	local sourceHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sourceHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
	sourceHeader:SetText("Source Character")

	local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", sourceHeader, "BOTTOMLEFT", 0, -8)
	label:SetText("Copy From")

	local dropdown = CreateFrame("Frame", "ChatCopyCopyFromDropdown", panel, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -6)
	UIDropDownMenu_SetWidth(dropdown, 260)
	local dropdownPlaceholder = "Select a character..."

	local sourceHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sourceHint:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -2)
	sourceHint:SetWidth(420)
	sourceHint:SetJustifyH("LEFT")
	sourceHint:SetText("Characters appear here after you've logged into them once with ChatCopy enabled.")

	local actionsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	actionsHeader:SetPoint("TOPLEFT", sourceHint, "BOTTOMLEFT", 0, -16)
	actionsHeader:SetText("Actions")

	local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	applyBtn:SetSize(140, 24)
	applyBtn:SetPoint("TOPLEFT", actionsHeader, "BOTTOMLEFT", 0, -6)
	applyBtn:SetText("Apply")
	applyBtn:SetScript("OnClick", function()
		if ChatCopy_ApplySnapshot(selectedSourceKey) then
			local targetKey = ChatCopy_GetCharacterKey()
			ChatCopy_RecordApplyForTarget(targetKey, selectedSourceKey)
			ChatCopy_Print("Applied. Reload UI to finalize?")
			if StaticPopup_Show then
				StaticPopup_Show("CHATCOPY_RELOAD_CONFIRM")
			else
				ChatCopy_Print("Type /reload to finalize.")
			end
		end
	end)

	local applyDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	applyDesc:SetPoint("TOPLEFT", applyBtn, "BOTTOMLEFT", 0, -2)
	applyDesc:SetWidth(420)
	applyDesc:SetJustifyH("LEFT")
	applyDesc:SetText("Apply the selected character's chat tabs and filters to this character. Reload to finalize.")

	local templateBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	templateBtn:SetSize(140, 24)
	templateBtn:SetPoint("TOPLEFT", applyDesc, "BOTTOMLEFT", 0, -10)
	templateBtn:SetText("Apply Template")
	templateBtn:SetScript("OnClick", function()
		if ChatCopy_ApplyTemplate() then
			local targetKey = ChatCopy_GetCharacterKey()
			ChatCopyDB.enforceFontSizes[targetKey] = true
			ChatCopy_Print("Template applied. Reload UI to finalize?")
			if StaticPopup_Show then
				StaticPopup_Show("CHATCOPY_RELOAD_CONFIRM")
			else
				ChatCopy_Print("Type /reload to finalize.")
			end
		end
	end)

	local templateDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	templateDesc:SetPoint("TOPLEFT", templateBtn, "BOTTOMLEFT", 0, -2)
	templateDesc:SetWidth(420)
	templateDesc:SetJustifyH("LEFT")
	templateDesc:SetText("Create General/Log/Whisper/Guild/Party tabs with common filters. Reload to finalize.")

	local applyAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	applyAllBtn:SetSize(140, 24)
	applyAllBtn:SetPoint("TOPLEFT", templateDesc, "BOTTOMLEFT", 0, -10)
	applyAllBtn:SetText("Apply to All")
	applyAllBtn:SetScript("OnClick", function()
		local currentKey = ChatCopy_GetCharacterKey()
		if ChatCopy_ApplySnapshotToAll(currentKey) then
			ChatCopy_Print("Using this character as the source. Other characters update on next login.")
			if StaticPopup_Show then
				StaticPopup_Show("CHATCOPY_RELOAD_CONFIRM")
			else
				ChatCopy_Print("Type /reload to finalize.")
			end
		end
	end)

	local applyAllDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	applyAllDesc:SetPoint("TOPLEFT", applyAllBtn, "BOTTOMLEFT", 0, -2)
	applyAllDesc:SetWidth(420)
	applyAllDesc:SetJustifyH("LEFT")
	applyAllDesc:SetText("Use this character as the source and queue all saved characters to update on next login.")

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
		local valid = {}
		for _, k in ipairs(keys) do
			valid[k] = true
		end
		if selectedSourceKey and not valid[selectedSourceKey] then
			selectedSourceKey = nil
		end
		UIDropDownMenu_SetSelectedValue(dropdown, selectedSourceKey)
		if selectedSourceKey then
			UIDropDownMenu_SetText(dropdown, selectedSourceKey)
		else
			UIDropDownMenu_SetText(dropdown, dropdownPlaceholder)
		end
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

		-- Refresh this character's snapshot after chat initializes so saved data stays current.
		-- This avoids applying stale snapshots (e.g., older saved fontSize=0 values).
		if C_Timer and C_Timer.After then
			if ChatCopyDB and ChatCopyDB.debug then
				ChatCopy_Print("[debug] Auto-snapshot will run in 2s")
			end
			C_Timer.After(2, function()
				local ok, err = pcall(ChatCopy_SnapshotCurrentCharacter)
				if ChatCopyDB and ChatCopyDB.debug then
					ChatCopy_Print("[debug] Auto-snapshot finished (ok=" .. tostring(ok) .. ")")
					if not ok then
						ChatCopy_Print("[debug] Auto-snapshot error: " .. tostring(err))
					end
				end
			end)
		end

		-- Brand new characters can have chat defaults re-applied during reload/login.
		-- If we just applied settings and the user reloaded, re-apply font sizes once after chat initializes.
		local pending = ChatCopyDB and ChatCopyDB.pendingApply
		local currentKey = ChatCopy_GetCharacterKey()

		local applyAllScheduled = ChatCopy_HandlePendingApplyAll(currentKey)

		-- If this character ever used Apply, keep font sizes stable across future reloads.
		if not applyAllScheduled and ChatCopyDB and ChatCopyDB.enforceFontSizes and ChatCopyDB.enforceFontSizes[currentKey] then
			ChatCopy_Debug("Font enforcement enabled; will reapply font sizes from this character's snapshot")
			if C_Timer and C_Timer.After then
				C_Timer.After(0.5, function()
					local ok, err = pcall(ChatCopy_ReapplyFontSizesFromSnapshot, currentKey)
					if ChatCopyDB and ChatCopyDB.debug then
						ChatCopy_Debug("Enforced font sizes (ok=" .. tostring(ok) .. ")")
						if not ok then
							ChatCopy_Debug("Enforce font sizes error: " .. tostring(err))
						end
					end
				end)
			else
				pcall(ChatCopy_ReapplyFontSizesFromSnapshot, currentKey)
			end
		end

		if not applyAllScheduled and type(pending) == "table" and pending.targetKey == currentKey and type(pending.sourceKey) == "string" then
			local sourceKey = pending.sourceKey
			ChatCopy_Debug("Pending apply detected; will reapply font sizes from: " .. tostring(sourceKey))
			if C_Timer and C_Timer.After then
				C_Timer.After(0.5, function()
					local ok, err = pcall(ChatCopy_ReapplyFontSizesFromSnapshot, sourceKey)
					ChatCopyDB.pendingApply = nil
					if ChatCopyDB and ChatCopyDB.debug then
						ChatCopy_Debug("Pending font size reapply complete (ok=" .. tostring(ok) .. ")")
						if not ok then
							ChatCopy_Debug("Pending font size reapply error: " .. tostring(err))
						end
					end
				end)
			else
				pcall(ChatCopy_ReapplyFontSizesFromSnapshot, sourceKey)
				ChatCopyDB.pendingApply = nil
			end
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Keep this quiet and minimal: snapshot so other characters can copy from it.
		local ok, err = pcall(ChatCopy_SnapshotCurrentCharacter)
		if ChatCopyDB and ChatCopyDB.debug and not ok then
			ChatCopy_Print("[debug] Logout snapshot error: " .. tostring(err))
		end
	end
end)
