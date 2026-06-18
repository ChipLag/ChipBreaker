local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChipGui = _G.chipbreaker.ChipGui

ChipGui:SetContext("games/Global.luau")

local globalMenu = ChipGui:NewMenu("Globals")

local currentSpeed = 16
local currentJump = 50
local noclipEnabled = false
local noclipConnection = nil

--- Apply the given walkspeed to the local player's character.
local function applyWalkspeed(speed)
	local player = Players.LocalPlayer
	if not player then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

--- Apply the given jump height to the local player's character.
local function applyJumpHeight(height)
	local player = Players.LocalPlayer
	if not player then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.JumpHeight = height
	end
end

--- Enable or disable noclip by toggling CanCollide on character parts
--- every frame via RunService.Stepped.
local function setNoclip(enabled)
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
	if enabled then
		noclipConnection = RunService.Stepped:Connect(function()
			local player = Players.LocalPlayer
			if not player then return end
			local character = player.Character
			if not character then return end
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
		end)
	end
end

--- Re-apply walkspeed and jump height after the character respawns.
local player = Players.LocalPlayer
if player then
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applyWalkspeed(currentSpeed)
		applyJumpHeight(currentJump)
	end)
end

globalMenu:AddSectionHeader("Movement")

globalMenu:AddSlider("Walkspeed", 16, 500, 16, function(value)
	currentSpeed = value
	applyWalkspeed(value)
end)

globalMenu:AddSlider("Jump Height", 1, 500, 50, function(value)
	currentJump = value
	applyJumpHeight(value)
end)

globalMenu:AddLabel("")

globalMenu:AddSectionHeader("Utilities")

globalMenu:AddToggle("Noclip", "N", function(enabled)
	noclipEnabled = enabled
	setNoclip(enabled)
end)

globalMenu:AddToggle("Toggle UI", "RightControl", function(enabled)
	ChipGui:Toggle()
end)
