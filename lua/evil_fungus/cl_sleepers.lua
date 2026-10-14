local POSING, CONSUMING, KEPT = EvilFungus.POSING, EvilFungus.CONSUMING, EvilFungus.KEPT

local SCAN = 0.5
local RANGE = 4000
local BATCH = 2500
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
local LIMB_SIDES = 5
local SHOWN = 0.02
local THICK = {
	{ "pelvis", 5 }, { "spine", 5.5 }, { "clavicle", 3 }, { "upperarm", 2.6 }, { "forearm", 2.2 },
	{ "hand", 1.6 }, { "finger", 0.5 }, { "thigh", 3.6 }, { "calf", 2.8 }, { "foot", 2 }, { "toe", 0.8 },
}
local THICK_DEFAULT = 1.5

local sleepers, nextScan = {}, 0

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
			local q = center[math.min(#center, i + 1)]
			local o = center[math.max(1, i - 1)]
			local tangent = q - o
			if tangent:LengthSqr() < 1e-6 then tangent = up end
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
		shapes[#shapes + 1] = { pts = pts, radii = radii, up = up, sides = ARM_SIDES, r = r, g = g, b = b, light = light }
	end
end

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
	shapes[#shapes + 1] = { pts = pts, radii = radii, up = up, sides = VEIN_SIDES, r = r, g = g, b = b, light = light }
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
				shapes[#shapes + 1] = { pts = { a, b }, radii = { rr, rr }, up = up, sides = LIMB_SIDES, r = r, g = g, b = bl, light = light }
			end
		end
	end
end

local function Draw(shapes, S)
	local i, n = 1, #shapes
	while i <= n do
		local quads, last = 0, i
		while last <= n do
			local q = (#shapes[last].pts - 1) * shapes[last].sides
			if quads > 0 and quads + q > BATCH then break end
			quads = quads + q
			last = last + 1
		end
		mesh.Begin(MATERIAL_QUADS, quads)
		local ok, err = pcall(function()
			for k = i, last - 1 do
				local sh = shapes[k]
				S.Polyline(sh.pts, sh.radii, sh.up, sh.sides, sh.r, sh.g, sh.b, sh.light)
			end
		end)
		mesh.End()
		if not ok then
			ErrorNoHalt("Evil Fungus couldn't draw a sleeper: ", err, "\n")
			return
		end
		i = last
	end
end

hook.Add("PostDrawOpaqueRenderables", "EvilFungusSleepers", function(depth, sky, sky3d)
	if depth or sky or sky3d then return end
	local S = EvilFungus.Strands
	if not S then return end
	local now = RealTime()
	if CurTime() >= nextScan then
		nextScan = CurTime() + SCAN
		sleepers = {}
		for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
			if rag:GetNW2Int(EvilFungus.STAGE_VAR, 0) > 0 then sleepers[#sleepers + 1] = rag end
		end
	end

	local eye, r2 = EyePos(), RANGE * RANGE
	local shapes = {}
	for _, rag in ipairs(sleepers) do
		if IsValid(rag) and rag:GetPos():DistToSqr(eye) < r2 then
			local stage = rag:GetNW2Int(EvilFungus.STAGE_VAR, 0)
			local since = CurTime() - rag:GetNW2Float(EvilFungus.STAGE_AT_VAR, 0)
			local nest = rag:GetNW2Vector(EvilFungus.NEST_VAR)
			local up = rag:GetNW2Vector(EvilFungus.NEST_UP_VAR)
			if up:LengthSqr() > 0.5 then
				local c = Cache(rag)
				rag:SetupBones()
				local spot = rag.EvilFungusSpot
				if not spot or spot.pos ~= nest then
					spot = { pos = nest, normal = up }
					rag.EvilFungusSpot = spot
				end
				local light = S.Light(spot)

				local grown = 0
				if stage == POSING then
					grown = math.Clamp(since / ARM_GROW, 0, 1)
				elseif stage == CONSUMING then
					grown = 1 - math.Clamp(since / ARM_SINK, 0, 1)
				end
				if grown > 0 then
					for _, bone in ipairs(c.grips) do
						local to = rag:GetBonePosition(bone)
						if to then
							local from = to - up * (to - nest):Dot(up)
							Arm(shapes, from, to, up, grown, now, light, S)
						end
					end
				end
				if stage == CONSUMING or stage == KEPT then
					Vein(shapes, rag, c, nest, up, now, light, S)
					Limbs(shapes, rag, c, up, light, S)
				end
			end
		end
	end
	if #shapes == 0 then return end
	render.SetMaterial(S.MAT)
	Draw(shapes, S)
end)
