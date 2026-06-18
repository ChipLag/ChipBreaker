local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local VERSION = "1.0.0"
local KEYBIND_FILE = "chipbreaker_keybinds.json"
local ANDROID_BUTTON_FILE = "chipbreaker_android_buttons.json"
local DRAG_THRESHOLD = 15  -- pixels before Android button registers as drag

local theme = {
	bg          = Color3.fromRGB(13, 13, 26),
	sidebar     = Color3.fromRGB(18, 18, 36),
	card        = Color3.fromRGB(24, 24, 50),
	cardHover   = Color3.fromRGB(30, 30, 60),
	accent      = Color3.fromRGB(68, 128, 255),
	accentDark  = Color3.fromRGB(50, 100, 220),
	text        = Color3.fromRGB(225, 225, 245),
	textDim     = Color3.fromRGB(130, 130, 165),
	border      = Color3.fromRGB(35, 35, 60),
	borderLight = Color3.fromRGB(45, 45, 75),
	danger      = Color3.fromRGB(255, 75, 75),
	success     = Color3.fromRGB(60, 200, 120),
	warning     = Color3.fromRGB(255, 180, 50),
	checkboxOff = Color3.fromRGB(40, 40, 68),
	sliderBg    = Color3.fromRGB(40, 40, 68),
	inputBg     = Color3.fromRGB(28, 28, 54),
	scrollBar   = Color3.fromRGB(45, 45, 75),
	keybindBg   = Color3.fromRGB(35, 35, 62),
	keybindOn   = Color3.fromRGB(68, 128, 255),
}

local ChipGui = {}

local state = {
	window            = nil,
	screenGui         = nil,
	menus             = {},         -- ordered list of menu names
	menuFrames        = {},         -- menuName -> frame with elements
	menuObjects       = {},         -- menuName -> menu object
	activeMenu        = nil,
	sidebarButtons    = {},         -- menuName -> sidebar button
	currentContext    = "unknown",  -- current keybind context (set by loaded scripts)
	keybindContexts   = {},         -- contextId -> { bindings }
	androidButtons    = {},         -- list of android button objects
	androidButtonQueue = {},        -- queued button descriptions
	keybindBadges     = {},         -- {badge, context} for toggle visibility
	isAndroid         = false,
	initialized       = false,
	visible           = true,
	connectionPool    = {},         -- connections for cleanup
}

_G.chipbreaker = _G.chipbreaker or {}
_G.chipbreaker.ChipGui = ChipGui

local function create(class, props, children)
	local obj = Instance.new(class)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	for _, child in ipairs(children or {}) do
		child.Parent = obj
	end
	return obj
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or theme.border
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

local function padding(parent, amount)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

--- Safely read and decode a JSON file from the executor filesystem.
local function safeRead(path)
	local ok, data = pcall(readfile, path)
	if not ok then return nil end
	local success, decoded = pcall(HttpService.JSONDecode, HttpService, data)
	if success then return decoded end
	return nil
end

--- Encode a table to JSON and write it to the executor filesystem.
local function safeWrite(path, data)
	local json = HttpService:JSONEncode(data)
	local ok = pcall(writefile, path, json)
	return ok
end

--- Compute a safe filesystem key from an arbitrary context string.
local function contextKey(id)
	return string.gsub(id or "unknown", "[^%w_%-]", "_")
end

--- Make a GUI frame draggable via mouse/touch.
--- Returns the InputBegan connection so it can be disconnected if needed.
local function makeDraggable(frame)
	local dragging = false
	local dragStart, startPos
	local moveCon, endCon

	local began = frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			moveCon = UserInputService.InputChanged:Connect(function(inp)
				if not dragging then return end
				if inp.UserInputType ~= Enum.UserInputType.MouseMovement
					and inp.UserInputType ~= Enum.UserInputType.Touch then return end
				local delta = inp.Position - dragStart
				frame.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end)
			endCon = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1
					or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = false
					if moveCon then moveCon:Disconnect() end
					if endCon then endCon:Disconnect() end
				end
			end)
		end
	end)

	return began
end

--- Tween a property on an instance.
local function tween(obj, props, time, style, direction)
	local tweenInfo = TweenInfo.new(
		time or 0.15,
		Enum.EasingStyle[style or "Quad"],
		Enum.EasingDirection[direction or "Out"]
	)
	local tw = TweenService:Create(obj, tweenInfo, props)
	tw:Play()
	return tw
end

--- Load all saved keybinds from disk.
function ChipGui:LoadAllKeybinds()
	return safeRead(KEYBIND_FILE) or {}
end

--- Save all keybind contexts to disk.
function ChipGui:SaveAllKeybinds()
	local data = {}
	for cid, binds in pairs(state.keybindContexts) do
		data[cid] = {}
		for _, b in ipairs(binds) do
			data[cid][b.label] = { key = b.currentKey, type = b.bindType }
		end
	end
	safeWrite(KEYBIND_FILE, data)
end

--- Get the saved key for a specific context + label.
function ChipGui:GetSavedKey(contextId, label)
	local all = self:LoadAllKeybinds()
	local ctx = all[contextId]
	if ctx and ctx[label] then
		return ctx[label].key
	end
	return nil
end

--- Load saved Android button positions.
function ChipGui:LoadButtonPositions()
	return safeRead(ANDROID_BUTTON_FILE) or {}
end

--- Save a single Android button's position.
function ChipGui:SaveButtonPosition(contextId, buttonId, xOffset, yOffset)
	local data = self:LoadButtonPositions()
	if not data[contextId] then data[contextId] = {} end
	data[contextId][buttonId] = { X = xOffset, Y = yOffset }
	safeWrite(ANDROID_BUTTON_FILE, data)
end

--- Get a saved Android button position.
function ChipGui:GetButtonPosition(contextId, buttonId)
	local data = self:LoadButtonPositions()
	if data[contextId] and data[contextId][buttonId] then
		return data[contextId][buttonId]
	end
	return nil
end

--- Set the current keybind context (call before creating elements with keybinds).
--- This allows each loaded script to have its own keybind namespace.
function ChipGui:SetContext(contextId)
	state.currentContext = contextId or "unknown"
end

--- Register a keybind for the current context.
--- @param label string - display name for the keybind
--- @param defaultKey string - default key (e.g. "Q")
--- @param bindType string - "toggle" or "press"
--- @param callback function - called when key is pressed
function ChipGui:RegisterKeybind(label, defaultKey, bindType, callback)
	local ctx = state.currentContext
	if not ctx or ctx == "unknown" then
		warn("ChipBreaker: RegisterKeybind called without setting context first.")
		return nil
	end

	if not state.keybindContexts[ctx] then
		state.keybindContexts[ctx] = {}
	end

	local savedKey = self:GetSavedKey(ctx, label)
	local actualKey = (savedKey ~= nil) and savedKey or defaultKey
	if not actualKey then return nil end

	local bind = {
		label = label,
		defaultKey = defaultKey,
		currentKey = actualKey,
		bindType = bindType or "toggle",
		callback = callback,
		keyDown = false,
	}

	local connection
	connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode ~= Enum.KeyCode[bind.currentKey] then return end
		bind.keyDown = true
		if bind.bindType == "press" then
			bind.callback(true)
		elseif bind.bindType == "toggle" then
			bind.callback()
		end
	end)

	local connectionEnd
	connectionEnd = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode ~= Enum.KeyCode[bind.currentKey] then return end
		bind.keyDown = false
		if bind.bindType == "press" then
			bind.callback(false)
		end
	end)

	table.insert(state.keybindContexts[ctx], bind)

	local control = {}
	function control:GetKey()
		return bind.currentKey
	end
	function control:SetKey(newKey)
		bind.currentKey = newKey
		ChipGui:SaveAllKeybinds()
	end
	function control:GetLabel()
		return bind.label
	end
	function control:GetContext()
		return ctx
	end
	return control
end

--- Update a keybind's key for a given context and label.
function ChipGui:UpdateKeybind(contextId, label, newKey)
	local ctx = state.keybindContexts[contextId]
	if not ctx then return end
	for _, bind in ipairs(ctx) do
		if bind.label == label then
			bind.currentKey = newKey
			self:SaveAllKeybinds()
			return bind
		end
	end
end

--- Get all keybinds grouped by context.
function ChipGui:GetAllKeybinds()
	return state.keybindContexts
end

--- Get all keybinds for a specific context.
function ChipGui:GetContextKeybinds(contextId)
	return state.keybindContexts[contextId]
end

--- Create a floating touch button on Android devices.
--- The button can be dragged (after a threshold) and saves its position.
--- @param contextId string - owning script context
--- @param buttonId string - unique identifier within the context
--- @param label string - display text
--- @param defaultX number - default X offset
--- @param defaultY number - default Y offset
--- @param onClick function - called when tapped
--- @param onGetState function - returns current toggle state for visual feedback
--- @return table - button control object
function ChipGui:CreateAndroidButton(contextId, buttonId, label, defaultX, defaultY, onClick, onGetState)
	if not state.isAndroid then return nil end
	if not state.screenGui then return nil end

	local saved = self:GetButtonPosition(contextId, buttonId)
	local posX = saved and saved.X or defaultX
	local posY = saved and saved.Y or defaultY

	-- Check for duplicate before creating
	local uid = contextId .. "_" .. buttonId
	for _, existing in ipairs(state.androidButtons) do
		if existing.uid == uid then
			return existing
		end
	end

	-- Use hash-based Y offset for unsaved positions so buttons don't stack
	if not saved then
		local hash = 0
		local str = uid
		for i = 1, #str do
			hash = hash + string.byte(str, i)
		end
		posY = 100 + (hash % 500)
	end

	local btnFrame = create("Frame", {
		Name = "AndroidBtn_" .. buttonId,
		Size = UDim2.new(0, 0, 0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, posX, 0, posY),
		BackgroundColor3 = theme.card,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		corner(btnFrame, 10),
		stroke(btnFrame, theme.accent, 1),
	})
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(60, 44)
	sizeConstraint.Parent = btnFrame
	btnFrame.Parent = state.screenGui

	local btnLabel = create("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = label,
		Font = Enum.Font.GothamSemibold,
		TextSize = 16,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	btnLabel.Parent = btnFrame

	local indicator = create("Frame", {
		Size = UDim2.new(0, 10, 0, 10),
		Position = UDim2.new(1, -16, 0, 17),
		BackgroundColor3 = theme.checkboxOff,
		BorderSizePixel = 0,
	}, {
		corner(indicator, 5),
	})
	indicator.Parent = btnFrame

	local dragging = false
	local moved = false
	local dragStart, frameStart

	local touchBegan = btnFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			frameStart = btnFrame.Position
		end
	end)

	local touchMoved = btnFrame.InputChanged:Connect(function(input)
		if not dragging or input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = (input.Position - dragStart).Magnitude
		if delta > DRAG_THRESHOLD then
			moved = true
			local offset = input.Position - dragStart
			btnFrame.Position = UDim2.new(
				frameStart.X.Scale, frameStart.X.Offset + offset.X,
				frameStart.Y.Scale, frameStart.Y.Offset + offset.Y
			)
		end
	end)

	local touchEnded = btnFrame.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = false
		if not moved then
			onClick()
		else
			self:SaveButtonPosition(
				contextId, buttonId,
				btnFrame.Position.X.Offset,
				btnFrame.Position.Y.Offset
			)
		end
	end)

	local btnObj = {
		uid = uid,
		contextId = contextId,
		frame = btnFrame,
		label = btnLabel,
		indicator = indicator,

		--- Update the visual state of the button.
		SetState = function(self, enabled)
			self.indicator.BackgroundColor3 = enabled and theme.success or theme.checkboxOff
		end,

		--- Update the position of the button.
		SetPosition = function(self, x, y)
			self.frame.Position = UDim2.new(0, x, 0, y)
		end,

		--- Get current position.
		GetPosition = function(self)
			return self.frame.Position.X.Offset, self.frame.Position.Y.Offset
		end,

		--- Remove the button from the screen.
		Destroy = function(self)
			touchBegan:Disconnect()
			touchMoved:Disconnect()
			touchEnded:Disconnect()
			self.frame:Destroy()
		end,
	}

	if onGetState then
		btnObj:SetState(onGetState())
	end

	table.insert(state.androidButtons, btnObj)
	return btnObj
end

--- Remove all Android buttons for a given context.
function ChipGui:RemoveContextButtons(contextId)
	for i = #state.androidButtons, 1, -1 do
		local btn = state.androidButtons[i]
		if btn.contextId == contextId then
			btn:Destroy()
			table.remove(state.androidButtons, i)
		end
	end
end

--- Queue an Android button description (created later when floating buttons are enabled).
function ChipGui:QueueAndroidButton(context, id, label, x, y, onClick, onGetState)
	table.insert(state.androidButtonQueue, {
		context = context,
		id = id,
		label = label,
		x = x,
		y = y,
		onClick = onClick,
		onGetState = onGetState,
	})
end

--- Create all queued Android buttons.
function ChipGui:FlushAndroidButtonQueue()
	for _, btn in ipairs(state.androidButtonQueue) do
		self:CreateAndroidButton(
			btn.context, btn.id, btn.label,
			btn.x, btn.y, btn.onClick, btn.onGetState
		)
	end
end

--- Destroy all created floating buttons (preserves queue descriptions for re-creation).
function ChipGui:RemoveAllFloatingButtons()
	for i = #state.androidButtons, 1, -1 do
		local btn = state.androidButtons[i]
		if btn.contextId ~= "_chipbreaker" then
			btn:Destroy()
			table.remove(state.androidButtons, i)
		end
	end
end

--- Show or hide all keybind badges on toggles/buttons in the GUI.
function ChipGui:SetKeybindBadgesVisible(visible)
	for _, entry in ipairs(state.keybindBadges) do
		entry.badge.Visible = visible
	end
end

--- Create a toggle/checkbox UI element.
--- @param parent instance - parent frame
--- @param label string - display text
--- @param defaultState boolean
--- @param onChange function(enabled)
--- @param keybind string|nil - optional default key
--- @return table - control object
local function createToggle(parent, label, defaultState, onChange, keybind)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	frame.Parent = parent

	local clickArea = create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})
	clickArea.Parent = frame

	local checkBox = create("Frame", {
		Size = UDim2.new(0, 20, 0, 20),
		Position = UDim2.new(0, 0, 0.5, -10),
		BackgroundColor3 = defaultState and theme.accent or theme.checkboxOff,
		BorderSizePixel = 0,
	}, {
		corner(checkBox, 5),
	})
	checkBox.Parent = frame

	local checkMark = create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 255, 255),
	})
	checkMark.Parent = checkBox

	local labelObj = create("TextLabel", {
		Size = UDim2.new(0, 0, 0, 20),
		Position = UDim2.new(0, 28, 0.5, -10),
		BackgroundTransparency = 1,
		Text = label,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
	})
	labelObj.Parent = frame

	local keybindBtn = nil
	local keybindControl = nil

	local function updateKeybindBadge(key)
		if not keybindBtn then return end
		if key and key ~= "" then
			keybindBtn.Visible = true
			keybindBtn.Text = "[" .. key .. "]"
		else
			keybindBtn.Visible = false
		end
	end

	if keybind then
		keybindBtn = create("TextButton", {
			Size = UDim2.new(0, 0, 0, 24),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = theme.keybindBg,
			AutoButtonColor = false,
			Text = "[" .. keybind .. "]",
			Font = Enum.Font.GothamSemibold,
			TextSize = 12,
			TextColor3 = theme.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.X,
		}, {
			corner(keybindBtn, 4),
		})
		keybindBtn.Parent = frame
		table.insert(state.keybindBadges, { badge = keybindBtn })

		local badgePad = Instance.new("UIPadding")
		badgePad.PaddingLeft = UDim.new(0, 8)
		badgePad.PaddingRight = UDim.new(0, 8)
		badgePad.Parent = keybindBtn

		local listening = false
		keybindBtn.MouseButton1Click:Connect(function()
			if listening then return end
			listening = true
			keybindBtn.Text = "[...]"
			keybindBtn.BackgroundColor3 = theme.keybindOn
			keybindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

			local rebindCon, rebindEndCon
			rebindCon = UserInputService.InputBegan:Connect(function(inp, gp)
				if gp then return end
				if inp.UserInputType == Enum.UserInputType.Keyboard then
					local keyName = inp.KeyCode.Name
					if keyName and keyName ~= "Unknown" then
						keybindControl:SetKey(keyName)
						updateKeybindBadge(keyName)
						keybindBtn.BackgroundColor3 = theme.keybindBg
						keybindBtn.TextColor3 = theme.textDim
						listening = false
						rebindCon:Disconnect()
						if rebindEndCon then rebindEndCon:Disconnect() end
					end
				elseif inp.UserInputType == Enum.UserInputType.MouseButton1
					or inp.UserInputType == Enum.UserInputType.MouseButton2 then
					keybindBtn.BackgroundColor3 = theme.keybindBg
					keybindBtn.TextColor3 = theme.textDim
					updateKeybindBadge(keybindControl:GetKey())
					listening = false
					rebindCon:Disconnect()
					if rebindEndCon then rebindEndCon:Disconnect() end
				end
			end)

			rebindEndCon = UserInputService.InputEnded:Connect(function(inp, gp)
				if gp then return end
				if inp.KeyCode == Enum.KeyCode.Escape and listening then
					keybindBtn.BackgroundColor3 = theme.keybindBg
					keybindBtn.TextColor3 = theme.textDim
					updateKeybindBadge(keybindControl:GetKey())
					listening = false
					rebindCon:Disconnect()
					rebindEndCon:Disconnect()
				end
			end)
		end)
	end

	local isOn = defaultState or false
	local control = {
		frame = frame,
		SetState = function(self, val)
			isOn = val
			checkBox.BackgroundColor3 = isOn and theme.accent or theme.checkboxOff
			if onChange then onChange(isOn) end
		end,
		GetState = function(self)
			return isOn
		end,
		Toggle = function(self)
			self:SetState(not isOn)
		end,
		BindKey = function(self, key)
			if keybindControl then
				keybindControl:SetKey(key)
				updateKeybindBadge(key)
			end
		end,
		UnbindKey = function(self)
			if keybindBtn then
				keybindBtn.Visible = false
			end
		end,
	}

	if keybind then
		keybindControl = ChipGui:RegisterKeybind(label, keybind, "toggle", function()
			control:Toggle()
		end)
	end

	clickArea.MouseButton1Click:Connect(function()
		control:Toggle()
	end)

	local function updateCheckMark()
		if isOn then
			checkMark.Text = "+"  -- Simple character instead of emoji.
		else
			checkMark.Text = ""
		end
	end
	updateCheckMark()

	local origSetState = control.SetState
	control.SetState = function(self, val)
		origSetState(self, val)
		updateCheckMark()
	end

	return control
end

--- Create a slider UI element.
local function createSlider(parent, label, min, max, defaultValue, onChange)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	})
	frame.Parent = parent

	local valueDisplay = create("TextLabel", {
		Size = UDim2.new(0, 60, 0, 18),
		Position = UDim2.new(1, -60, 0, 0),
		BackgroundTransparency = 1,
		Text = tostring(defaultValue),
		Font = Enum.Font.GothamSemibold,
		TextSize = 12,
		TextColor3 = theme.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	valueDisplay.Parent = frame

	local labelObj = create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 18),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = label,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	labelObj.Parent = frame

	local track = create("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.new(0, 0, 0, 28),
		BackgroundColor3 = theme.sliderBg,
		BorderSizePixel = 0,
	}, {
		corner(track, 2),
	})
	track.Parent = frame

	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = theme.accent,
		BorderSizePixel = 0,
	}, {
		corner(fill, 2),
	})
	fill.Parent = track

	local thumb = create("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(0, -7, 0.5, -7),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, {
		corner(thumb, 7),
		stroke(thumb, theme.accent, 2),
	})
	thumb.Parent = track

	local inputFrame = create("Frame", {
		Size = UDim2.new(0, 50, 0, 20),
		Position = UDim2.new(1, -50, 0, 0),
		BackgroundColor3 = theme.inputBg,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		corner(inputFrame, 4),
	})
	inputFrame.Parent = frame

	local manualInput = create("TextBox", {
		Size = UDim2.new(1, -6, 1, 0),
		Position = UDim2.new(0, 3, 0, 0),
		BackgroundTransparency = 1,
		Text = tostring(defaultValue),
		PlaceholderText = tostring(defaultValue),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = theme.text,
		ClearTextOnFocus = true,
	})
	manualInput.Parent = inputFrame

	local currentValue = defaultValue
	local range = max - min
	if range <= 0 then range = 1 end

	local function setValueFromFraction(fraction)
		fraction = math.clamp(fraction, 0, 1)
		local val = min + fraction * range
		val = math.floor(val + 0.5)
		currentValue = val
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		thumb.Position = UDim2.new(fraction, -7, 0.5, -7)
		valueDisplay.Text = tostring(val)
		if onChange then onChange(val) end
	end

	local initFraction = (defaultValue - min) / range
	setValueFromFraction(initFraction)

	local dragging = false
	local trackSize = track.AbsoluteSize.X

	local function updateFromMouse(mousePos)
		local trackAbsPos = track.AbsolutePosition
		local relX = mousePos.X - trackAbsPos.X
		local fraction = relX / track.AbsoluteSize.X
		setValueFromFraction(fraction)
	end

	local thumbBegan = thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			trackSize = track.AbsoluteSize.X
		end
	end)

	local inputChanged = UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			updateFromMouse(input.Position)
		end
	end)

	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local trackClick = track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			updateFromMouse(input.Position)
		end
	end)

	valueDisplay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if inputFrame.Visible then return end
			inputFrame.Visible = true
			valueDisplay.Visible = false
			manualInput:CaptureFocus()
		end
	end)

	manualInput.FocusLost:Connect(function(enterPressed)
		inputFrame.Visible = false
		valueDisplay.Visible = true
		if enterPressed then
			local val = tonumber(manualInput.Text)
			if val then
				val = math.clamp(val, min, max)
				currentValue = val
				local frac = (val - min) / range
				setValueFromFraction(frac)
			end
		end
		manualInput.Text = tostring(currentValue)
	end)

	local control = {
		frame = frame,
		GetValue = function(self)
			return currentValue
		end,
		SetValue = function(self, val)
			val = math.clamp(val, min, max)
			local frac = (val - min) / range
			setValueFromFraction(frac)
		end,
	}

	return control
end

--- Create a button UI element.
local function createButton(parent, text, callback, keybind)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})
	frame.Parent = parent

	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = theme.card,
		AutoButtonColor = false,
		Text = text,
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextColor3 = theme.text,
	}, {
		corner(btn, 6),
		stroke(btn, theme.borderLight, 1),
	})
	btn.Parent = frame

	btn.MouseEnter:Connect(function()
		tween(btn, { BackgroundColor3 = theme.cardHover }, 0.1)
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, { BackgroundColor3 = theme.card }, 0.15)
	end)
	btn.MouseButton1Click:Connect(function()
		tween(btn, { BackgroundColor3 = theme.accentDark }, 0.08)
		tween(btn, { BackgroundColor3 = theme.cardHover }, 0.12, "Quad", "Out", 0.08)
		callback()
	end)

	local control = { frame = frame, button = btn }

	if keybind then
		local keybindControl = ChipGui:RegisterKeybind(text, keybind, "press", function(pressed)
			if pressed then
				callback()
			end
		end)

		local badge = create("TextButton", {
			Size = UDim2.new(0, 0, 0, 24),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = theme.keybindBg,
			AutoButtonColor = false,
			Text = "[" .. keybind .. "]",
			Font = Enum.Font.GothamSemibold,
			TextSize = 12,
			TextColor3 = theme.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.X,
		}, {
			corner(badge, 4),
		})
		badge.Parent = frame
		table.insert(state.keybindBadges, { badge = badge })

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = badge
	end

	return control
end

--- Create a label UI element.
local function createLabel(parent, text, fontSize)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
	})
	frame.Parent = parent

	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamSemibold,
		TextSize = fontSize or 14,
		TextColor3 = theme.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label.Parent = frame

	return { frame = frame, label = label }
end

--- Create a section header label.
local function createSectionHeader(parent, text)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	})
	frame.Parent = parent

	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label.Parent = frame

	local line = create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = theme.border,
		BorderSizePixel = 0,
	})
	line.Parent = frame

	return { frame = frame, label = label }
end

--- Create an input text box.
local function createInput(parent, placeholder, onSubmit)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})
	frame.Parent = parent

	local inputBg = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = theme.inputBg,
		BorderSizePixel = 0,
	}, {
		corner(inputBg, 6),
		stroke(inputBg, theme.border, 1),
	})
	inputBg.Parent = frame

	local inputBox = create("TextBox", {
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = theme.textDim,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.text,
		ClearTextOnFocus = false,
	})
	inputBox.Parent = inputBg

	inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and onSubmit then
			onSubmit(inputBox.Text)
		end
	end)

	local debounceTimer = nil
	inputBox:GetPropertyChangedSignal("Text"):Connect(function()
		if debounceTimer then
			debounceTimer:Disconnect()
		end
		debounceTimer = task.delay(0.15, function()
			if onSubmit then
				onSubmit(inputBox.Text)
			end
		end)
	end)

	return {
		frame = frame,
		input = inputBox,
		GetText = function(self) return inputBox.Text end,
		SetText = function(self, text) inputBox.Text = text end,
	}
end

--- Create a list container (scrollable list of items).
local function createList(parent)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 0, 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Parent = frame
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local listObj = {}

	--- Add a checkbox to this list.
	function listObj:AddCheckbox(label, keybind, callback)
		if type(keybind) == "function" then
			callback = keybind
			keybind = nil
		end
		return createToggle(frame, label, false, callback, keybind)
	end

	--- Add a label to this list.
	function listObj:AddLabel(text, fontSize)
		return createLabel(frame, text, fontSize)
	end

	--- Add a section header to this list.
	function listObj:AddSectionHeader(text)
		return createSectionHeader(frame, text)
	end

	--- Add a button to this list.
	function listObj:AddButton(text, keybind, callback)
		if type(keybind) == "function" then
			callback = keybind
			keybind = nil
		end
		return createButton(frame, text, callback, keybind)
	end

	--- Add a custom frame to the list.
	function listObj:AddFrame(customFrame)
		customFrame.Parent = frame
		return customFrame
	end

	--- Clear all items from the list.
	function listObj:Clear()
		for _, child in ipairs(frame:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	listObj.Frame = frame

	return listObj
end

--- Create a new menu tab.
--- @param name string - display name for the tab
--- @return table - menu control object with Add___ methods
function ChipGui:NewMenu(name)
	if not state.initialized then
		self:ShowWindow()
	end

	for _, m in ipairs(state.menus) do
		if m == name then
			warn("ChipBreaker: Menu '" .. name .. "' already exists.")
			return state.menuObjects[name]
		end
	end

	table.insert(state.menus, name)

	local contentFrame = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.scrollBar,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	contentFrame.Parent = state.menuContainer

	local layout = Instance.new("UIListLayout")
	layout.Parent = contentFrame
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local spacer = create("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundTransparency = 1,
	})
	spacer.Parent = contentFrame

	state.menuFrames[name] = contentFrame

	local btn = create("TextButton", {
		Size = UDim2.new(1, -12, 0, 32),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 36),
		AutoButtonColor = false,
		Text = "  " .. name,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, {
		corner(btn, 6),
	})
	btn.Parent = state.sidebarScroll

	btn.MouseButton1Click:Connect(function()
		self:ActivateMenu(name)
	end)

	btn.MouseEnter:Connect(function()
		if state.activeMenu ~= name then
			tween(btn, { BackgroundColor3 = theme.card }, 0.1)
		end
	end)

	btn.MouseLeave:Connect(function()
		if state.activeMenu ~= name then
			btn.BackgroundColor3 = Color3.fromRGB(18, 18, 36)
		end
	end)

	state.sidebarButtons[name] = btn

	if #state.menus == 1 then
		self:ActivateMenu(name)
	end

	local menuObj = {}

	state.menuObjects[name] = menuObj

	function menuObj:AddToggle(label, keybind, callback)
		if type(keybind) == "function" then
			callback = keybind
			keybind = nil
		end
		return createToggle(contentFrame, label, false, callback, keybind)
	end

	function menuObj:AddSlider(label, min, max, default, callback)
		return createSlider(contentFrame, label, min, max, default, callback)
	end

	function menuObj:AddInput(placeholder, callback)
		return createInput(contentFrame, placeholder, callback)
	end

	function menuObj:AddList()
		return createList(contentFrame)
	end

	function menuObj:AddLabel(text, fontSize)
		return createLabel(contentFrame, text, fontSize)
	end

	function menuObj:AddSectionHeader(text)
		return createSectionHeader(contentFrame, text)
	end

	function menuObj:AddButton(text, keybind, callback)
		if type(keybind) == "function" then
			callback = keybind
			keybind = nil
		end
		return createButton(contentFrame, text, callback, keybind)
	end

	function menuObj:GetName()
		return name
	end

	return menuObj
end

--- Activate a menu tab by name.
function ChipGui:ActivateMenu(name)
	for _, frame in pairs(state.menuFrames) do
		frame.Visible = false
	end

	for btnName, btn in pairs(state.sidebarButtons) do
		btn.BackgroundColor3 = Color3.fromRGB(18, 18, 36)
		btn.TextColor3 = theme.textDim
	end

	local content = state.menuFrames[name]
	if content then
		content.Visible = true
		content.CanvasPosition = Vector2.new(0, 0)
	end

	local btn = state.sidebarButtons[name]
	if btn then
		btn.BackgroundColor3 = theme.card
		btn.TextColor3 = theme.text
	end

	state.activeMenu = name
end

--- Hide the entire window.
function ChipGui:Hide()
	if state.window then
		state.window.Visible = false
		state.visible = false
	end
end

--- Show the window.
function ChipGui:Show()
	if state.window then
		state.window.Visible = true
		state.visible = true
	else
		self:ShowWindow()
	end
end

--- Toggle window visibility.
function ChipGui:Toggle()
	if state.visible then
		self:Hide()
	else
		self:Show()
	end
end

--- Create and show the main ChipBreaker window.
function ChipGui:ShowWindow()
	if state.initialized then
		self:Show()
		return
	end

	state.isAndroid = UserInputService.TouchEnabled

	local screenGui = create("ScreenGui", {
		Name = "ChipBreaker",
		DisplayOrder = 100,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local guiParent = CoreGui
	local ok, result = pcall(gethui)
	if ok and result then
		guiParent = result
	end
	screenGui.Parent = guiParent

	local window = create("Frame", {
		Name = "MainWindow",
		Size = UDim2.new(0, 680, 0, 480),
		Position = UDim2.new(0.5, -340, 0.5, -240),
		BackgroundColor3 = theme.bg,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		corner(window, 8),
		stroke(window, theme.border, 1),
	})
	window.Parent = screenGui

	local titleBar = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.sidebar,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
	})

	titleBar.Parent = window

	local titleLabel = create("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1,
		Text = "ChipBreaker  v" .. VERSION,
		Font = Enum.Font.GothamSemibold,
		TextSize = 14,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	titleLabel.Parent = titleBar

	local minBtn = create("TextButton", {
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -66, 0, 4),
		BackgroundColor3 = Color3.fromRGB(40, 40, 68),
		AutoButtonColor = false,
		Text = "_",
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = theme.text,
	}, {
		corner(minBtn, 6),
	})
	minBtn.Parent = titleBar
	minBtn.MouseEnter:Connect(function()
		minBtn.BackgroundColor3 = theme.borderLight
	end)
	minBtn.MouseLeave:Connect(function()
		minBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 68)
	end)
	minBtn.MouseButton1Click:Connect(function()
		self:Hide()
	end)

	local closeBtn = create("TextButton", {
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -34, 0, 4),
		BackgroundColor3 = Color3.fromRGB(40, 40, 68),
		AutoButtonColor = false,
		Text = "X",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = theme.text,
	}, {
		corner(closeBtn, 6),
	})
	closeBtn.Parent = titleBar
	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = theme.danger
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 68)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		self:Hide()
	end)

	makeDraggable(window)

	local sidebar = create("Frame", {
		Size = UDim2.new(0, 170, 1, -36),
		Position = UDim2.new(0, 0, 0, 36),
		BackgroundColor3 = theme.sidebar,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
	})
	sidebar.Parent = window

	local sidebarScroll = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	sidebarScroll.Parent = sidebar

	state.sidebarScroll = sidebarScroll

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.Parent = sidebarScroll
	sidebarLayout.Padding = UDim.new(0, 2)
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local contentArea = create("Frame", {
		Size = UDim2.new(1, -170, 1, -36),
		Position = UDim2.new(0, 170, 0, 36),
		BackgroundColor3 = theme.bg,
		BorderSizePixel = 0,
	})
	contentArea.Parent = window

	state.menuContainer = create("Frame", {
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	state.menuContainer.Parent = contentArea

	state.window = window
	state.screenGui = screenGui
	state.initialized = true

	self:NewMenu("Home")
	self:NewMenu("Globals")
	self:NewMenu("Scripts")
	self:NewMenu("Settings")

	if #state.menus > 0 then
		self:ActivateMenu(state.menus[1])
	end

	self:SetupHomeMenu()
	self:SetupSettingsMenu()

	if state.isAndroid then
		self:CreateToggleButton()
		self:SetKeybindBadgesVisible(false)
	end

	state.currentContext = "_chipbreaker"
	ChipGui:RegisterKeybind("Toggle GUI", "RightShift", "toggle", function()
		self:Toggle()
	end)

	return window
end

--- Set up the Home menu with welcome information.
function ChipGui:SetupHomeMenu()
	local home = self:NewMenu("Home")
	home:AddSectionHeader("Welcome to ChipBreaker")
	home:AddLabel("A clean script hub with per-script keybind management.")
	home:AddLabel("Use the Globals tab to set a toggle key.")
	home:AddLabel("")

	home:AddSectionHeader("Getting Started")
	home:AddLabel("1. Browse the Globals tab for universal settings.")
	home:AddLabel("2. Use the Scripts tab to enable game-type modules.")
	home:AddLabel("3. Bind keys to toggles by clicking the key badge.")
	home:AddLabel("")

	home:AddSectionHeader("Key Features")
	home:AddLabel("- Walkspeed and JumpHeight sliders")
	home:AddLabel("- Noclip and other global toggles")
	home:AddLabel("- Per-script keybind saving (no conflicts)")
	home:AddLabel("- Android touch button support")
	home:AddLabel("- Clean, modern interface")

	home:AddLabel("")
	local versionLabel = home:AddLabel("ChipBreaker v" .. VERSION, 12)
end

--- Set up the Settings menu with keybind management.
function ChipGui:SetupSettingsMenu()
	local settingsMenu = self:NewMenu("Settings")

	settingsMenu:AddSectionHeader("Keybind Manager")
	settingsMenu:AddLabel("Click a keybind below to change it.")

	local keybindList = settingsMenu:AddList()

	local function refreshKeybindList()
		keybindList:Clear()

		local hasAny = false
		for contextId, binds in pairs(state.keybindContexts) do
			if #binds > 0 then
				hasAny = true
				keybindList:AddSectionHeader("  [" .. contextId .. "]")
				for _, bind in ipairs(binds) do
					local row = create("Frame", {
						Size = UDim2.new(1, 0, 0, 28),
						BackgroundColor3 = theme.card,
						BorderSizePixel = 0,
					}, {
						corner(row, 6),
					})

					local labelEl = create("TextLabel", {
						Size = UDim2.new(1, -80, 1, 0),
						Position = UDim2.new(0, 10, 0, 0),
						BackgroundTransparency = 1,
						Text = bind.label,
						Font = Enum.Font.Gotham,
						TextSize = 13,
						TextColor3 = theme.text,
						TextXAlignment = Enum.TextXAlignment.Left,
					})
					labelEl.Parent = row

					local keyBtn = create("TextButton", {
						Size = UDim2.new(0, 0, 0, 24),
						Position = UDim2.new(1, -6, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundColor3 = theme.keybindBg,
						AutoButtonColor = false,
						Text = "[" .. bind.currentKey .. "]",
						Font = Enum.Font.GothamSemibold,
						TextSize = 12,
						TextColor3 = theme.textDim,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.X,
					}, {
						corner(keyBtn, 4),
					})
					local pad = Instance.new("UIPadding")
					pad.PaddingLeft = UDim.new(0, 8)
					pad.PaddingRight = UDim.new(0, 8)
					pad.Parent = keyBtn
					keyBtn.Parent = row

					keyBtn.MouseButton1Click:Connect(function()
						keyBtn.Text = "[...]"
						keyBtn.BackgroundColor3 = theme.keybindOn
						keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

						local rebindCon = UserInputService.InputBegan:Connect(function(inp, gp2)
							if gp2 then return end
							if inp.UserInputType == Enum.UserInputType.Keyboard then
								local keyName = inp.KeyCode.Name
								if keyName and keyName ~= "Unknown" then
									ChipGui:UpdateKeybind(contextId, bind.label, keyName)
									bind.currentKey = keyName
									keyBtn.Text = "[" .. keyName .. "]"
									keyBtn.BackgroundColor3 = theme.keybindBg
									keyBtn.TextColor3 = theme.textDim
									rebindCon:Disconnect()
								end
							elseif inp.UserInputType == Enum.UserInputType.MouseButton1
								or inp.UserInputType == Enum.UserInputType.MouseButton2 then
								keyBtn.BackgroundColor3 = theme.keybindBg
								keyBtn.TextColor3 = theme.textDim
								keyBtn.Text = "[" .. bind.currentKey .. "]"
								rebindCon:Disconnect()
							end
						end)
					end)

					keybindList:AddFrame(row)
				end
			end
		end

		if not hasAny then
			keybindList:AddLabel("No keybinds registered yet.", 12)
		end
	end

	refreshKeybindList()

	settingsMenu:AddSectionHeader("Floating Touch Buttons")
	settingsMenu:AddLabel("Create per-toggle floating buttons for touch input.")
	settingsMenu:AddToggle("Show Floating Buttons", nil, function(enabled)
		if enabled then
			ChipGui:FlushAndroidButtonQueue()
			ChipGui:SetKeybindBadgesVisible(false)
		else
			ChipGui:RemoveAllFloatingButtons()
			ChipGui:SetKeybindBadgesVisible(true)
		end
	end)

	settingsMenu:AddSectionHeader("About")
	settingsMenu:AddLabel("ChipBreaker v" .. VERSION)
	settingsMenu:AddLabel("A Roblox script hub with clean UI design.")
end

--- Create a toggle button for the GUI itself on Android.
function ChipGui:CreateToggleButton()
	if not state.isAndroid then return end
	local btn = self:CreateAndroidButton(
		"_chipbreaker", "toggle_gui",
		"CB", 10, 50,
		function()
			self:Toggle()
		end,
		function()
			return state.visible
		end
	)
	return btn
end

return ChipGui
