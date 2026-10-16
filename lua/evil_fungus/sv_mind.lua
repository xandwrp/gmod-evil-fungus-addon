EvilFungus = EvilFungus or {}
EvilFungus.Profiles = EvilFungus.Profiles or {}

local CONSUMING, KEPT = EvilFungus.CONSUMING, EvilFungus.KEPT

local UPDATE = 1
local PLAYER_BRAIN = 1
local NPC_BRAIN = 0.1
local SKILL_MAX = 2
local WATCH = 0.1

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

-- Everything one person has done to get away from it, since it last had them.
function EvilFungus.Profile(ply)
	local key = ply:IsBot() and "bot " .. ply:Nick() or ply:SteamID64()
	local p = EvilFungus.Profiles[key]
	if not p then
		p = { did = {}, at = {} }
		EvilFungus.Profiles[key] = p
	end
	return p
end

local function Skill(p)
	local skill = 0
	for tactic, full in pairs(TACTICS) do skill = skill + math.min(1, (p.did[tactic] or 0) / full) end
	return math.min(SKILL_MAX, skill)
end

-- Whoever was hardest to catch has the most worth having.
function EvilFungus.Brain(ent)
	if not IsValid(ent) then return 0 end
	if ent:IsPlayer() then return PLAYER_BRAIN * (1 + Skill(EvilFungus.Profile(ent))) end
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
	return 1 - 1 / (1 + (self.know[tactic] or 0))
end

function Mind:Keep(brain)
	self.kept = self.kept + brain
end

-- Someone getting away from it in front of it. Only once a tick, however many patches of it see.
-- It takes a little from that, depending on how much it already understands.
function Mind:Watch(ply, tactic, amount)
	local p = EvilFungus.Profile(ply)
	local now = CurTime()
	if p.at[tactic] == now then return end
	p.at[tactic] = now
	p.did[tactic] = (p.did[tactic] or 0) + amount
	self.know[tactic] = (self.know[tactic] or 0) + amount / TACTICS[tactic] * WATCH * self:Grasp()
end

-- Whatever someone knew about getting away from it, it knows once it's done with them. They start over.
function Mind:Learn(p)
	local learning = EvilFungus.Setting("learning")
	for tactic, full in pairs(TACTICS) do
		self.know[tactic] = (self.know[tactic] or 0) + math.min(1, (p.did[tactic] or 0) / full) * learning
		p.did[tactic] = 0
	end
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
