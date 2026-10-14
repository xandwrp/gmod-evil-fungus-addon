EvilFungus = EvilFungus or {}
EvilFungus.Creatures = EvilFungus.Creatures or {}

local function Creature(ent)
	return ent:IsNPC() or ent:IsNextBot()
end
EvilFungus.Creature = Creature

hook.Add("OnEntityCreated", "EvilFungusCreatures", function(ent)
	timer.Simple(0, function()
		if IsValid(ent) and Creature(ent) then EvilFungus.Creatures[ent] = true end
	end)
end)

hook.Add("EntityRemoved", "EvilFungusCreatures", function(ent)
	EvilFungus.Creatures[ent] = nil
end)

for _, ent in ipairs(ents.GetAll()) do
	if Creature(ent) then EvilFungus.Creatures[ent] = true end
end
