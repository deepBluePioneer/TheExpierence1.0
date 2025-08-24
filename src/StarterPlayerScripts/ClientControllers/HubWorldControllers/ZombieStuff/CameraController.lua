-- ClientControllers/CameraController.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local CameraController = Knit.CreateController {
    Name = "CameraController"
}

-- ====== CONFIG ======
local DEFAULT_HEIGHT = 35
local MIN_HEIGHT = 10
local MAX_HEIGHT = 200
local LERP_ALPHA = 0.25

-- ====== STATE ======
CameraController._enabled = false
CameraController._height = DEFAULT_HEIGHT
CameraController._steppedCn = nil
CameraController._charCnns = {}
CameraController._rootPart = nil

-- ====== INTERNALS ======
local function getRootPart(character: Model?)
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end

    local hum = character:FindFirstChildOfClass("Humanoid")
    return hum and hum.RootPart or nil
end

local function attachToCharacter(self)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    self._rootPart = getRootPart(character)

    for _, conn in pairs(self._charCnns) do conn:Disconnect() end
    self._charCnns = {
        LocalPlayer.CharacterAdded:Connect(function(char)
            self._rootPart = nil
            task.defer(function()
                self._rootPart = getRootPart(char)
            end)
        end),
        LocalPlayer.CharacterRemoving:Connect(function()
            self._rootPart = nil
        end),
    }
end

local function stepUpdate(self, _, dt)
    if not self._enabled then return end
    if not self._rootPart or not self._rootPart:IsDescendantOf(workspace) then
        self._rootPart = getRootPart(LocalPlayer.Character)
        if not self._rootPart then return end
    end

    local rootPos = self._rootPart.Position
    local desiredPos = rootPos + Vector3.new(0, self._height, 0)
    local desiredCFrame = CFrame.new(desiredPos, rootPos)

    local alpha = 1 - (1 - LERP_ALPHA) ^ (math.max(dt, 1/240) * 240)
    Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, alpha)
end

-- ====== PUBLIC API ======
function CameraController:SetEnabled(enabled: boolean)
    if self._enabled == enabled then return end
    self._enabled = enabled

    if enabled then
        Camera.CameraType = Enum.CameraType.Scriptable
        attachToCharacter(self)

        if not self._steppedCn then
            self._steppedCn = RunService.Stepped:Connect(function(t, dt)
                stepUpdate(self, t, dt)
            end)
        end
    else
        if self._steppedCn then
            self._steppedCn:Disconnect()
            self._steppedCn = nil
        end
        Camera.CameraType = Enum.CameraType.Custom
    end
end

function CameraController:SetHeight(height: number)
    self._height = math.clamp(height, MIN_HEIGHT, MAX_HEIGHT)
end

function CameraController:_bindHeightScroll()
    return UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseWheel and self._enabled then
            local delta = input.Position.Z
            self:SetHeight(self._height + delta * -2)
        end
    end)
end

-- ====== KNIT LIFECYCLE ======
function CameraController:KnitInit() end

function CameraController:KnitStart()
   -- self:SetEnabled(true)
   -- self._scrollConn = self:_bindHeightScroll()
end

return CameraController
