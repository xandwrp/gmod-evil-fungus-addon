local POSING, CONSUMING, KEPT = EvilFungus.POSING, EvilFungus.CONSUMING, EvilFungus.KEPT

local SCAN = 0.5
local RANGE = 4000
local FIBER_RANGE = 1800
local BATCH = 2500
local STATIC_QUADS = 15000
local REBUILD = 2

local ARM_GROW = 0.8
local ARM_SINK = 1.2
local ARM_SAMPLES = 8
local ARM_SIDES = 4
local ARM_RISE = 8
local BRAID = 3
local BRAID_R = 1.1
local TWIST = 9
local ARM_R = { 0.9, 0.35 }

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

local LIMB_SIDES = 5
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
	if c and c.model == rag:GetModel() then return c end
	c = { model = rag:GetModel(), limbs = {}, grips = {} }
	local head = EvilFungus.HeadBone(rag)
	c.head = head
	for bone = 0, rag:GetBoneCount() - 1 do
		local parent = rag:GetBoneParent(bone)
		if parent and parent >= 0 and not (head and EvilFungus.UnderHead(rag, bone, head)) then
			c.limbs[#c.limbs + 1] = { bone = bone, parent = parent, thick = Thickness(rag:GetBoneName(bone)) }
		end
	end
	for _, name in pairs(EvilFungus.HOLD_BONES) do
		local bone = rag:LookupBone(name)
		if bone then c.grips[#c.grips + 1] = bone end
	end
	if #c.grips == 0 then c.grips[1] = 0 end
	c.pelvis = rag:LookupBone(EvilFungus.HOLD_BONES.pelvis) or 0
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

-- Braids of fine strands that rise off the mat and wind round whatever it's moving.
local function Arm(shapes, from, to, up, grown, now, light, S)
	local h = math.max(4, (to - from):Dot(up))
	local lift = from + up * (h * 1.2 + ARM_RISE)
	local center = {}
	for i = 0, ARM_SAMPLES do center[i + 1] = Bezier(from, lift, to, i / ARM_SAMPLES * grown) end

	local r, g, b = Mix(S.ROOT, S.BODY_THIN, 0.5)
	for j = 0, BRAID - 1 do
		local pts, radii = {}, {}
		for i, p in ipairs(center) do
			local t = (i - 1) / ARM_SAMPLES
			local tangent = center[math.min(#center, i + 1)] - center[math.max(1, i - 1)]
			if tangent:LengthSqr() < 1e-6 then tangent = Vector(up) end
			tangent:Normalize()
			local side = tangent:Cross(up)
			if side:LengthSqr() < 1e-6 then side = tangent:Cross(Vector(1, 0, 0)) end
			side:Normalize()
			local bin = tangent:Cross(side)
			local phi = j / BRAID * math.pi * 2 + t * TWIST + now * 0.5
			local spread = BRAID_R * (1 - t * 0.6)
			pts[i] = p + side * (math.cos(phi) * spread) + bin * (math.sin(phi) * spread)
			radii[i] = Lerp(t, ARM_R[1], ARM_R[2])
		end
		Shape(shapes, pts, radii, up, ARM_SIDES, r, g, b, light)
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
	local pelvis = rag:GetBonePosition(c.pelvis)
	if pelvis then list[#list + 1] = pelvis - up * 3 end
	return list
end

local function Fibers(shapes, rag, c, nest, up, t, now, light)
	local seed = rag:EntIndex()
	for h, hole in ipairs(Holes(rag, c, up)) do
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
	local span = math.max(1, EvilFungus.Setting("consume_time"))
	for i = 1, WIRES do
		local born = i <= WIRES_AT_ONCE and 0 or (i - WIRES_AT_ONCE) / (WIRES - WIRES_AT_ONCE) * span
		local age = t - born
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
	local head = c.head and rag:GetBonePosition(c.head)
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
				Shape(shapes, { a, b }, { rr, rr }, up, LIMB_SIDES, r, g, bl, light)
			end
		end
	end
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

hook.Add("PostDrawOpaqueRenderables", "EvilFungusSleepers", function(depth, sky, sky3d)
	if depth or sky or sky3d then return end
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
		for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
			if rag:GetNW2Int(EvilFungus.STAGE_VAR, 0) > 0 then sleepers[#sleepers + 1] = rag end
		end
	end

	render.SetMaterial(S.MAT)
	local eye = EyePos()
	local shapes = {}
	for _, rag in ipairs(sleepers) do
		local d2 = IsValid(rag) and rag:GetPos():DistToSqr(eye)
		if d2 and d2 < RANGE * RANGE then
			local nest, up, light = Frame(rag, S)
			if nest then
				local c = Cache(rag)
				rag:SetupBones()
				local stage = rag:GetNW2Int(EvilFungus.STAGE_VAR, 0)
				local since = clock - rag:GetNW2Float(EvilFungus.STAGE_AT_VAR, 0)
				local t = clock - rag:GetNW2Float(EvilFungus.SINCE_VAR, clock)
				local close = d2 < FIBER_RANGE * FIBER_RANGE

				if stage == KEPT then
					local growing = t < EvilFungus.Setting("consume_time") + WIRE_GROW + 1
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
					local grown = 0
					if stage == POSING then
						grown = math.Clamp(since / ARM_GROW, 0, 1)
					elseif stage == CONSUMING then
						grown = 1 - math.Clamp(since / ARM_SINK, 0, 1)
					end
					if grown > 0 then
						for _, bone in ipairs(c.grips) do
							local to = rag:GetBonePosition(bone)
							if to then Arm(shapes, Floor(to, nest, up), to, up, grown, now, light, S) end
						end
					end
					if stage == POSING or stage == CONSUMING then
						if close then Fibers(shapes, rag, c, nest, up, t, now, light) end
						Wires(shapes, rag, c, nest, up, t, light, S)
					end
					if stage == CONSUMING then
						Vein(shapes, rag, c, nest, up, now, light, S)
						Limbs(shapes, rag, c, up, light, S)
					end
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
