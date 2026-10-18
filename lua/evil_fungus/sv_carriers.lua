EvilFungus = EvilFungus or {}
EvilFungus.Carriers = EvilFungus.Carriers or {}

-- Evil Crawlers don't bleed, so it has no use for them. They walk out of it covered in spores anyway.
local CRAWLER = "evil_crawler"
local CHECK = 0.2
local PICKUP_RADIUS = 48
local PICKUP_RATE = 0.6
local CARRY_MAX = 3
local CARRY_SHARE = 0.2
local CARRY_MIN = 10
local DROP_EVERY = 1500
local DROP_CLEAR = 500
local PAD = Vector(PICKUP_RADIUS, PICKUP_RADIUS, PICKUP_RADIUS)
local WATER = bit.bor(CONTENTS_WATER, CONTENTS_SLIME)
local CARRIED = "EvilFungusSpores"
local INFECT_TIME = 60
local INFECT_SHED = { 10, 18 }
local INFECT_MASS = 25
local INFECT_CLEAR = 300
local INFECT_DUST = 3

local ai_disabled = GetConVar("ai_disabled")
local Carriers = EvilFungus.Carriers

local function Infected(c)
	return (c.EvilFungusInfected or 0) > CurTime()
end

local function Dust(c)
	local n = c.EvilFungusSpores and #c.EvilFungusSpores or 0
	if Infected(c) then n = math.max(n, INFECT_DUST) end
	if c:GetNW2Int(CARRIED, 0) ~= n then c:SetNW2Int(CARRIED, n) end
end

local function Load(c, load)
	c.EvilFungusSpores = load
	Dust(c)
end

-- The world under its body, if it's on any.
local function Ground(c)
	local up, pos = c.BodyUp or vector_up, c:GetPos()
	local tr = util.TraceLine({ start = pos, endpos = pos - up * (c.BodyHeight or 64) * 2, mask = MASK_SOLID_BRUSHONLY })
	if not tr.HitWorld or tr.StartSolid or tr.HitSky or tr.HitNoDraw then return end
	return tr.HitPos, tr.HitNormal
end

local function Pickup(c, foot)
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and not colony.Absorbed and colony.Mat
		if mat and mat.mins and foot:WithinAABox(mat.mins - PAD, mat.maxs + PAD) and mat:Nearest(foot, PICKUP_RADIUS) then
			local mass = colony.Body * CARRY_SHARE
			if mass < CARRY_MIN then return end
			colony:Spend(mass)
			local load = c.EvilFungusSpores or {}
			load[#load + 1] = { mass = mass, mind = colony.Mind, creator = colony:GetCreator() }
			Load(c, load)
			return
		end
	end
end

local function Plant(from, pos, normal, spore, clear)
	if not EvilFungus.Room() or EvilFungus.Taken(pos, clear) then return false end
	if bit.band(util.PointContents(pos + normal * 2), WATER) ~= 0 then return false end
	if not EvilFungus.Plant(pos, normal, spore.mass, spore.mind, spore.creator) then return false end
	local fx = EffectData()
	fx:SetStart(from)
	fx:SetOrigin(pos)
	fx:SetNormal(normal)
	util.Effect("evil_fungus_spore", fx, true, true)
	return true
end

local function Carry(c, dt)
	local last, pos = c.EvilFungusLast, c:GetPos()
	c.EvilFungusLast = pos
	if c:GetAct() == EvilCrawler.ACT_DEAD or c.Falling or c:GetSwimming() then return end

	local rate = EvilFungus.Setting("carried")
	local load = c.EvilFungusSpores
	if rate <= 0 then
		c.EvilFungusInfected = nil
		if load then Load(c, nil) else Dust(c) end
		return
	end

	local foot, normal = Ground(c)
	local now = CurTime()
	if Infected(c) and foot and now >= (c.EvilFungusShedAt or 0) then
		c.EvilFungusShedAt = now + math.Rand(INFECT_SHED[1], INFECT_SHED[2]) / rate
		local by = c.EvilFungusInfectedBy or {}
		Plant(pos, foot, normal, { mass = INFECT_MASS, mind = by.mind, creator = by.creator }, INFECT_CLEAR)
	end
	Dust(c)
	if (not load or #load < CARRY_MAX) and math.random() < dt * EvilFungus.TimeScale() * rate * PICKUP_RATE then
		Pickup(c, foot or pos - (c.BodyUp or vector_up) * (c.BodyHeight or 64))
		load = c.EvilFungusSpores
	end

	-- Every so far it goes, one shakes loose wherever it happens to be.
	if not load or not foot or not last then return end
	if math.random() >= 1 - math.exp(-pos:Distance(last) * rate / DROP_EVERY) then return end
	local i = math.random(#load)
	if not Plant(pos, foot, normal, load[i], DROP_CLEAR) then return end
	table.remove(load, i)
	Load(c, #load > 0 and load or nil)
end

function EvilFungus.Infect(c, colony)
	if not IsValid(c) or c:GetClass() ~= CRAWLER then return end
	local now = CurTime()
	if not Infected(c) then c.EvilFungusShedAt = now + math.Rand(INFECT_SHED[1], INFECT_SHED[2]) * 0.5 end
	c.EvilFungusInfected = now + INFECT_TIME
	c.EvilFungusInfectedBy = { mind = IsValid(colony) and colony.Mind or nil, creator = IsValid(colony) and colony:GetCreator() or nil }
	Carriers[c] = true
	Dust(c)
end

local nextCheck = 0
hook.Add("Think", "EvilFungusCarriers", function()
	local now = CurTime()
	if now < nextCheck or not EvilCrawler or not next(Carriers) then return end
	local dt = CHECK + now - nextCheck
	nextCheck = now + CHECK
	if ai_disabled and ai_disabled:GetBool() then return end
	for c in pairs(Carriers) do
		if IsValid(c) then Carry(c, math.min(dt, CHECK * 3)) end
	end
end)

local function Track(ent)
	if ent:GetClass() == CRAWLER then Carriers[ent] = true end
end

hook.Add("OnEntityCreated", "EvilFungusCarriers", function(ent)
	timer.Simple(0, function()
		if IsValid(ent) then Track(ent) end
	end)
end)

-- Whatever it was still carrying when it died comes up where it rotted.
hook.Add("EntityRemoved", "EvilFungusCarriers", function(ent)
	if not Carriers[ent] then return end
	Carriers[ent] = nil
	local load = ent.EvilFungusSpores
	if not load or not EvilCrawler or ent:GetAct() ~= EvilCrawler.ACT_DEAD
		or CurTime() - ent:GetActStart() < EvilCrawler.CORPSE_TIME - 1 then
		return
	end
	local pos, normal = Ground(ent)
	if not pos then return end
	local spore = { mass = 0, mind = load[1].mind, creator = load[1].creator }
	for _, s in ipairs(load) do spore.mass = spore.mass + s.mass end
	local from = ent:GetPos()
	timer.Simple(0, function() Plant(from, pos, normal, spore) end)
end)

for _, ent in ipairs(ents.GetAll()) do Track(ent) end
