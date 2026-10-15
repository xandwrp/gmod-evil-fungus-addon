local MAT = CreateMaterial("evil_fungus_strand", "UnlitGeneric", {
	["$basetexture"] = "vgui/white",
	["$vertexcolor"] = 1,
	["$nocull"] = 1,
})

local LEVELS = 15
local SEGMENTS = 2
local ROOT_SIDES = 4
local BODY_SIDES = 6
local R_THIN, R_THICK = 0.5, 3.2
local TAPER = 0.7
local LIFT = 0.45
local BEND = 0.35
local WIGGLE = 0.12
local DRAW_RANGE = 6000
local BUILD_BUDGET = 400
local MAX_CHUNK_EDGES = 1500
local BODY_BATCH = 200
local BODY_NODES = 500
local BODY_LOD = { { 1200, 6, 2 }, { 3000, 4, 1 }, { math.huge, 3, 1 } }
local BODY_R = 2.2
local BODY_SHOW = 6
local BODY_GONE = 0.01
local PULSE, PULSE_RATE, PULSE_SPREAD = 0.15, 2.5, 0.9
local SHADE_LOW = 0.55

local COST_SMOOTH = 0.05
local cv_cost = CreateClientConVar("evil_fungus_cost", "0", true, false, "Show how many milliseconds a frame the fungus takes to draw")

EvilFungus.Cost = EvilFungus.Cost or {}

-- Milliseconds this part took, smoothed over the last few dozen frames.
function EvilFungus.Measure(name, since)
	local t = SysTime()
	local cost = EvilFungus.Cost
	cost[name] = Lerp(COST_SMOOTH, cost[name] or 0, (t - since) * 1000)
	return t
end

local ROOT = { 165, 155, 135 }
local VEIN = { 205, 180, 115 }
local BODY_THIN = { 205, 150, 80 }
local BODY_THICK = { 160, 75, 40 }

local function Hash(i)
	local x = math.sin(i * 12.9898) * 43758.5453
	return x - math.floor(x)
end

local function Light(node)
	local l = node.light
	if l then return l end
	local c = render.ComputeLighting(node.pos + node.normal * 3, node.normal)
	l = math.min(1.5, 0.1 + math.sqrt((c.x + c.y + c.z) / 3) * 1.25)
	node.light = l
	return l
end

local trig = {}
local function Trig(sides)
	local t = trig[sides]
	if not t then
		t = { c = {}, s = {} }
		for k = 0, sides - 1 do
			local a = (k + 0.5) / sides * math.pi * 2
			t.c[k], t.s[k] = math.cos(a), math.sin(a)
		end
		trig[sides] = t
	end
	return t
end

local scratch = Vector()
local rx, ry, rz, rs = { {}, {} }, { {}, {} }, { {}, {} }, { {}, {} }

local function Vert(ring, k, cr, cg, cb)
	scratch:SetUnpacked(rx[ring][k], ry[ring][k], rz[ring][k])
	mesh.Position(scratch)
	local s = rs[ring][k]
	mesh.Color(math.min(255, cr * s), math.min(255, cg * s), math.min(255, cb * s), 255)
	mesh.AdvanceVertex()
end

-- One strand as a short tube bowed around corners and wavering a little, radius ra at its old end and rb at its new one.
local function Tube(e, ra, rb, sides, cr, cg, cb, segments)
	segments = segments or SEGMENTS
	local a, b = e.a, e.b
	local na, nb = a.normal, b.normal
	local la, lb = Light(a), Light(b)
	local ax, ay, az = a.pos.x + na.x * ra * LIFT, a.pos.y + na.y * ra * LIFT, a.pos.z + na.z * ra * LIFT
	local bx, by, bz = b.pos.x + nb.x * rb * LIFT, b.pos.y + nb.y * rb * LIFT, b.pos.z + nb.z * rb * LIFT

	local ux, uy, uz = na.x + nb.x, na.y + nb.y, na.z + nb.z
	local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
	if ul < 1e-3 then ux, uy, uz, ul = na.x, na.y, na.z, 1 end
	ux, uy, uz = ux / ul, uy / ul, uz / ul

	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	local sx, sy, sz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux
	local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
	if sl > 1e-6 then sx, sy, sz = sx / sl, sy / sl, sz / sl end

	local bend = (1 - na:Dot(nb)) * len * BEND
	local wig = (Hash(e.eid) - 0.5) * 2 * WIGGLE * len
	local cx = (ax + bx) * 0.5 + ux * bend + sx * wig
	local cy = (ay + by) * 0.5 + uy * bend + sy * wig
	local cz = (az + bz) * 0.5 + uz * bend + sz * wig

	local tr = Trig(sides)
	for seg = 0, segments do
		local t = seg / segments
		local o = 1 - t
		local px = ax * o * o + cx * 2 * t * o + bx * t * t
		local py = ay * o * o + cy * 2 * t * o + by * t * t
		local pz = az * o * o + cz * 2 * t * o + bz * t * t
		local tx = (cx - ax) * 2 * o + (bx - cx) * 2 * t
		local ty = (cy - ay) * 2 * o + (by - cy) * 2 * t
		local tz = (cz - az) * 2 * o + (bz - cz) * 2 * t
		local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
		if tl < 1e-6 then tx, ty, tz, tl = 1, 0, 0, 1 end
		tx, ty, tz = tx / tl, ty / tl, tz / tl

		local vx, vy, vz = na.x * o + nb.x * t, na.y * o + nb.y * t, na.z * o + nb.z * t
		local d = vx * tx + vy * ty + vz * tz
		vx, vy, vz = vx - tx * d, vy - ty * d, vz - tz * d
		local vl = math.sqrt(vx * vx + vy * vy + vz * vz)
		if vl < 1e-6 then
			if math.abs(tz) < 0.9 then vx, vy, vz = 0, 0, 1 else vx, vy, vz = 1, 0, 0 end
			d = vx * tx + vy * ty + vz * tz
			vx, vy, vz = vx - tx * d, vy - ty * d, vz - tz * d
			vl = math.sqrt(vx * vx + vy * vy + vz * vz)
		end
		vx, vy, vz = vx / vl, vy / vl, vz / vl
		local wx, wy, wz = ty * vz - tz * vy, tz * vx - tx * vz, tx * vy - ty * vx

		local r = ra * o + rb * t
		local light = la * o + lb * t
		local ring = seg % 2 + 1
		local X, Y, Z, S = rx[ring], ry[ring], rz[ring], rs[ring]
		for k = 0, sides - 1 do
			local c, s = tr.c[k], tr.s[k]
			X[k] = px + (vx * c + wx * s) * r
			Y[k] = py + (vy * c + wy * s) * r
			Z[k] = pz + (vz * c + wz * s) * r
			S[k] = light * (SHADE_LOW + (1 - SHADE_LOW) * math.max(0, c))
		end

		if seg > 0 then
			local prev = 3 - ring
			for k = 0, sides - 1 do
				local k2 = (k + 1) % sides
				Vert(prev, k, cr, cg, cb)
				Vert(prev, k2, cr, cg, cb)
				Vert(ring, k2, cr, cg, cb)
				Vert(ring, k, cr, cg, cb)
			end
		end
	end
end

-- A tube through any list of points, for shapes that aren't mat strands.
local function Polyline(pts, radii, up, sides, cr, cg, cb, light)
	local tr = Trig(sides)
	local n = #pts
	for i = 1, n do
		local p, q = pts[math.max(1, i - 1)], pts[math.min(n, i + 1)]
		local tx, ty, tz = q.x - p.x, q.y - p.y, q.z - p.z
		local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
		if tl < 1e-6 then tx, ty, tz, tl = 1, 0, 0, 1 end
		tx, ty, tz = tx / tl, ty / tl, tz / tl

		local vx, vy, vz = up.x, up.y, up.z
		local d = vx * tx + vy * ty + vz * tz
		vx, vy, vz = vx - tx * d, vy - ty * d, vz - tz * d
		local vl = math.sqrt(vx * vx + vy * vy + vz * vz)
		if vl < 1e-6 then
			if math.abs(tz) < 0.9 then vx, vy, vz = 0, 0, 1 else vx, vy, vz = 1, 0, 0 end
			d = vx * tx + vy * ty + vz * tz
			vx, vy, vz = vx - tx * d, vy - ty * d, vz - tz * d
			vl = math.sqrt(vx * vx + vy * vy + vz * vz)
		end
		vx, vy, vz = vx / vl, vy / vl, vz / vl
		local wx, wy, wz = ty * vz - tz * vy, tz * vx - tx * vz, tx * vy - ty * vx

		local pt, r = pts[i], radii[i]
		local ring = i % 2 + 1
		local X, Y, Z, S = rx[ring], ry[ring], rz[ring], rs[ring]
		for k = 0, sides - 1 do
			local c, s = tr.c[k], tr.s[k]
			X[k] = pt.x + (vx * c + wx * s) * r
			Y[k] = pt.y + (vy * c + wy * s) * r
			Z[k] = pt.z + (vz * c + wz * s) * r
			S[k] = light * (SHADE_LOW + (1 - SHADE_LOW) * math.max(0, c))
		end

		if i > 1 then
			local prev = 3 - ring
			for k = 0, sides - 1 do
				local k2 = (k + 1) % sides
				Vert(prev, k, cr, cg, cb)
				Vert(prev, k2, cr, cg, cb)
				Vert(ring, k2, cr, cg, cb)
				Vert(ring, k, cr, cg, cb)
			end
		end
	end
end

EvilFungus.Strands = {
	Polyline = Polyline, Light = Light, MAT = MAT,
	ROOT = ROOT, VEIN = VEIN, BODY_THIN = BODY_THIN, BODY_THICK = BODY_THICK,
}

local function Radius(e)
	return Lerp(e.level / LEVELS, R_THIN, R_THICK)
end

local function Build(chunk)
	if chunk.mesh then
		chunk.mesh:Destroy()
		chunk.mesh = nil
	end
	if chunk.count <= 0 then
		EvilFungus.Client.chunks[chunk.key] = nil
		return 0
	end

	local list = {}
	for e in pairs(chunk.edges) do
		list[#list + 1] = e
		if #list >= MAX_CHUNK_EDGES then break end
	end

	local im = Mesh(MAT)
	mesh.Begin(im, MATERIAL_QUADS, #list * SEGMENTS * ROOT_SIDES)
	local ok, err = pcall(function()
		for _, e in ipairs(list) do
			local k = e.level / LEVELS
			local tint = 0.9 + 0.2 * Hash(e.eid + 7)
			local r = Radius(e)
			Tube(e, r, r * TAPER, ROOT_SIDES,
				Lerp(k, ROOT[1], VEIN[1]) * tint, Lerp(k, ROOT[2], VEIN[2]) * tint, Lerp(k, ROOT[3], VEIN[3]) * tint)
		end
	end)
	mesh.End()
	if not ok then ErrorNoHalt("Evil Fungus couldn't build a mat chunk: ", err, "\n") end
	chunk.mesh = im
	return #list
end

local function Rebuild()
	local now, budget = RealTime(), BUILD_BUDGET
	for _, chunk in pairs(EvilFungus.Client.chunks) do
		if chunk.due and now >= chunk.due then
			chunk.due = nil
			budget = budget - Build(chunk)
			if budget <= 0 then return end
		end
	end
end

local frame = 0
local lodLists = { {}, {}, {} }
local candidates = {}

local function BodyEdge(e, sides, segments)
	local a, b = e.a, e.b
	local t = RealTime() * PULSE_RATE
	local base = Radius(e)
	local ra = base + BODY_R * math.sqrt(a.shown) * (1 + PULSE * math.sin(t + a.nid * PULSE_SPREAD))
	local rb = base + BODY_R * math.sqrt(b.shown) * (1 + PULSE * math.sin(t + b.nid * PULSE_SPREAD))
	local k = math.Clamp((a.shown + b.shown) / 8, 0, 1)
	Tube(e, ra, rb, sides,
		Lerp(k, BODY_THIN[1], BODY_THICK[1]), Lerp(k, BODY_THIN[2], BODY_THICK[2]), Lerp(k, BODY_THIN[3], BODY_THICK[3]), segments)
end

local function Pick(node, M)
	local b1, b2, b3, s1, s2, s3 = nil, nil, nil, -1, -1, -1
	for _, e in ipairs(node.edges) do
		local other = e.a == node and e.b or e.a
		local score = (M.body[other] and other.shown or 0) + e.level * 0.05
		if score > s1 then
			b3, s3, b2, s2, b1, s1 = b2, s2, b1, s1, e, score
		elseif score > s2 then
			b3, s3, b2, s2 = b2, s2, e, score
		elseif score > s3 then
			b3, s3 = e, score
		end
	end
	return b1, b2, b3
end

local function Queue(list, e)
	if e and e.frame ~= frame then
		e.frame = frame
		list[#list + 1] = e
	end
end

-- Only the heaviest parts of the body, only a few strands out of each, and less detail the further away it is.
local function DrawBody(eye)
	local M = EvilFungus.Client
	local r2, n = DRAW_RANGE * DRAW_RANGE, 0
	for node in pairs(M.body) do
		if node.shown > BODY_GONE then
			local d2 = node.pos:DistToSqr(eye)
			if d2 < r2 then
				n = n + 1
				candidates[n] = node
				node.eyeDist = d2
			end
		end
	end
	for i = #candidates, n + 1, -1 do candidates[i] = nil end
	if n > BODY_NODES then
		table.sort(candidates, function(a, b) return a.shown > b.shown end)
		for i = n, BODY_NODES + 1, -1 do candidates[i] = nil end
		n = BODY_NODES
	end

	frame = frame + 1
	for i = 1, n do
		local node = candidates[i]
		local lod = #BODY_LOD
		for l, band in ipairs(BODY_LOD) do
			if node.eyeDist < band[1] * band[1] then
				lod = l
				break
			end
		end
		local list = lodLists[lod]
		local e1, e2, e3 = Pick(node, M)
		Queue(list, e1)
		Queue(list, e2)
		Queue(list, e3)
	end
	M.bodyDrawn = 0

	for l, list in ipairs(lodLists) do
		local sides, segments = BODY_LOD[l][2], BODY_LOD[l][3]
		M.bodyDrawn = M.bodyDrawn + #list
		for first = 1, #list, BODY_BATCH do
			local last = math.min(#list, first + BODY_BATCH - 1)
			mesh.Begin(MATERIAL_QUADS, (last - first + 1) * segments * sides)
			local ok, err = pcall(function()
				for i = first, last do BodyEdge(list[i], sides, segments) end
			end)
			mesh.End()
			if not ok then
				ErrorNoHalt("Evil Fungus couldn't draw its body: ", err, "\n")
				break
			end
		end
		for i = #list, 1, -1 do list[i] = nil end
	end
end

hook.Add("Think", "EvilFungusRender", function()
	local M = EvilFungus.Client
	local k = math.min(1, FrameTime() * BODY_SHOW)
	for node in pairs(M.body) do
		node.shown = node.shown + (node.target - node.shown) * k
		if node.target <= 0 and node.shown < BODY_GONE then
			node.shown = 0
			M.body[node] = nil
		end
	end
end)

hook.Add("PostDrawOpaqueRenderables", "EvilFungusRender", function(depth, sky, sky3d)
	if depth or sky or sky3d then return end
	local t = SysTime()
	Rebuild()
	t = EvilFungus.Measure("rebuild", t)

	local eye = EyePos()
	local r = DRAW_RANGE + 128
	local r2 = r * r
	render.SetMaterial(MAT)
	for _, chunk in pairs(EvilFungus.Client.chunks) do
		if chunk.mesh and chunk.center:DistToSqr(eye) < r2 then chunk.mesh:Draw() end
	end
	t = EvilFungus.Measure("chunks", t)
	DrawBody(eye)
	EvilFungus.Measure("body", t)
end)

hook.Add("HUDPaint", "EvilFungusCost", function()
	if not cv_cost:GetBool() then return end
	local M, c = EvilFungus.Client, EvilFungus.Cost
	local chunks, strands = 0, 0
	for _, chunk in pairs(M.chunks) do
		chunks = chunks + 1
		strands = strands + chunk.count
	end
	local lines = {
		("rebuilding mat  %.2f ms"):format(c.rebuild or 0),
		("drawing mat     %.2f ms  (%d chunks, %d strands)"):format(c.chunks or 0, chunks, strands),
		("drawing body    %.2f ms  (%d strands)"):format(c.body or 0, M.bodyDrawn or 0),
		("sleepers        %.2f ms"):format(c.sleepers or 0),
	}
	for i, line in ipairs(lines) do
		draw.SimpleText(line, "BudgetLabel", 24, 120 + i * 14, color_white)
	end
end)
