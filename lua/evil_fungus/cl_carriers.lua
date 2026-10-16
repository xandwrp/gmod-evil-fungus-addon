-- A crawler that's been through the mat sheds a little spore dust as it goes, more the more it's carrying.
local CRAWLER = "evil_crawler"
local SMOKE = "particle/particle_smokegrenade"
local COLOR = { 225, 215, 185 }
local CHECK = 0.1
local SHED = 3
local RANGE = 3000
local SPREAD = 16
local CARRIED = "EvilFungusSpores"

local nextCheck = 0
hook.Add("Think", "EvilFungusCarriers", function()
	local now = CurTime()
	if now < nextCheck then return end
	nextCheck = now + CHECK
	local eye = EyePos()
	for _, c in ipairs(ents.FindByClass(CRAWLER)) do
		local carried = c:GetNW2Int(CARRIED, 0)
		if carried > 0 and not c:IsDormant() and c:GetPos():DistToSqr(eye) < RANGE * RANGE
			and math.random() < CHECK * SHED * carried then
			local pos = c:GetPos() + VectorRand() * SPREAD
			local emitter = ParticleEmitter(pos)
			if emitter then
				local p = emitter:Add(SMOKE, pos)
				if p then
					p:SetVelocity(VectorRand() * 8)
					p:SetDieTime(math.Rand(1.5, 3))
					p:SetStartAlpha(90)
					p:SetEndAlpha(0)
					p:SetStartSize(math.Rand(2, 4))
					p:SetEndSize(math.Rand(6, 10))
					p:SetColor(COLOR[1], COLOR[2], COLOR[3])
					p:SetAirResistance(60)
					p:SetGravity(Vector(0, 0, -8))
					p:SetRoll(math.Rand(0, 360))
				end
				emitter:Finish()
			end
		end
	end
end)
