local ChipGui = _G.chipbreaker.ChipGui

local Games = {
	List = {},      -- gameId -> { Name, File }
	Types = {},     -- typeName -> file path
}

--- Register a specific game by ID.
--- @param gameId string - unique game identifier
--- @param name string - display name
--- @param file string - path to load via loadmodule
function Games:Add(gameId, name, file)
	self.List[gameId] = {
		Name = name,
		File = file,
	}
end

--- Register a game type (category) that can be toggled in the Scripts menu.
--- @param typeName string - display name (e.g. "Brainrot", "Generic Tycoon")
--- @param file string - path to the script that handles this type
function Games:AddType(typeName, file)
	self.Types[typeName] = file
end

--- Get all registered game types as a list of { name, file } pairs.
function Games:GetTypes()
	local result = {}
	for name, file in pairs(self.Types) do
		table.insert(result, { name = name, file = file })
	end
	return result
end

--- Filter game types by a search query (case-insensitive).
--- @param query string - search text
--- @return table - filtered list of { name, file }
function Games:FilterTypes(query)
	if not query or query == "" then
		return self:GetTypes()
	end
	local q = query:lower()
	local result = {}
	for name, file in pairs(self.Types) do
		if name:lower():find(q, 1, true) then
			table.insert(result, { name = name, file = file })
		end
	end
	return result
end

--- Create a new game-specific module with its own menu tab.
--- Game-specific scripts (e.g. BladeBall, PetSim) use this
--- to register their toggles, sliders, and buttons.
--- @param gameName string - name of the game (used as menu tab name)
--- @param contextFile string - the source file for keybind context
--- @return table - module control object
function Games:CreateModule(gameName, contextFile)
	local context = contextFile or "games/scripts/" .. gameName .. ".luau"

	ChipGui:SetContext(context)

	local menu = ChipGui:NewMenu(gameName)

	local module = {}

	--- Add a toggle to this game's menu.
	--- @param label string - display text
	--- @param key string|nil - optional default keybind
	--- @param callback function(enabled)
	--- @return table - toggle control object
	function module:AddToggle(label, key, callback)
		if type(key) == "function" then
			callback = key
			key = nil
		end
		local btnId = label:gsub("%s+", "_")
		local toggle = menu:AddToggle(label, key, callback, context, btnId)

		local btnLabel = label:sub(1, 4)
		ChipGui:QueueAndroidButton(
			context, btnId, btnLabel,
			50 + (#Games.Types * 70), 100,
			function()
				toggle:Toggle()
			end,
			function()
				return toggle:GetState()
			end
		)

		return toggle
	end

	--- Add a slider to this game's menu.
	--- @param label string - display text
	--- @param min number
	--- @param max number
	--- @param default number
	--- @param callback function(value)
	--- @return table - slider control object
	function module:AddSlider(label, min, max, default, callback)
		return menu:AddSlider(label, min, max, default, callback)
	end

	--- Add a button to this game's menu.
	--- @param label string - display text
	--- @param keybind string|nil - optional keybind
	--- @param callback function()
	--- @return table - button control object
	function module:AddButton(label, keybind, callback)
		if type(keybind) == "function" then
			callback = keybind
			keybind = nil
		end
		local btnId = label:gsub("%s+", "_")
		local btn = menu:AddButton(label, keybind, callback, context, btnId)

		local btnLabel = label:sub(1, 4)
		ChipGui:QueueAndroidButton(
			context, btnId, btnLabel,
			50 + (#Games.Types * 70), 100,
			function()
				callback()
			end,
			nil
		)

		return btn
	end

	--- Add a label to this game's menu.
	--- @param text string
	--- @param fontSize number|nil
	--- @return table - label control object
	function module:AddLabel(text, fontSize)
		return menu:AddLabel(text, fontSize)
	end

	--- Add a section header to this game's menu.
	--- @param text string
	--- @return table - section header control object
	function module:AddSectionHeader(text)
		return menu:AddSectionHeader(text)
	end

	--- Get the underlying menu name.
	function module:GetName()
		return gameName
	end

	--- Get the context string for keybinds.
	function module:GetContext()
		return context
	end

	return module
end

return Games
