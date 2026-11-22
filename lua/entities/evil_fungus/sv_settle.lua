local Mat = EvilFungus.Mat

local FOLD_INTERVAL = { 2, 0.5 }
local FOLDS = { 12, 128 }
local AGE = 30
local GROW_MASS = 1
local WAKE_RADIUS = 128
local FOOD_WAKE = 64
local KEEP_CLEAR = 96
local ROUSE_INTERVAL = 0.1
local FLAT = 16
local BOX_PAD = Vector(256, 256, 256)
-- Settled mat keeps its strands asleep (still drawn, left out of every calculation) until the client is
-- drawing this many times the mat size. Past that, settling throws the strands away for a plain patch.
local DRAWN = 4
-- Around the stretch of route being grown along. A route that starts on (or runs over) settled mat can't
-- be grown along or counted as reached, since the patches cover the spots the points sit on.
local ROUTE_WAKE = 64
-- Settled patches in a straight line on the same flat surface merge into runs of up to this many, and at
-- most so many runs are made a pass.
local RUN_MAX = 8
local RUNS = { 8, 64 }
local RUN_FLAT = 12
local RUN_FACING = 0.95
-- Only so many settled patches are looked at for merging in one pass; the cursor carries on next pass.
local MERGE_SCAN = 256
-- Which two axes lie along a surface facing each way (Mat.Bucket: up, down, +x, -x, +y, -y).
local ALONG = { [0] = { 1, 2 }, [1] = { 1, 2 }, [2] = { 2, 3 }, [3] = { 2, 3 }, [4] = { 1, 3 }, [5] = { 1, 3 } }

function ENT:Stirring()
	local list = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then list[#list + 1] = { ply:GetPos(), WAKE_RADIUS } end
	end
	for ent in pairs(EvilFungus.Creatures) do
		if IsValid(ent) then list[#list + 1] = { ent:GetPos(), WAKE_RADIUS } end
	end
	for ent in pairs(EvilFungus.Foods) do
		if IsValid(ent) then list[#list + 1] = { ent:GetPos(), FOOD_WAKE } end
	end
	for _, crawler in ipairs(ents.FindByClass("evil_crawler")) do list[#list + 1] = { crawler:GetPos(), WAKE_RADIUS } end
	local route = self.Route
	if route then
		for j = math.max(1, route.i - 1), math.min(#route.points, route.i + 1) do
			list[#list + 1] = { route.points[j].pos, ROUTE_WAKE }
		end
		if route.from and not route.from.dead then list[#list + 1] = { route.from.pos, ROUTE_WAKE } end
	end
	return list
end

function ENT:Rouse(now)
	local mat = self.Mat
	if not next(mat.settled) or not mat.mins or now < (self.NextRouse or 0) then return end
	self.NextRouse = now + ROUSE_INTERVAL
	local mins, maxs = mat.mins - BOX_PAD, mat.maxs + BOX_PAD
	for _, s in ipairs(self:Stirring()) do
		if s[1]:WithinAABox(mins, maxs) then mat:Wake(s[1], s[2], now) end
	end
end

local function Loose(self, mat, node, now, age)
	return not node.air and not node.burn and not node.heat and not mat.woven[node] and node.m < GROW_MASS
		and now - (node.born or 0) > age and node ~= self.Goal and node ~= self.PreyNode and not (self.Sources and self.Sources[node])
end

local function Key(cell, bucket)
	return cell * 8 + bucket
end

local function Flat(list)
	local first = list[1]
	local px, py, pz = first.x, first.y, first.z
	local nx, ny, nz = first.normal:Unpack()
	local flat = {}
	for _, node in ipairs(list) do
		if math.abs((node.x - px) * nx + (node.y - py) * ny + (node.z - pz) * nz) <= FLAT then flat[#flat + 1] = node end
	end
	return flat
end

function ENT:Settling(now)
	local hurt = EvilFungus.Setting("hurtilizer")
	if hurt <= 0 and EvilFungus.Setting("settle") <= 0 then return end
	if now < (self.NextFold or 0) then return end
	self.NextFold = now + Lerp(hurt, FOLD_INTERVAL[1], FOLD_INTERVAL[2])
	local age, most = AGE * (1 - hurt), math.Round(Lerp(hurt, FOLDS[1], FOLDS[2]))
	local mat = self.Mat
	local groups, blocked = {}, {}
	for _, node in pairs(mat.nodes) do
		local cell = Mat.FeltCell(node.x, node.y, node.z)
		if not node.bucket then node.bucket = Mat.Bucket(node.normal) end
		local key = not node.felt and not node.air and Key(cell, node.bucket)
		if key and not blocked[key] then
			if Loose(self, mat, node, now, age) then
				local g = groups[key]
				if not g then
					g = { cell = cell, list = {} }
					groups[key] = g
				end
				g.list[#g.list + 1] = node
			else
				blocked[key] = true
				groups[key] = nil
			end
		end
	end

	local stirring = self:Stirring()
	local folds = 0
	local Net = EvilFungus.Net
	local keep = Net and Net.count < DRAWN * EvilFungus.Setting("max_nodes")
	for key, g in pairs(groups) do
		if not blocked[key] then
			local first = g.list[1]
			local clear = true
			for _, s in ipairs(stirring) do
				local r = s[2] + KEEP_CLEAR + Mat.FELT
				if s[1]:DistToSqr(first.pos) < r * r then
					clear = false
					break
				end
			end
			if clear then
				self:Opened(mat:Fold(Flat(g.list), g.cell, now, keep))
				folds = folds + 1
				if folds >= most then break end
			end
		end
	end
	if folds > 0 then self.GoalStale = true end
	self:Merging(now, stirring, age, math.Round(Lerp(hurt, RUNS[1], RUNS[2])))
end

local function GridKey(bucket, c)
	return ((c[1] + 512) * 1048576 + (c[2] + 512) * 1024 + (c[3] + 512)) * 8 + bucket
end

local function Lined(a, b)
	return a.normal:Dot(b.normal) > RUN_FACING and math.abs((b.pos - a.pos):Dot(a.normal)) <= RUN_FLAT and Mat.Reaches(a, b)
end

-- Straight runs of settled patches, side by side on the same flat face, fold into one run each.
function ENT:Merging(now, stirring, age, most)
	local mat = self.Mat
	local at, grid = {}, {}
	-- Walk a slice of the settled patches each pass instead of the whole tree. The cursor wraps, and a
	-- removed key just resets it, so no patch starves and no pass goes unbounded.
	local scanned, start, cursor = 0, self.MergeAt, self.MergeAt
	local wrapped = false
	while scanned < MERGE_SCAN do
		local ok, node = pcall(next, mat.settled, cursor)
		if not ok then
			cursor, start, node = nil, nil, next(mat.settled)
		end
		if node == nil then
			if not start or wrapped then break end
			wrapped, cursor = true, nil
			node = next(mat.settled)
			if node == nil then break end
		end
		if wrapped and node == start then break end
		cursor = node
		scanned = scanned + 1
		if node.sleepers and not node.run and not node.burn and not node.heat and not mat.woven[node]
			and now - (node.born or 0) > age and node ~= self.Goal and node ~= self.PreyNode and not (self.Sources and self.Sources[node]) then
			local clear = true
			for _, s in ipairs(stirring) do
				local r = s[2] + KEEP_CLEAR + Mat.FELT
				if s[1]:DistToSqr(node.pos) < r * r then
					clear = false
					break
				end
			end
			if clear then
				local c = { math.floor(node.x / Mat.FELT), math.floor(node.y / Mat.FELT), math.floor(node.z / Mat.FELT) }
				local key = GridKey(node.bucket, c)
				if not grid[key] then
					grid[key], at[node] = node, c
				end
			end
		end
	end
	self.MergeAt = cursor
	if not next(at) then return end

	local function Next(node, axis, step)
		local c = at[node]
		local n = { c[1], c[2], c[3] }
		n[axis] = n[axis] + step
		return grid[GridKey(node.bucket, n)]
	end

	local used, made = {}, 0
	for _, axis in ipairs({ 1, 2, 3 }) do
		for node in pairs(at) do
			local along = ALONG[node.bucket]
			if not used[node] and (along[1] == axis or along[2] == axis) then
				local prev = Next(node, axis, -1)
				-- Only start from the front end of a line, so each line is taken in one go.
				if not (prev and not used[prev] and Lined(prev, node)) then
					local run, last = { node }, node
					while #run < RUN_MAX do
						local nxt = Next(last, axis, 1)
						if not nxt or used[nxt] or not Lined(last, nxt) then break end
						run[#run + 1], last = nxt, nxt
					end
					if #run >= 2 then
						for _, p in ipairs(run) do used[p] = true end
						local merged = mat:Fold(run, node.felt, now, true)
						merged.run = true
						made = made + 1
						if made >= most then
							self.GoalStale, self.MergeAt = true, cursor
							return
						end
					end
				end
			end
		end
	end
	if made > 0 then self.GoalStale = true end
end
