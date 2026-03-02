local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local NUM_BARS = 6
local BAR_IN_TIME = 0.25
local BAR_OUT_TIME = 0.25
local STAGGER_DELAY = 0.04
local WIPE_COLOR = Color3.fromRGB(10, 10, 20)
local BAR_COLORS = {
	Color3.fromRGB(10, 10, 20),
	Color3.fromRGB(18, 18, 35),
	Color3.fromRGB(10, 10, 20),
	Color3.fromRGB(22, 22, 42),
	Color3.fromRGB(10, 10, 20),
	Color3.fromRGB(15, 15, 30),
}
local DISPLAY_ORDER = 999

local LakelandWipeTransition = {}

function LakelandWipeTransition.new(playerGui)
	local trove = Trove.new()
	local wiping = false
	local destroyed = false

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LakelandWipeTransition"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Parent = playerGui
	trove:Add(screenGui)

	local bars = {}
	local barHeight = 1 / NUM_BARS

	for i = 1, NUM_BARS do
		local bar = Instance.new("Frame")
		bar.Name = "WipeBar_" .. i
		bar.AnchorPoint = Vector2.new(0, 0)
		bar.Size = UDim2.fromScale(1, barHeight + 0.002)
		bar.Position = UDim2.fromScale(-1, (i - 1) * barHeight)
		bar.BackgroundColor3 = BAR_COLORS[i] or WIPE_COLOR
		bar.BackgroundTransparency = 0
		bar.BorderSizePixel = 0
		bar.ZIndex = 1
		bar.Parent = screenGui
		bars[i] = bar
	end

	local function resetBars()
		for i = 1, NUM_BARS do
			bars[i].Position = UDim2.fromScale(-1, (i - 1) * barHeight)
		end
	end

	local function wipe(onMidpoint)
		if wiping or destroyed then
			if onMidpoint then
				onMidpoint()
			end
			return
		end
		wiping = true
		resetBars()

		local lastInTween = nil
		local ok1 = pcall(function()
			for i = 1, NUM_BARS do
				local bar = bars[i]
				local yPos = (i - 1) * barHeight
				bar.Position = UDim2.fromScale(-1, yPos)

				local inInfo = TweenInfo.new(BAR_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local tw = TweenService:Create(bar, inInfo, {
					Position = UDim2.fromScale(0, yPos),
				})
				tw:Play()
				lastInTween = tw

				if i < NUM_BARS then
					task.wait(STAGGER_DELAY)
				end
			end

			if lastInTween then
				lastInTween.Completed:Wait()
			end
		end)

		if onMidpoint then
			onMidpoint()
		end

		if not ok1 or destroyed then
			wiping = false
			return
		end

		task.wait(0.05)

		local lastOutTween = nil
		pcall(function()
			for i = 1, NUM_BARS do
				local bar = bars[i]
				local yPos = (i - 1) * barHeight

				local outInfo = TweenInfo.new(BAR_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local tw = TweenService:Create(bar, outInfo, {
					Position = UDim2.fromScale(1, yPos),
				})
				tw:Play()
				lastOutTween = tw

				if i < NUM_BARS then
					task.wait(STAGGER_DELAY)
				end
			end

			if lastOutTween then
				lastOutTween.Completed:Wait()
			end
		end)

		if not destroyed then
			resetBars()
		end
		wiping = false
	end

	local function isWiping()
		return wiping
	end

	local function destroy()
		destroyed = true
		trove:Destroy()
	end

	return {
		wipe = wipe,
		isWiping = isWiping,
		destroy = destroy,
	}
end

return LakelandWipeTransition
