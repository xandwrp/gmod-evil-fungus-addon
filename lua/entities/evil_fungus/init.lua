AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("evil_fungus/sv_mat.lua")
include("sv_feel.lua")
include("sv_debug.lua")

local Mat = EvilFungus.Mat
local EMPTY = Mat.EMPTY

local CAP = 4
local FLOW = 160
local SPREAD = 0.8
local SPREAD_MASS = 0.2
local GROW_MASS = 1
local GROW_COST = 0.1
local MIN_BODY = 8
local REACH_RATE = 2.5
local SPREAD_RATE = 3
local REACH_JITTER = 0.7
local SEED_RING = 8
local DECIDE_INTERVAL = 0.25
local COST_WINDOW = 1
local WANDER_TIME = { 8, 16 }
local WANDER_RANGE = 700
local WANDER_TRIES = 6
local PATROL_CHANCE = 0.3
local PATROL_NODES = 40
local ARRIVE = 32
local REST_TIME = { 2, 5 }
local LOSE_TIME = 8
local NEAR_GOAL = 96

local ai_disabled = GetConVar("ai_disabled")

EvilFungus.Colonies = EvilFungus.Colonies or {}

-- Every strand on the map, all fungus together, since it's all one fungus.
function EvilFungus.Strands()
	local n = 0
	for colony in pairs(EvilFungus.Colonies) do
		if colony.Mat then n = n + colony.Mat.count end
	end
	return n
end

function ENT:SpawnFunction(ply, tr, class)
	if not tr.HitWorld or tr.HitSky then return end

	local ent = ents.Create(class)
	ent:SetPos(tr.HitPos + tr.HitNormal * 4)
	ent.SpawnAt = tr.HitPos
	ent.SpawnUp = tr.HitNormal
	ent:Spawn()
	ent:Activate()
	return ent
end

function ENT:Initialize()
	self:SetModel("models/props_junk/PopCan01a.mdl")
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:DrawShadow(false)

	local now = CurTime()
	local mat = EvilFungus.NewMat()
	self.Mat = mat

	local up = self.SpawnUp or vector_up
	local seed = mat:Add(self.SpawnAt or self:GetPos(), up)
	local ring = { seed }
	local ang = up:Angle()
	local right, side = ang:Right(), ang:Up()
	for i = 1, SEED_RING do
		local a = i / SEED_RING * math.pi * 2
		local node = mat:Grow(seed, right * math.cos(a) + side * math.sin(a), now)
		if node then ring[#ring + 1] = node end
	end
	local share = EvilFungus.Setting("start_mass") / #ring
	for _, node in ipairs(ring) do mat:SetMass(node, share) end

	self.Center, self.Up, self.Body = seed.pos, up, share * #ring
	self.ReachDebt, self.SpreadDebt = 0, 0
	self.NextDecide = 0
	self.TargetUntil = 0
	self.Costs, self.CostReport, self.CostSince = {}, {}, now
	self:InitFeel()

	EvilFungus.Colonies[self] = true
	for _, node in ipairs(ring) do
		if self:Meet(node, now) then return end
	end
end

function ENT:Think()
	local now = CurTime()
	if self.Absorbed then return end
	if not (ai_disabled and ai_disabled:GetBool()) then
		local t = SysTime()
		if now >= self.NextDecide then
			self:Decide(now)
			self.NextDecide = now + DECIDE_INTERVAL
			t = self:Cost("decide", t)
		end
		local dt = FrameTime()
		self:Flow(dt, now)
		t = self:Cost("flow", t)
		self:Spread(dt, now)
		if self.Absorbed then return end
		t = self:Cost("grow", t)
		self:Feel(now)
		self:Cost("feel", t)
	end
	self:Report(now)
	self:DebugDraw(now)
	self:NextThink(now)
	return true
end

function ENT:Cost(name, since)
	local t = SysTime()
	self.Costs[name] = (self.Costs[name] or 0) + t - since
	return t
end

-- Milliseconds of server time each part took over the last second.
function ENT:Report(now)
	local span = now - self.CostSince
	if span < COST_WINDOW then return end
	for name, cost in pairs(self.Costs) do
		self.CostReport[name] = cost * 1000 / span
		self.Costs[name] = 0
	end
	self.CostSince = now
end

function ENT:Settle()
	local center, up, body = Vector(), Vector(), 0
	for node in pairs(self.Mat.full) do
		center:Add(node.pos * node.m)
		up:Add(node.normal * node.m)
		body = body + node.m
	end
	self.Body = body
	if body <= EMPTY then return end
	self.Center = center / body
	self.Up = up:GetNormalized()
	self:SetPos(self.Center + self.Up * 4)
end

function ENT:Closest(pos)
	local node = self.Mat:Nearest(pos, NEAR_GOAL)
	if node then return node end
	local bestD2 = math.huge
	for _, n in pairs(self.Mat.nodes) do
		local d2 = n.pos:DistToSqr(pos)
		if d2 < bestD2 then node, bestD2 = n, d2 end
	end
	return node
end

local function RandomNode(set, accept)
	local pick, seen = nil, 0
	for key, value in pairs(set) do
		local node = value == true and key or value
		if not accept or accept(node) then
			seen = seen + 1
			if math.random(seen) == 1 then pick = node end
		end
	end
	return pick
end

function ENT:PickTarget(now)
	self.TargetUntil = now + math.Rand(WANDER_TIME[1], WANDER_TIME[2])
	self.Resting = false
	self.GoalStale = true

	if self.Mat.count > PATROL_NODES and math.random() < PATROL_CHANCE then
		self.Target = RandomNode(self.Mat.nodes).pos
		return
	end

	local from = self.Center + self.Up * 16
	for _ = 1, WANDER_TRIES do
		local dir = VectorRand():GetNormalized()
		local tr = util.TraceLine({ start = from, endpos = from + dir * WANDER_RANGE, mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit and not tr.HitSky and not tr.HitNoDraw and not tr.StartSolid and tr.Fraction > 0.15 then
			self.Target = tr.HitPos
			return
		end
	end
	self.Target = self.Center
end

function ENT:Decide(now)
	self:Settle()

	local prey, node = self.Prey, self.PreyNode
	self.Hunting = IsValid(prey) and node and not node.dead and now - self.FeltAt < LOSE_TIME
		and self:Perceivable(prey)
	if not self.Hunting then
		self.Prey, self.PreyNode, self.Eating = nil, nil, nil
	end

	local goal
	if self.Hunting then
		goal = node
		self.Target = self:Touches(prey) and prey:GetPos() or node.pos
	else
		if not self.Target or now >= self.TargetUntil then self:PickTarget(now) end
		goal = self.Goal
		if self.GoalStale or not goal or goal.dead then
			goal = self:Closest(self.Target)
			self.GoalStale = false
		end
		if not self.Resting and goal.m > GROW_MASS and goal.pos:Distance(self.Target) < ARRIVE then
			self.Resting = true
			self.TargetUntil = math.min(self.TargetUntil, now + math.Rand(REST_TIME[1], REST_TIME[2]))
		end
	end
	self.Goal = goal

	-- Only the body needs to know the way, so the search ends once it has reached every part of it.
	local mat = self.Mat
	local left, reached = 0, {}
	for _ in pairs(mat.full) do left = left + 1 end
	self.Dist = mat:Distances({ [goal] = 0 }, function(e) return e.len / mat:Conductance(e, now) end, nil,
		function(node)
			if not mat.full[node] or reached[node] then return false end
			reached[node] = true
			left = left - 1
			return left <= 0
		end)
end

local flowList = {}

function ENT:Flow(dt, now)
	local dist, mat = self.Dist, self.Mat
	if not dist then return end

	local n = 0
	for node in pairs(mat.full) do
		n = n + 1
		flowList[n] = node
	end

	local rate = FLOW * EvilFungus.Setting("flow_speed")
	local spread = math.min(0.25, SPREAD * dt)
	for i = 1, n do
		local node = flowList[i]
		flowList[i] = nil
		local m = node.m
		if m > EMPTY and not node.dead then
			local d, down, to = dist[node] or math.huge, nil, nil
			for _, e in ipairs(node.edges) do
				local other = mat:Other(e, node)
				local od = dist[other]
				if od and od < d and other.m < CAP then d, down, to = od, e, other end
			end
			if down then
				local q = m * math.min(0.9, rate * mat:Conductance(down, now) / down.len * dt)
				m = m - q
				mat:SetMass(to, to.m + q)
				mat:Thicken(down, q, now)
			end
			if m > SPREAD_MASS then
				for _, e in ipairs(node.edges) do
					local other = mat:Other(e, node)
					if other.m < m then
						local q = (m - other.m) * spread
						m = m - q
						mat:SetMass(other, other.m + q)
					end
				end
			end
			mat:SetMass(node, m)
		end
	end
end

local function Frontier(node)
	return node.m > GROW_MASS
end

function ENT:Sprout(from, dir, now)
	local node = self.Mat:Grow(from, dir, now)
	if not node then return end
	self.Mat:SetMass(from, from.m - GROW_COST)
	local goal, target = self.Goal, self.Target
	if not self.Hunting and goal and target and node.pos:DistToSqr(target) < goal.pos:DistToSqr(target) then
		self.Goal = node
	end
	self:Meet(node, now)
	return node
end

-- There is only one fungus. Two mats that touch recognise each other and carry on as one.
function ENT:Meet(node, now)
	local reach = Vector(Mat.FUSE, Mat.FUSE, Mat.FUSE)
	local pos = node.pos
	for other in pairs(EvilFungus.Colonies) do
		local mat = other ~= self and IsValid(other) and not other.Absorbed and other.Mat
		if mat and mat.mins and pos:WithinAABox(mat.mins - reach, mat.maxs + reach) then
			local theirs = mat:Nearest(pos, Mat.FUSE, function(n) return Mat.Facing(node, n) and Mat.Reaches(node, n) end)
			if theirs then return self:Fuse(other, node, theirs, now) end
		end
	end
	return false
end

function ENT:Fuse(other, mine, theirs, now)
	local keep, lose = self, other
	if other.Mat.count > self.Mat.count then keep, lose = other, self end

	keep.Mat:Absorb(lose.Mat)
	keep.Mat:Link(mine, theirs, now)
	keep:Adopt(lose)
	keep:Ripple(mine, now)
	keep.NextDecide = 0
	keep.GoalStale = true

	lose.Absorbed = true
	EvilFungus.Colonies[lose] = nil
	lose:Remove()
	return lose == self
end

function ENT:Spread(dt, now)
	local mat = self.Mat
	if self.Body < MIN_BODY then return end
	local speed = EvilFungus.Setting("grow_speed")
	self.ReachDebt = math.min(3, self.ReachDebt + REACH_RATE * speed * dt)
	self.SpreadDebt = math.min(3, self.SpreadDebt + SPREAD_RATE * speed * dt)
	if self.ReachDebt < 1 and self.SpreadDebt < 1 then return end
	if EvilFungus.Strands() >= EvilFungus.Setting("max_nodes") then
		self.ReachDebt, self.SpreadDebt = 0, 0
		return
	end

	local target = self.Target
	while self.ReachDebt >= 1 and target do
		self.ReachDebt = self.ReachDebt - 1
		local best, bestD2 = nil, math.huge
		for node in pairs(mat.full) do
			if Frontier(node) then
				local d2 = node.pos:DistToSqr(target)
				if d2 < bestD2 then best, bestD2 = node, d2 end
			end
		end
		if best and bestD2 > ARRIVE * ARRIVE then
			local dir = (target - best.pos):GetNormalized() + VectorRand() * REACH_JITTER
			self:Sprout(best, dir, now)
			if self.Absorbed then return end
		end
	end

	while self.SpreadDebt >= 1 do
		self.SpreadDebt = self.SpreadDebt - 1
		local from = RandomNode(mat.full, Frontier)
		if from then self:Sprout(from, VectorRand(), now) end
		if self.Absorbed then return end
	end
end

function ENT:OnRemove()
	EvilFungus.Colonies[self] = nil
	self:ReleaseAll()
end
