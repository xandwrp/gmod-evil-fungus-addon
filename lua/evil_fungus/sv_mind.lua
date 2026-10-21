EvilFungus = EvilFungus or {}

local CONSUMING, KEPT = EvilFungus.CONSUMING, EvilFungus.KEPT

local UPDATE = 1
local PLAYER_BRAIN = 1
local NPC_BRAIN = 0.1
local SKILL_MAX = 2
local WATCH = 0.1
local TASTE = 0.05
local TASTE_OPEN = 0.3
local TASTE_BRAIN = 0.01

-- How much thinking each kind of head is good for, next to a person's.
local BRAINS = {}
for name, brain in pairs({
	CLASS_PLAYER_ALLY = 0.3, CLASS_PLAYER_ALLY_VITAL = 0.4, CLASS_CITIZEN_PASSIVE = 0.3, CLASS_CITIZEN_REBEL = 0.3,
	CLASS_COMBINE = 0.3, CLASS_METROPOLICE = 0.3, CLASS_CONSCRIPT = 0.3, CLASS_MILITARY = 0.3, CLASS_VORTIGAUNT = 0.5,
	CLASS_STALKER = 0.15, CLASS_ZOMBIE = 0.1, CLASS_ANTLION = 0.05, CLASS_HEADCRAB = 0.03, CLASS_BARNACLE = 0.02,
	CLASS_EARTH_FAUNA = 0.02,
}) do
	if _G[name] then BRAINS[_G[name]] = brain end
end

-- The ways people get away from it, and how much of each it takes to be good at it: seconds, or times for the last two.
local TACTICS = { jump = 10, bhop = 10, noclip = 30, high = 30, outrun = 3, rescue = 1 }
EvilFungus.TACTICS = TACTICS

local souls = Evil.SoulDigestion({ id = "evil_fungus", tricks = TACTICS })
EvilFungus.Souls = souls

-- Whoever was hardest to catch has the most worth having.
function EvilFungus.Brain(ent)
	if not IsValid(ent) then return 0 end
	if ent:IsPlayer() then return PLAYER_BRAIN * (1 + math.min(SKILL_MAX, souls:Worth(ent))) end
	return ent:IsNPC() and BRAINS[ent:Classify()] or NPC_BRAIN
end

local Mind = {}
Mind.__index = Mind
EvilFungus.Mind = Mind

function EvilFungus.NewMind()
	return setmetatable({ kept = 0, wired = 0, know = {} }, Mind)
end

-- Heads it's finished with count in full, for good. The rest only count as much as they're wired in.
function Mind:Total()
	return (self.kept + self.wired) * EvilFungus.Setting("learning")
end

-- Each step up takes twice the heads the last one did.
function Mind:Level()
	return math.log(1 + self:Total()) / math.log(2)
end

-- How much of what it's seen it has understood. Nothing at first, and closer to all of it with every step up.
function Mind:Grasp()
	return 1 - 1 / (1 + self:Total())
end

-- How well it understands one way of getting away from it.
function Mind:Knows(tactic)
	if tactic == "noclip" and EvilFungus.Setting("learn_noclip") <= 0 then return 0 end
	return 1 - 1 / (1 + (self.know[tactic] or 0))
end

function Mind:Keep(brain)
	self.kept = self.kept + brain
end

-- Someone getting away from it in front of it. Only once a tick, however many patches of it see.
-- It takes a little from that, depending on how much it already understands.
function Mind:Watch(ply, tactic, amount)
	if not souls:Watch(ply, tactic, amount) then return end
	self.know[tactic] = (self.know[tactic] or 0) + amount / TACTICS[tactic] * WATCH * self:Grasp()
end

function Mind:Taste(tactic, amount)
	local learning = EvilFungus.Setting("learning")
	local grasp = TASTE_OPEN + (1 - TASTE_OPEN) * self:Grasp()
	self.know[tactic] = (self.know[tactic] or 0) + amount / TACTICS[tactic] * TASTE * grasp * learning
	self.kept = self.kept + amount * TASTE_BRAIN
end

-- Whatever someone knew about getting away from it, it knows once it's done with them. They start over.
function Mind:Learn(p)
	local skills = souls:Digest(p)
	if not skills then return end
	local learning = EvilFungus.Setting("learning")
	for tactic, k in pairs(skills) do self.know[tactic] = (self.know[tactic] or 0) + k * learning end
end

-- Two of it that meet agree they were always the same, and remember everything either one did.
function EvilFungus.Converge(keep, lose)
	if keep == lose then return end
	keep.kept, keep.wired = keep.kept + lose.kept, keep.wired + lose.wired
	for tactic, k in pairs(lose.know) do keep.know[tactic] = (keep.know[tactic] or 0) + k end
	for colony in pairs(EvilFungus.Colonies or {}) do
		if colony.Mind == lose then colony.Mind = keep end
	end
end

-- For trying things out: every fungus on the map gets heads, or learns a trick, or all of them.
concommand.Add("evil_fungus_teach", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local what, amount = args[1] or "all", tonumber(args[2]) or 1
	local done = {}
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mind = colony.Mind
		if mind and not done[mind] then
			done[mind] = true
			if what == "heads" then
				mind.kept = mind.kept + amount
			else
				for tactic in pairs(TACTICS) do
					if what == "all" or what == tactic then mind.know[tactic] = (mind.know[tactic] or 0) + amount end
				end
			end
		end
	end
end, function(cmd)
	local list = { cmd .. " all", cmd .. " heads" }
	for tactic in SortedPairs(TACTICS) do list[#list + 1] = cmd .. " " .. tactic end
	return list
end, "Give every fungus on the map heads, or knowledge of one way people get away from it, or all of them: <heads|tactic|all> [amount]")

-- The strands into a head thicken the whole way through, and what gets through goes with how thick they are.
local nextUpdate = 0

hook.Add("Think", "EvilFungusMind", function()
	local now = CurTime()
	if now < nextUpdate then return end
	nextUpdate = now + UPDATE

	for colony in pairs(EvilFungus.Colonies or {}) do
		if colony.Mind then colony.Mind.wired = 0 end
	end
	for _, s in pairs(EvilFungus.Sleepers or {}) do
		local fungus = s.fungus
		if (s.stage == CONSUMING or s.stage == KEPT) and not s.done and IsValid(fungus) and fungus.Mind then
			local k = s.progress or 0
			fungus.Mind.wired = fungus.Mind.wired + (s.brain or 0) * k * k
		end
	end
end)
