local GITHUB_BASE = "https://raw.githubusercontent.com/ChipLag/ChipBreaker/main/"

--- Load a module from the GitHub repository.
--- Each module is loaded via loadstring and executed in a new closure,
--- so state is shared through the _G.chipbreaker table.
local function loadmodule(path)
	local url = GITHUB_BASE .. path
	local source = game:HttpGet(url)
	return loadstring(source)()
end

_G.chipbreaker = _G.chipbreaker or {}
_G.chipbreaker.loadmodule = loadmodule

local ChipGui = loadmodule("chiplib/gui.luau")
_G.chipbreaker.ChipGui = ChipGui

ChipGui:ShowWindow()

loadmodule("games/Global.luau")

local Games = loadmodule("games/Games.luau")
_G.chipbreaker.Games = Games

ChipGui:SetContext("games/scripts")

Games:AddType("Tycoon", "games/types/Tycoon.luau")
Games:AddType("Brainrot", "games/types/Brainrot.luau")
Games:AddType("Simulator", "games/types/Simulator.luau")
Games:AddType("Fighting", "games/types/Fighting.luau")
Games:AddType("Horror", "games/types/Horror.luau")

local loadedTypes = {}

local scriptsMenu = ChipGui:NewMenu("Scripts")

scriptsMenu:AddLabel("Enable scripts for the detected game type.")

scriptsMenu:AddInput("Filter game types...", function(query)
	rebuildTypeList(query)
end)

local typeList = scriptsMenu:AddList()

typeList:AddLabel("")
typeList:AddLabel("Check a type to load it. Uncheck to unload.")

--- Rebuild the game type checkbox list based on a search filter.
--- @param query string - search text (empty = show all)
local function rebuildTypeList(query)
	typeList:Clear()

	local filtered = Games:FilterTypes(query)

	for _, typeInfo in ipairs(filtered) do
		local typeName = typeInfo.name
		local typeFile = typeInfo.file
		local isChecked = loadedTypes[typeName] ~= nil

		local checkbox = typeList:AddCheckbox(typeName, function(enabled)
			if enabled then
				if loadedTypes[typeName] == nil then
					local success, script = pcall(loadmodule, typeFile)
					if success then
						if script and script.Initialize then
							loadedTypes[typeName] = script:Initialize()
						else
							loadedTypes[typeName] = script
						end
					else
						warn("ChipBreaker: Failed to load type '" .. typeName .. "': " .. tostring(script))
						loadedTypes[typeName] = false
					end
				end
			else
				if loadedTypes[typeName] then
					local script = loadedTypes[typeName]
					if type(script) == "table" and script.Deinitialize then
						script:Deinitialize()
					end
					loadedTypes[typeName] = nil
				end
			end
		end)

		if isChecked then
			checkbox:SetState(true)
		end
	end
end

rebuildTypeList("")

local exampleModule = loadmodule("games/scripts/ExampleGame.luau")
