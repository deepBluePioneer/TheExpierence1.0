--[[ 
	modified by SaltyPotter to include orientation	
	borrowed math and ideas from: @fractality, @Validark, @Quenty, @XAXA, @EgoMoose
	
	use cases:
		Camera following anything physics-based (without jitter issues):
		
			---- I'm using dictionaries to send CFrame information ----
			
			local position={RightVector=startCF.RightVector, UpVector=startCF.UpVector, Position=startCF.Position}
			local velocity={RightVector=Vector3.new(), UpVector=Vector3.new(), Position=Vector3.new()}
			local goal={RightVector=goalCF.RightVector, UpVector=goalCF.UpVector, Position=goalCF.Position}
			local spring=springModule.new(position, velocity, goal)
			
			---- you can adjust the frequency and dampness to your liking, i found a 2:1 profile is a nice smooth effect ----
			
			spring.frequency=2
			spring.dampener=1
			
			runservice.Stepped:Connect(function(t, dt)
				---- update the goal every step ----
				spring.goal={RightVector=goalCF.RightVector, UpVector=goalCF.UpVector, Position=goalCF.Position}
				---- call :update(), it returns a CFrame ----
				camera.CFrame=spring:update(dt)
			end)
			
		other:
			same as above, but you can use .RenderStepped since there's no physics involved
]]

local spring={}
spring.__index=spring

local tau = math.pi * 2
local exp = math.exp
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt

local EPSILON = 1e-4

function spring.new(position:{},velocity:{},goal:{})
	setmetatable({},spring)
	spring.position=position
	spring.velocity=velocity
	spring.goal=goal
	spring.frequency=10
	spring.dampener=1
	return spring
end

function spring:adjust(key:string,dt:number)
	local dampingRatio = self.dampener
	local angularFrequency = self.frequency * tau
	local goal = self.goal[key]
	local p0 = self.position[key]
	local v0 = self.velocity[key]

	local offset = p0 - goal
	local decay = exp(-dampingRatio * angularFrequency * dt)
	local position

	if dampingRatio == 1 then -- Critically damped
		position = (offset * (1 + angularFrequency * dt) + v0 * dt) * decay + goal
		self.velocity[key] = (v0 * (1 - angularFrequency * dt) - offset * (angularFrequency * angularFrequency * dt)) * decay
	elseif dampingRatio < 1 then -- Underdamped
		local e = 1 - dampingRatio * dampingRatio
		local c = sqrt(e)
		local y = angularFrequency * c
		local i = cos(y * dt)
		local j = sin(y * dt)

		-- Damping ratios approaching 1 can cause division by small numbers.
		-- To fix that, group terms around z=j/c and find an approximation for z.
		-- Start with the definition of z:
		--    z = sin(dt*angularFrequency*c)/c
		-- Substitute a=dt*angularFrequency:
		--    z = sin(a*c)/c
		-- Take the Maclaurin expansion of z with respect to c:
		--    z = a - (a^3*c^2)/6 + (a^5*c^4)/120 + O(c^6)
		--    z ≈ a - (a^3*c^2)/6 + (a^5*c^4)/120
		-- Rewrite in Horner form:
		--    z ≈ a + ((a*a)*(c*c)*(c*c)/20 - c*c)*(a*a*a)/6

		local z
		if c > EPSILON then
			z = j / c
		else
			local a = dt * angularFrequency
			local a_2 = a * a
			z = a * (((e*e * a_2 - 20*e) / 120) * a_2 + 1)
		end

		-- Frequencies approaching 0 present a similar problem.
		-- We want an approximation for y as angularFrequency approaches 0, where:
		--    y = sin(dt*angularFrequency*c)/(angularFrequency*c)
		-- Substitute b=dt*c:
		--    y = sin(b*c)/b
		-- Now reapply the process from z.

		if y > EPSILON then
			y = j / y
		else
			local b = y * y
			local dd = dt * dt
			y = dt * (dd * (b*b*dd / 20 - b) / 6 + 1)
		end

		local ze = z * dampingRatio
		position = (offset * (i + ze) + v0 * y) * decay + goal
		self.velocity[key] = (v0 * (i - ze) - offset * (z * angularFrequency)) * decay
	else -- Overdamped
		local x = -angularFrequency * dampingRatio
		local y = angularFrequency * sqrt(dampingRatio * dampingRatio - 1)
		local r1 = x + y
		local r2 = x - y

		local co2 = (v0 - offset * r1) / (2 * y)
		local co1 = offset - co2

		local e1 = co1 * exp(r1 * dt)
		local e2 = co2 * exp(r2 * dt)

		position = e1 + e2 + goal
		self.velocity[key] = e1 * r1 + e2 * r2
	end

	self.position[key] = position
end

function spring:update(dt:number)
	local t={}
	for key,_ in self.goal do 
		spring:adjust(key,dt)
		t[key]=self.position[key]
	end
	return CFrame.fromMatrix(t.Position,t.RightVector,t.UpVector):Orthonormalize()
end

return spring