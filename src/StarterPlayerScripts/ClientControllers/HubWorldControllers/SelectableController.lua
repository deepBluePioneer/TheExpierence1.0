local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SelectableController = Knit.CreateController { Name = "SelectableController" }

local function init()
      -- Set up the cursor images and item name frame
      self:SetupCursorAndItemName()

      -- Start raycasting in the update loop
      RunService.RenderStepped:Connect(function()
          self:Update()
      end)
  
      -- Variable to store the current highlighted object
      self.currentHighlighted = nil
      self.highlightInstance = nil
end

function SelectableController:KnitStart()
  
end

function SelectableController:SetupCursorAndItemName()
    local player = Players.LocalPlayer
    if not player then
        warn("LocalPlayer not found.")
        return
    end

    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then
        warn("PlayerGui not found.")
        return
    end

    -- Cursor setup
    local screenGui = playerGui:FindFirstChild("ScreenGui") -- Replace "ScreenGui" with the actual name
    if not screenGui then
        warn("ScreenGui not found.")
        return
    end

    local cursorFrame = screenGui:FindFirstChild("cursorFrame")
    if not cursorFrame then
        warn("cursorFrame not found.")
        return
    end

    self.cursorInner = cursorFrame:FindFirstChild("cursor_inner")
    self.cursorOuter = cursorFrame:FindFirstChild("cursor_outer")

    if not self.cursorInner or not self.cursorOuter then
        warn("Cursor images (cursor_inner or cursor_outer) not found.")
    end

    -- Ensure the inner cursor is always visible initially
    if self.cursorInner then
        self.cursorInner.Visible = true
    end
    -- Ensure the outer cursor is hidden initially
    if self.cursorOuter then
        self.cursorOuter.Visible = false
    end

    -- Item name frame setup
    local itemNameFrame = screenGui:FindFirstChild("ItemNameSelectionFrame")
    if not itemNameFrame then
        warn("ItemNameSelectionFrame not found.")
        return
    end

    self.itemNameLabel = itemNameFrame:FindFirstChild("txt_itemName")
    if not self.itemNameLabel then
        warn("txt_itemName not found in ItemNameSelectionFrame.")
        return
    end

    -- Ensure item name label is initially empty
    self.itemNameLabel.Text = ""
end

function SelectableController:Update()
    local player = Players.LocalPlayer
    if not player then return end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    -- Perform raycasting
    local hitInstance, isValid = self:PerformRaycast(camera)

    -- Update highlight and cursor based on result
    if isValid then
        self:UpdateHighlight(hitInstance)
        self:UpdateItemName(hitInstance)
    else
        self:UpdateHighlight(nil)
        self:UpdateItemName(nil)
    end

    self:UpdateCursorAppearance(isValid)
end

function SelectableController:PerformRaycast(camera)
    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)

    -- Create the ray from the center of the screen
    local unitRay = camera:ViewportPointToRay(screenCenter.X, screenCenter.Y)
    local rayOrigin = unitRay.Origin
    local rayDirection = unitRay.Direction * 1000 -- Extend 1000 studs

    -- Prepare raycast parameters
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {Players.LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

    -- Find all objects tagged as "selectable"
    for _, instance in pairs(CollectionService:GetTagged("selectable")) do
        if instance:IsA("BasePart") then
            local partPosition = instance.Position
            local directionToPart = (partPosition - rayOrigin).Unit

            -- Calculate the dot product
            local dot = directionToPart:Dot(unitRay.Direction)
            local angleThreshold = 0.95 -- Adjust for precision
            if dot >= angleThreshold then
                -- Perform a final raycast to confirm visibility
                local raycastResult = Workspace:Raycast(rayOrigin, directionToPart * 10, raycastParams)
                if raycastResult and raycastResult.Instance == instance then
                    return instance, true
                end
            end
        end
    end

    return nil, false
end

function SelectableController:UpdateHighlight(hitInstance)
    if not hitInstance then
        if self.highlightInstance then
            self.highlightInstance:Destroy()
            self.highlightInstance = nil
            self.currentHighlighted = nil
        end
        return
    end

    local rootModel = hitInstance:FindFirstAncestorOfClass("Model")
    if rootModel and rootModel ~= self.currentHighlighted then
        if self.highlightInstance then
            self.highlightInstance:Destroy()
        end

        local highlight = Instance.new("Highlight")
        highlight.Parent = rootModel
        self.highlightInstance = highlight
        self.highlightInstance.FillColor = Color3.new(1, 1, 1)
        self.highlightInstance.FillTransparency = 1

        self.currentHighlighted = rootModel
    end
end

function SelectableController:UpdateCursorAppearance(isValid)
    if self.cursorOuter then
        self.cursorOuter.Visible = isValid
    end

    if self.cursorInner then
        self.cursorInner.Visible = true -- Always visible
    end
end

function SelectableController:UpdateItemName(hitInstance)
    if not self.itemNameLabel then return end

    if hitInstance then
        local itemName = hitInstance:GetAttribute("ItemName") -- Assumes attribute name is "ItemName"
        if itemName and typeof(itemName) == "string" then
            self.itemNameLabel.Text = itemName
        else
            self.itemNameLabel.Text = ""
        end
    else
        self.itemNameLabel.Text = ""
    end
end

function SelectableController:KnitInit()
    -- Add controller initialization logic here
end

return SelectableController
