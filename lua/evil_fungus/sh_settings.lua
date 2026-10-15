EvilFungus = EvilFungus or {}

EvilFungus.SETTINGS = {
	{ name = "attack_players", default = 1, min = 0, max = 1, label = "Eats players",
		help = "Players standing on the mat are food. At 0 it leaves players alone entirely" },
	{ name = "attack_npcs", default = 1, min = 0, max = 1, label = "Eats NPCs",
		help = "People and animals standing on the mat are food. Anything that doesn't bleed never is" },
	{ name = "sleep_time", default = 4, min = 0.5, max = 30, decimals = 1, label = "Sleep time",
		help = "Seconds with its body on you before you go under" },
	{ name = "consume_time", default = 300, min = 10, max = 1800, decimals = 0, label = "Consume time",
		help = "Seconds it takes to replace a sleeper with itself, everything but the head" },
	{ name = "rescue_time", default = 60, min = 0, max = 600, decimals = 0, label = "Rescue window",
		help = "Seconds into being consumed that a sleeper can still be torn free" },
	{ name = "give_up", default = 0, min = 0, max = 1, label = "Sleepers can respawn",
		help = "Players who've gone under can respawn before their rescue window closes" },
	{ name = "eat_props", default = 1, min = 0, max = 1, label = "Eats plants and bodies",
		help = "Plants, fruit, meat and bodies left on the mat get eaten" },
	{ name = "aggression", default = 1, min = 0, max = 5, decimals = 2, label = "Aggression",
		help = "How far off it feels footsteps, how long it keeps after someone and how fast it grows and flows at them. At 0 it never notices anyone" },
	{ name = "grow_cost", default = 1, min = 0, max = 3, decimals = 2, label = "Growth cost",
		help = "How much body each new strand costs. At 0 spreading is free and it never runs out" },
	{ name = "sprawl", default = 1, min = 0, max = 5, decimals = 2, label = "Sprawl",
		help = "How much it branches off at random instead of heading somewhere, and how much its paths wander" },
	{ name = "spores", default = 1, min = 0, max = 10, decimals = 2, label = "Spores",
		help = "How often a well-fed fungus throws spores that start new patches nearby. At 0 it never does" },
	{ name = "time_scale", default = 1, min = 0.1, max = 20, decimals = 1, label = "Time scale",
		help = "Runs the fungus faster or slower than the game: growth, flow, sensing, putting people under and consuming them" },
	{ name = "max_nodes", default = 2500, min = 200, max = 15000, decimals = 0, label = "Mat size",
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

function EvilFungus.TimeScale()
	return convars.time_scale:GetFloat()
end

if CLIENT then return end

util.AddNetworkString("EvilFungusSetting")

net.Receive("EvilFungusSetting", function(_, ply)
	local s = byConVar[net.ReadString()]
	local value = tonumber(net.ReadString())
	if not s or not value or not IsValid(ply) or not ply:IsSuperAdmin() then return end
	RunConsoleCommand(s.convar, tostring(math.Clamp(value, s.min, s.max)))
end)
