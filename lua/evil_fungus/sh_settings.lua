EvilFungus = EvilFungus or {}

EvilFungus.SETTINGS = {
	{ name = "attack_players", default = 1, min = 0, max = 1, label = "Eats players",
		help = "Players standing on the mat are food. At 0 it leaves players alone entirely" },
	{ name = "attack_npcs", default = 1, min = 0, max = 1, label = "Eats NPCs",
		help = "People and animals standing on the mat are food. Anything that doesn't bleed never is" },
	{ name = "eat_props", default = 1, min = 0, max = 1, label = "Eats plants and bodies",
		help = "Plants, fruit, meat and bodies left on the mat get eaten" },
	{ name = "max_nodes", default = 2500, min = 200, max = 8000, decimals = 0, label = "Mat size",
		help = "Most strands all the fungus on the map can lay together before it stops spreading" },
	{ name = "start_mass", default = 60, min = 10, max = 400, decimals = 0, label = "Starting body",
		help = "How much body a fresh fungus has to spread with" },
	{ name = "grow_speed", default = 1, min = 0, max = 5, decimals = 2, label = "Spread speed",
		help = "How fast it grows over new ground" },
	{ name = "flow_speed", default = 1, min = 0.1, max = 5, decimals = 2, label = "Flow speed",
		help = "How fast its body moves through the mat it already has" },
}

local convars, byConVar = {}, {}
for _, s in ipairs(EvilFungus.SETTINGS) do
	s.convar = "evil_fungus_" .. s.name
	convars[s.name] = CreateConVar(s.convar, tostring(s.default), bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), s.help, s.min, s.max)
	byConVar[s.convar] = s
end

function EvilFungus.Setting(name)
	return convars[name]:GetFloat()
end

if CLIENT then return end

util.AddNetworkString("EvilFungusSetting")

net.Receive("EvilFungusSetting", function(_, ply)
	local s = byConVar[net.ReadString()]
	local value = tonumber(net.ReadString())
	if not s or not value or not IsValid(ply) or not ply:IsSuperAdmin() then return end
	RunConsoleCommand(s.convar, tostring(math.Clamp(value, s.min, s.max)))
end)
