local SMOKE = "particle/particle_smokegrenade"
local PUFF = 24
local TRAIL = 16
local LANDING = 18
local COLOR = { 225, 215, 185 }

local function Speck(emitter, pos, vel, size, life)
	local p = emitter:Add(SMOKE, pos)
	if not p then return end
	p:SetVelocity(vel)
	p:SetDieTime(life)
	p:SetStartAlpha(110)
	p:SetEndAlpha(0)
	p:SetStartSize(size)
	p:SetEndSize(size * 3)
	p:SetColor(COLOR[1], COLOR[2], COLOR[3])
	p:SetAirResistance(60)
	p:SetGravity(Vector(0, 0, -8))
	p:SetRoll(math.Rand(0, 360))
end

function EFFECT:Init(data)
	local from, to, up = data:GetStart(), data:GetOrigin(), data:GetNormal()
	local emitter = ParticleEmitter(from)
	if not emitter then return end
	for _ = 1, PUFF do Speck(emitter, from, VectorRand() * 60 + Vector(0, 0, 40), math.Rand(3, 7), math.Rand(1.5, 3)) end
	for i = 1, TRAIL do Speck(emitter, LerpVector(i / TRAIL, from, to), VectorRand() * 10, math.Rand(2, 4), math.Rand(1, 2.5)) end
	for _ = 1, LANDING do Speck(emitter, to + up * 4, (VectorRand() + up) * 40, math.Rand(3, 6), math.Rand(1.5, 3)) end
	emitter:Finish()
end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
