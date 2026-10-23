local CONSUMING, KEPT, HOST, SPENT = EvilFungus.CONSUMING, EvilFungus.KEPT, EvilFungus.HOST, EvilFungus.SPENT

local SCAN = 0.5
local RANGE = 4000
local FIBER_RANGE = 1800
local BATCH = 2500
local STATIC_QUADS = 8000
local REBUILD = 2

local VEIN_SAMPLES = 6
local VEIN_SIDES = 6
local VEIN_R = { 1.2, 3 }
local VEIN_BOW = 8
local VEIN_PULSE = 0.12
local BEADS = 3
local BEAD_SPEED = 0.5
local BEAD_LENGTH = 0.08
local BEAD_SWELL = 1.25
local BEAD_GLOW = 1.5
local BEAD = { 255, 235, 170 }

local FIBERS_PER_HOLE = 3
local FIBER_SAMPLES = 4
local FIBER_SIDES = 3
local FIBER_R = { 0.22, 0.08 }
local FIBER_DELAY = { 0.3, 2.8 }
local FIBER_GROW = 1.2
local FIBER_SEEK = 1.5
local FIBER_WOBBLE = 2.5
local FIBER_ROOT = { 5, 14 }
local FRESH = { 232, 226, 212 }

local SKIN_FIBERS = 20
local SKIN_DELAY = { 0.5, 6.5 }
local SKIN_R = { 0.15, 0.07 }

local WIRES_AT_ONCE = 4
local WIRES = 48
local WIRE_GROW = 4
local WIRE_SAMPLES = 4
local WIRE_SIDES = 4
local WIRE_R = { 0.45, 0.8 }
local WIRE_SPAN = { 8, 16 }
local WIRE_ARCH = 0.6

local TENDRILS = 8
local TENDRIL_SAMPLES = 4
local TENDRIL_SIDES = 4
local TENDRIL_LENGTH = { 10, 28 }
local TENDRIL_R = { 0.7, 0.15 }
local TENDRIL_SWAY = 4

local TETHER_SAMPLES = 8
local TETHER_SIDES = 6
local TETHER_R = { 3, 1.6 }
local TETHER_SAG = 0.15
local LIGHT_EVERY = 0.5

local LIMB_SIDES = 6
-- Rounded ends, as how far past the joint and how wide, so a part's ends close over and the joints run together.
local CAP = { { 0.34, 0.94 }, { 0.71, 0.71 }, { 1, 0.08 } }
local SHOWN = 0.02
local THICK = {
	{ "pelvis", 5 }, { "spine", 5.5 }, { "clavicle", 3 }, { "upperarm", 2.6 }, { "forearm", 2.2 },
	{ "hand", 1.6 }, { "finger", 0.5 }, { "thigh", 3.6 }, { "calf", 2.8 }, { "foot", 2 }, { "toe", 0.8 },
}
local THICK_DEFAULT = 1.5

-- Eyes, nose, mouth and ears, measured from the eyes attachment: forward, right, up.
local HOLES = {
	{ 0.3, -1.3, 0 }, { 0.3, 1.3, 0 }, { 1.5, 0, -1.6 }, { 0.8, 0, -3.6 }, { -2.6, -3.4, -1.2 }, { -2.6, 3.4, -1.2 },
}

local sleepers, nextScan = {}, 0

local function Rand(seed, i, k)
	local x = math.sin(seed * 1.618 + i * 12.731 + k * 3.317) * 43758.5453
	return x - math.floor(x)
end

local function Thickness(name)
	name = string.lower(name or "")
	for _, t in ipairs(THICK) do
		if string.find(name, t[1], 1, true) then return t[2] end
	end
	return THICK_DEFAULT
end

local function Cache(rag)
	local c = rag.EvilFungusCache
	local whole = rag:GetNW2Bool(EvilFungus.WHOLE_VAR, false)
	if c and c.model == rag:GetModel() and c.whole == whole then return c end
	c = { model = rag:GetModel(), limbs = {}, whole = whole }
	local head = EvilFungus.HeadBone(rag)
	c.head = head
	for bone = 0, rag:GetBoneCount() - 1 do
		local parent = rag:GetBoneParent(bone)
		if parent and parent >= 0 and (whole or not (head and EvilFungus.UnderHead(rag, bone, head))) then
			c.limbs[#c.limbs + 1] = { bone = bone, parent = parent, thick = Thickness(rag:GetBoneName(bone)) }
		end
	end
	local eyes = rag:LookupAttachment("eyes")
	c.eyes = eyes and eyes > 0 and eyes or nil
	rag.EvilFungusCache = c
	return c
end

local function Bezier(a, b, c, t)
	local o = 1 - t
	return a * (o * o) + b * (2 * t * o) + c * (t * t)
end

local function Mix(a, b, k)
	return Lerp(k, a[1], b[1]), Lerp(k, a[2], b[2]), Lerp(k, a[3], b[3])
end

local function Floor(p, nest, up)
	return p - up * (p - nest):Dot(up)
end

local function Across(up, angle)
	local a = up:Angle()
	return a:Right() * math.cos(angle) + a:Up() * math.sin(angle)
end

local function Shape(shapes, pts, radii, up, sides, r, g, b, light)
	if #pts >= 2 then
		shapes[#shapes + 1] = { pts = pts, radii = radii, up = up, sides = sides, r = r, g = g, b = b, light = light }
	end
end

-- A hair-thin strand off the mat that feels around a spot before it takes hold.
local function Fiber(shapes, root, tip, up, grown, seek, now, seed, radius, light)
	if seek < 1 then
		local w = FIBER_WOBBLE * (1 - seek)
		tip = tip + Vector(math.sin(now * 7 + seed), math.sin(now * 5.3 + seed * 2), math.sin(now * 6.1 + seed * 3)) * w
	end
	local h = math.max(2, (tip - root):Dot(up))
	local lift = root + up * (h + 3)
	local pts, radii = {}, {}
	for i = 0, FIBER_SAMPLES do
		local t = i / FIBER_SAMPLES * grown
		pts[i + 1] = Bezier(root, lift, tip, t)
		radii[i + 1] = Lerp(i / FIBER_SAMPLES, radius[1], radius[2])
	end
	Shape(shapes, pts, radii, up, FIBER_SIDES, FRESH[1], FRESH[2], FRESH[3], light)
end

local function Holes(rag, c, up)
	local list = {}
	local att = c.eyes and rag:GetAttachment(c.eyes)
	if att then
		local f, r, u = att.Ang:Forward(), att.Ang:Right(), att.Ang:Up()
		for _, o in ipairs(HOLES) do list[#list + 1] = att.Pos + f * o[1] + r * o[2] + u * o[3] end
	elseif c.head then
		local p = rag:GetBonePosition(c.head)
		if p then list[1] = p + up * 3 end
	end
	return list
end

local function Fibers(shapes, rag, c, nest, up, t, now, light)
	local seed = rag:EntIndex()
	for h, hole in ipairs(c.whole and {} or Holes(rag, c, up)) do
		for j = 1, FIBERS_PER_HOLE do
			local k = h * 10 + j
			local age = t - Lerp(Rand(seed, k, 1), FIBER_DELAY[1], FIBER_DELAY[2])
			if age > 0 then
				local root = Floor(hole, nest, up) + Across(up, Rand(seed, k, 2) * math.pi * 2) * Lerp(Rand(seed, k, 3), FIBER_ROOT[1], FIBER_ROOT[2])
				local grown = math.min(1, age / FIBER_GROW)
				local seek = math.Clamp((age - FIBER_GROW) / FIBER_SEEK, 0, 1)
				Fiber(shapes, root, hole, up, grown, seek, now, seed + k, FIBER_R, light)
			end
		end
	end

	local limbs = c.limbs
	if #limbs == 0 then return end
	for i = 1, SKIN_FIBERS do
		local age = t - Lerp(Rand(seed, i, 4), SKIN_DELAY[1], SKIN_DELAY[2])
		if age > 0 then
			local limb = limbs[1 + math.floor(Rand(seed, i, 5) * #limbs)]
			local a, b = rag:GetBonePosition(limb.parent), rag:GetBonePosition(limb.bone)
			if a and b then
				local side = Across(up, Rand(seed, i, 6) * math.pi * 2)
				local skin = Lerp(Rand(seed, i, 7), a, b) + (up * Lerp(Rand(seed, i, 8), 0.3, 1) + side * 0.5) * limb.thick
				local root = Floor(skin, nest, up) + side * (limb.thick + Lerp(Rand(seed, i, 9), 2, 8))
				Fiber(shapes, root, skin, up, math.min(1, age / FIBER_GROW), 1, now, seed + i, SKIN_R, light)
			end
		end
	end
end

-- Thicker strands thrown over the body from one side to the other, more of them the longer it's had them.
local function Wires(shapes, rag, c, nest, up, t, light, S)
	local limbs = c.limbs
	if #limbs == 0 then return end
	local seed = rag:EntIndex()
	local consumed = rag:GetNW2Float(EvilFungus.CONSUMED_VAR, 0)
	local span = math.max(1, EvilFungus.Setting("consume_time")) / EvilFungus.TimeScale()
	for i = 1, WIRES do
		local age = t
		if i > WIRES_AT_ONCE then age = (consumed - (i - WIRES_AT_ONCE) / (WIRES - WIRES_AT_ONCE)) * span end
		if age <= 0 then break end
		local limb = limbs[1 + math.floor(Rand(seed, i, 11) * #limbs)]
		local a, b = rag:GetBonePosition(limb.parent), rag:GetBonePosition(limb.bone)
		if a and b then
			local over = Lerp(Rand(seed, i, 12), a, b) + up * (limb.thick + 0.8)
			local base = Floor(over, nest, up)
			local side = Across(up, Rand(seed, i, 13) * math.pi * 2) * Lerp(Rand(seed, i, 14), WIRE_SPAN[1], WIRE_SPAN[2])
			local h = math.max(2, (over - base):Dot(up))
			local from, to = base + side, base - side
			local pts = {}
			for j = 0, WIRE_SAMPLES do
				pts[#pts + 1] = Bezier(from, (from + over) * 0.5 + up * (h * WIRE_ARCH), over, j / WIRE_SAMPLES)
			end
			for j = 1, WIRE_SAMPLES do
				pts[#pts + 1] = Bezier(over, (over + to) * 0.5 + up * (h * WIRE_ARCH), to, j / WIRE_SAMPLES)
			end
			local keep = math.max(2, math.ceil(#pts * math.min(1, age / WIRE_GROW)))
			for j = #pts, keep + 1, -1 do pts[j] = nil end
			local radius = Lerp(Rand(seed, i, 15), WIRE_R[1], WIRE_R[2])
			local radii = {}
			for j = 1, #pts do radii[j] = radius end
			local r, g, bl = Mix(S.ROOT, S.VEIN, Rand(seed, i, 16) * 0.5)
			Shape(shapes, pts, radii, up, WIRE_SIDES, r, g, bl, light)
		end
	end
end

-- The head's still working, just not for them anymore. You can see it going down the vein.
local function Vein(shapes, rag, c, nest, up, now, light, S)
	local head = not c.whole and c.head and rag:GetBonePosition(c.head)
	if not head then return end
	local into = nest + up
	local bow = (head + into) * 0.5 + up * VEIN_BOW
	local pulse = 1 + VEIN_PULSE * math.sin(now * 2 + rag:EntIndex())
	local pts, radii = {}, {}
	for i = 0, VEIN_SAMPLES do
		local t = i / VEIN_SAMPLES
		pts[i + 1] = Bezier(head, bow, into, t)
		radii[i + 1] = Lerp(t, VEIN_R[1], VEIN_R[2]) * pulse
	end
	local r, g, b = Mix(S.BODY_THIN, S.BODY_THICK, 0.6)
	Shape(shapes, pts, radii, up, VEIN_SIDES, r, g, b, light)

	for j = 0, BEADS - 1 do
		local t = (now * BEAD_SPEED + j / BEADS) % 1
		local s0 = math.max(0, t - BEAD_LENGTH)
		local bead, bradii = {}, {}
		for i = 0, 2 do
			local u = Lerp(i / 2, s0, t)
			bead[i + 1] = Bezier(head, bow, into, u)
			bradii[i + 1] = Lerp(u, VEIN_R[1], VEIN_R[2]) * pulse * BEAD_SWELL
		end
		Shape(shapes, bead, bradii, up, VEIN_SIDES, BEAD[1], BEAD[2], BEAD[3], light * BEAD_GLOW)
	end
end

-- Wherever a part has shrunk away, fungus fills the same shape.
local function Limbs(shapes, rag, c, up, light, S)
	local min = EvilFungus.MIN_SCALE
	for _, limb in ipairs(c.limbs) do
		local scale = rag:GetManipulateBoneScale(limb.bone).x
		local gone = math.Clamp((1 - scale) / (1 - min), 0, 1)
		if gone > SHOWN then
			local a, b = rag:GetBonePosition(limb.parent), rag:GetBonePosition(limb.bone)
			if a and b and a:DistToSqr(b) > 0.25 then
				local rr = limb.thick * gone
				local r, g, bl = Mix(S.ROOT, S.VEIN, gone * 0.5)
				local dir = (b - a):GetNormalized()
				local pts, radii = {}, {}
				for i = #CAP, 1, -1 do
					pts[#pts + 1], radii[#radii + 1] = a - dir * (rr * CAP[i][1]), rr * CAP[i][2]
				end
				pts[#pts + 1], radii[#radii + 1] = a, rr
				pts[#pts + 1], radii[#radii + 1] = b, rr
				for i = 1, #CAP do
					pts[#pts + 1], radii[#radii + 1] = b + dir * (rr * CAP[i][1]), rr * CAP[i][2]
				end
				Shape(shapes, pts, radii, up, LIMB_SIDES, r, g, bl, light)
			end
		end
	end
end

local function Tendrils(shapes, rag, c, now, light, S)
	local limbs = c.limbs
	if #limbs == 0 then return end
	local seed = rag:EntIndex()
	for i = 1, TENDRILS do
		local limb = limbs[1 + math.floor(Rand(seed, i, 21) * #limbs)]
		local a, b = rag:GetBonePosition(limb.parent), rag:GetBonePosition(limb.bone)
		if a and b then
			local root = Lerp(Rand(seed, i, 22), a, b)
			local len = Lerp(Rand(seed, i, 23), TENDRIL_LENGTH[1], TENDRIL_LENGTH[2])
			local phase = Rand(seed, i, 24) * math.pi * 2
			local pts, radii = {}, {}
			for j = 0, TENDRIL_SAMPLES do
				local t = j / TENDRIL_SAMPLES
				local sway = TENDRIL_SWAY * t * t
				pts[j + 1] = root + Vector(math.sin(now * 2.3 + phase + t * 2) * sway, math.cos(now * 1.9 + phase + t * 2) * sway, -len * t)
				radii[j + 1] = Lerp(t, TENDRIL_R[1], TENDRIL_R[2])
			end
			local r, g, bl = Mix(S.ROOT, S.VEIN, Rand(seed, i, 25) * 0.5)
			Shape(shapes, pts, radii, vector_up, TENDRIL_SIDES, r, g, bl, light)
		end
	end
end

local function Tether(shapes, rag, anchor, light, S)
	local to = rag:WorldSpaceCenter()
	local mid = (anchor + to) * 0.5 - vector_up * (anchor:Distance(to) * TETHER_SAG)
	local pts, radii = {}, {}
	for i = 0, TETHER_SAMPLES do
		local t = i / TETHER_SAMPLES
		pts[i + 1] = Bezier(anchor, mid, to, t)
		radii[i + 1] = Lerp(t, TETHER_R[1], TETHER_R[2])
	end
	local r, g, b = Mix(S.BODY_THIN, S.BODY_THICK, 0.5)
	Shape(shapes, pts, radii, vector_up, TETHER_SIDES, r, g, b, light)
end

local function Lit(rag, clock, S)
	local lit = rag.EvilFungusLit
	if not lit or clock - lit.at > LIGHT_EVERY then
		lit = { at = clock, light = S.Light({ pos = rag:WorldSpaceCenter(), normal = vector_up }) }
		rag.EvilFungusLit = lit
	end
	return lit.light
end

local function Quads(sh)
	return (#sh.pts - 1) * sh.sides
end

local function Emit(shapes, first, last, S)
	for k = first, last do
		local sh = shapes[k]
		S.Polyline(sh.pts, sh.radii, sh.up, sh.sides, sh.r, sh.g, sh.b, sh.light)
	end
end

local function Draw(shapes, S)
	local i, n = 1, #shapes
	while i <= n do
		local quads, last = 0, i
		while last <= n do
			local q = Quads(shapes[last])
			if quads > 0 and quads + q > BATCH then break end
			quads = quads + q
			last = last + 1
		end
		mesh.Begin(MATERIAL_QUADS, quads)
		local ok, err = pcall(Emit, shapes, i, last - 1, S)
		mesh.End()
		if not ok then
			ErrorNoHalt("Evil Fungus couldn't draw a sleeper: ", err, "\n")
			return
		end
		i = last
	end
end

-- Kept sleepers don't move, so their wiring is built once in a while instead of every frame.
local function Bake(rag, shapes, S)
	if rag.EvilFungusMesh then rag.EvilFungusMesh:Destroy() end
	rag.EvilFungusMesh = nil
	local quads, last = 0, 0
	for k, sh in ipairs(shapes) do
		local q = Quads(sh)
		if quads + q > STATIC_QUADS then break end
		quads, last = quads + q, k
	end
	if quads == 0 then return end
	local im = Mesh(S.MAT)
	mesh.Begin(im, MATERIAL_QUADS, quads)
	local ok, err = pcall(Emit, shapes, 1, last, S)
	mesh.End()
	if not ok then ErrorNoHalt("Evil Fungus couldn't build a sleeper: ", err, "\n") end
	rag.EvilFungusMesh = im
end

local function Forget(rag)
	if rag.EvilFungusMesh then
		rag.EvilFungusMesh:Destroy()
		rag.EvilFungusMesh = nil
	end
end

local function Frame(rag, S)
	local nest = rag:GetNW2Vector(EvilFungus.NEST_VAR)
	local up = rag:GetNW2Vector(EvilFungus.NEST_UP_VAR)
	if up:LengthSqr() < 0.5 then return end
	local spot = rag.EvilFungusSpot
	if not spot or spot.pos ~= nest then
		spot = { pos = nest, normal = up }
		rag.EvilFungusSpot = spot
	end
	return nest, up, S.Light(spot)
end

EvilFungus.DrawPass("EvilFungusSleepers", function()
	local S = EvilFungus.Strands
	if not S then return end
	local started = SysTime()
	local now, clock = RealTime(), CurTime()
	if clock >= nextScan then
		nextScan = clock + SCAN
		for _, rag in ipairs(sleepers) do
			if IsValid(rag) and rag:GetNW2Int(EvilFungus.STAGE_VAR, 0) ~= KEPT then Forget(rag) end
		end
		sleepers = {}
		for _, rag in ipairs(ents.FindByClass("prop_ragdoll*")) do
			if rag:GetNW2Int(EvilFungus.STAGE_VAR, 0) > 0 then sleepers[#sleepers + 1] = rag end
		end
	end

	render.SetMaterial(S.MAT)
	local eye = EyePos()
	local shapes = {}
	for _, rag in ipairs(sleepers) do
		local d2 = IsValid(rag) and rag:GetPos():DistToSqr(eye)
		local stage = d2 and rag:GetNW2Int(EvilFungus.STAGE_VAR, 0)
		if d2 and d2 < RANGE * RANGE and (stage == HOST or stage == SPENT) then
			local c = Cache(rag)
			rag:SetupBones()
			local light = Lit(rag, clock, S)
			Limbs(shapes, rag, c, vector_up, light, S)
			if stage == HOST then
				Tendrils(shapes, rag, c, now, light, S)
				local anchor = rag:GetNW2Vector(EvilFungus.ANCHOR_VAR)
				if not anchor:IsZero() then Tether(shapes, rag, anchor, light, S) end
			end
		elseif d2 and d2 < RANGE * RANGE then
			local nest, up, light = Frame(rag, S)
			if nest then
				local c = Cache(rag)
				rag:SetupBones()
				local t = clock - rag:GetNW2Float(EvilFungus.SINCE_VAR, clock)
				local close = d2 < FIBER_RANGE * FIBER_RANGE

				if stage == KEPT then
					local growing = rag:GetNW2Float(EvilFungus.CONSUMED_VAR, 0) < 1 or t < WIRE_GROW + 1
					if not rag.EvilFungusMesh or growing and clock - (rag.EvilFungusBakedAt or 0) > REBUILD then
						local static = {}
						Limbs(static, rag, c, up, light, S)
						Wires(static, rag, c, nest, up, t, light, S)
						Fibers(static, rag, c, nest, up, t, now, light)
						Bake(rag, static, S)
						rag.EvilFungusBakedAt = clock
					end
					if rag.EvilFungusMesh then rag.EvilFungusMesh:Draw() end
					Vein(shapes, rag, c, nest, up, now, light, S)
				else
					if stage == CONSUMING then
						if close then Fibers(shapes, rag, c, nest, up, t, now, light) end
						Wires(shapes, rag, c, nest, up, t, light, S)
						Vein(shapes, rag, c, nest, up, now, light, S)
					end
					Limbs(shapes, rag, c, up, light, S)
				end
			end
		end
	end
	if #shapes > 0 then Draw(shapes, S) end
	EvilFungus.Measure("sleepers", started)
end)

hook.Add("EntityRemoved", "EvilFungusSleepers", function(ent)
	if ent.EvilFungusMesh then Forget(ent) end
end)
