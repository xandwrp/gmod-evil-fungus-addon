EvilFungus = EvilFungus or {}
local Sleep = EvilFungus.Sleep or { drowsy = {}, sleepers = {}, afraid = {} }
Sleep.afraid = Sleep.afraid or {}
EvilFungus.Sleep = Sleep
EvilFungus.Sleepers = Sleep.sleepers

local POSING, CONSUMING, KEPT, FREED = EvilFungus.POSING, EvilFungus.CONSUMING, EvilFungus.KEPT, EvilFungus.FREED

local UPDATE = 0.1
local CONSUME_UPDATE = 1
local WEAR_OFF = 8
local DOSE_FRESH = 0.3

local NEST_SEARCH = 192
local NEST_FAR = 400
local NEST_CANDIDATES = 12
local NEST_APART = 72
local SUPPORT = 24
local CARRY_SPEED = 80
local CARRY_LIFT = 10
local GAIN = 12
local MAX_SPEED = 420
local RESPONSE = 20
local STALL_TIME = 1.5
local STALL_GAIN = 0.95
local KICK = 1.2
local KICK_JITTER = 35
local TORSO = { pelvis = true, chest = true, head = true }
local FLIP_DOT = 0.5
local FLIP_SPEED = 220
local TORSO_TOL, LIMB_TOL = 12, 18
local FACE_UP = 0.6
local POSED_FOR = 0.5
local POSE_TIMEOUT = 15
local LOOSEN = 1.3
local EXTRACT = 80
local TORN_FOR = 0.35
local HIT_GRACE = 2
local TUG_GRIP = 2
local SLAM_SPEED = 250
local WAKE_AFTER = 10

local SHRINK_SPAN = 0.25
local FOOD_PER_KG = 0.5
local FOOD_VALUE = { 10, 60 }
local PALE = { 215, 205, 190 }

local FEAR_TIME = 90
local FEAR_UPDATE = 0.5
local FEAR_RADIUS = { 128, 320 }
local FLEE_DIST = 400
local FLEE_AGAIN = 1.5

local REST_TORSO = 30
local CATCH_RADIUS = 64
local LOWER_SPEED = 30
local WRAP_HOLD = 2
local WRAP_OUT = 12

local STANDING_OFFSETS = { Vector(0, 0, 0), Vector(32, 0, 0), Vector(-32, 0, 0), Vector(0, 32, 0), Vector(0, -32, 0) }

-- Snow angel, in units for a normal-sized person: along the body toward the head, out to its left, and up off the surface.
local POSE = {
	pelvis = { 0, 0, 5, TORSO_TOL }, chest = { 16, 0, 6, TORSO_TOL }, head = { 30, 0, 5, TORSO_TOL },
	lshoulder = { 20, 8, 5, LIMB_TOL }, rshoulder = { 20, -8, 5, LIMB_TOL },
	lelbow = { 27, 18, 3, LIMB_TOL }, relbow = { 27, -18, 3, LIMB_TOL },
	lhand = { 32, 27, 3, LIMB_TOL }, rhand = { 32, -27, 3, LIMB_TOL },
	lknee = { -17, 10, 4, LIMB_TOL }, rknee = { -17, -10, 4, LIMB_TOL },
	lfoot = { -33, 14, 3, LIMB_TOL }, rfoot = { -33, -14, 3, LIMB_TOL },
}

-- Wound up against a strand in the air: upright along it, arms at the sides, legs together, front facing out.
local WRAP = {
	pelvis = { 0, 0, 0, TORSO_TOL }, chest = { 16, 0, 1, TORSO_TOL }, head = { 30, 0, 1, TORSO_TOL },
	lshoulder = { 20, 8, 0, LIMB_TOL }, rshoulder = { 20, -8, 0, LIMB_TOL },
	lelbow = { 10, 10, 1, LIMB_TOL }, relbow = { 10, -10, 1, LIMB_TOL },
	lhand = { 0, 9, 2, LIMB_TOL }, rhand = { 0, -9, 2, LIMB_TOL },
	lknee = { -17, 4, 0, LIMB_TOL }, rknee = { -17, -4, 0, LIMB_TOL },
	lfoot = { -33, 3, 0, LIMB_TOL }, rfoot = { -33, -3, 0, LIMB_TOL },
}

local function Drowsy(ent, d)
	ent.EvilFungusDrowsy = d
	if ent:IsPlayer() then ent:SetNW2Float(EvilFungus.DROWSY_VAR, d) end
end

local function Kilos(ent)
	local kg = 0
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then kg = kg + phys:GetMass() end
	end
	return kg
end

local function Pose(rag, ent)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local m = ent:GetBoneMatrix(rag:TranslatePhysBoneToBone(i))
		if IsValid(phys) and m then
			phys:SetPos(m:GetTranslation())
			phys:SetAngles(m:GetAngles())
			phys:Wake()
		end
	end
end

local function Body(ent)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag.EvilFungusSleeper = true
	rag:SetModel(ent:GetModel())
	rag:SetPos(ent:GetPos())
	rag:SetAngles(ent:GetAngles())
	rag:SetSkin(ent:GetSkin())
	rag:SetColor(ent:GetColor())
	rag:SetMaterial(ent:GetMaterial())
	for _, group in ipairs(ent:GetBodyGroups()) do
		rag:SetBodygroup(group.id, ent:GetBodygroup(group.id))
	end
	if ent:IsPlayer() then rag:SetNW2Vector(EvilFungus.COLOR_VAR, ent:GetPlayerColor()) end
	rag:Spawn()
	rag:Activate()

	local ok, err = pcall(Pose, rag, ent)
	if not ok or rag:GetPhysicsObjectCount() == 0 then
		if not ok then ErrorNoHalt("Evil Fungus couldn't lay a sleeper down: ", tostring(err), "\n") end
		rag:Remove()
		return
	end
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	return rag
end

local function Hide(npc)
	npc.EvilFungusHadNoTarget = npc:IsFlagSet(FL_NOTARGET)
	npc.EvilFungusMoveType = npc:GetMoveType()
	npc:SetNoDraw(true)
	npc:DrawShadow(false)
	npc:SetNotSolid(true)
	npc:SetMoveType(MOVETYPE_NONE)
	npc:AddFlags(FL_NOTARGET)
	npc:AddEFlags(EFL_NO_THINK_FUNCTION)
	npc:ClearSchedule()
	npc:SetEnemy(NULL)
end

local function Show(npc, spot)
	npc:SetPos(spot)
	npc:SetAngles(Angle(0, math.Rand(0, 360), 0))
	npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
	npc:SetMoveType(npc.EvilFungusMoveType or MOVETYPE_STEP)
	npc:SetNotSolid(false)
	npc:SetNoDraw(false)
	npc:DrawShadow(true)
	if not npc.EvilFungusHadNoTarget then npc:RemoveFlags(FL_NOTARGET) end
end

local function StandingSpot(ent, rag)
	local pos = rag:GetPos()
	local mins, maxs, mask = ent:OBBMins(), ent:OBBMaxs(), MASK_NPCSOLID
	if ent:IsPlayer() then
		mins, maxs = ent:GetHull()
		mask = MASK_PLAYERSOLID
	end
	for _, offset in ipairs(STANDING_OFFSETS) do
		local from = pos + offset + Vector(0, 0, 8)
		local tr = util.TraceHull({ start = from, endpos = from - Vector(0, 0, 96), mins = mins, maxs = maxs, mask = mask, filter = { ent, rag } })
		if not tr.StartSolid then return tr.HitPos end
	end
	return pos
end

local function Grips(rag)
	local grips, used = {}, {}
	for key, name in pairs(EvilFungus.HOLD_BONES) do
		local bone = rag:LookupBone(name)
		local index = bone and rag:TranslateBoneToPhysBone(bone)
		if not index or index < 0 or used[index] or not IsValid(rag:GetPhysicsObjectNum(index)) then
			return { pelvis = 0 }, false
		end
		used[index] = true
		grips[key] = index
	end
	return grips, true
end

local function GripPos(s, key)
	return s.rag:GetPhysicsObjectNum(s.grips[key]):GetPos()
end

-- Which way the front of the chest is pointing, worked out from where the shoulders and head are.
local function Facing(s)
	local across = GripPos(s, "lshoulder") - GripPos(s, "rshoulder")
	local f = across:Cross(GripPos(s, "head") - GripPos(s, "pelvis"))
	f:Normalize()
	return f
end

local function Tangent(v, up)
	local t = v - up * v:Dot(up)
	if t:LengthSqr() < 1e-4 then
		t = up:Angle():Up()
		t = t - up * t:Dot(up)
	end
	t:Normalize()
	return t
end

local function HeadWay(s, up)
	local v = s.biped and GripPos(s, "head") - GripPos(s, "pelvis") or s.rag:GetForward()
	return Tangent(v, up)
end

local function Target(s, key, at)
	local o = (s.pose or POSE)[key]
	local lift = o[3] * s.size + CARRY_LIFT * (1 - s.arrived)
	return at + s.along * (o[1] * s.size) + s.left * (o[2] * s.size) + s.up * lift
end

local function Clear(from, to)
	return not util.TraceLine({ start = from, endpos = to, mask = MASK_SOLID_BRUSHONLY }).Hit
end

-- How much room a spot leaves to lie spread out: open air to every limb, and something solid under it.
local function Room(s, node)
	local up = node.normal
	local along = HeadWay(s, up)
	local left = along:Cross(up)
	local base = node.pos + up * 8
	local score = 0
	for key, o in pairs(POSE) do
		if s.biped or key == "pelvis" then
			local spot = node.pos + along * (o[1] * s.size) + left * (o[2] * s.size)
			if Clear(base, spot + up * 8) and not Clear(spot + up * 4, spot - up * SUPPORT) then score = score + 1 end
		end
	end
	return score, along, left
end

local function SetStage(s, stage)
	s.stage, s.stageAt = stage, CurTime()
	s.rag:SetNW2Int(EvilFungus.STAGE_VAR, stage)
	s.rag:SetNW2Float(EvilFungus.STAGE_AT_VAR, s.stageAt)
end

local function Nest(s)
	local fungus = s.fungus
	if not IsValid(fungus) or not fungus.Mat then return false end
	local from = s.rag:GetPhysicsObjectNum(s.grips.pelvis):GetPos()
	local list = {}
	fungus.Mat:Near(from, NEST_SEARCH, function(node, d2)
		if not s.rejected[node] and not node.air then list[#list + 1] = { node = node, d2 = d2 } end
	end)
	table.sort(list, function(a, b) return a.d2 < b.d2 end)
	if #list == 0 then
		local far = fungus.Mat:Nearest(from, NEST_FAR, function(node) return not node.air and not s.rejected[node] end)
		if far then list[1] = { node = far } end
	end

	local best, bestScore
	for i = 1, math.min(#list, NEST_CANDIDATES) do
		local node = list[i].node
		local crowded = false
		for _, other in pairs(Sleep.sleepers) do
			if other ~= s and other.nest and other.stage ~= FREED and other.nest.pos:DistToSqr(node.pos) < NEST_APART * NEST_APART then
				crowded = true
				break
			end
		end
		if not crowded then
			local score, along, left = Room(s, node)
			if not bestScore or score > bestScore then best, bestScore, s.along, s.left = node, score, along, left end
		end
	end
	if not best then return false end

	s.nest, s.up, s.nestAt, s.okFor, s.bestError = best, best.normal, CurTime(), 0, nil
	s.rag:SetNW2Vector(EvilFungus.NEST_VAR, best.pos)
	s.rag:SetNW2Vector(EvilFungus.NEST_UP_VAR, best.normal)
	return true
end

local function Tugged(s, now)
	return s.gripped or now - (s.hitAt or -math.huge) < HIT_GRACE
end

-- Arms out, legs out, back to the mat: the way it likes to keep things. Pull on one and it pulls back harder.
local function Steer(s, dt)
	local at = s.carry
	local rag = s.rag
	local grip = Tugged(s, CurTime()) and TUG_GRIP or 1
	local top = MAX_SPEED * grip
	for key, index in pairs(s.grips) do
		local phys = rag:GetPhysicsObjectNum(index)
		if IsValid(phys) then
			local want = (Target(s, key, at) - phys:GetPos()) * (GAIN * grip)
			local speed = want:Length()
			if speed > top then want = want * (top / speed) end
			local vel = phys:GetVelocity()
			phys:SetVelocity(vel + (want - vel) * math.min(1, RESPONSE * dt))
			phys:Wake()
		end
	end

	if s.biped then
		local facing = Facing(s)
		if facing:Dot(s.up) < FLIP_DOT then
			local axis = facing:Cross(s.up)
			if axis:LengthSqr() < 1e-4 then axis = Vector(s.along) end
			axis:Normalize()
			for _, key in ipairs({ "pelvis", "chest" }) do
				local phys = rag:GetPhysicsObjectNum(s.grips[key])
				phys:AddAngleVelocity(phys:WorldToLocalVector(axis * FLIP_SPEED))
			end
		end
	end
end

local function Error(s)
	local total = 0
	for key, index in pairs(s.grips) do
		total = total + s.rag:GetPhysicsObjectNum(index):GetPos():Distance(Target(s, key, s.carry))
	end
	return total
end

-- An arm or leg caught on a joint limit or folded under the body gets shoved until it comes free.
local function Unstick(s, now)
	local err = Error(s)
	if not s.bestError or err < s.bestError * STALL_GAIN then
		s.bestError, s.stalledAt = err, now
		return
	end
	if now - s.stalledAt < STALL_TIME then return end
	s.bestError, s.stalledAt = nil, now
	for key, index in pairs(s.grips) do
		local phys = s.rag:GetPhysicsObjectNum(index)
		local off = Target(s, key, s.carry) - phys:GetPos()
		local tol = POSE[key][4] * s.loose
		if not TORSO[key] and off:LengthSqr() > tol * tol then
			phys:AddVelocity(off * KICK + VectorRand() * KICK_JITTER + s.up * KICK_JITTER)
		end
	end
end

local function Posed(s)
	if s.arrived < 1 then return false end
	local at = s.carry
	for key, index in pairs(s.grips) do
		local tol = POSE[key][4] * s.loose
		if s.rag:GetPhysicsObjectNum(index):GetPos():DistToSqr(Target(s, key, at)) > tol * tol then return false end
	end
	return not s.biped or Facing(s):Dot(s.up) > FACE_UP
end

-- Only something from outside gets a sleeper back: a hand on them, a hit, a blast. Flinging them about itself doesn't count.
-- Whoever last laid a hand on a sleeper, or hit one, or threw something at one.
local function Touched(s, by)
	if IsValid(by) and by:IsPlayer() then s.by = by end
end

local function Thrower(ent)
	if ent:IsPlayer() then return ent end
	return ent.GetPhysicsAttacker and ent:GetPhysicsAttacker(HIT_GRACE)
end

local function Rescued(s)
	local fungus = s.fungus
	if IsValid(s.by) and IsValid(fungus) then fungus.Mind:Watch(s.by, "rescue", 1) end
	Sleep.Free(s)
end

local function Torn(s, dt, now)
	local pelvis = s.rag:GetPhysicsObjectNum(s.grips.pelvis):GetPos()
	if pelvis:DistToSqr(Target(s, "pelvis", s.carry)) > EXTRACT * EXTRACT and Tugged(s, now) then
		s.tornFor = (s.tornFor or 0) + dt
		return s.tornFor >= TORN_FOR
	end
	s.tornFor = 0
	return false
end

-- Outermost parts go first, the trunk last, and the head not at all.
local function Schedule(rag)
	local head = EvilFungus.HeadBone(rag)
	local list, deepest = {}, 1
	for bone = 0, rag:GetBoneCount() - 1 do
		if not (head and EvilFungus.UnderHead(rag, bone, head)) then
			local depth, p = 0, rag:GetBoneParent(bone)
			while p and p >= 0 do
				depth = depth + 1
				p = rag:GetBoneParent(p)
			end
			list[#list + 1] = { bone = bone, depth = depth, scale = 1 }
			deepest = math.max(deepest, depth)
		end
	end
	for _, b in ipairs(list) do b.start = (1 - b.depth / deepest) * (1 - SHRINK_SPAN) end
	return list
end

local function Freeze(rag)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:EnableMotion(false) end
	end
end

local function Consume(s)
	SetStage(s, CONSUMING)
	s.consumeStart = CurTime()
	s.schedule = Schedule(s.rag)
	s.food = math.Clamp(Kilos(s.rag) * FOOD_PER_KG, FOOD_VALUE[1], FOOD_VALUE[2])
	s.fed, s.progress, s.held = 0, 0, 0
end

local function Keep(s)
	SetStage(s, KEPT)
	Freeze(s.rag)
	local owner = s.owner
	s.owner = nil
	if not IsValid(owner) then return end
	if owner:IsPlayer() then
		if owner.EvilFungusHeld == s then owner.EvilFungusHeld = nil end
	else
		owner.EvilFungusAsleep = nil
		owner:SetHealth(0)
		hook.Run("OnNPCKilled", owner, s.fungus, s.fungus)
		owner:Remove()
	end
end

function Sleep.Free(s)
	if s.stage >= KEPT then return end
	SetStage(s, FREED)
	if IsValid(s.fungus) then s.fungus:Unclaim(s.rag) end
end

local function Wake(s)
	local rag, owner = s.rag, s.owner
	Sleep.sleepers[rag] = nil
	rag.EvilFungusSleeper = nil
	rag:SetNW2Int(EvilFungus.STAGE_VAR, 0)
	for _, b in ipairs(s.schedule or {}) do rag:ManipulateBoneScale(b.bone, Vector(1, 1, 1)) end

	local rescued = IsValid(owner) and (not owner:IsPlayer() or owner.EvilFungusHeld == s)
	if not rescued then
		if EvilFungus.Food(rag) then EvilFungus.Foods[rag] = true end
		return
	end

	local spot = StandingSpot(owner, rag)
	if owner:IsPlayer() then
		local kit = s.kit or {}
		owner.EvilFungusHeld = nil
		owner.EvilFungusWaking = true
		owner:UnSpectate()
		owner:Spawn()
		owner.EvilFungusWaking = nil
		owner:SetNW2Bool(EvilFungus.ASLEEP_VAR, false)
		owner:SetPos(spot)
		owner:SetHealth(s.health or owner:GetMaxHealth())
		owner:SetArmor(kit.armor or 0)
		owner:StripWeapons()
		owner:RemoveAllAmmo()
		for _, w in ipairs(kit.weapons or {}) do
			local wep = owner:Give(w.class, true)
			if IsValid(wep) then
				wep:SetClip1(w.clip1)
				wep:SetClip2(w.clip2)
			end
		end
		for id, count in pairs(kit.ammo or {}) do owner:SetAmmo(count, id) end
		if kit.active then owner:SelectWeapon(kit.active) end
	else
		owner.EvilFungusAsleep = nil
		Show(owner, spot)
		owner.EvilFungusFear = 1
		Sleep.afraid[owner] = true
	end
	rag:Remove()
end

-- Builds up while the fibers are on you and wears off once they aren't.
function EvilFungus.Sedate(ent, amount, fungus)
	ent.EvilFungusDosedAt = CurTime()
	Sleep.drowsy[ent] = true
	Drowsy(ent, math.min(1, (ent.EvilFungusDrowsy or 0) + amount))
	if ent.EvilFungusDrowsy < 1 then return false end
	Sleep.Under(ent, fungus)
	return true
end

-- As far as the game is concerned a player just died. The body stays, and it's the fungus's now.
function Sleep.Under(ent, fungus)
	Sleep.drowsy[ent] = nil
	Drowsy(ent, 0)
	local rag = Body(ent)
	local aloft = not ent:IsOnGround() or nil

	if ent:IsPlayer() then
		local s
		if rag then
			local active = ent:GetActiveWeapon()
			local kit = { armor = ent:Armor(), ammo = ent:GetAmmo(), weapons = {}, active = IsValid(active) and active:GetClass() }
			for _, wep in ipairs(ent:GetWeapons()) do
				kit.weapons[#kit.weapons + 1] = { class = wep:GetClass(), clip1 = wep:Clip1(), clip2 = wep:Clip2() }
			end
			s = { kit = kit, health = ent:Health(), aloft = aloft }
		end
		ent:KillSilent()
		ent:AddDeaths(1)
		hook.Run("PlayerDeath", ent, fungus, fungus)
		ent:SetNW2Bool(EvilFungus.ASLEEP_VAR, true)
		if not rag then return end
		ent:Spectate(OBS_MODE_CHASE)
		ent:SpectateEntity(rag)
		ent.EvilFungusHeld = s
		Sleep.Hold(rag, ent, fungus, s)
		return rag
	end

	if not rag then
		ent:SetHealth(0)
		hook.Run("OnNPCKilled", ent, fungus, fungus)
		ent:Remove()
		return
	end
	Hide(ent)
	ent.EvilFungusAsleep = rag
	Sleep.Hold(rag, ent, fungus, { aloft = aloft })
	return rag
end

-- Caught up in the air, they're held on the strand that got them, and the way down is back along it.
local function Hang(s)
	local from = s.rag:GetPhysicsObjectNum(s.grips.pelvis):GetPos()
	local node = s.fungus.Mat:Nearest(from, CATCH_RADIUS, function(n) return n.air end)
	if not node then return false end
	local path = { node }
	while true do
		local low
		for _, e in ipairs(node.edges) do
			local other = e.a == node and e.b or e.a
			if other.air and other.height < node.height and (not low or other.height < low.height) then low = other end
		end
		if not low then break end
		path[#path + 1] = low
		node = low
	end

	local first = path[1]
	s.path, s.leg, s.pose, s.arrived, s.wrapAt = path, 1, WRAP, 1, CurTime()
	s.along = Vector(first.normal)
	s.up = Tangent(from - first.pos, s.along)
	s.left = s.along:Cross(s.up)
	s.nest = first
	s.rag:SetNW2Vector(EvilFungus.NEST_VAR, first.pos)
	s.rag:SetNW2Vector(EvilFungus.NEST_UP_VAR, s.up)
	s.rag:SetNW2Float(EvilFungus.WRAP_VAR, s.wrapAt)
	return true
end

function Sleep.Hold(rag, owner, fungus, s)
	s.rag, s.owner, s.rejected, s.loose, s.arrived = rag, owner, {}, 1, 0
	s.brain = EvilFungus.Brain(owner)
	s.profile = owner:IsPlayer() and EvilFungus.Profile(owner) or nil
	s.grips, s.biped = Grips(rag)
	s.size = 1
	if s.biped then
		s.size = math.Clamp(GripPos(s, "head"):Distance(GripPos(s, "pelvis")) / REST_TORSO, 0.5, 2)
	end
	s.carry = rag:GetPhysicsObjectNum(s.grips.pelvis):GetPos()
	s.since = CurTime()
	rag:SetNW2Float(EvilFungus.SINCE_VAR, s.since)
	Sleep.sleepers[rag] = s
	SetStage(s, POSING)
	if IsValid(fungus) then fungus:Claim(rag) end
	rag:AddCallback("PhysicsCollide", function(ent, data)
		local held = Sleep.sleepers[ent]
		local hit = data.HitEntity
		if held and IsValid(hit) and not hit:IsWorld() and data.Speed > SLAM_SPEED then
			held.hitAt = CurTime()
			Touched(held, Thrower(hit))
		end
	end)
	if s.aloft and IsValid(s.fungus) and Hang(s) then return end
	if not Nest(s) then Sleep.Free(s) end
end

local function Land(s, now)
	s.path, s.pose, s.arrived = nil, nil, 0
	s.rag:SetNW2Float(EvilFungus.LANDED_VAR, now)
	SetStage(s, POSING)
	if not Nest(s) then Sleep.Free(s) end
end

-- Hangs on to them up there for a moment while it winds them up, then works them down the strands back to the ground.
local function Lowering(s, dt, now)
	if Torn(s, dt, now) then return Rescued(s) end
	s.fungus.TunnelAt = now
	local node = s.path[s.leg]
	while node and node.dead do
		s.leg = s.leg + 1
		node = s.path[s.leg]
	end
	if not node then return Land(s, now) end
	if s.nest ~= node then
		s.nest = node
		s.rag:SetNW2Vector(EvilFungus.NEST_VAR, node.pos)
	end

	local to = node.pos + s.up * (WRAP_OUT * s.size)
	local d = to - s.carry
	local step = LOWER_SPEED * dt
	if d:LengthSqr() <= step * step then
		s.carry = to
		if s.leg > 1 or now - s.wrapAt >= WRAP_HOLD then s.leg = s.leg + 1 end
	else
		s.carry = s.carry + d:GetNormalized() * step
	end
	Steer(s, dt)
end

local function Posing(s, dt, now)
	if Torn(s, dt, now) then return Rescued(s) end
	local floor = s.nest.pos
	local d = floor - s.carry
	local step = CARRY_SPEED * dt
	if d:LengthSqr() <= step * step then
		s.carry = Vector(floor)
		s.arrived = math.min(1, s.arrived + dt * 2)
	else
		s.carry = s.carry + d:GetNormalized() * step
	end
	Steer(s, dt)
	if s.arrived >= 1 then Unstick(s, now) end

	if Posed(s) then
		s.okFor = s.okFor + dt
		if s.okFor >= POSED_FOR then return Consume(s) end
	else
		s.okFor = 0
	end

	if now - s.nestAt > POSE_TIMEOUT then
		s.rejected[s.nest] = true
		s.loose = s.loose * LOOSEN
		if not Nest(s) then
			s.rejected = {}
			Nest(s)
		end
	end
end

hook.Add("Tick", "EvilFungusSleep", function()
	local now, dt = CurTime(), engine.TickInterval()
	for rag, s in pairs(Sleep.sleepers) do
		if not IsValid(rag) then
			Sleep.sleepers[rag] = nil
		elseif s.stage == POSING then
			if not IsValid(s.fungus) then
				Sleep.Free(s)
			elseif s.path then
				Lowering(s, dt, now)
			elseif s.nest and not s.nest.dead then
				Posing(s, dt, now)
			else
				Sleep.Free(s)
			end
		elseif s.stage == CONSUMING then
			if Torn(s, dt, now) then Rescued(s) else Steer(s, dt) end
		end
	end
end)

local function Digest(s, now)
	s.progress = math.min(1, s.progress + CONSUME_UPDATE * EvilFungus.TimeScale() / math.max(1, EvilFungus.Setting("consume_time")))
	local k = s.progress
	local min = EvilFungus.MIN_SCALE
	for _, b in ipairs(s.schedule) do
		local scale = Lerp(math.Clamp((k - b.start) / SHRINK_SPAN, 0, 1), 1, min)
		if math.abs(scale - b.scale) > 0.01 or scale == min and b.scale ~= min then
			b.scale = scale
			s.rag:ManipulateBoneScale(b.bone, Vector(scale, scale, scale))
		end
	end
	s.rag:SetColor(Color(Lerp(k, 255, PALE[1]), Lerp(k, 255, PALE[2]), Lerp(k, 255, PALE[3])))
	s.rag:SetNW2Float(EvilFungus.CONSUMED_VAR, k)

	local due = s.food * k
	local fungus, nest = s.fungus, s.nest
	if due > s.fed and IsValid(fungus) and nest and not nest.dead then
		fungus.Mat:SetMass(nest, nest.m + due - s.fed)
	end
	s.fed = due
	if k >= 1 then
		s.done = true
		if IsValid(fungus) then
			fungus.Mind:Keep(s.brain)
			if s.profile then fungus.Mind:Learn(s.profile) end
		end
	end
end

-- Whatever got pulled out of it wants nothing to do with it, or anything it's grown over, for a good while.
local function Fear(now)
	for npc in pairs(Sleep.afraid) do
		if not IsValid(npc) or not npc:IsNPC() then
			Sleep.afraid[npc] = nil
		else
			npc.EvilFungusFear = npc.EvilFungusFear - FEAR_UPDATE / FEAR_TIME
			if npc.EvilFungusFear <= 0 then
				Sleep.afraid[npc] = nil
			elseif now >= (npc.EvilFungusFleeAt or 0) and not npc.EvilFungusAsleep then
				local pos = npc:GetPos()
				local radius = Lerp(npc.EvilFungusFear, FEAR_RADIUS[1], FEAR_RADIUS[2])
				local pad = Vector(radius, radius, radius)
				for colony in pairs(EvilFungus.Colonies or {}) do
					local mat = IsValid(colony) and colony.Mat
					local node = mat and mat.mins and pos:WithinAABox(mat.mins - pad, mat.maxs + pad) and mat:Nearest(pos, radius)
					if node then
						local away = pos - node.pos
						away.z = 0
						if away:LengthSqr() < 1 then
							away = VectorRand()
							away.z = 0
						end
						away:Normalize()
						npc:SetLastPosition(pos + away * FLEE_DIST)
						npc:SetSchedule(SCHED_FORCED_GO_RUN)
						npc.EvilFungusFleeAt = now + FLEE_AGAIN
						break
					end
				end
			end
		end
	end
end

local nextUpdate, nextConsume, nextFear = 0, 0, 0

hook.Add("Think", "EvilFungusSleep", function()
	local now = CurTime()
	if now >= nextUpdate then
		nextUpdate = now + UPDATE
		for ent in pairs(Sleep.drowsy) do
			if not IsValid(ent) then
				Sleep.drowsy[ent] = nil
			elseif now - (ent.EvilFungusDosedAt or 0) > DOSE_FRESH then
				local d = ent.EvilFungusDrowsy - UPDATE * EvilFungus.TimeScale() / WEAR_OFF
				if d <= 0 then
					d = 0
					Sleep.drowsy[ent] = nil
				end
				Drowsy(ent, d)
			end
		end

		local rescue = EvilFungus.Setting("rescue_time")
		local scale = EvilFungus.TimeScale()
		for rag, s in pairs(Sleep.sleepers) do
			if IsValid(rag) then
				local owner = s.owner
				if IsValid(owner) then
					if not owner:IsPlayer() then
						owner:SetPos(rag:GetPos())
					elseif owner.EvilFungusHeld == s and owner:GetObserverTarget() ~= rag then
						owner:SpectateEntity(rag)
					end
				end
				if s.stage == CONSUMING then s.held = s.held + UPDATE * scale end
				if s.stage == CONSUMING and s.held >= rescue then
					Keep(s)
				elseif s.stage == FREED and now - s.stageAt >= WAKE_AFTER then
					Wake(s)
				end
			end
		end
	end

	if now >= nextConsume then
		nextConsume = now + CONSUME_UPDATE
		for rag, s in pairs(Sleep.sleepers) do
			if IsValid(rag) and (s.stage == CONSUMING or s.stage == KEPT) and not s.done then Digest(s, now) end
		end
	end

	if now >= nextFear then
		nextFear = now + FEAR_UPDATE
		Fear(now)
	end
end)

local function Locked(ent)
	local s = Sleep.sleepers[ent]
	return s ~= nil and s.stage == KEPT
end

local function Held(ent)
	return Sleep.sleepers[ent] ~= nil
end

hook.Add("PhysgunPickup", "EvilFungusSleep", function(_, ent) if Locked(ent) then return false end end)
hook.Add("GravGunPickupAllowed", "EvilFungusSleep", function(_, ent) if Locked(ent) then return false end end)
hook.Add("CanTool", "EvilFungusSleep", function(_, tr) if IsValid(tr.Entity) and Held(tr.Entity) then return false end end)
hook.Add("CanProperty", "EvilFungusSleep", function(_, _, ent) if Held(ent) then return false end end)
hook.Add("EntityTakeDamage", "EvilFungusSleep", function(ent, dmg)
	if ent.EvilFungusAsleep or Locked(ent) then return true end
	local s = Sleep.sleepers[ent]
	if s then
		s.hitAt = CurTime()
		Touched(s, dmg:GetAttacker())
	end
end)

local function Grabbed(ply, ent)
	local s = Sleep.sleepers[ent]
	if s then
		s.gripped = true
		Touched(s, ply)
	end
end

local function Dropped(_, ent)
	local s = Sleep.sleepers[ent]
	if s then
		s.gripped = nil
		s.hitAt = CurTime()
	end
end

local function Punted(ply, ent)
	local s = Sleep.sleepers[ent]
	if s then
		s.hitAt = CurTime()
		Touched(s, ply)
	end
end

hook.Add("OnPhysgunPickup", "EvilFungusSleep", Grabbed)
hook.Add("PhysgunDrop", "EvilFungusSleep", Dropped)
hook.Add("GravGunOnPickedUp", "EvilFungusSleep", Grabbed)
hook.Add("GravGunOnDropped", "EvilFungusSleep", Dropped)
hook.Add("GravGunPunt", "EvilFungusSleep", Punted)

hook.Add("PlayerDeathThink", "EvilFungusSleep", function(ply)
	if ply.EvilFungusHeld and EvilFungus.Setting("give_up") == 0 then return false end
end)

hook.Add("EntityRemoved", "EvilFungusSleep", function(ent)
	local s = Sleep.sleepers[ent]
	if not s then return end
	Sleep.sleepers[ent] = nil
	local owner = s.owner
	if not IsValid(owner) then return end
	if owner:IsPlayer() then
		if owner.EvilFungusHeld == s then owner.EvilFungusHeld = nil end
	elseif owner.EvilFungusAsleep then
		owner:Remove()
	end
end)

hook.Add("PlayerSpawn", "EvilFungusSleep", function(ply)
	if ply.EvilFungusWaking then return end
	local s = ply.EvilFungusHeld
	if s then s.owner = nil end
	ply.EvilFungusHeld = nil
	ply:SetNW2Bool(EvilFungus.ASLEEP_VAR, false)
	Drowsy(ply, 0)
	Sleep.drowsy[ply] = nil
end)
