-- BloodSplatterParticle Module Script

local BloodSplatterParticle = {}
BloodSplatterParticle.__index = BloodSplatterParticle

-- Constructor
function BloodSplatterParticle.new(parent, position, size, lifetime)
    local self = setmetatable({}, BloodSplatterParticle)
    
    -- Create a new ParticleEmitter
    local particleEmitter = Instance.new("ParticleEmitter")
    particleEmitter.Texture = "rbxassetid://your_texture_id_here" -- Replace with your blood splatter texture ID
    particleEmitter.Size = NumberSequence.new(size or 5)
    particleEmitter.Lifetime = NumberRange.new(lifetime or 1)
    particleEmitter.Rate = 0 -- Initially 0, we will use burst
    particleEmitter:Emit(50) -- Emit 50 particles as a burst

    -- Set the parent and position
    particleEmitter.Parent = parent
    particleEmitter.Position = position

    self.particleEmitter = particleEmitter
    return self
end

-- Method to set size
function BloodSplatterParticle:setSize(size)
    self.pparticleEmitter.Size = NumberSequence.new(size)
end

-- Method to set lifetime
function BloodSplatterParticle:setLifetime(lifetime)
    self.particleEmitter.Lifetime = NumberRange.new(lifetime)
end

-- Method to set position
function BloodSplatterParticle:setPosition(position)
    self.particleEmitter.Position = position
end

-- Method to remove the particle emitter
function BloodSplatterParticle:remove()
    self.particleEmitter:Destroy()
end

return BloodSplatterParticle
