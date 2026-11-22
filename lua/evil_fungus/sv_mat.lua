EvilFungus = EvilFungus or {}

local Mat = {}
Mat.__index = Mat
EvilFungus.Mat = Mat

local CELL = 32
local STEP = 20
local SPACING = 13
local FUSE = 28
local FUSE_CHANCE = 0.5
local LIFT = 4
local MASK = MASK_SOLID_BRUSHONLY
local D_FLOOR = 0.4
local D_MAX = 10
local D_GAIN = 0.06
local D_DECAY = 0.004
local EMPTY = 0.01
local RISE_MIN = 0.1
local FELT = 64
local FELT_HALF = FELT / 2
local FELT_FLAT = 12
local FELT_DROP = 24
local FELT_FACING = 0.5
local FELT_GRID = 4
local FELT_LATTICE = FELT / FELT_GRID
local FELT_SPACING = 8
local FELT_FULL = 10
local SOW_SPACING = 40

Mat.STEP = STEP
Mat.FELT = FELT
Mat.D_FLOOR = D_FLOOR
Mat.D_MAX = D_MAX
Mat.EMPTY = EMPTY
Mat.FUSE = FUSE

function EvilFungus.NewMat()
	return setmetatable({ nodes = {}, count = 0, cells = {}, full = {}, air = {}, burning = {}, woven = {}, wovenCount = 0,
		settled = {}, settledCount = 0, felt = {}, sleeping = 0, nextId = 1 }, Mat)
end

local function Key(ix, iy, iz)
	return (ix + 512) * 1048576 + (iy + 512) * 1024 + (iz + 512)
end

function Mat.Bucket(normal)
	local x, y, z = normal:Unpack()
	local ax, ay, az = math.abs(x), math.abs(y), math.abs(z)
	if az >= ax and az >= ay then return z > 0 and 0 or 1 end
	if ax >= ay then return x > 0 and 2 or 3 end
	return y > 0 and 4 or 5
end

function Mat.FeltCell(x, y, z)
	return Key(math.floor(x / FELT), math.floor(y / FELT), math.floor(z / FELT))
end

local function Place(self, node)
	node.id = self.nextId
	self.nextId = self.nextId + 1
	self.nodes[node.id] = node
	self.count = self.count + 1
	if node.m > EMPTY then self.full[node] = true end
	if node.air then self.air[node] = true end

	local x, y, z = node.x, node.y, node.z
	local key = Key(math.floor(x / CELL), math.floor(y / CELL), math.floor(z / CELL))
	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[node] = true
	node.cell = key

	local mins, maxs = self.mins, self.maxs
	if not mins then
		self.mins, self.maxs = Vector(x, y, z), Vector(x, y, z)
	elseif x < mins.x or y < mins.y or z < mins.z or x > maxs.x or y > maxs.y or z > maxs.z then
		self.mins = Vector(math.min(mins.x, x), math.min(mins.y, y), math.min(mins.z, z))
		self.maxs = Vector(math.max(maxs.x, x), math.max(maxs.y, y), math.max(maxs.z, z))
	end
end

-- Strands never move, so their position is also kept as plain numbers. Reading a Vector costs a call into the engine.
local function Unpack(node)
	node.x, node.y, node.z = node.pos:Unpack()
	node.up = node.normal.z
end

-- A hidden strand is server-only: the client never hears about it or any link to it.
function Mat:Add(pos, normal, height, hidden)
	local node = { pos = pos, normal = normal, m = 0, edges = {}, air = height and true or nil, height = height or 0, born = CurTime(), hidden = hidden or nil }
	Unpack(node)
	Place(self, node)
	if EvilFungus.Net and not hidden then EvilFungus.Net.Node(node) end
	return node
end

-- Takes a strand out of everything the mat works over, without telling the client it's gone.
local function Unplace(self, node)
	local cell = self.cells[node.cell]
	if cell then
		cell[node] = nil
		if next(cell) == nil then self.cells[node.cell] = nil end
	end
	self.full[node], self.air[node], self.burning[node] = nil, nil, nil
	self.nodes[node.id] = nil
	self.count = self.count - 1
end

local function Drop(list, item)
	for i, x in ipairs(list) do
		if x == item then
			table.remove(list, i)
			return
		end
	end
end

local function Has(list, item)
	for _, x in ipairs(list) do
		if x == item then return true end
	end
	return false
end

-- Takes over every strand of another mat, body and all, leaving it empty.
function Mat:Absorb(other)
	for _, node in pairs(other.nodes) do Place(self, node) end
	for node, at in pairs(other.burning) do self.burning[node] = at end
	for node in pairs(other.woven) do self.woven[node] = true end
	self.wovenCount = self.wovenCount + other.wovenCount
	self.settledCount = self.settledCount + other.settledCount
	self.sleeping = (self.sleeping or 0) + (other.sleeping or 0)
	other.sleeping = 0
	for node in pairs(other.settled) do self.settled[node] = true end
	-- Every patch's cell, including patches asleep inside a run, which aren't counted as settled themselves.
	for cell, set in pairs(other.felt) do
		local mine = self.felt[cell] or {}
		for node in pairs(set) do mine[node] = true end
		self.felt[cell] = mine
	end
	other.nodes, other.cells, other.full, other.air, other.burning, other.count = {}, {}, {}, {}, {}, 0
	other.woven, other.wovenCount, other.settled, other.settledCount, other.felt = {}, 0, {}, 0, {}
	other.mins, other.maxs = nil, nil
end

-- Settled mat destroyed outright (rather than woken) takes everything sleeping under it with it: strands
-- are dropped from the client, and patches asleep inside a run take their own strands too.
local function Bury(self, node)
	for _, s in ipairs(node.sleepers) do
		s.asleep, s.patch = nil, nil
		if s.sleepers then
			local set = self.felt[s.felt]
			if set then
				set[s] = nil
				if next(set) == nil then self.felt[s.felt] = nil end
			end
			Bury(self, s)
		else
			self.sleeping = self.sleeping - 1
			if EvilFungus.Net then EvilFungus.Net.Drop(s) end
		end
	end
	node.sleepers = nil
end

-- Tells the client the whole mat is gone: every strand it's drawing, awake or asleep under settled mat
-- (and under patches asleep inside runs), since sleepers aren't in the mat's own list of strands.
function Mat:Forget()
	local Net = EvilFungus.Net
	if not Net then return end
	local function Under(node)
		for _, s in ipairs(node.sleepers) do
			if s.sleepers then Under(s) end
			Net.Drop(s)
		end
	end
	for _, node in pairs(self.nodes) do
		if node.sleepers then Under(node) end
		Net.Drop(node)
	end
end

function Mat:Remove(node)
	if EvilFungus.Net then EvilFungus.Net.Drop(node) end
	local cell = self.cells[node.cell]
	if cell then
		cell[node] = nil
		if next(cell) == nil then self.cells[node.cell] = nil end
	end
	for _, e in ipairs(node.edges) do
		local other = e.a == node and e.b or e.a
		for i, oe in ipairs(other.edges) do
			if oe == e then table.remove(other.edges, i) break end
		end
	end
	self.full[node] = nil
	self.air[node] = nil
	self.burning[node] = nil
	if self.woven[node] then
		self.woven[node] = nil
		self.wovenCount = self.wovenCount - 1
	end
	if node.felt then
		if self.settled[node] then self.settledCount = self.settledCount - 1 end
		self.settled[node] = nil
		local set = self.felt[node.felt]
		if set then
			set[node] = nil
			if next(set) == nil then self.felt[node.felt] = nil end
		end
	end
	self.nodes[node.id] = nil
	self.count = self.count - 1
	node.dead = true
	if node.sleepers and not node.waking then Bury(self, node) end
end

function Mat:Weave(node, catch)
	node.weave = catch
	if self.woven[node] then return end
	self.woven[node] = true
	self.wovenCount = self.wovenCount + 1
end

function Mat:Other(e, node)
	return e.a == node and e.b or e.a
end

function Mat:Linked(a, b)
	for _, e in ipairs(a.edges) do
		if e.a == b or e.b == b then return true end
	end
	return false
end

function Mat:Link(a, b, now, D)
	local e = { a = a, b = b, len = math.max(1, a.pos:Distance(b.pos)), D = D or D_FLOOR, t = now }
	a.edges[#a.edges + 1] = e
	b.edges[#b.edges + 1] = e
	if EvilFungus.Net and not (a.hidden or b.hidden) then EvilFungus.Net.Edge(e) end
	return e
end

function Mat:Conductance(e, now)
	if e.t == now then return e.D end
	if e.D > D_FLOOR then
		e.D = D_FLOOR + (e.D - D_FLOOR) * math.exp(-D_DECAY * (now - e.t))
	end
	e.t = now
	return e.D
end

function Mat:Thicken(e, flux, now)
	e.D = math.min(D_MAX, self:Conductance(e, now) + flux * D_GAIN)
	if EvilFungus.Net then EvilFungus.Net.Touch(e) end
end

function Mat:SetMass(node, m)
	if node.dead then return end
	node.m = m
	self.full[node] = m > EMPTY or nil
end

function Mat:Near(pos, radius, visit)
	local r2 = radius * radius
	local px, py, pz = pos:Unpack()
	local x0, y0, z0 = math.floor((px - radius) / CELL), math.floor((py - radius) / CELL), math.floor((pz - radius) / CELL)
	local x1, y1, z1 = math.floor((px + radius) / CELL), math.floor((py + radius) / CELL), math.floor((pz + radius) / CELL)
	for ix = x0, x1 do
		for iy = y0, y1 do
			for iz = z0, z1 do
				local cell = self.cells[Key(ix, iy, iz)]
				if cell then
					for node in pairs(cell) do
						local dx, dy, dz = node.x - px, node.y - py, node.z - pz
						local d2 = dx * dx + dy * dy + dz * dz
						if d2 <= r2 and visit(node, d2) == false then return end
					end
				end
			end
		end
	end
end

function Mat:Nearest(pos, radius, accept)
	local best, bestD2 = nil, math.huge
	self:Near(pos, radius, function(node, d2)
		if d2 < bestD2 and (not accept or accept(node)) then best, bestD2 = node, d2 end
	end)
	return best, best and math.sqrt(bestD2)
end

local function Trace(from, to)
	local tr = util.TraceLine({ start = from, endpos = to, mask = MASK })
	if not tr.Hit or tr.StartSolid or tr.HitSky or tr.HitNoDraw then return nil, tr end
	return tr
end

-- One step across whatever surface the node is on: straight on, up into an inside corner, or over an outside edge.
function Mat:Walk(node, dir, step)
	step = step or STEP
	local p, n = node.pos, node.normal
	dir = dir - n * dir:Dot(n)
	if dir:LengthSqr() < 1e-6 then return end
	dir:Normalize()

	local lift = p + n * LIFT
	local ahead = lift + dir * step
	local wall, blocked = Trace(lift, ahead)
	if wall then return wall.HitPos, wall.HitNormal end
	if blocked.Hit then return end

	local floor = Trace(ahead, ahead - n * (LIFT + step * 0.6))
	if floor then return floor.HitPos, floor.HitNormal end

	local below = ahead - n * (LIFT + step * 0.5)
	local edge = Trace(below, below - dir * (step * 1.5))
	if edge then return edge.HitPos, edge.HitNormal end
end

function Mat.Facing(a, b)
	return a.normal:Dot(b.normal) > 0.3
end

function Mat.Reaches(a, b)
	return not util.TraceLine({ start = a.pos + a.normal * LIFT, endpos = b.pos + b.normal * LIFT, mask = MASK }).Hit
end

function Mat:Covered(pos, normal)
	local set = next(self.settled) and self.felt[Mat.FeltCell(pos:Unpack())]
	if not set then return false end
	local bucket = Mat.Bucket(normal)
	for node in pairs(set) do
		if node.bucket == bucket and math.abs((pos - node.pos):Dot(node.normal)) < FELT_FLAT then return true end
	end
	return false
end

function Mat:Crowded(pos, normal, spacing)
	if self:Covered(pos, normal) then return true end
	local crowded = false
	self:Near(pos, spacing or SPACING, function(node)
		if node.normal:Dot(normal) > 0.3 then
			crowded = true
			return false
		end
	end)
	return crowded
end

function Mat:Grow(from, dir, now, spacing)
	local pos, normal = self:Walk(from, dir, spacing and spacing * 1.5)
	if not pos or self:Crowded(pos, normal, spacing) then return end
	if bit.band(util.PointContents(pos + normal * 2), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end

	local node = self:Add(pos, normal)
	self:Link(from, node, now)
	self:Near(pos, FUSE, function(other)
		if other ~= node and other ~= from and Mat.Facing(node, other) and not self:Linked(node, other)
			and math.random() < FUSE_CHANCE then
			if Mat.Reaches(node, other) then self:Link(node, other, now) end
		end
	end)
	return node
end

-- Straight to a spot already known to be on a surface and in view, without stepping there.
function Mat:Leap(from, pos, normal, now)
	if self:Crowded(pos, normal) then return end
	if bit.band(util.PointContents(pos + normal * 2), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end
	local node = self:Add(pos, normal)
	self:Link(from, node, now)
	self:Near(pos, FUSE, function(other)
		if other ~= node and other ~= from and Mat.Facing(node, other) and not self:Linked(node, other)
			and math.random() < FUSE_CHANCE and Mat.Reaches(node, other) then
			self:Link(node, other, now)
		end
	end)
	return node
end

-- Straight out into open air, held up by nothing but the strand behind it.
function Mat:Rise(from, dir, now)
	local start = from.air and from.pos or from.pos + from.normal * LIFT
	dir = dir:GetNormalized()
	if not from.air and dir:Dot(from.normal) < RISE_MIN then return end
	local pos = start + dir * STEP
	if util.TraceLine({ start = start, endpos = pos + dir * LIFT, mask = MASK }).Hit then return end
	if self:Crowded(pos, from.normal) then return end
	if bit.band(util.PointContents(pos), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end

	local node = self:Add(pos, from.normal, from.height + 1)
	self:Link(from, node, now)
	return node
end

local function Surface(start, normal, reach)
	local tr = util.TraceLine({ start = start + normal * reach, endpos = start - normal * reach * 1.5, mask = MASK })
	if not tr.Hit or tr.StartSolid or tr.HitSky or tr.HitNoDraw or tr.HitNormal:Dot(normal) < FELT_FACING then return end
	return tr.HitPos, tr.HitNormal
end

-- Folds quiet strands into one patch that stands in for them in everything the mat works out. The same
-- goes one level up: a straight run of patches folds into one run, with the patches asleep inside it.
-- With keep, the strands themselves are only put to sleep: the client goes on drawing them exactly as they
-- were, and the patch standing in for them is hidden. Without it they're gone for good and the client gets
-- the patch instead.
function Mat:Fold(list, cell, now, keep)
	local inside, m, cx, cy, cz, nx, ny, nz = {}, 0, 0, 0, 0, 0, 0, 0
	for _, node in ipairs(list) do
		inside[node] = true
		m = m + node.m
		cx, cy, cz = cx + node.x, cy + node.y, cz + node.z
		local a, b, c = node.normal:Unpack()
		nx, ny, nz = nx + a, ny + b, nz + c
	end
	local n = #list
	local mid, up = Vector(cx / n, cy / n, cz / n), Vector(nx, ny, nz):GetNormalized()
	local pos, normal = Surface(mid, up, FELT_DROP)
	if not pos then
		local best, bestD2 = list[1], math.huge
		for _, node in ipairs(list) do
			local d2 = node.pos:DistToSqr(mid)
			if d2 < bestD2 then best, bestD2 = node, d2 end
		end
		pos, normal = best.pos, best.normal
	end

	local links = {}
	for _, node in ipairs(list) do
		for _, e in ipairs(node.edges) do
			local other = e.a == node and e.b or e.a
			if not inside[other] then links[other] = math.max(links[other] or 0, self:Conductance(e, now)) end
		end
	end
	if keep then
		-- Sleepers keep every link they had, the client keeps drawing them, and the awake strands round the
		-- edge just stop seeing the links back in until they wake.
		for _, node in ipairs(list) do
			for _, e in ipairs(node.edges) do
				local other = e.a == node and e.b or e.a
				if not inside[other] then Drop(other.edges, e) end
			end
		end
		local strands = 0
		for _, node in ipairs(list) do
			Unplace(self, node)
			node.asleep, node.dead, node.m0 = true, true, node.m
			node.m = 0
			if node.felt then
				-- A patch asleep in a run stays in its cell's lookup, so it still covers its ground and
				-- still wakes when something comes near it, but it only counts once, as part of the run.
				if self.settled[node] then
					self.settled[node] = nil
					self.settledCount = self.settledCount - 1
				end
			else
				strands = strands + 1
			end
		end
		self.sleeping = (self.sleeping or 0) + strands
	else
		for _, node in ipairs(list) do self:Remove(node) end
	end

	local felt = self:Felt(pos, normal, cell, n, keep and list or nil)
	if keep then
		for _, node in ipairs(list) do node.patch = felt end
	end
	self:SetMass(felt, m)
	for other, D in pairs(links) do
		if not other.dead then self:Link(felt, other, now, D) end
	end
	return felt
end

-- What actually holds a strand's share of the body: the strand itself, or the patch it's asleep under.
-- Nil once it's really gone.
function Mat.Holder(node)
	while node and node.dead do
		node = node.asleep and node.patch or nil
	end
	return node
end

-- The nearest settled patch whose ground reaches within radius of a spot. A patch sits at the middle of its
-- cell, so it's looked for half a cell further out.
function Mat:NearestPatch(pos, radius, accept)
	local node, d = self:Nearest(pos, radius + FELT_HALF, function(n) return n.felt and (not accept or accept(n)) end)
	return node, d and math.max(0, d - FELT_HALF)
end

function Mat:Felt(pos, normal, cell, folded, sleepers)
	local felt = self:Add(pos, normal, nil, sleepers ~= nil)
	felt.felt, felt.bucket, felt.folded, felt.sleepers = cell, Mat.Bucket(normal), folded, sleepers
	self.settled[felt] = true
	self.settledCount = self.settledCount + 1
	local set = self.felt[cell] or {}
	set[felt] = true
	self.felt[cell] = set
	return felt
end

function Mat:Sow(from, dir, now)
	local n = from.normal
	dir = dir - n * dir:Dot(n)
	if dir:LengthSqr() < 1e-6 then return end
	dir:Normalize()
	local pos, normal = self:Walk(from, dir, FELT)
	if not pos or self:Crowded(pos, normal, SOW_SPACING) then return end
	if bit.band(util.PointContents(pos + normal * 2), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end
	local felt = self:Felt(pos, normal, Mat.FeltCell(pos:Unpack()), FELT_FULL)
	self:Link(from, felt, now)
	return felt
end

function Mat:Bud(felt, dir, now)
	local n = felt.normal
	dir = dir - n * dir:Dot(n)
	if dir:LengthSqr() < 1e-6 then return end
	dir:Normalize()
	local lift = felt.pos + n * LIFT
	local rim = felt.pos + dir * (FELT_HALF - STEP * 0.5)
	if util.TraceLine({ start = lift, endpos = rim + n * LIFT, mask = MASK }).Hit then return end
	local pos, normal = self:Walk({ pos = rim, normal = n }, dir)
	if not pos or self:Crowded(pos, normal) then return end
	if bit.band(util.PointContents(pos + normal * 2), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end
	local node = self:Add(pos, normal)
	self:Link(felt, node, now)
	return node
end

local function Nearest(list, pos)
	local best, bestD2 = nil, math.huge
	for _, node in ipairs(list) do
		local d2 = node.pos:DistToSqr(pos)
		if d2 < bestD2 then best, bestD2 = node, d2 end
	end
	return best
end

-- Brings the strands under a hidden patch back exactly as they were, links and all. Nothing about them
-- changed on the client, so there's nothing to send but whatever new links the patch picked up meanwhile.
local function Rise(self, felt, now)
	local sleepers, m = felt.sleepers, felt.m
	local links = {}
	for _, e in ipairs(felt.edges) do links[#links + 1] = { e.a == felt and e.b or e.a, self:Conductance(e, now) } end
	felt.waking = true
	self:Remove(felt)
	felt.sleepers = nil

	local mine, sum = {}, 0
	for _, s in ipairs(sleepers) do
		mine[s], sum = true, sum + (s.m0 or 0)
	end
	local strands = 0
	for _, s in ipairs(sleepers) do
		s.asleep, s.dead, s.patch = nil, nil, nil
		Place(self, s)
		if s.felt then
			self.settled[s] = true
			self.settledCount = self.settledCount + 1
		else
			strands = strands + 1
		end
	end
	for _, s in ipairs(sleepers) do
		for i = #s.edges, 1, -1 do
			local e = s.edges[i]
			local other = e.a == s and e.b or e.a
			if other.dead and not other.asleep then
				-- Its other end died while this lot slept; the client already lost the link with it.
				table.remove(s.edges, i)
				local Net = EvilFungus.Net
				if Net and e.eid and Net.edges[e.eid] == e then Net.edges[e.eid], Net.dirty[e] = nil, nil end
			elseif not Has(other.edges, e) then
				other.edges[#other.edges + 1] = e
			end
		end
	end
	for _, s in ipairs(sleepers) do
		self:SetMass(s, sum > 0 and m * (s.m0 or 0) / sum or m / #sleepers)
		s.m0 = nil
	end
	-- Anything that grew onto the patch while it slept is joined to the nearest sleeper for real.
	-- A neighbour still asleep is left alone: it has no live mass to give, and linking to it would let
	-- flow push body into a strand the mat treats as dead, losing it at the edge.
	for _, link in ipairs(links) do
		local other = link[1]
		if not other.dead and not other.asleep then
			local joined = false
			for _, e in ipairs(other.edges) do
				if mine[e.a] or mine[e.b] then
					joined = true
					break
				end
			end
			if not joined then self:Link(Nearest(sleepers, other.pos), other, now, link[2]) end
		end
	end
	self.sleeping = self.sleeping - strands
	return sleepers
end

-- Wakes whatever a patch is asleep inside, from the top down, so the patch itself is back in the mat.
local function Rouse(self, node, now)
	local holder = node.asleep and node.patch
	if not holder then return end
	Rouse(self, holder, now)
	if not holder.dead then Rise(self, holder, now) end
end

function Mat:Unfold(felt, now)
	if felt.sleepers then return Rise(self, felt, now) end
	local pos, normal, m = felt.pos, felt.normal, felt.m
	local links = {}
	for _, e in ipairs(felt.edges) do links[#links + 1] = { e.a == felt and e.b or e.a, self:Conductance(e, now) } end
	self:Remove(felt)

	local ang = normal:Angle()
	local right, side = ang:Right(), ang:Up()
	local grid, made = {}, {}
	for i = 1, FELT_GRID do
		grid[i] = {}
		for j = 1, FELT_GRID do
			local off = right * ((i - (FELT_GRID + 1) / 2) * FELT_LATTICE) + side * ((j - (FELT_GRID + 1) / 2) * FELT_LATTICE)
			local p, n = Surface(pos + off, normal, FELT_DROP * 0.5)
			if p and not self:Crowded(p, n, FELT_SPACING) then
				local node = self:Add(p, n)
				grid[i][j] = node
				made[#made + 1] = node
			end
		end
	end
	if #made == 0 then made[1] = self:Add(pos, normal) end

	for i = 1, FELT_GRID do
		for j = 1, FELT_GRID do
			local node = grid[i][j]
			if node then
				local r, u = grid[i + 1] and grid[i + 1][j], grid[i][j + 1]
				if r and Mat.Reaches(node, r) then self:Link(node, r, now) end
				if u and Mat.Reaches(node, u) then self:Link(node, u, now) end
			end
		end
	end

	local seen, parts = {}, {}
	for _, node in ipairs(made) do
		if not seen[node] then
			local part, stack = {}, { node }
			seen[node] = true
			while #stack > 0 do
				local at = table.remove(stack)
				part[#part + 1] = at
				for _, e in ipairs(at.edges) do
					local other = e.a == at and e.b or e.a
					if not seen[other] then
						seen[other] = true
						stack[#stack + 1] = other
					end
				end
			end
			parts[#parts + 1] = part
		end
	end
	for i = 2, #parts do
		local node = parts[i][1]
		self:Link(node, Nearest(parts[1], node.pos), now)
	end

	for _, link in ipairs(links) do
		local other = link[1]
		if not other.dead then self:Link(Nearest(made, other.pos), other, now, link[2]) end
	end
	local share = m / #made
	for _, node in ipairs(made) do self:SetMass(node, share) end
	return made
end

function Mat:Wake(pos, radius, now)
	if not next(self.settled) then return end
	local reach = radius + FELT_HALF
	local r2 = reach * reach
	local px, py, pz = pos:Unpack()
	local x0, y0, z0 = math.floor((px - reach) / FELT), math.floor((py - reach) / FELT), math.floor((pz - reach) / FELT)
	local x1, y1, z1 = math.floor((px + reach) / FELT), math.floor((py + reach) / FELT), math.floor((pz + reach) / FELT)
	local woke
	for ix = x0, x1 do
		for iy = y0, y1 do
			for iz = z0, z1 do
				local set = self.felt[Key(ix, iy, iz)]
				if set then
					for node in pairs(set) do
						if not node.burn and node.pos:DistToSqr(pos) <= r2 then
							woke = woke or {}
							woke[#woke + 1] = node
						end
					end
				end
			end
		end
	end
	if not woke then return end
	-- Only the patches actually in reach wake their strands. Waking one inside a run splits the run back into
	-- its patches; the rest of them settle back into runs on their own.
	for _, node in ipairs(woke) do
		if node.asleep then Rouse(self, node, now) end
		if not node.dead then self:Unfold(node, now) end
	end
	return true
end

local function Push(h, d, v)
	local n = h.n + 1
	h.n = n
	local i = n
	while i > 1 do
		local p = math.floor(i / 2)
		if h.d[p] <= d then break end
		h.d[i], h.v[i] = h.d[p], h.v[p]
		i = p
	end
	h.d[i], h.v[i] = d, v
end

local function Pop(h)
	local n = h.n
	if n == 0 then return end
	local topD, topV = h.d[1], h.v[1]
	local d, v = h.d[n], h.v[n]
	h.d[n], h.v[n] = nil, nil
	n = n - 1
	h.n = n
	local i = 1
	while true do
		local c = i * 2
		if c > n then break end
		if c < n and h.d[c + 1] < h.d[c] then c = c + 1 end
		if h.d[c] >= d then break end
		h.d[i], h.v[i] = h.d[c], h.v[c]
		i = c
	end
	if n > 0 then h.d[i], h.v[i] = d, v end
	return topD, topV
end

-- Graph distance from the sources, by each edge's cost, out to the limit.
-- Stops as soon as stop(node, d) says so; everything nearer than that node is exact, the rest is left unfinished.
function Mat:Distances(sources, cost, limit, stop, owner)
	limit = limit or math.huge
	local dist, h = {}, { n = 0, d = {}, v = {} }
	for node, d in pairs(sources) do
		dist[node] = d
		Push(h, d, node)
	end
	while h.n > 0 do
		local d, node = Pop(h)
		if d <= dist[node] then
			if stop and stop(node, d) then return dist, node, d end
			for _, e in ipairs(node.edges) do
				local other = e.a == node and e.b or e.a
				local nd = d + cost(e)
				if nd <= limit and nd < (dist[other] or math.huge) then
					dist[other] = nd
					if owner then owner[other] = owner[node] end
					Push(h, nd, other)
				end
			end
		end
	end
	return dist
end

for colony in pairs(EvilFungus.Colonies or {}) do
	local mat = colony.Mat
	if mat and not mat.air then mat.air = {} end
	if mat and not mat.burning then mat.burning = {} end
	if mat and not mat.woven then mat.woven, mat.wovenCount = {}, 0 end
	if mat and not mat.settled then mat.settled, mat.felt = {}, {} end
	if mat and not mat.settledCount then mat.settledCount = table.Count(mat.settled) end
	if mat and not mat.sleeping then mat.sleeping = 0 end
	for _, node in pairs(mat and mat.nodes or {}) do
		if not node.x then Unpack(node) end
		node.height = node.height or 0
	end
end
