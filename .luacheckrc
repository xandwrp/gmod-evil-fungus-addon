stds.gmod = dofile("tools/gmod_std.lua")
std = "luajit+gmod"
max_line_length = false
unused_args = false
ignore = { "42.", "43.", "581" }
globals = { "Evil", "EvilNeedsAPI", "EvilCrawler", "EvilFungus", "EvilBarnacle", "EvilSnake", "Terminus" }
read_globals = { "hg", "VJ_MOVETYPE_STATIONARY" }
files["lua/entities/**"] = { globals = { "ENT" } }
files["lua/effects/**"] = { globals = { "EFFECT" } }
