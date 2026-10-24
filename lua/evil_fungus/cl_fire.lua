local BURN_TIME = 3 -- Seconds a strand burns at burn speed 1.
local CHECK = 0.05
local RANGE = 3000
local PER_CHECK = 120
local LIGHT = 0x46756e67
local GLOW = { 255, 140, 60 }
local FLAMES = { "particles/flamelet1", "particles/flamelet2", "particles/flamelet3", "particles/flamelet4", "particles/flamelet5" }

local burning = {}

net.Receive("EvilFungusBurn", function()
	local now = RealTime()
	for _ = 1, net.ReadUInt(12) do burning[net.ReadUInt(24)] = now end
end)

local function Flame(emitter, node)
	local p = emitter:Add(FLAMES[math.random(#FLAMES)], node.pos + node.normal * 2 + VectorRand() * (node.felt and 28 or 3))
	if not p then return false end
	p:SetVelocity(node.normal * math.Rand(15, 35) + VectorRand() * 5)
	p:SetDieTime(math.Rand(0.3, 0.6))
	p:SetStartAlpha(220)
	p:SetEndAlpha(0)
	p:SetStartSize(math.Rand(4, 8))
	p:SetEndSize(1)
	p:SetRoll(math.Rand(0, 360))
	p:SetRollDelta(math.Rand(-2, 2))
	p:SetLighting(false)
	return true
end

local nextCheck = 0

hook.Add("Think", "EvilFungusFire", function()
	local now = RealTime()
	if now < nextCheck or not next(burning) then return end
	nextCheck = now + CHECK
	local speed = EvilFungus.Setting("burn_speed")
	if speed <= 0 or EvilFungus.Setting("killable") <= 0 then
		burning = {}
		return
	end
	local life = BURN_TIME / speed
	local nodes = EvilFungus.Client and EvilFungus.Client.nodes or {}
	local eye = EvilFungus.View and EvilFungus.View.origin or EyePos()
	local r2 = RANGE * RANGE
	local emitter, made, nearest, nearestD2 = nil, 0, nil, math.huge
	for nid, at in pairs(burning) do
		local node = nodes[nid]
		if not node or now - at > life + 1 then
			burning[nid] = nil
		else
			local d2 = node.pos:DistToSqr(eye)
			if d2 < r2 then
				if d2 < nearestD2 then nearest, nearestD2 = node, d2 end
				if made < PER_CHECK then
					emitter = emitter or ParticleEmitter(node.pos)
					if emitter and Flame(emitter, node) then made = made + 1 end
				end
			end
		end
	end
	if emitter then emitter:Finish() end
	if nearest then
		local light = DynamicLight(LIGHT)
		if light then
			light.pos = nearest.pos + nearest.normal * 12
			light.r, light.g, light.b = GLOW[1], GLOW[2], GLOW[3]
			light.brightness = 2
			light.size = 192
			light.decay = 1000
			light.dietime = CurTime() + 0.2
		end
	end
end)
