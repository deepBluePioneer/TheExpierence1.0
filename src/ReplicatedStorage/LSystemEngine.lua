local LSystemEngine = {}

local function expand(axiom, rules, iterations)
	local s = axiom
	for _ = 1, iterations do
		local parts = {}
		for i = 1, #s do
			local c = s:sub(i, i)
			local rep = rules[c]
			if rep then
				table.insert(parts, rep)
			else
				table.insert(parts, c)
			end
		end
		s = table.concat(parts)
	end
	return s
end

local function degToRad(d)
	return math.rad(d)
end

function LSystemEngine.generate(ruleDef, worldCFrame, scale, rngSeed)
	local axiom = ruleDef.axiom or "F"
	local rules = ruleDef.rules or { F = "F" }
	local iterations = math.clamp(ruleDef.iterations or 2, 1, 5)
	local angleDeg = ruleDef.angle or 25
	local segLen = (ruleDef.segmentLength or 3) * scale
	local segThick = (ruleDef.segmentThickness or 0.8) * scale
	local lenDecay = ruleDef.lengthDecay or 0.75
	local thickDecay = ruleDef.thicknessDecay or 0.7
	local mat = ruleDef.material or Enum.Material.SmoothPlastic
	local col = ruleDef.color or Color3.new(0.5, 0.5, 0.5)
	local leafOn = ruleDef.leafEnabled
	local leafSize = (ruleDef.leafSize or 2) * scale
	local leafCol = ruleDef.leafColor or col

	local rng = Random.new(rngSeed)

	local model = Instance.new("Model")
	model.Name = ruleDef.name or "LSystemPlant"

	local stack = {}
	local cf = worldCFrame
	local curLen = segLen
	local curThick = segThick
	local depth = 0

	local s = expand(axiom, rules, iterations)
	local angle = degToRad(angleDeg)

	for i = 1, #s do
		local cmd = s:sub(i, i)
		if cmd == "F" or cmd == "G" then
			local jitter = 0.92 + rng:NextNumber() * 0.16
			local L = curLen * jitter
			local t = math.max(0.15, curThick * (0.9 + rng:NextNumber() * 0.2))
			local p = Instance.new("Part")
			p.Name = "Seg"
			p.Anchored = true
			p.CanCollide = false
			p.Material = mat
			p.Color = col
			p.Size = Vector3.new(t, L, t)
			p.CFrame = cf * CFrame.new(0, L * 0.5, 0)
			p.CastShadow = true
			p.Parent = model
			cf = cf * CFrame.new(0, L, 0)
			curLen = curLen * lenDecay
			curThick = curThick * thickDecay
		elseif cmd == "f" then
			cf = cf * CFrame.new(0, curLen * 0.5, 0)
		elseif cmd == "+" then
			cf = cf * CFrame.Angles(0, angle * (0.85 + rng:NextNumber() * 0.3), 0)
		elseif cmd == "-" then
			cf = cf * CFrame.Angles(0, -angle * (0.85 + rng:NextNumber() * 0.3), 0)
		elseif cmd == "^" then
			cf = cf * CFrame.Angles(-angle * (0.85 + rng:NextNumber() * 0.3), 0, 0)
		elseif cmd == "&" then
			cf = cf * CFrame.Angles(angle * (0.85 + rng:NextNumber() * 0.3), 0, 0)
		elseif cmd == "\\" then
			cf = cf * CFrame.Angles(0, 0, angle * 0.5)
		elseif cmd == "/" then
			cf = cf * CFrame.Angles(0, 0, -angle * 0.5)
		elseif cmd == "[" then
			table.insert(stack, { cf = cf, len = curLen, thick = curThick, d = depth })
			depth = depth + 1
		elseif cmd == "]" then
			local st = table.remove(stack)
			if st then
				cf = st.cf
				curLen = st.len
				curThick = st.thick
				depth = st.d
			end
		elseif cmd == "L" and leafOn then
			local lf = Instance.new("Part")
			lf.Name = "Leaf"
			lf.Shape = Enum.PartType.Ball
			lf.Anchored = true
			lf.CanCollide = false
			lf.Material = Enum.Material.Grass
			lf.Color = leafCol
			local ls = leafSize * (0.7 + rng:NextNumber() * 0.5)
			lf.Size = Vector3.new(ls, ls, ls)
			lf.CFrame = cf * CFrame.new(0, curLen * 0.2, 0)
			lf.Parent = model
		end
	end

	return model
end

return LSystemEngine
