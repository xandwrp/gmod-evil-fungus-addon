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

function EvilFungus.Bleeds(ent)
	if ent.IsVJBaseSNPC then return isstring(ent.BloodColor) and ent.BloodColor ~= "Oil" end
	local blood = ent.GetBloodColor and ent:GetBloodColor()
	return blood ~= nil and blood >= 0 and blood ~= BLOOD_COLOR_MECH
end

function EvilFungus.CrawlerHas(ent)
	if not EvilCrawler then return false end
	if ent.EvilCrawlerVictim or IsValid(ent.EvilCrawlerOwner) then return true end
	if ent:IsPlayer() then return EvilCrawler.Holder and EvilCrawler.Holder(ent) and true or false end
	local ply = EvilCrawler.Faker and EvilCrawler.Faker(ent)
	return ply and (ply.EvilCrawlerVictim or EvilCrawler.Holder and EvilCrawler.Holder(ply)) and true or false
end

local function Food(ent)
	if not PROPS[ent:GetClass()] then return false end
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
