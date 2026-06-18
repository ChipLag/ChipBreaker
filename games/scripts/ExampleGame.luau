local ChipGui = _G.chipbreaker.ChipGui
local Games = _G.chipbreaker.Games

local module = Games:CreateModule("Example Game", "games/scripts/ExampleGame.luau")

module:AddSectionHeader("Auto Farm")
module:AddToggle("Auto Collect", "C", function(enabled)
end, true)

module:AddToggle("Auto Sell", "S", function(enabled)
end, true)

module:AddSectionHeader("Combat")
module:AddToggle("Auto Attack", "A", function(enabled)
end, true)

module:AddToggle("Auto Dodge", "D", function(enabled)
end, true)

module:AddSectionHeader("Settings")
module:AddSlider("Reach Range", 10, 100, 50, function(value)
end)

module:AddLabel("")
module:AddButton("Teleport to Farm", function()
end, true)

return module
