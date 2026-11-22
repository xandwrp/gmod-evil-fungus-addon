-- Finding the way round. Growing straight at something is all it does until that stops getting it any
-- closer; then it feels its way over the surfaces ahead of the mat, the same way a strand would step,
-- and follows what it found one point at a time. No navmesh: the map's own brushes are the graph.

local Mat = EvilFungus.Mat

-- Step length follows how much searching is left: long strides while the target is still far off, finer and
-- finer ones as it closes in, so the last stretch is sampled where the mat actually has to squeeze through.
local STEP_NEAR = 20
local STEP_FAR = 50
local STEP_RAMP_NEAR = 200
local STEP_RAMP_FAR = 1200
-- Dedup grid can't be coarser than the finest step or the close-in probes all collapse into one node.
local CELL = STEP_NEAR
local DIRS = 8
-- How much the search leans on heading straight for the target over trying the ways round. It starts at
-- WEIGHT_START, fanning out evenly over every face round where it's stuck, and leans harder toward the target
-- the more it has looked, reaching WEIGHT_END by WEIGHT_RAMP points, so it covers the obstacle first and then
-- commits to a way past it. Changes in WEIGHT_STEPS jumps, since each one re-sorts what's waiting.
local WEIGHT_START = 1.0
local WEIGHT_END = 1.4
local WEIGHT_RAMP = 1200
local WEIGHT_STEPS = 8
local MAX_NODES = 1500
local EXPANSIONS_PER_TICK = 6
local SEEDS_NEAR = 8
local SEEDS_RANDOM = 8
local GOAL_REACH = 80
local LIFT = 4
local STALL = 3
local GAIN = 24
local NEAR = 64
local MOVED = 256
local PLAN_DROP = 512
local LOCK_TIME = 6
local KEEP_MOVED = 160
-- A route point only counts as reached when a strand is planted on the point itself. Growth steps in
-- strides and lands where it lands, so LeapTo puts a node exactly on the point to finish it; merely
-- being near it no longer counts.
local ON = 4
local LOOKAHEAD = 5
-- How far ahead the route's growing strand looks for mat to hop onto when it can't grow.
local HOP = 24
-- A point nothing has got onto in this long is given up on and the route moves to the next one; this many
-- given up on in a row and the whole route is.
local POINT_TIMEOUT = 8
local POINT_SKIPS = 2
local RETRY = 5
local COOLDOWN = 1
local PARTIAL_GAIN = 128
local SMOOTH_SPAN = 6
local SMOOTH_LEN = 160
local BEND = 0.9
-- A strand at the crease on either face is close enough to have rounded the corner. Requiring the exit face
-- itself (dot > BEND) deadlocked on bends sharper than ~26 degrees until the point timed out and was skipped.
local CORNER_FACING = 0.5
local CORNER_FAR = 2 * 40
local CORNER_PROBE = 12
local LEAP_RANGE = 64
local LEAP_GAP = 0.75
-- Eighths of a turn off the current heading for a probe to try, in order, when a stride won't go: straight
-- on first, then dodging to its own side, then the other.
local DODGE = { 0, 1, -1, 2, -2, 3, -3 }
-- Probing, for when the search comes up empty: feelers set off from the stuck front in every
-- direction across the surfaces, each holding its heading and turning toward the target a little more every
-- stride (PROBE_TURN_MIN at the start, up to PROBE_TURN_MAX by PROBE_TURN_RAMP strides). The ones heading
-- away swing out wide over walls and ceilings before they come round, so between them they cover the room,
-- and the first to get to the target is followed.
-- Feelers per starting strand. The search's 16 strands at 4 each is 64 feelers, sharing PROBE_BUDGET strides.
local PROBE_DIRS = 4
local PROBE_BUDGET = 3000
local PROBE_TURN_MIN = math.rad(2)
local PROBE_TURN_MAX = math.rad(6)
local PROBE_TURN_RAMP = 40
local PROBE_MAX_STRIDES = 120
local MASK = MASK_SOLID_BRUSHONLY
local WET = bit.bor(CONTENTS_WATER, CONTENTS_SLIME)

-- All fungus on the map shares one budget of steps a tick, so several stuck patches can't stall the server.
-- It's split evenly between the ones searching, or whichever thought first each tick took the lot and the
-- rest never finished a search.
hook.Add("Tick", "EvilFungusNav", function()
	local n = 0
	for colony in pairs(EvilFungus.Colonies or {}) do
		if IsValid(colony) and colony.Plan then n = n + 1 end
	end
	EvilFungus.NavLeft = EXPANSIONS_PER_TICK
	EvilFungus.NavShare = math.max(1, math.floor(EXPANSIONS_PER_TICK / math.max(1, n)))
end)

local function Key(pos, normal)
	local x, y, z = pos:Unpack()
	local ix, iy, iz = math.floor(x / CELL) + 1024, math.floor(y / CELL) + 1024, math.floor(z / CELL) + 1024
	return ((ix * 2048 + iy) * 2048 + iz) * 8 + Mat.Bucket(normal)
end

-- Remaining distance to go -> stride length: STEP_NEAR at STEP_RAMP_NEAR and closer, STEP_FAR from
-- STEP_RAMP_FAR out, linear in between.
local function StepFor(h)
	if h <= STEP_RAMP_NEAR then return STEP_NEAR end
	if h >= STEP_RAMP_FAR then return STEP_FAR end
	return STEP_NEAR + (STEP_FAR - STEP_NEAR) * ((h - STEP_RAMP_NEAR) / (STEP_RAMP_FAR - STEP_RAMP_NEAR))
end

local function Clear(a, an, b, bn)
	return not util.TraceLine({ start = a + an * LIFT, endpos = b + (bn or an) * LIFT, mask = MASK }).Hit
end

-- A plain binary heap on f.
local function Push(heap, item)
	local n = #heap + 1
	heap[n] = item
	while n > 1 do
		local p = math.floor(n / 2)
		if heap[p].f <= item.f then break end
		heap[n], heap[p] = heap[p], item
		n = p
	end
end

local function Pop(heap)
	local top, n = heap[1], #heap
	if n == 0 then return end
	local last = heap[n]
	heap[n] = nil
	n = n - 1
	if n == 0 then return top end
	heap[1] = last
	local i = 1
	while true do
		local l, r, s = i * 2, i * 2 + 1, i
		if l <= n and heap[l].f < heap[s].f then s = l end
		if r <= n and heap[r].f < heap[s].f then s = r end
		if s == i then break end
		heap[i], heap[s] = heap[s], heap[i]
		i = s
	end
	return top
end

-- Where on the mat to start feeling from: the bit already nearest, which is where greed got stuck, and a
-- scattering from the rest, since the way round often starts somewhere else entirely.
-- The part of the mat the body can actually get to: everything joined by strands to wherever most of the
-- mass is. Bits that got cut off (burnt through, blown apart, settled away) are still lying around and still
-- count as mat, but nothing can flow out to them, so they can't grow, pay for anything, or carry a route on.
-- Worked out once per decision and reused.
function ENT:Connected(now)
	if self.BodySet and self.BodySetAt == now then return self.BodySet end
	local label, best, bestMass = {}, nil, -1
	for _, node in pairs(self.Mat.nodes) do
		if not label[node] then
			local part, mass, stack = {}, 0, { node }
			label[node] = part
			while #stack > 0 do
				local n = stack[#stack]
				stack[#stack] = nil
				part[n] = true
				mass = mass + n.m
				for _, e in ipairs(n.edges) do
					local o = e.a == n and e.b or e.a
					if not label[o] and not o.dead then
						label[o] = part
						stack[#stack + 1] = o
					end
				end
			end
			if mass > bestMass then best, bestMass = part, mass end
		end
	end
	self.BodySet, self.BodySetAt = best or {}, now
	return self.BodySet
end

-- The strand of the body nearest a spot, for steering the body at.
local function BodyNearest(mat, body, pos)
	local node = mat:Nearest(pos, 96, function(n) return body[n] and not n.air end)
	if node then return node end
	local bestD2 = math.huge
	for n in pairs(body) do
		if not n.air and not n.dead then
			local d2 = n.pos:DistToSqr(pos)
			if d2 < bestD2 then node, bestD2 = n, d2 end
		end
	end
	return node
end

-- Settled mat counts too. A patch with strands asleep under it offers those strands, each where it
-- really lies, rather than the one hidden stand-in at the patch's middle; they're woken once a route
-- starting there is followed.
local function Seeds(body, target)
	local near, pool = {}, {}
	local function Consider(node)
		pool[#pool + 1] = node
		local d2 = node.pos:DistToSqr(target)
		if #near < SEEDS_NEAR or d2 < near[#near].d2 then
			local at = #near + 1
			while at > 1 and near[at - 1].d2 > d2 do at = at - 1 end
			table.insert(near, at, { node = node, d2 = d2 })
			near[SEEDS_NEAR + 1] = nil
		end
	end
	-- A run's sleepers are patches, each with strands of its own asleep under it.
	local function Offer(node)
		for _, sleeper in ipairs(node.sleepers) do
			if sleeper.sleepers then Offer(sleeper) elseif not sleeper.air then Consider(sleeper) end
		end
	end
	for node in pairs(body) do
		if node.sleepers then
			Offer(node)
		elseif not node.air and not node.dead then
			Consider(node)
		end
	end
	local list, seen = {}, {}
	for _, s in ipairs(near) do
		list[#list + 1], seen[s.node] = s.node, true
	end
	for _ = 1, math.min(SEEDS_RANDOM, #pool) do
		local node = pool[math.random(#pool)]
		if not seen[node] then list[#list + 1], seen[node] = node, true end
	end
	return list
end

local function WeightAt(expanded)
	local stage = math.min(WEIGHT_STEPS, math.floor(expanded / WEIGHT_RAMP * WEIGHT_STEPS))
	return WEIGHT_START + (WEIGHT_END - WEIGHT_START) * stage / WEIGHT_STEPS
end

-- New weight: everything still waiting gets scored again and the heap rebuilt. Stale copies of a point
-- (pushed again when a shorter way to it turned up) and already-finished points are dropped on the way.
local function Reweigh(plan, weight)
	plan.weight = weight
	local old, heap, kept = plan.heap, {}, {}
	for _, q in ipairs(old) do
		if not q.closed and not kept[q] then
			kept[q] = true
			q.f = q.g + q.h * weight
			Push(heap, q)
		end
	end
	plan.heap = heap
end

function ENT:StartPlan(target, now)
	local heap, seen = {}, {}
	local plan = { heap = heap, seen = seen, target = Vector(target.x, target.y, target.z), expanded = 0, weight = WeightAt(0) }
	plan.seeds = Seeds(self:Connected(now), target)
	for _, node in ipairs(plan.seeds) do
		local p = { pos = node.pos, normal = node.normal, g = 0 }
		p.h = node.pos:Distance(target)
		p.f = p.h * plan.weight
		local key = Key(p.pos, p.normal)
		if not seen[key] then
			seen[key] = p
			Push(heap, p)
			if not plan.closest or p.h < plan.closest.h then plan.closest = p end
		end
	end
	self.NavTried = now
	if not plan.closest then return end
	self.Plan = plan
	self.NavLockUntil = now + LOCK_TIME
end

local function Goal(p, target)
	return p.h < GOAL_REACH and Clear(p.pos, p.normal, target)
end

-- Where the face one point is on meets the face the next one is on: the crease of an inside corner or the
-- lip of an outside one. The two planes cross along a line; the corner is the bit of that line nearest the
-- two points. Its normal splits the two faces, so the mat coming off either side counts as touching it.
local function Corner(a, b)
	local n1, n2 = a.normal, b.normal
	local c = n1:Dot(n2)
	local det = 1 - c * c
	if det < 0.05 then return end
	local h1, h2 = n1:Dot(a.pos), n2:Dot(b.pos)
	local origin = n1 * ((h1 - h2 * c) / det) + n2 * ((h2 - h1 * c) / det)
	local along = n1:Cross(n2):GetNormalized()
	local mid = (a.pos + b.pos) * 0.5
	local pos = origin + along * (mid - origin):Dot(along)
	if pos:DistToSqr(mid) > CORNER_FAR * CORNER_FAR then return end
	local normal = (n1 + n2):GetNormalized()
	-- There has to be something solid right there, or the planes only meet in thin air (a gap, a ledge
	-- with nothing under the line) and a point there would hang the front off nothing.
	local tr = util.TraceLine({ start = pos + normal * CORNER_PROBE, endpos = pos - normal * CORNER_PROBE, mask = MASK })
	if not tr.Hit or tr.StartSolid then return end
	return { pos = pos, normal = normal, corner = true, exit = n2 }
end

-- Whether a step the search took really stays on the surface. With steps this long, the outside-edge wrap
-- in Mat:Walk can carry straight over the top of a thin wall and land on the floor or face on the far side,
-- which puts a waypoint through the wall. A real step either has open air between its two ends (flat, or an
-- inside corner), or bends over a lip that is actually there, with open air on both legs of the bend.
local function Joined(a, b)
	if Clear(a.pos, a.normal, b.pos, b.normal) then return true end
	local c = Corner(a, b)
	return c ~= nil and Clear(a.pos, a.normal, c.pos, c.normal) and Clear(c.pos, c.normal, b.pos, b.normal)
end

-- Walks the found points back to the mat, puts a point on every corner it goes round, then drops every
-- point that can be seen past on the same face, so the front grows in long straight runs instead of
-- zigzagging through every probe. Corners are never smoothed away: rounding them is the hard part.
local function Unwind(last)
	local back = {}
	local p = last
	while p do
		back[#back + 1] = p
		p = p.from
	end
	local raw = {}
	for i = #back, 1, -1 do
		local q = back[i]
		local prev = raw[#raw]
		if prev and prev.normal:Dot(q.normal) < BEND then
			local corner = Corner(prev, q)
			if corner then raw[#raw + 1] = corner end
		end
		raw[#raw + 1] = q
	end
	local out, i = {}, 1
	while i < #raw do
		local j = math.min(#raw, i + SMOOTH_SPAN)
		for k = i + 1, j do
			if raw[k].corner then
				j = k
				break
			end
		end
		while j > i + 1 do
			local a, b = raw[i], raw[j]
			if a.normal:Dot(b.normal) > 0.9 and a.pos:DistToSqr(b.pos) < SMOOTH_LEN * SMOOTH_LEN and Clear(a.pos, a.normal, b.pos, b.normal) then break end
			j = j - 1
		end
		out[#out + 1] = { pos = raw[j].pos, normal = raw[j].normal, corner = raw[j].corner, exit = raw[j].exit }
		i = j
	end
	return out
end

function ENT:FinishPlan(last, now, partial)
	local plan = self.Plan
	self.Plan = nil
	local points = Unwind(last)
	if #points == 0 then return end
	self.Route = { points = points, i = 1, for_ = plan.target, progress = now, partial = partial, probed = plan.probes ~= nil }
	self.NavLockUntil = now + LOCK_TIME
	self.Waypoint, self.GoalStale = nil, true
end

function ENT:FailPlan(now)
	local plan = self.Plan
	self.Plan = nil
	self:NavFailed(plan.target, now, plan.probes ~= nil, plan.seeds)
end

-- Greedy, then the search, then the probes. When the search (or the route it found) comes to nothing, the
-- probes get a go at the same target straight away; only once they've come to nothing too does it wait a bit
-- before starting over.
function ENT:NavFailed(target, now, probed, seeds)
	if not probed and EvilFungus.Setting("nav_probes") > 0 then
		self:StartProbes(target, now, seeds)
		if self.Plan then return end
	end
	self.NavFailFor, self.NavFailUntil = Vector(target.x, target.y, target.z), now + RETRY
end

-- The nearest point still waiting to be looked past, ignoring the starting points on the mat itself.
local function Frontier(heap)
	local best
	for _, q in ipairs(heap) do
		if not q.closed and q.from and (not best or q.h < best.h) then best = q end
	end
	return best
end

-- A few steps of the search each tick, out of the shared budget.
function ENT:StepPlan(now)
	local plan = self.Plan
	if not plan then return end
	if plan.probes then return self:StepProbes(now) end
	local seen, target = plan.seen, plan.target
	local share = EvilFungus.NavShare or EXPANSIONS_PER_TICK
	while share > 0 and (EvilFungus.NavLeft or 0) > 0 do
		share = share - 1
		EvilFungus.NavLeft = EvilFungus.NavLeft - 1
		local weight = WeightAt(plan.expanded)
		if weight ~= plan.weight then Reweigh(plan, weight) end
		local heap = plan.heap
		local p = Pop(heap)
		if not p or plan.expanded >= MAX_NODES then
			-- Out of map or out of patience. If it got somewhere much nearer than the mat already is,
			-- going there is still better than grinding where it is. Where it was still getting somewhere is
			-- the edge it hadn't finished looking past, not the nearest point overall: that's nearly always
			-- the far end of a dead end pressed up against the wall between it and the target, which the
			-- search already filled in and gave up on. Only when there's no edge left at all (everything
			-- reachable looked at) does plain nearest stand.
			local c = Frontier(heap) or plan.closest
			local have = self:Closest(target, true)
			if c and c.from and have and c.h < have.pos:Distance(target) - PARTIAL_GAIN then
				return self:FinishPlan(c, now, true)
			end
			return self:FailPlan(now)
		end
		if not p.closed then
			p.closed = true
			plan.expanded = plan.expanded + 1
			if Goal(p, target) then return self:FinishPlan(p, now, false) end
			local ang = p.normal:Angle()
			local right, up = ang:Right(), ang:Up()
			local step = StepFor(p.h)
			for k = 1, DIRS do
				local a = k / DIRS * math.pi * 2
				local pos, normal = Mat.Walk(nil, p, right * math.cos(a) + up * math.sin(a), step)
				if pos and bit.band(util.PointContents(pos + normal * 2), WET) == 0 then
					local key = Key(pos, normal)
					local g = p.g + p.pos:Distance(pos)
					local old = seen[key]
					if (not old or not old.closed and g < old.g) and Joined(p, { pos = pos, normal = normal }) then
						local q = old or { pos = pos, normal = normal }
						q.g, q.from = g, p
						q.h = q.h or pos:Distance(target)
						q.f = g + q.h * plan.weight
						seen[key] = q
						Push(heap, q)
						if q.h < plan.closest.h then plan.closest = q end
					end
				end
			end
		end
	end
end

-- Whether the mat has actually got to a point. Being near isn't enough: a point just round a corner or on
-- the far face of a thin wall is within reach of the mat stuck on this side, and counting that as reached
-- skipped the route straight past the way round and left the front pushing into the same wall as before.
-- A corner is only rounded once the mat is on the face past it, right at the crease or lip. Mat that has
-- merely got close on the face before it hasn't gone round anything yet.
-- Only the body counts: a cut-off scrap lying on a waypoint hasn't got there, and moving the route on past it
-- left the next point for something with nothing behind it to grow with.
local function Touched(mat, body, p)
	if p.corner then
		return mat:Nearest(p.pos, ON, function(n)
			return body[n] and not n.air
				and (n.normal:Dot(p.exit) > BEND or n.normal:Dot(p.normal) > CORNER_FACING)
				and Clear(n.pos, n.normal, p.pos, p.normal)
		end) ~= nil
	end
	return mat:Nearest(p.pos, ON, function(n)
		return body[n] and not n.air and n.normal:Dot(p.normal) > 0.3 and Clear(n.pos, n.normal, p.pos, p.normal)
	end) ~= nil
end

-- A route point close by and in plain view of the strand nearest it doesn't need growing to: the strand
-- just reaches over and puts one there, if it can pay for it. Corners land on the face past the crease, so
-- they count as rounded. Spaced out so a route can't be crossed faster than growth could manage.
-- Round a corner or over a lip the straight line to the point is cut by the very solid the mat goes round.
-- Where the crease between the strand and the point is real, and both legs of the bend are clear, the strand
-- plants on the crease first and then on the point, so the reach runs over the solid the way growth would
-- instead of cutting through a wall or onto a face round the far side of a lip.
function ENT:LeapTo(p, now)
	if now < (self.LeapAt or 0) then return end
	local body = self:Connected(now)
	local from = self.Mat:Nearest(p.pos, LEAP_RANGE, function(n) return body[n] and not n.air end)
	if not from then return end
	if not Clear(from.pos, from.normal, p.pos, p.normal) then
		-- Both legs of the bend have to be clear, the same check the search makes: one leg alone plants
		-- through a thin wall, or over a lip onto the face round the far side of it.
		if not Joined(from, p) then return end
		local c = Corner(from, p)
		if not c then return end
		-- On the crease first, so the strand follows the solid round the bend instead of cutting the corner.
		local crease = self:Leap(from, c.pos, c.normal, now)
		if not crease then return end
		body[crease] = true
		from = crease
	end
	local node = self:Leap(from, p.pos, p.exit or p.normal, now)
	if not node then return end
	body[node] = true
	self.LeapAt = now + LEAP_GAP / math.max(0.1, EvilFungus.Setting("grow_speed") * EvilFungus.TimeScale())
	return node
end

function ENT:DropRoute()
	if not self.Route then return end
	self.Route, self.Waypoint, self.GoalStale = nil, nil, true
end

-- The point on the route to grow at right now, or nil once there's no route worth following.
-- The second return is true when the target walked off the end of the route, which is worth a fresh look.
function ENT:RoutePoint(now)
	local route, target = self.Route, self.Target
	if not route then return end
	local points = route.points
	if target:DistToSqr(route.for_) > KEEP_MOVED * KEEP_MOVED then
		-- Moved a little and still in plain view of where the route comes out: the route still does.
		-- Otherwise, if where it comes out is still well nearer the target than anything the mat has, it's
		-- still worth finishing: throwing it away and searching again from the stuck front only finds the same
		-- way out, or a worse one, and a partial route never had the target in view in the first place.
		local last = points[#points]
		local have = self:Closest(target, true)
		if target:DistToSqr(route.for_) < MOVED * MOVED and Clear(last.pos, last.normal, target) then
			route.for_ = Vector(target.x, target.y, target.z)
		elseif have and last.pos:Distance(target) < have.pos:Distance(target) - PARTIAL_GAIN then
			route.for_, route.partial = Vector(target.x, target.y, target.z), true
		else
			self:DropRoute()
			return nil, true
		end
	end
	local mat, reached = self.Mat, nil
	local body = self:Connected(now)
	for j = math.min(#points, route.i + LOOKAHEAD), route.i, -1 do
		if Touched(mat, body, points[j]) then
			reached = j
			break
		end
	end
	-- Still getting along it: keep hold of who it's for, or the lock ran out partway down a long route and
	-- the first other person nearby pulled it off before it got anywhere.
	if reached then
		route.i, route.progress, route.skips = reached + 1, now, 0
		self.NavLockUntil = now + LOCK_TIME
	end
	if route.i > #points then return self:DropRoute() end
	if self:LeapTo(points[route.i], now) and Touched(mat, body, points[route.i]) then
		route.i, route.progress, route.skips = route.i + 1, now, 0
		self.NavLockUntil = now + LOCK_TIME
		if route.i > #points then return self:DropRoute() end
	end
	if now - route.progress > POINT_TIMEOUT / EvilFungus.TimeScale() then
		route.skips = (route.skips or 0) + 1
		if route.skips >= POINT_SKIPS then
			self:DropRoute()
			return self:NavFailed(target, now, route.probed)
		end
		route.i, route.progress = route.i + 1, now
		if route.i > #points then return self:DropRoute() end
	end
	return points[route.i].pos
end

-- Past the first point, each stretch of the route is grown from the strand nearest the point before it,
-- so the mat follows the route round instead of whatever bit of it happens to be nearest the next point
-- (often on the wrong side of the very wall the route goes round). The first point has nothing before it,
-- so that one is still grown at from wherever on the mat is nearest.
-- The strand it grows from moves along with each new strand that gets closer to the point.
function ENT:RouteFrom(now)
	local route = self.Route
	if not route or route.i < 2 or route.i > #route.points then return end
	local body = self:Connected(now)
	local from = route.from
	if route.fromFor ~= route.i or not from or from.dead or not body[from] then
		from = BodyNearest(self.Mat, body, route.points[route.i - 1].pos)
		route.from, route.fromFor = from, route.i
	end
	return from
end

-- After growing from the route's strand: a new strand closer to the point takes over. If nothing grew
-- (usually because there's mat there already), it hops onto a strand just ahead that it can see instead.
function ENT:RouteStep(from, node, now)
	local route = self.Route
	if not route or route.from ~= from or route.i > #route.points then return end
	local way = route.points[route.i].pos
	local d2 = from.pos:DistToSqr(way)
	if node then
		if node.pos:DistToSqr(way) < d2 then route.from = node end
		return
	end
	local dir = way - from.pos
	if dir:LengthSqr() < 1 then return end
	dir:Normalize()
	local body = self:Connected(now)
	local ahead = self.Mat:Nearest(from.pos + dir * HOP, HOP, function(n)
		return n ~= from and body[n] and not n.air and n.pos:DistToSqr(way) < d2 and Clear(from.pos, from.normal, n.pos, n.normal)
	end)
	if ahead then route.from = ahead end
end

local function Rotate(v, n, a)
	return v * math.cos(a) + n:Cross(v) * math.sin(a)
end

local function Flat(v, n)
	v = v - n * v:Dot(n)
	if v:LengthSqr() < 1e-4 then return end
	return v:GetNormalized()
end

-- Keeps a heading going the same way when a stride goes round onto another face: into an inside corner it
-- turns up the wall, over a lip it turns down the far side, on the flat it just stays put.
local function Carry(dir, n1, n2)
	local k = dir:Dot(n2)
	return Flat(dir - n2 * k - n1 * k, n2)
end

local function Toward(p, target)
	return Flat(target - p.pos, p.normal)
end

-- Keeps track of whether growing straight at the target is still getting anywhere, and starts looking for
-- a way round once it isn't. Returns the node to steer the body at while a route is being followed.
function ENT:Navigate(goal, now)
	local target = self.Target
	-- The search and the probes each have their own setting; either one on is enough to go looking for a way
	-- round. With the search off, being stuck goes straight to the probes.
	local searching, probing = EvilFungus.Setting("pathfinding") > 0, EvilFungus.Setting("nav_probes") > 0
	if not target or self.Tending or (self.Hunting and (self.Tunnel or 0) > 0) or EvilFungus.Setting("hurtilizer") > 0
		or not searching and not probing then
		self.Plan, self.NavAt, self.NavSince, self.NavKey = nil, nil, nil, nil
		self:DropRoute()
		return
	end

	local point, moved = self:RoutePoint(now)
	if point then
		self.Waypoint = point
		return self:RouteFrom(now) or BodyNearest(self.Mat, self:Connected(now), point) or goal
	end

	-- A search only gets thrown away when the target ends up somewhere else entirely. Someone running about,
	-- or the aim swinging ahead of them, used to scrap it before it could finish; the route it finds still
	-- gets checked against where the target really is once it's being followed.
	if self.Plan then
		-- Whichever kind of looking just got switched off is dropped, and stuck starts over with what's left.
		if target:DistToSqr(self.Plan.target) > PLAN_DROP * PLAN_DROP
			or self.Plan.probes and not probing or not self.Plan.probes and not searching then
			self.Plan = nil
		end
		return
	end

	-- Stuck means the strand nearest the target isn't going anywhere. Only the strand counts, not the target:
	-- someone running around used to keep resetting this and it never looked for a way round. The nearest
	-- strand has to be new growth to count as moving, or the nearest one just changing over to some old bit of
	-- mat as the target circles would look like progress too.
	if not goal then return end
	local d = goal.pos:Distance(target)
	-- Going after something new starts the clock again, so it gets a fair go at growing straight there
	-- before it's judged stuck. Who or what it's after, not where they've walked to.
	local key = self.Hunting and self.Prey or self.Carrion or self.TargetUntil
	if key ~= self.NavKey then
		self.NavKey, self.NavAt, self.NavSince = key, goal.pos, now
		if not moved then return end
	end
	if not self.NavAt or goal.pos:DistToSqr(self.NavAt) > GAIN * GAIN and (goal.born or 0) > self.NavSince then
		self.NavAt, self.NavSince = goal.pos, now
		if not moved then return end
	end
	if d < NEAR then return end
	if self.NavFailFor and now < self.NavFailUntil and target:DistToSqr(self.NavFailFor) < MOVED * MOVED then return end
	if now - (self.NavTried or -math.huge) < COOLDOWN then return end
	if moved or now - self.NavSince > STALL / EvilFungus.TimeScale() then
		if searching then
			self:StartPlan(target, now)
		else
			self:StartProbes(target, now)
			if not self.Plan then self.NavFailFor, self.NavFailUntil = Vector(target.x, target.y, target.z), now + RETRY end
		end
	end
end

-- While it's searching or following what it found, it doesn't drop who it's after for someone else, unless
-- they walk onto the mat. Flipping between two people used to throw away every search halfway through.
function ENT:PreyLocked(now)
	if EvilFungus.Setting("pathfinding") <= 0 and EvilFungus.Setting("nav_probes") <= 0 then return false end
	return (self.Plan ~= nil or self.Route ~= nil) and now < (self.NavLockUntil or 0)
end

-- Starts from the same strands the search did (handed over when it failed, or picked the same way if it was
-- the route that came to nothing), a few feelers fanned out from each.
function ENT:StartProbes(target, now, seeds)
	self.NavTried = now
	seeds = seeds or Seeds(self:Connected(now), target)
	if #seeds == 0 then return end
	local plan = { target = Vector(target.x, target.y, target.z), probes = {}, expanded = 0, at = 1, seen = {} }
	for i, node in ipairs(seeds) do
		local start = { pos = node.pos, normal = node.normal, g = 0, h = node.pos:Distance(target) }
		if not plan.closest or start.h < plan.closest.h then plan.closest = start end
		local base = Toward(start, target) or node.normal:Angle():Right()
		-- Every other strand's fan is turned half a gap, so neighbouring strands don't send theirs out along
		-- the same lines.
		local offset = i % 2 == 0 and math.pi / PROBE_DIRS or 0
		for k = 0, PROBE_DIRS - 1 do
			local a = (k / PROBE_DIRS * math.pi * 2 + offset) % (math.pi * 2)
			-- A feeler that set off to one side keeps dodging to that side when something's in the way, so
			-- the two halves of the fan go round opposite sides of whatever it's stuck behind.
			plan.probes[#plan.probes + 1] = { tip = start, dir = Rotate(base, node.normal, a), side = a <= math.pi and 1 or -1, strides = 0 }
		end
	end
	self.Plan = plan
	self.NavLockUntil = now + LOCK_TIME
end

-- One stride of one feeler at a time, taking turns, out of the shared budget.
function ENT:StepProbes(now)
	local plan = self.Plan
	local target, probes = plan.target, plan.probes
	local share = EvilFungus.NavShare or EXPANSIONS_PER_TICK
	while share > 0 and (EvilFungus.NavLeft or 0) > 0 do
		share = share - 1
		EvilFungus.NavLeft = EvilFungus.NavLeft - 1
		local probe
		for _ = 1, #probes do
			local cand = probes[plan.at]
			plan.at = plan.at % #probes + 1
			if not cand.dead then
				probe = cand
				break
			end
		end
		if not probe or plan.expanded >= PROBE_BUDGET then
			local c, have = plan.closest, self:Closest(target, true)
			if c and c.from and have and c.h < have.pos:Distance(target) - PARTIAL_GAIN then
				return self:FinishPlan(c, now, true)
			end
			return self:FailPlan(now)
		end
		plan.expanded = plan.expanded + 1
		local p = probe.tip
		local dir = Flat(probe.dir, p.normal) or probe.dir
		local want = Toward(p, target)
		if want then
			local turn = PROBE_TURN_MIN + (PROBE_TURN_MAX - PROBE_TURN_MIN) * math.min(1, probe.strides / PROBE_TURN_RAMP)
			local ang = math.acos(math.Clamp(dir:Dot(want), -1, 1))
			local sign = p.normal:Cross(dir):Dot(want) >= 0 and 1 or -1
			dir = Rotate(dir, p.normal, sign * math.min(ang, turn))
		end
		local step, went = StepFor(p.h), nil
		for _, k in ipairs(DODGE) do
			local d = Rotate(dir, p.normal, k * probe.side * math.pi / 4)
			local pos, normal = Mat.Walk(nil, p, d, step)
			if pos and bit.band(util.PointContents(pos + normal * 2), WET) == 0 then
				-- Ground another feeler already covered: dodge it, or stop if there's nowhere new to go.
				local key = Key(pos, normal)
				if not plan.seen[key] then
					local q = { pos = pos, normal = normal, from = p }
					if Joined(p, q) then
						plan.seen[key] = true
						q.g, q.h = p.g + p.pos:Distance(pos), pos:Distance(target)
						probe.tip, probe.dir = q, Carry(d, p.normal, normal) or Flat(d, normal) or d
						probe.strides = probe.strides + 1
						went = q
						break
					end
				end
			end
		end
		if not went then
			probe.dead = true
		else
			if went.h < plan.closest.h then plan.closest = went end
			if Goal(went, target) then return self:FinishPlan(went, now, false) end
			if probe.strides >= PROBE_MAX_STRIDES then probe.dead = true end
		end
	end
end

local PROBE = Color(140, 255, 140)
local ROUTE = Color(0, 200, 255)
local PLAN = Color(0, 90, 140)
local CORNER = Color(255, 220, 0)

function ENT:DebugNav(life)
	local route = self.Route
	if route then
		local prev
		for i, p in ipairs(route.points) do
			local at = p.pos + p.normal * 3
			if prev then debugoverlay.Line(prev, at, life, i <= route.i and ROUTE or PLAN, true) end
			debugoverlay.Cross(at, i == route.i and 10 or p.corner and 7 or 4, life, p.corner and CORNER or route.probed and PROBE or ROUTE, true)
			prev = at
		end
	end
	local plan = self.Plan
	if plan and plan.closest then
		debugoverlay.Cross(plan.closest.pos, 8, life, PLAN, true)
	end
	if plan and plan.probes then
		for _, probe in ipairs(plan.probes) do
			if not probe.dead then debugoverlay.Cross(probe.tip.pos, 3, life, PROBE, true) end
		end
	end
end
