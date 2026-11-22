-- Lighting is baked into vertex colours; the cubemap on top, masked by the texture's alpha, is the grease.
local function Skin(name, texture, sheen)
	return CreateMaterial(name, "UnlitGeneric", {
		["$basetexture"] = texture,
		["$vertexcolor"] = 1,
		["$nocull"] = 1,
		["$envmap"] = "env_cubemap",
		["$basealphaenvmapmask"] = 1,
		["$envmaptint"] = sheen,
		["$envmapcontrast"] = 1,
		["$envmapsaturation"] = 0.4,
	})
end

local MAT = Skin("evil_fungus_fiber", "evil_fungus/fiber", "[.3 .28 .24]")
local FLESH = Skin("evil_fungus_flesh", "evil_fungus/flesh", "[.75 .7 .72]")

local LEVELS = 15
local SEGMENTS = 2
local ROOT_SIDES = 4
local R_THIN, R_THICK = 0.5, 3.2
local TAPER = 0.7
local LIFT = 0.45
local BEND = 0.35
local WIGGLE = 0.12
local DRAW_RANGE = 6000
local BUILD_MS = 1.5
local MAX_CHUNK_EDGES = 1500
local MAX_CHUNK_QUADS = 8000
local SHAPES_PER_BUILD = 24
local BODY_MS = 1.5
local BODY_NODES = 500
local BODY_CELL = 48
local BODY_PICK = 0.1
local STRAIGHT = 0.3
-- Out to how far, how many sides and bends a strand of body gets, and how often it's rebuilt to pulse.
local BODY_LOD = { { 1200, 6, 2, 0.1 }, { 3000, 4, 1, 0.25 }, { math.huge, 3, 1, 0.5 } }
local BODY_R = 2.2
local BODY_SHOW = 6
local BODY_GONE = 0.01
local PULSE, PULSE_RATE, PULSE_SPREAD = 0.15, 2.5, 0.9
local SHADE_LOW = 0.55
local TEX_STRETCH = 1.4
local WEB_HALF = 40
local WEB_FULL = 10
local WEB_GRID = 2
local WEB_REACH = 16
local WEB_FACING = 0.5
local WEB_LIFT = 0.5
local WEB_VARIANTS = 4
local WEB_INSET = 0.004
local VEIN_SHOWN = 4
local VIEW_SLACK = 16
local STALE_FRAMES = 2

local WEB = CreateMaterial("evil_fungus_web", "UnlitGeneric", {
	["$basetexture"] = "evil_fungus/web",
	["$vertexcolor"] = 1,
	["$alphatest"] = 1,
	["$alphatestreference"] = 0.5,
	["$nocull"] = 1,
})

local COST_SMOOTH = 0.05
local cv_cost = CreateClientConVar("evil_fungus_cost", "0", false, false, "Show how many milliseconds a frame the fungus takes to draw")

EvilFungus.Cost = EvilFungus.Cost or {}

-- Milliseconds this part took, smoothed over the last few dozen frames.
function EvilFungus.Measure(name, since)
	local t = SysTime()
	local cost = EvilFungus.Cost
	cost[name] = Lerp(COST_SMOOTH, cost[name] or 0, (t - since) * 1000)
	return t
end

local ROOT, VEIN, BODY_THIN, BODY_THICK = {}, {}, {}, {}
local PALETTE = {
	{ ROOT, 175, 165, 150 }, { VEIN, 200, 175, 140 }, { BODY_THIN, 200, 185, 180 }, { BODY_THICK, 140, 95, 105 },
}
local tinted

local function Tint()
	local r, g, b = EvilFungus.Settings:Color("color")
	local v = r * 65536 + g * 256 + b
	if v == tinted then return false end
	tinted = v
	for _, p in ipairs(PALETTE) do
		p[1][1], p[1][2], p[1][3] = p[2] * r / 255, p[3] * g / 255, p[4] * b / 255
	end
	return true
end
Tint()

timer.Create("EvilFungusTint", 1, 0, function()
	if not Tint() or not EvilFungus.Client then return end
	for _, node in pairs(EvilFungus.Client.nodes or {}) do node.sheet = nil end
	for _, chunk in pairs(EvilFungus.Client.chunks or {}) do EvilFungus.Client.Stale(chunk, 0) end
	for _, rag in ipairs(ents.FindByClass("prop_ragdoll*")) do
		if rag.EvilFungusMesh then
			rag.EvilFungusMesh:Destroy()
			rag.EvilFungusMesh = nil
		end
	end
end)

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

-- Meshes built before a reload may be in another vertex format, so everything is rebuilt.
for _, chunk in pairs(EvilFungus.Client and EvilFungus.Client.chunks or {}) do
	if chunk.mesh then chunk.mesh:Destroy() end
	if chunk.webMesh then chunk.webMesh:Destroy() end
	if chunk.bodyMesh then chunk.bodyMesh:Destroy() end
	chunk.mesh, chunk.webMesh, chunk.bodyMesh, chunk.bodyBuilt = nil, nil, nil, nil
	EvilFungus.Client.Stale(chunk, 0)
end
for _, cell in pairs(EvilFungus.Client and EvilFungus.Client.bodyCells or {}) do
	if cell.bodyMesh then cell.bodyMesh:Destroy() end
	cell.bodyMesh, cell.bodyBuilt = nil, nil
end
for _, rag in ipairs(ents.FindByClass("prop_ragdoll*")) do
	if rag.EvilFungusMesh then
		rag.EvilFungusMesh:Destroy()
		rag.EvilFungusMesh = nil
	end
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

-- Every ring vertex goes into two to four quads, so its position, normal and colour are worked out once, as the ring is laid.
local rp, rn, rr, rg, rb, rv = { {}, {} }, { {}, {} }, { {}, {} }, { {}, {} }, { {}, {} }, {}
local Position, Normal, TexCoord, Colour, Advance = mesh.Position, mesh.Normal, mesh.TexCoord, mesh.Color, mesh.AdvanceVertex

local function Vert(ring, k, u)
	Position(rp[ring][k])
	Normal(rn[ring][k])
	TexCoord(0, u, rv[ring])
	Colour(rr[ring][k], rg[ring][k], rb[ring][k], 255)
	Advance()
end

-- The texture wraps once around a strand and repeats along it once per circumference, so wrinkles keep their shape on thick and thin.
local function Quads(prev, ring, sides)
	for k = 0, sides - 1 do
		local u, u2 = k / sides, (k + 1) / sides
		local k2 = (k + 1) % sides
		Vert(prev, k, u)
		Vert(prev, k2, u2)
		Vert(ring, k2, u2)
		Vert(ring, k, u)
	end
end

local function Ring(ring, px, py, pz, vx, vy, vz, wx, wy, wz, r, light, tr, sides, cr, cg, cb)
	local P, N, R, G, B = rp[ring], rn[ring], rr[ring], rg[ring], rb[ring]
	for k = 0, sides - 1 do
		local c, s = tr.c[k], tr.s[k]
		local ox, oy, oz = vx * c + wx * s, vy * c + wy * s, vz * c + wz * s
		local p = P[k]
		if not p then
			p = Vector()
			P[k], N[k] = p, Vector()
		end
		p:SetUnpacked(px + ox * r, py + oy * r, pz + oz * r)
		N[k]:SetUnpacked(ox, oy, oz)
		local shade = light * (SHADE_LOW + (1 - SHADE_LOW) * math.max(0, c))
		R[k], G[k], B[k] = math.min(255, cr * shade), math.min(255, cg * shade), math.min(255, cb * shade)
	end
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
	local vScale = 1 / (math.pi * (ra + rb) * TEX_STRETCH)
	local v, lx, ly, lz = Hash(e.eid + 3), ax, ay, az
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

		local ring = seg % 2 + 1
		v = v + math.sqrt((px - lx) ^ 2 + (py - ly) ^ 2 + (pz - lz) ^ 2) * vScale
		lx, ly, lz = px, py, pz
		rv[ring] = v
		Ring(ring, px, py, pz, vx, vy, vz, wx, wy, wz, ra * o + rb * t, la * o + lb * t, tr, sides, cr, cg, cb)
		if seg > 0 then Quads(3 - ring, ring, sides) end
	end
end

-- A tube through any list of points, for shapes that aren't mat strands.
local function Polyline(pts, radii, up, sides, cr, cg, cb, light)
	local tr = Trig(sides)
	local n = #pts
	local rsum = 0
	for i = 1, n do rsum = rsum + radii[i] end
	local vScale = 1 / (2 * math.pi * math.max(0.25, rsum / n) * TEX_STRETCH)
	local v = 0
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

		local pt = pts[i]
		local ring = i % 2 + 1
		if i > 1 then v = v + pt:Distance(pts[i - 1]) * vScale end
		rv[ring] = v
		Ring(ring, pt.x, pt.y, pt.z, vx, vy, vz, wx, wy, wz, radii[i], light, tr, sides, cr, cg, cb)
		if i > 1 then Quads(3 - ring, ring, sides) end
	end
end

EvilFungus.Strands = {
	Polyline = Polyline, Light = Light, MAT = MAT, FLESH = FLESH,
	ROOT = ROOT, VEIN = VEIN, BODY_THIN = BODY_THIN, BODY_THICK = BODY_THICK,
}

local function Radius(e)
	return Lerp(e.level / LEVELS, R_THIN, R_THICK)
end

local function Web(node)
	local web = node.sheet
	if web then return web end
	local n = node.normal
	local ang = n:Angle()
	local spin = Hash(node.nid * 7) * math.pi * 2
	local c, s = math.cos(spin), math.sin(spin)
	local r0, u0 = ang:Right(), ang:Up()
	local right, up = r0 * c + u0 * s, u0 * c - r0 * s
	local half = Lerp(math.min(1, (node.folded or WEB_FULL) / WEB_FULL), WEB_HALF * 0.5, WEB_HALF)
	local variant = node.nid % WEB_VARIANTS
	local ou, ov = (variant % 2) * 0.5, math.floor(variant / 2) * 0.5
	local pts, quads = {}, 0
	for i = 0, WEB_GRID do
		pts[i] = {}
		for j = 0, WEB_GRID do
			local su, sv = i / WEB_GRID, j / WEB_GRID
			local start = node.pos + n * WEB_REACH + (right * (su * 2 - 1) + up * (sv * 2 - 1)) * half
			local tr = util.TraceLine({ start = start, endpos = start - n * WEB_REACH * 2.5, mask = MASK_SOLID_BRUSHONLY })
			if tr.Hit and not tr.StartSolid and not tr.HitSky and tr.HitNormal:Dot(n) > WEB_FACING then
				local lit = render.ComputeLighting(tr.HitPos + tr.HitNormal * 3, tr.HitNormal)
				local l = math.min(1.5, 0.1 + math.sqrt((lit.x + lit.y + lit.z) / 3) * 1.25)
				pts[i][j] = {
					pos = tr.HitPos + tr.HitNormal * WEB_LIFT, normal = tr.HitNormal,
					u = ou + WEB_INSET + su * (0.5 - WEB_INSET * 2), v = ov + WEB_INSET + sv * (0.5 - WEB_INSET * 2),
					r = math.min(255, ROOT[1] * l), g = math.min(255, ROOT[2] * l), b = math.min(255, ROOT[3] * l),
				}
			end
		end
	end
	for i = 0, WEB_GRID - 1 do
		for j = 0, WEB_GRID - 1 do
			if pts[i][j] and pts[i + 1][j] and pts[i + 1][j + 1] and pts[i][j + 1] then quads = quads + 1 end
		end
	end
	web = { pts = pts, quads = quads }
	node.sheet = web
	return web
end

local function WebVert(p)
	Position(p.pos)
	Normal(p.normal)
	TexCoord(0, p.u, p.v)
	Colour(p.r, p.g, p.b, 255)
	Advance()
end

local function Lay(web)
	local pts = web.pts
	for i = 0, WEB_GRID - 1 do
		for j = 0, WEB_GRID - 1 do
			local a, b, c, d = pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1]
			if a and b and c and d then
				WebVert(a)
				WebVert(b)
				WebVert(c)
				WebVert(d)
			end
		end
	end
end

local function Build(chunk)
	if chunk.mesh then
		chunk.mesh:Destroy()
		chunk.mesh = nil
	end
	if chunk.webMesh then
		chunk.webMesh:Destroy()
		chunk.webMesh = nil
	end
	if chunk.count <= 0 then
		EvilFungus.Client.chunks[chunk.key] = nil
		return
	end

	local webs, flat, shaped = {}, 0, 0
	for node in pairs(chunk.patches) do
		local web = node.sheet
		if not web and shaped < SHAPES_PER_BUILD then
			shaped = shaped + 1
			web = Web(node)
		elseif not web then
			chunk.due = RealTime()
		end
		if web and web.quads > 0 and flat + web.quads <= MAX_CHUNK_QUADS then
			webs[#webs + 1] = web
			flat = flat + web.quads
		end
	end
	if flat > 0 then
		local im = Mesh(WEB)
		mesh.Begin(im, MATERIAL_QUADS, flat)
		local ok, err = pcall(function()
			for _, web in ipairs(webs) do Lay(web) end
		end)
		mesh.End()
		if not ok then ErrorNoHalt("Evil Fungus couldn't build a settled chunk: ", err, "\n") end
		chunk.webMesh = im
	end

	local list, quads, tube = {}, 0, SEGMENTS * ROOT_SIDES
	for e in pairs(chunk.edges) do
		if #list >= MAX_CHUNK_EDGES or quads + tube > MAX_CHUNK_QUADS then break end
		if not (e.a.felt or e.b.felt) or e.level >= VEIN_SHOWN then
			list[#list + 1] = e
			quads = quads + tube
		end
	end
	if quads <= 0 then return end

	local im = Mesh(MAT)
	mesh.Begin(im, MATERIAL_QUADS, quads)
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
end

-- Only so long a frame goes on rebuilding the mat. Whatever's left waits for the next one.
local function Rebuild()
	local now, stop = RealTime(), SysTime() + BUILD_MS / 1000
	for _, chunk in pairs(EvilFungus.Client.chunks) do
		if chunk.due and now >= chunk.due then
			chunk.due = nil
			Build(chunk)
			if SysTime() >= stop then return end
		end
	end
end

local pass = {}
local candidates = {}
local cells, cellCount = {}, 0

local function BodyEdge(e, ra, rb, sides, segments)
	local k = math.Clamp((e.a.shown + e.b.shown) / 8, 0, 1)
	Tube(e, ra, rb, sides,
		Lerp(k, BODY_THIN[1], BODY_THICK[1]), Lerp(k, BODY_THIN[2], BODY_THICK[2]), Lerp(k, BODY_THIN[3], BODY_THICK[3]), segments)
end

-- How far a strand bows away from straight at its middle.
local function Bow(e)
	local bow = e.bow
	if bow then return bow end
	local a, b = e.a, e.b
	local len = a.pos:Distance(b.pos)
	bow = 0.5 * ((1 - a.normal:Dot(b.normal)) * len * BEND + math.abs(Hash(e.eid) - 0.5) * 2 * WIGGLE * len)
	e.bow = bow
	return bow
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

-- The body's strands are kept in small cells of their own, so no one rebuild is ever very big.
local function CellFor(e, M)
	local cell = e.bodyCell
	if cell then return cell end
	local a, b = e.a.pos, e.b.pos
	local ix = math.floor((a.x + b.x) * 0.5 / BODY_CELL)
	local iy = math.floor((a.y + b.y) * 0.5 / BODY_CELL)
	local iz = math.floor((a.z + b.z) * 0.5 / BODY_CELL)
	local key = (ix + 512) * 1048576 + (iy + 512) * 1024 + (iz + 512)
	cell = M.bodyCells[key]
	if not cell then
		cell = { list = {}, n = 0, center = Vector((ix + 0.5) * BODY_CELL, (iy + 0.5) * BODY_CELL, (iz + 0.5) * BODY_CELL) }
		M.bodyCells[key] = cell
	end
	e.bodyCell = cell
	return cell
end

local function Queue(e, M)
	if not e or e.pass == pass then return 0 end
	e.pass = pass
	local cell = CellFor(e, M)
	if cell.pass ~= pass then
		cell.pass = pass
		cell.n = 0
	end
	cell.n = cell.n + 1
	cell.list[cell.n] = e
	return 1
end

local function Lod(d2)
	for _, band in ipairs(BODY_LOD) do
		if d2 < band[1] * band[1] then return band end
	end
	return BODY_LOD[#BODY_LOD]
end

local function ForgetBody(cell)
	if cell.bodyMesh then
		cell.bodyMesh:Destroy()
		cell.bodyMesh = nil
	end
	cell.bodyBuilt = nil
end

local bodyRa, bodyRb, bodySegments = {}, {}, {}

local function BakeBody(cell)
	ForgetBody(cell)
	cell.bodyBuilt = RealTime()
	local list, n = cell.list, cell.n
	for i = #list, n + 1, -1 do list[i] = nil end
	if n == 0 then return end

	-- A strand whose bow would be lost inside its own thickness is drawn straight.
	local sides, most = cell.lod[2], cell.lod[3]
	local t = RealTime() * PULSE_RATE * EvilFungus.Setting("pulse_speed")
	local quads = 0
	for i = 1, n do
		local e = list[i]
		local a, b = e.a, e.b
		local base = Radius(e)
		local ra = base + BODY_R * math.sqrt(a.shown) * (1 + PULSE * math.sin(t + a.nid * PULSE_SPREAD))
		local rb = base + BODY_R * math.sqrt(b.shown) * (1 + PULSE * math.sin(t + b.nid * PULSE_SPREAD))
		local segments = most > 1 and Bow(e) < STRAIGHT * math.min(ra, rb) and 1 or most
		bodyRa[i], bodyRb[i], bodySegments[i] = ra, rb, segments
		quads = quads + sides * segments
	end

	local im = Mesh(FLESH)
	mesh.Begin(im, MATERIAL_QUADS, quads)
	local ok, err = pcall(function()
		for i = 1, n do BodyEdge(list[i], bodyRa[i], bodyRb[i], sides, bodySegments[i]) end
	end)
	mesh.End()
	if not ok then ErrorNoHalt("Evil Fungus couldn't build its body: ", err, "\n") end
	cell.bodyMesh = im
end

-- Which strands are body worth drawing, and where. What the server says about the body only changes a few times a second.
local function Select(eye, M)
	local r2, n = DRAW_RANGE * DRAW_RANGE, 0
	for node in pairs(M.body) do
		if node.shown > BODY_GONE then
			local d2 = node.pos:DistToSqr(eye)
			if d2 < r2 then
				n = n + 1
				candidates[n] = node
				node.d2 = d2
			end
		end
	end
	for i = #candidates, n + 1, -1 do candidates[i] = nil end
	if n > BODY_NODES then
		table.sort(candidates, function(a, b) return a.d2 < b.d2 end)
		for i = n, BODY_NODES + 1, -1 do candidates[i] = nil end
		n = BODY_NODES
	end

	pass = {}
	local queued = 0
	for i = 1, n do
		local e1, e2, e3 = Pick(candidates[i], M)
		queued = queued + Queue(e1, M) + Queue(e2, M) + Queue(e3, M)
	end
	M.bodyDrawn = queued

	for i = 1, cellCount do
		if cells[i].pass ~= pass then ForgetBody(cells[i]) end
		cells[i] = nil
	end
	local count = 0
	for _, cell in pairs(M.bodyCells) do
		if cell.pass == pass then
			count = count + 1
			cells[count] = cell
			cell.lod = Lod(cell.center:DistToSqr(eye))
		end
	end
	cellCount = count
	table.sort(cells, function(a, b) return (a.bodyBuilt or -1) < (b.bodyBuilt or -1) end)
end

local nextPick, baked = 0, -1

-- The body is the only part that moves. Each cell is rebuilt to pulse every so often, nearer ones more often,
-- stalest first and only for so long a frame.
local function DrawBody(eye, main)
	local M = EvilFungus.Client
	local frame = FrameNumber()
	if main and baked ~= frame then
		baked = frame
		local now = RealTime()
		if now >= nextPick then
			nextPick = now + BODY_PICK
			Select(eye, M)
		end

		local stop = SysTime() + BODY_MS / 1000
		for i = 1, cellCount do
			local cell = cells[i]
			if now - (cell.bodyBuilt or -math.huge) >= cell.lod[4] then
				BakeBody(cell)
				if SysTime() >= stop then break end
			end
		end
	end

	render.SetMaterial(FLESH)
	for i = 1, cellCount do
		local im = cells[i].bodyMesh
		if im then im:Draw() end
	end
end

local shownAt = -1

local function Show()
	local frame = FrameNumber()
	if shownAt == frame then return end
	shownAt = frame
	local M = EvilFungus.Client
	local k = math.min(1, FrameTime() * BODY_SHOW)
	for node in pairs(M.body) do
		node.shown = node.shown + (node.target - node.shown) * k
		if node.target <= 0 and node.shown < BODY_GONE then
			node.shown = 0
			M.body[node] = nil
		end
	end
end

hook.Add("Think", "EvilFungusRender", Show)

local view = EvilFungus.View or { frame = -1 }
EvilFungus.View = view

hook.Add("RenderScene", "EvilFungusView", function(origin)
	view.origin, view.frame = origin, FrameNumber()
end)

function EvilFungus.MainView(depth, _, sky3d)
	if depth or sky3d then return false end
	if view.frame ~= FrameNumber() or not view.origin then return true end
	return not render.GetRenderTarget() or EyePos():DistToSqr(view.origin) < VIEW_SLACK * VIEW_SLACK
end

local IDENTITY = Matrix()

local function Clean()
	render.SetStencilEnable(false)
	render.SetScissorRect(0, 0, 0, 0, false)
	render.OverrideDepthEnable(false, false)
	render.OverrideColorWriteEnable(false, false)
	render.OverrideAlphaWriteEnable(false, false)
	render.OverrideBlend(false)
	render.MaterialOverride()
	render.CullMode(MATERIAL_CULLMODE_CCW)
	render.DepthRange(0, 1)
	render.SetBlend(1)
	render.SetColorModulation(1, 1, 1)
end

function EvilFungus.DrawPass(name, draw)
	local drawn
	local function Run(depth, sky, sky3d)
		if depth or sky3d then return end
		local main = EvilFungus.MainView(depth, sky, sky3d)
		drawn = FrameNumber()
		Clean()
		local clip = not render.GetRenderTarget() and render.EnableClipping(false)
		cam.PushModelMatrix(IDENTITY)
		local ok, err = pcall(draw, main)
		cam.PopModelMatrix()
		if clip then render.EnableClipping(true) end
		if not ok then ErrorNoHalt("Evil Fungus couldn't draw: ", err, "\n") end
	end
	local function Late(depth, sky, sky3d)
		if drawn ~= FrameNumber() then Run(depth, sky, sky3d) end
	end
	local function Reset(depth, _, sky3d)
		if not depth and not sky3d then drawn = nil end
	end
	hook.Add("PreDrawOpaqueRenderables", name, Reset)
	hook.Add("PostDrawOpaqueRenderables", name, Run)
	hook.Add("PreDrawTranslucentRenderables", name, Late)
	hook.Add("PostDrawTranslucentRenderables", name, function(depth, sky, sky3d)
		Late(depth, sky, sky3d)
		Reset(depth, sky, sky3d)
	end)
end

local rebuilt, eye = -1, Vector()

EvilFungus.DrawPass("EvilFungusRender", function(main)
	local t = SysTime()
	local frame = FrameNumber()
	local fresh = view.frame == frame and view.origin
	if main and rebuilt ~= frame and (fresh or not render.GetRenderTarget() or frame - rebuilt > STALE_FRAMES) then
		rebuilt, eye = frame, fresh and Vector(fresh) or EyePos()
		Show()
		Rebuild()
		t = EvilFungus.Measure("rebuild", t)
	end
	local from = main and eye or EyePos()

	local r = DRAW_RANGE + 128
	local r2 = r * r
	render.SetMaterial(MAT)
	for _, chunk in pairs(EvilFungus.Client.chunks) do
		if chunk.mesh and chunk.center:DistToSqr(from) < (chunk.cull or r2) then chunk.mesh:Draw() end
	end
	render.SetMaterial(WEB)
	for _, chunk in pairs(EvilFungus.Client.chunks) do
		if chunk.webMesh and chunk.center:DistToSqr(from) < (chunk.cull or r2) then chunk.webMesh:Draw() end
	end
	t = EvilFungus.Measure("chunks", t)
	DrawBody(from, main)
	EvilFungus.Measure("body", t)
end)

hook.Add("HUDPaint", "EvilFungusCost", function()
	if not cv_cost:GetBool() then return end
	local M, c = EvilFungus.Client, EvilFungus.Cost
	local chunks, strands, patches = 0, 0, 0
	for _, chunk in pairs(M.chunks) do
		chunks = chunks + 1
		strands = strands + chunk.count
		for _ in pairs(chunk.patches or {}) do patches = patches + 1 end
	end
	strands = strands - patches
	local lines = {
		("rebuilding mat  %.2f ms"):format(c.rebuild or 0),
		("drawing mat     %.2f ms  (%d chunks, %d strands, %d settled)"):format(c.chunks or 0, chunks, strands, patches),
		("drawing body    %.2f ms  (%d strands)"):format(c.body or 0, M.bodyDrawn or 0),
		("sleepers        %.2f ms"):format(c.sleepers or 0),
		("synced          %d of %d nodes"):format(M.count or 0, GetGlobal2Int(EvilFungus.NODES_VAR, 0)),
	}
	for i, line in ipairs(lines) do
		draw.SimpleText(line, "BudgetLabel", 24, 120 + i * 14, color_white)
	end
end)
