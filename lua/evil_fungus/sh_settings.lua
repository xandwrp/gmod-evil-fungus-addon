EvilFungus = EvilFungus or {}

EvilFungus.SETTINGS = {
	{ name = "attack_players", default = 1, min = 0, max = 1, label = "Eats players",
		help = "Players standing on the mat are food. At 0 it leaves players alone entirely" },
	{ name = "attack_npcs", default = 1, min = 0, max = 1, label = "Eats NPCs",
		help = "People and animals standing on the mat are food. Anything that doesn't bleed never is" },
	{ name = "sleep_time", default = 4, min = 0.5, max = 30, decimals = 1, label = "Sleep time",
		help = "Seconds with its body on you before you go under" },
	{ name = "grip", default = 0.85, min = 0, max = 1, decimals = 2, label = "Grip",
		help = "How much it slows anyone walking through it where it's thickest. At 1 they can't move" },
	{ name = "consume_time", default = 300, min = 10, max = 1800, decimals = 0, label = "Consume time",
		help = "Seconds it takes to replace a sleeper with itself, everything but the head" },
	{ name = "rescue_time", default = 60, min = 0, max = 600, decimals = 0, label = "Rescue window",
		help = "Seconds into being consumed that a sleeper can still be pulled off the mat" },
	{ name = "give_up", default = 1, min = 0, max = 1, label = "Sleepers can give up",
		help = "Players who've gone under can press jump to respawn straight away instead of waiting out their rescue window" },
	{ name = "killable", default = 1, min = 0, max = 1, label = "Can be killed",
		help = "Fire spreads through it and burns it away, explosions blow holes in it and bullets cut its strands. At 0 nothing hurts it" },
	{ name = "eat_props", default = 1, min = 0, max = 1, label = "Eats plants and bodies",
		help = "Plants, fruit, meat and bodies left on the mat get eaten" },
	{ name = "aggression", default = 1, min = 0, max = 20, decimals = 2, label = "Aggression",
		help = "How far off it feels footsteps, how long it keeps after someone and how fast it grows and flows at them. At 0 it never notices anyone" },
	{ name = "smell", default = 0, min = 0, max = 4000, decimals = 0, label = "Smell",
		help = "How far off the mat it smells people and animals breathing and goes for where they are. Running and being hurt carry further, walls stop it. At 0 it only feels what walks on it" },
	{ name = "vibration", default = 0, min = 0, max = 4000, decimals = 0, label = "Vibration",
		help = "How far through the ground it feels something moving along it at a walk. Faster and heavier carry further. People and animals get hunted where it came from, anything else it goes to look at. At 0 it only feels what walks on it" },
	{ name = "scavenge", default = 1500, min = 0, max = 6000, decimals = 0, label = "Scavenging",
		help = "How far off it smells bodies lying around and grows out to them when it's got nothing better to do. Walls stop it. At 0 it waits for them to end up on it" },
	{ name = "learning", default = 1, min = 0, max = 10, decimals = 2, label = "Learning",
		help = "How much smarter every head it takes in makes it, and how much it learns from watching and eating people get away. At 0 it never gets any smarter" },
	{ name = "learn_noclip", default = 1, min = 0, max = 1, label = "Learns noclip",
		help = "At 0 it never catches on to noclipping, however much it sees" },
	{ name = "grow_cost", default = 1, min = 0, max = 3, decimals = 2, label = "Growth cost",
		help = "How much body each new strand costs. At 0 spreading is free and it never runs out" },
	{ name = "sprawl", default = 1, min = 0, max = 5, decimals = 2, label = "Sprawl",
		help = "How much it branches off at random instead of heading somewhere, and how much its paths wander" },
	{ name = "spores", default = 1, min = 0, max = 10, decimals = 2, label = "Spores",
		help = "How often a well-fed fungus throws spores that start new patches nearby. At 0 it never does" },
	{ name = "carried", default = 1, min = 0, max = 10, decimals = 2, label = "Carried spores", needs = "EvilCrawler",
		help = "How easily Evil Crawlers walking through the mat pick up spores, and how often they shake one off somewhere else. At 0 they never carry any" },
	{ name = "time_scale", default = 1, min = 0.1, max = 20, decimals = 1, label = "Time scale",
		help = "Runs the fungus faster or slower than the game: growth, flow, sensing, putting people under and consuming them" },
	{ name = "max_nodes", default = 2500, min = 200, max = 15000, decimals = 0, label = "Mat size",
		help = "Most strands all the fungus on the map can lay together before it stops spreading" },
	{ name = "start_mass", default = 60, min = 10, max = 400, decimals = 0, label = "Starting body",
		help = "How much body a fresh fungus has to spread with" },
	{ name = "grow_speed", default = 1, min = 0, max = 10, decimals = 2, label = "Spread speed",
		help = "How fast it grows over new ground" },
	{ name = "flow_speed", default = 1, min = 0.1, max = 10, decimals = 2, label = "Flow speed",
		help = "How fast its body moves through the mat it already has" },
}

-- Anything a preset leaves out goes back to its default.
EvilFungus.PRESETS = {
	{ name = "normal", label = "Normal", values = {} },
	{ name = "unhinged", label = "Unhinged", values = {
		sleep_time = 1, grip = 1, consume_time = 60, rescue_time = 15,
		aggression = 20, learning = 4, smell = 3000, vibration = 2000, scavenge = 5000, grow_cost = 0.25, sprawl = 2.5, spores = 8, carried = 4,
		max_nodes = 6000, start_mass = 150, grow_speed = 3, flow_speed = 3,
	} },
}

EvilFungus.Settings = Evil.Settings({
	id = "evil_fungus", title = "Evil Fungus", rows = EvilFungus.SETTINGS, presets = EvilFungus.PRESETS,
	fill = true, reset = false,
	extra = function(panel)
		panel:Button("Remove all fungus", "evil_fungus_clear").Think = Evil.AdminOnly
	end,
})

function EvilFungus.Setting(name)
	return EvilFungus.Settings:Get(name)
end

function EvilFungus.TimeScale()
	return EvilFungus.Settings:Get("time_scale")
end
