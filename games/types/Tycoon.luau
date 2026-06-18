local ChipGui = _G.chipbreaker.ChipGui
local Games = _G.chipbreaker.Games

local module = Games:CreateModule("Tycoon Helper", "games/types/T-Tycoon.luau")
local active = false

module:AddSectionHeader("Purchasing")
module:AddToggle("Auto Buy Dropper", "B", function(enabled)
	if not active then return end
end)

module:AddToggle("Auto Buy Generator", "G", function(enabled)
	if not active then return end
end)

module:AddSectionHeader("Collection")
module:AddToggle("Auto Collect Cash", "C", function(enabled)
	if not active then return end
end)

module:AddToggle("Auto Rebirth", "R", function(enabled)
	if not active then return end
end)

module:AddSectionHeader("Misc")
module:AddSlider("Walk Speed", 16, 200, 16, function(value)
	if not active then return end
end)

local tycoonModule = {}

function tycoonModule:Initialize()
	active = true
	return self
end

function tycoonModule:Deinitialize()
	active = false
end

return tycoonModule
