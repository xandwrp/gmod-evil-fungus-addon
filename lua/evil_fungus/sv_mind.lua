EvilFungus = EvilFungus or {}

local CONSUMING, KEPT = EvilFungus.CONSUMING, EvilFungus.KEPT

local UPDATE = 1
local PLAYER_BRAIN = 1
local NPC_BRAIN = 0.1

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

function EvilFungus.Brain(ent)
	if not IsValid(ent) then return 0 end
	if ent:IsPlayer() then return PLAYER_BRAIN end
	return ent:IsNPC() and BRAINS[ent:Classify()] or NPC_BRAIN
end

local Mind = {}
Mind.__index = Mind
EvilFungus.Mind = Mind

function EvilFungus.NewMind()
	return setmetatable({ kept = 0, wired = 0 }, Mind)
end

-- Heads it's finished with count in full, for good. The rest only count as much as they're wired in.
function Mind:Total()
	return self.kept + self.wired
end

-- Each step up takes twice the heads the last one did.
function Mind:Level()
	return math.log(1 + self:Total()) / math.log(2)
end

-- How much of what it's seen it has understood. Nothing at first, and closer to all of it with every step up.
function Mind:Grasp()
	return 1 - 1 / (1 + self:Total())
end

function Mind:Keep(brain)
	self.kept = self.kept + brain
end

-- Two of it that meet agree they were always the same, and remember everything either one did.
function EvilFungus.Converge(keep, lose)
	if keep == lose then return end
	keep.kept, keep.wired = keep.kept + lose.kept, keep.wired + lose.wired
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
