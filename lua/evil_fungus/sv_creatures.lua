EvilFungus = EvilFungus or {}
EvilFungus.Creatures = EvilFungus.Creatures or {}
EvilFungus.Foods = EvilFungus.Foods or {}

local PROPS = { prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true, prop_ragdoll = true }
local ORGANIC = { flesh = true, bloodyflesh = true, alienflesh = true, zombieflesh = true, antlion = true, watermelon = true, foliage = true }
local GREENS = {
	"foliage", "plant", "tree", "bush", "shrub", "fern", "flower", "ivy", "cactus", "hedge", "leaf", "leaves", "grass",
	"melon", "watermelon", "banana", "bananna", "orange", "apple", "cabbage", "lettuce", "pumpkin", "carrot", "potato",
	"bread", "meat", "gib", "hgibs", "corpse", "skull",
}

-- Only NPCs, never nextbots. Whether it's food is down to whether it bleeds, checked when it matters.
local function Creature(ent)
	return ent:IsNPC()
end
EvilFungus.Creature = Creature

local MECHANICAL = { "oil", "spark", "mech", "robot", "metal" }

local function Mechanical(name)
	if not isstring(name) then return false end
	name = string.lower(name)
	for _, word in ipairs(MECHANICAL) do
		if string.find(name, word, 1, true) then return true end
	end
	return false
end

local function ZBaseBleeds(ent)
	local decal, particles = ent.CustomBloodDecals, ent.CustomBloodParticles
	if not decal and not particles then return false end
	if Mechanical(decal) then return false end
	for _, name in ipairs(istable(particles) and particles or {}) do
		if Mechanical(name) then return false end
	end
	return true
end

local FLESH = { flesh = true, bloodyflesh = true, alienflesh = true, zombieflesh = true, antlion = true }
local fleshy = {}

local function Fleshy(model)
	if fleshy[model] == nil then
		local info = util.GetModelInfo(model)
		local found = info and FLESH[string.lower(info.SurfacePropName or "")] or false
		if not found and info and isstring(info.KeyValues) then
			for prop in string.gmatch(string.lower(info.KeyValues), '"surfaceprop"%s*"([^"]+)"') do
				if FLESH[prop] then
					found = true
					break
				end
			end
		end
		fleshy[model] = found
	end
	return fleshy[model]
end

function EvilFungus.Bleeds(ent)
	if ent.IsVJBaseSNPC then return isstring(ent.BloodColor) and ent.BloodColor ~= "Oil" end
	if ent.IsZBaseNPC and ent.BloodColor == DONT_BLEED then return ZBaseBleeds(ent) end
	local blood = ent.GetBloodColor and ent:GetBloodColor()
	if blood == DONT_BLEED and ent:IsNPC() then return Fleshy(ent:GetModel() or "") end
	return blood ~= nil and blood >= 0 and blood ~= BLOOD_COLOR_MECH
end

local FOOTING = Vector(0, 0, 12)
local FOOT_LIFT = Vector(0, 0, 4)

function EvilFungus.OnGround(ent)
	if ent:IsOnGround() then return true end
	if not ent:IsNPC() or ent:GetMoveType() == MOVETYPE_FLY then return false end
	local pos = ent:GetPos()
	return util.TraceLine({ start = pos + FOOT_LIFT, endpos = pos - FOOTING, filter = ent, mask = MASK_NPCSOLID }).Hit
end

local SPEED_SAMPLE = 0.1
local SPEED_STALE = 1
local SPEED_MAX = 1000

function EvilFungus.Speed(ent)
	local speed = ent:GetVelocity():Length()
	if not ent:IsNPC() then return speed end
	local now, pos = CurTime(), ent:GetPos()
	local at = ent.EvilFungusMovedAt
	if not at or now - at > SPEED_STALE then
		ent.EvilFungusMoved, ent.EvilFungusLastPos, ent.EvilFungusMovedAt = 0, pos, now
	elseif now - at >= SPEED_SAMPLE then
		ent.EvilFungusMoved = math.min(SPEED_MAX, pos:Distance(ent.EvilFungusLastPos) / (now - at))
		ent.EvilFungusLastPos, ent.EvilFungusMovedAt = pos, now
	end
	return math.max(speed, ent.EvilFungusMoved)
end

function EvilFungus.CrawlerHas(ent)
	if not EvilCrawler then return false end
	if ent.EvilCrawlerVictim or IsValid(ent.EvilCrawlerOwner) then return true end
	if ent:IsPlayer() then return EvilCrawler.Holder and EvilCrawler.Holder(ent) and true or false end
	local ply = EvilCrawler.Faker and EvilCrawler.Faker(ent)
	return ply and (ply.EvilCrawlerVictim or EvilCrawler.Holder and EvilCrawler.Holder(ply)) and true or false
end

local function Food(ent)
	if ent.EvilFungusBurnt or not PROPS[ent:GetClass()] then return false end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) and ORGANIC[phys:GetMaterial()] then return true end
	local model = string.lower(ent:GetModel() or "")
	for _, word in ipairs(GREENS) do
		if string.find(model, "%f[%a]" .. word) then return true end
	end
	return false
end
EvilFungus.Food = Food

local function Track(ent)
	if ent.EvilFungusSleeper then return end
	if Creature(ent) then
		EvilFungus.Creatures[ent] = true
	elseif Food(ent) then
		EvilFungus.Foods[ent] = true
	end
end

hook.Add("OnEntityCreated", "EvilFungusCreatures", function(ent)
	timer.Simple(0, function()
		if IsValid(ent) then Track(ent) end
	end)
end)

hook.Add("EntityRemoved", "EvilFungusCreatures", function(ent)
	EvilFungus.Creatures[ent] = nil
	EvilFungus.Foods[ent] = nil
end)

for _, ent in ipairs(ents.GetAll()) do Track(ent) end
