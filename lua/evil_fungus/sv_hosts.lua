EvilFungus = EvilFungus or {}
local Hosts = EvilFungus.Hosts or { list = {} }
EvilFungus.Hosts = Hosts
local list = Hosts.list

local HOST, SPENT, LOOSE = EvilFungus.HOST, EvilFungus.SPENT, EvilFungus.LOOSE

local MAX_HOSTS = 8
local RISE_AT = { 0.3, 0.5 }
local RISE_TIME = 2.5
local RISE_LOW = 8
local RISE_PULL = 90
local HEALTH = 120
local HEAD_HIT = 12
local HEAD_DAMAGE = 2
local BLAST_DAMAGE = 2
local BURN_DAMAGE = 3
local BURN_RATE = 30

local STAND = 0.93
local STRIDE = 0.6
local HUNCH = 0.35
local NOD = 0.7
local LOLL = 1.5
local BOB = 1.5
local KNEE = 0.12
local STEP_TIME = 0.35
local STEP_LIFT = 8
local ANKLE = 4
local ARRIVE = 0.12
local PULL = 700
local DAMP = 0.8

local SPEED = 70
local LUNGE = 1.5
local LUNGE_RANGE = 160
local HAUL_SPEED = 45
local HAUL_PULL = 350
local HAUL_PAST = 48
local HAUL_SLIP = 96
local HOME_NEAR = 512
local FOOTING = 0.5
local TURN = 140
local LEASH = 24
local WALL_LOOK = 40
local DETOUR_LOOK = 96
local DETOUR_TIME = 1.5
local STUCK_TIME = 2
local STUCK_MOVE = 12
local ARRIVED = 24

local SCAN = 0.5
local SIGHT = 1600
local REACH = 52
local DOSE = 1.5
local HAUL_TIME = 40
local WANDER = { 6, 11 }
local WANDER_RANGE = { 250, 600 }
local SHED = { 12, 20 }
local SHED_MASS = 20
local SHED_CLEAR = 300
local TETHER_REACH = 64
local TETHER_HEIGHT = 128
local PACE_AHEAD = 35
local PACE_OUT = 0.75
local PACE_TURN = { 8, 16 }
local HAND_OFF = 0.6

local PERCH_UP = 700
local PERCH_MIN = 110
local PERCH_WALL = 400
local PERCH_HIGH = 260
local PERCH_FOOT = 40
local HANG = 10
local CLIMB_TIME = 15
local HOIST_TIME = 5
local HOIST_SPEED = 90
local HOIST_NEAR = 16
local WRITHE_TIME = 3
local WRITHE_KICK = { 0.12, 0.3 }
local WRITHE_FORCE = 250
local BURST_MASS = 60
local BURST_CLEAR = 120

local GROAN = { 5, 9 }
local RISE_SOUND = "npc/barnacle/barnacle_tongue_pull%d.wav"
local GROAN_SOUND = "npc/barnacle/barnacle_digesting%d.wav"
local GRAB_SOUND = "npc/barnacle/barnacle_bark%d.wav"
local BURST_SOUNDS = { "physics/flesh/flesh_bloody_break.wav", "npc/antlion_grub/squashed.wav" }
local EYE_FLAGS = 65536 + 131072
local WATER = bit.bor(CONTENTS_WATER, CONTENTS_SLIME)

local PARTS = {
	{ "pelvis", { "pelvis", "hips" } },
	{ "chest", { "spine4", "spine3", "spine2", "chest", "spine1", "spine" } },
	{ "head", { "head" } },
	{ "thigh", { "thigh" }, true },
	{ "calf", { "calf", "shin" }, true },
	{ "foot", { "foot" }, true },
	{ "upperarm", { "upperarm", "upper_arm" }, true },
	{ "forearm", { "forearm", "lowerarm" }, true },
	{ "hand", { "hand" }, true },
}
local NEEDED = { "pelvis", "chest", "head", "thighl", "thighr", "footl", "footr" }
local SIDES = { l = -1, r = 1 }

local ai_disabled = GetConVar("ai_disabled")
local ai_ignoreplayers = GetConVar("ai_ignoreplayers")

local function Side(name)
	if string.find(name, "left", 1, true) or string.find(name, "_l_", 1, true) or string.find(name, "%.l_") or string.find(name, "^l_") or string.find(name, "[_%.]l$") then return "l" end
	if string.find(name, "right", 1, true) or string.find(name, "_r_", 1, true) or string.find(name, "%.r_") or string.find(name, "^r_") or string.find(name, "[_%.]r$") then return "r" end
end

local function Measure(rag, found)
	local seen = {}
	for _, key in ipairs(NEEDED) do
		local i = found[key]
		if not i or seen[i] then return end
		seen[i] = true
	end
	local function At(key)
		local i = found[key]
		local phys = i and rag:GetPhysicsObjectNum(i)
		return IsValid(phys) and phys:GetPos() or nil
	end
	local function Leg(side)
		local thigh, calf, foot = At("thigh" .. side), At("calf" .. side), At("foot" .. side)
		if calf then return thigh:Distance(calf) + calf:Distance(foot) end
		return thigh:Distance(foot)
	end

	local pelvis, chest, head = At("pelvis"), At("chest"), At("head")
	local thighl, thighr = At("thighl"), At("thighr")
	if not (pelvis and chest and head and thighl and thighr and At("footl") and At("footr")) then return end
	local leg, torso = (Leg("l") + Leg("r")) * 0.5, pelvis:Distance(chest)
	if leg < 12 or torso < 4 then return end
	local axis = (chest - pelvis):GetNormalized()
	local rig = {
		phys = found, leg = leg, torso = torso, neck = chest:Distance(head),
		hip = thighl:Distance(thighr) * 0.5, hipDrop = ((thighl + thighr) * 0.5 - pelvis):Dot(axis),
	}
	rig.stand = leg * STAND - rig.hipDrop + ANKLE
	rig.stride = leg * STRIDE

	local ul, ur = At("upperarml"), At("upperarmr")
	if ul and ur then
		rig.shoulder, rig.shoulderUp = ul:Distance(ur) * 0.5, ((ul + ur) * 0.5 - chest):Dot(axis)
		local fl, hl = At("forearml"), At("handl")
		rig.arm = hl and (fl and ul:Distance(fl) + fl:Distance(hl) or ul:Distance(hl)) or torso
	end
	return rig
end

local function Rig(rag)
	if rag.EvilFungusRig ~= nil then return rag.EvilFungusRig end
	local found, rank = {}, {}
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local name = string.lower(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)) or "")
		for _, part in ipairs(PARTS) do
			local side = part[3] and Side(name)
			if not part[3] or side then
				for r, word in ipairs(part[2]) do
					if string.find(name, word, 1, true) then
						local key = part[1] .. (side or "")
						if not rank[key] or r < rank[key] then found[key], rank[key] = i, r end
						break
					end
				end
			end
		end
	end
	local rig = Measure(rag, found) or false
	rag.EvilFungusRig = rig
	return rig
end

local function Part(h, key)
	local i = h.rig.phys[key]
	if not i then return end
	local phys = h.rag:GetPhysicsObjectNum(i)
	if IsValid(phys) then return phys end
end

local function Push(h, key, pos, arrive, speed, dt)
	local phys = Part(h, key)
	if not phys then return end
	phys:Wake()
	phys:ComputeShadowControl({
		secondstoarrive = arrive, pos = pos, angle = phys:GetAngles(),
		maxspeed = speed, maxspeeddamp = speed * 2, maxangular = 0, maxangulardamp = 0,
		dampfactor = DAMP, teleportdistance = 0, deltatime = dt,
	})
end

local function Solid(ent)
	return not (ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "prop_ragdoll" or ent.EvilFungusSleeper)
end

local function Floor(pos, depth)
	local tr = util.TraceLine({ start = pos + vector_up * 24, endpos = pos - vector_up * depth, filter = Solid, mask = MASK_SOLID })
	if tr.Hit and not tr.StartSolid then return tr.HitPos, tr.HitNormal end
end

local function Count()
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	return n
end

local function Colony(h)
	local c = h.fungus
	if IsValid(c) and not c.Absorbed then return c end
	for colony in pairs(EvilFungus.Colonies or {}) do
		if IsValid(colony) and not colony.Absorbed then
			h.fungus = colony
			return colony
		end
	end
end

local function Fights(npc)
	return IsValid(npc) and npc:IsNPC() and npc:GetClass() ~= "npc_bullseye"
end

local function Hates(npc)
	return Fights(npc) and not npc.EvilFungusAlly
end

local function Expose(h)
	local eye = ents.Create("npc_bullseye")
	if not IsValid(eye) then return end
	eye:SetPos(h.rag:GetPos() + vector_up * 16)
	eye:SetParent(h.rag)
	eye:SetKeyValue("spawnflags", tostring(EYE_FLAGS))
	eye:Spawn()
	eye:Activate()
	h.rag:DeleteOnRemove(eye)
	h.eye = eye
	for _, npc in ipairs(ents.GetAll()) do
		if Hates(npc) then npc:AddEntityRelationship(eye, D_HT, 0) end
	end
end

local function Prey(ent)
	if not IsValid(ent) or ent:IsFlagSet(FL_NOTARGET) or ent.EvilFungusAsleep or ent.EvilFungusAlly or EvilFungus.CrawlerHas(ent) or Evil.Owner(ent) then return false end
	if ent:IsPlayer() then
		return EvilFungus.Setting("attack_players") > 0
			and not (ai_ignoreplayers and ai_ignoreplayers:GetBool())
			and ent:Alive() and not ent:InVehicle()
			and ent:GetMoveType() ~= MOVETYPE_NOCLIP
			and ent:GetObserverMode() == OBS_MODE_NONE
	end
	return EvilFungus.Setting("attack_npcs") > 0 and Fights(ent) and ent:Health() > 0 and EvilFungus.Bleeds(ent)
end

local function Smells(from, ent)
	return not util.TraceLine({ start = from, endpos = ent:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit
end

local function Within(h, ent)
	local t = h.tether
	if not t then return true end
	local p, r = ent:GetPos(), t.radius + TETHER_REACH
	return (p.x - t.at.x) ^ 2 + (p.y - t.at.y) ^ 2 < r * r and math.abs(p.z - t.at.z) < TETHER_HEIGHT
end

local function Pick(h, from)
	local best, bestD2 = nil, SIGHT * SIGHT
	local function Try(ent)
		local d2 = ent:GetPos():DistToSqr(from)
		if d2 < bestD2 and Prey(ent) and Within(h, ent) and Smells(from, ent) then best, bestD2 = ent, d2 end
	end
	for _, ply in ipairs(player.GetAll()) do Try(ply) end
	for ent in pairs(EvilFungus.Creatures or {}) do
		if IsValid(ent) then Try(ent) end
	end
	return best
end

local function Footing(n)
	return not n.air and n.up > FOOTING
end

local function Home(pos)
	local best, bestD2
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and not colony.Absorbed and colony.Mat
		if mat and mat.count > 0 then
			local node = mat:Nearest(pos, HOME_NEAR, Footing)
			if not node then
				local nearD2
				for _, n in pairs(mat.nodes) do
					if Footing(n) then
						local d2 = n.pos:DistToSqr(pos)
						if not nearD2 or d2 < nearD2 then node, nearD2 = n, d2 end
					end
				end
			end
			local d2 = node and node.pos:DistToSqr(pos)
			if d2 and (not bestD2 or d2 < bestD2) then best, bestD2 = node.pos, d2 end
		end
	end
	return best
end

local function Plant(h, from, pos, normal, mass, clear)
	if not EvilFungus.Room() or EvilFungus.Taken(pos, clear) then return false end
	if bit.band(util.PointContents(pos + normal * 2), WATER) ~= 0 then return false end
	if not EvilFungus.Plant(pos, normal, mass, h.mind, h.creator) then return false end
	local fx = EffectData()
	fx:SetStart(from)
	fx:SetOrigin(pos)
	fx:SetNormal(normal)
	util.Effect("evil_fungus_spore", fx, true, true)
	return true
end

local function Release(h)
	local hl = h.haul
	h.haul = nil
	if hl and hl.s.hauler == h.rag then
		hl.s.hauler = nil
		hl.s.stageAt = CurTime()
	end
end

local function Collapse(h)
	local rag = h.rag
	list[rag] = nil
	if h.haul then Release(h) end
	SafeRemoveEntity(h.eye)
	if not IsValid(rag) then return end
	rag:SetNW2Int(EvilFungus.STAGE_VAR, SPENT)
	rag:SetNW2Vector(EvilFungus.ANCHOR_VAR, vector_origin)
	rag.EvilFungusSleeper = nil
	rag.DoNotDuplicate = nil
	rag.EvilFungusSpent = true
	if rag:IsOnFire() then rag.EvilFungusBurnt = true end
	if EvilFungus.Food(rag) then EvilFungus.Foods[rag] = true end
end

local function Reset(h)
	local pelvis = Part(h, "pelvis")
	local at = pelvis and pelvis:GetPos() or h.rag:GetPos()
	local ground = Floor(at, h.rig.leg * 3)
	h.root = ground or Vector(at.x, at.y, at.z - h.rig.stand)
	h.feet = {}
	for side in pairs(SIDES) do
		local foot = Part(h, "foot" .. side)
		local pos = foot and foot:GetPos() or h.root
		h.feet[side] = { at = Floor(pos, h.rig.leg) or pos }
	end
	h.stuckPos, h.stuckAt = h.root, CurTime()
end

local function Facing(h)
	local pelvis, head = Part(h, "pelvis"), Part(h, "head")
	if not pelvis or not head then return 0 end
	local d = head:GetPos() - pelvis:GetPos()
	d.z = 0
	return d:LengthSqr() > 1 and d:Angle().y or math.Rand(0, 360)
end

local function Rouse(h, now)
	h.limp = nil
	if h.state == "hoist" or h.state == "writhe" then return end
	if h.state ~= "rise" then h.resume = h.state end
	h.yaw = Facing(h)
	h.state, h.stateAt = "rise", now
	Reset(h)
end

local function Step(h, side, sign, f, r, now, k)
	local foot, rig = h.feet[side], h.rig
	if foot.start then
		local t = (now - foot.start) / STEP_TIME
		if t < 1 then return LerpVector(t, foot.from, foot.to) + vector_up * (math.sin(t * math.pi) * STEP_LIFT) end
		foot.at, foot.start = foot.to, nil
	end
	local other = h.feet[side == "l" and "r" or "l"]
	if k < 1 or other.start then return foot.at end
	local home = h.root + r * (sign * rig.hip)
	local away = Vector(foot.at.x - home.x, foot.at.y - home.y, 0):Length()
	local otherHome = h.root - r * (sign * rig.hip)
	local otherAway = Vector(other.at.x - otherHome.x, other.at.y - otherHome.y, 0):Length()
	if away > rig.stride * 0.5 and away >= otherAway then
		local to = home + f * (rig.stride * 0.45 * h.moving)
		foot.from, foot.to, foot.start = foot.at, Floor(to, rig.leg * 2) or to, now
	end
	return foot.at
end

local function Stance(h, now, dt, k, reach, drag)
	local rig = h.rig
	local ang = Angle(0, h.yaw, 0)
	local f, r, up = ang:Forward(), ang:Right(), vector_up
	local pelvis = h.root + up * (Lerp(k, RISE_LOW, rig.stand) + math.sin(h.phase * 2) * BOB * k)
	local axis = LerpVector(k, f, (up + f * HUNCH):GetNormalized()):GetNormalized()
	local chest = pelvis + axis * rig.torso
	local nod = LerpVector(k, f, (up + f * NOD):GetNormalized()):GetNormalized()
	local head = chest + nod * rig.neck + r * (math.sin(now * 1.3 + h.seed) * LOLL)
	local pull = Lerp(k, RISE_PULL, PULL)
	Push(h, "pelvis", pelvis, ARRIVE, pull, dt)
	Push(h, "chest", chest, ARRIVE, pull, dt)
	Push(h, "head", head, ARRIVE * 1.5, pull, dt)
	for side, sign in pairs(SIDES) do
		local hip = pelvis + axis * rig.hipDrop + r * (sign * rig.hip)
		local foot = Step(h, side, sign, f, r, now, k) + up * ANKLE
		Push(h, "thigh" .. side, hip, ARRIVE, pull, dt)
		Push(h, "foot" .. side, foot, ARRIVE * 0.7, pull, dt)
		Push(h, "calf" .. side, (hip + foot) * 0.5 + f * (rig.leg * KNEE), ARRIVE * 2, pull * 0.6, dt)
		if rig.arm then
			local shoulder = chest + axis * rig.shoulderUp + r * (sign * rig.shoulder)
			Push(h, "upperarm" .. side, shoulder, ARRIVE * 2, pull * 0.6, dt)
			local hand
			if drag and side == "r" then
				hand = pelvis + r * (rig.hip * 2) - f * 8
			elseif reach then
				hand = reach + r * (sign * 5)
			else
				hand = shoulder + f * (rig.arm * 0.85) - up * (rig.arm * 0.2) + up * (math.sin(now * 2 + sign + h.seed) * 2)
			end
			Push(h, "hand" .. side, hand, ARRIVE * 2.5, pull * 0.5, dt)
		end
	end
	return f, r
end

local function Steer(h, goal, speed, now, dt)
	local rig = h.rig
	local want = h.yaw
	local to = goal and goal - h.root
	if to then to.z = 0 end
	local moving = to and to:LengthSqr() > ARRIVED * ARRIVED
	if now < (h.detourUntil or 0) then
		want = h.detourYaw
	elseif moving then
		want = to:Angle().y
	end
	h.yaw = math.ApproachAngle(h.yaw, want, TURN * dt)
	local fwd = Angle(0, h.yaw, 0):Forward()

	local pelvis = Part(h, "pelvis")
	local actual = pelvis and pelvis:GetPos() or h.root
	if moving then
		local eye = h.root + vector_up * (rig.stand * 0.6)
		local tr = util.TraceLine({ start = eye, endpos = eye + fwd * WALL_LOOK, filter = Solid, mask = MASK_SOLID })
		local stuck = now - h.stuckAt > STUCK_TIME
		if stuck then
			if Vector(actual.x - h.stuckPos.x, actual.y - h.stuckPos.y, 0):Length() < STUCK_MOVE and now >= (h.detourUntil or 0) then
				h.detourYaw = h.yaw + (math.random() < 0.5 and -1 or 1) * math.Rand(90, 150)
				h.detourUntil = now + DETOUR_TIME
			end
			h.stuckPos, h.stuckAt = actual, now
		end
		if tr.Hit and tr.HitNormal.z < 0.7 and now >= (h.detourUntil or 0) then
			local best, bestFrac
			for _, turn in ipairs({ 70, -70 }) do
				local dir = Angle(0, h.yaw + turn, 0):Forward()
				local frac = util.TraceLine({ start = eye, endpos = eye + dir * DETOUR_LOOK, filter = Solid, mask = MASK_SOLID }).Fraction
				if not bestFrac or frac > bestFrac then best, bestFrac = turn, frac end
			end
			h.detourYaw, h.detourUntil = h.yaw + best, now + DETOUR_TIME
		end
	else
		h.stuckPos, h.stuckAt = actual, now
	end

	local step = moving and math.min(speed * dt, to:Length()) or 0
	local root = h.root + fwd * step
	local off = Vector(root.x - actual.x, root.y - actual.y, 0)
	if off:Length() > LEASH then
		off:Normalize()
		root = Vector(actual.x, actual.y, root.z) + off * LEASH
	end
	local t = h.tether
	if t then
		local out = Vector(root.x - t.at.x, root.y - t.at.y, 0)
		local len = out:Length()
		if len > t.radius then root = Vector(t.at.x, t.at.y, root.z) + out * (t.radius / len) end
	end
	local ground = Floor(Vector(root.x, root.y, actual.z), 512)
	if ground then root.z = ground.z end
	h.root = root
	h.moving = moving and 1 or 0
	h.phase = h.phase + step / math.max(1, rig.stride) * math.pi
end

local function Wander(h, now, from)
	if h.wanderGoal and now < (h.wanderAt or 0) and Vector(h.wanderGoal.x - h.root.x, h.wanderGoal.y - h.root.y, 0):Length() > ARRIVED * 2 then
		return h.wanderGoal
	end
	h.wanderAt = now + math.Rand(WANDER[1], WANDER[2])
	local dir = Angle(0, math.Rand(0, 360), 0):Forward()
	local tr = util.TraceLine({ start = from, endpos = from + dir * math.Rand(WANDER_RANGE[1], WANDER_RANGE[2]), filter = Solid, mask = MASK_SOLID })
	h.wanderGoal = tr.HitPos - dir * 32
	return h.wanderGoal
end

local function Pace(h, now)
	local t = h.tether
	if now >= (h.paceAt or 0) then
		h.paceAt = now + math.Rand(PACE_TURN[1], PACE_TURN[2])
		h.pace = math.random() < 0.5 and -1 or 1
	end
	local out = Vector(h.root.x - t.at.x, h.root.y - t.at.y, 0)
	local yaw = out:LengthSqr() > 1 and out:Angle().y or math.Rand(0, 360)
	return t.at + Angle(0, yaw + h.pace * PACE_AHEAD, 0):Forward() * (t.radius * PACE_OUT)
end

local function Ceiling(pelvis, groundZ)
	local tr = util.TraceLine({ start = pelvis, endpos = pelvis + vector_up * PERCH_UP, mask = MASK_SOLID_BRUSHONLY })
	if tr.Hit and not tr.HitSky and not tr.HitNoDraw and not tr.StartSolid and tr.HitNormal.z < -0.7 and tr.HitPos.z - groundZ >= PERCH_MIN then
		return tr.HitPos, tr.HitNormal
	end
end

local function Wall(pelvis, groundZ)
	local from = Vector(pelvis.x, pelvis.y, groundZ + PERCH_FOOT)
	local spin = math.Rand(0, 360)
	local best, bestScore
	for i = 0, 7 do
		local dir = Angle(0, spin + i * 45, 0):Forward()
		local tr = util.TraceLine({ start = from, endpos = from + dir * PERCH_WALL, mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit and not tr.HitSky and not tr.HitNoDraw and not tr.StartSolid and math.abs(tr.HitNormal.z) < 0.3 then
			local n = tr.HitNormal
			local off = tr.HitPos + n * 8
			local up = util.TraceLine({ start = off, endpos = off + vector_up * PERCH_HIGH, mask = MASK_SOLID_BRUSHONLY })
			local rise = up.Hit and up.Fraction * PERCH_HIGH - 16 or PERCH_HIGH
			if rise + PERCH_FOOT >= PERCH_MIN then
				local at = tr.HitPos + vector_up * rise
				local back = util.TraceLine({ start = at + n * 16, endpos = at - n * 16, mask = MASK_SOLID_BRUSHONLY })
				if back.Hit and not back.HitSky and not back.HitNoDraw and math.abs(back.HitNormal.z) < 0.3 then
					local score = rise - tr.Fraction * PERCH_WALL * 0.5
					if not bestScore or score > bestScore then
						best, bestScore = { back.HitPos, back.HitNormal, Vector(tr.HitPos.x, tr.HitPos.y, groundZ) + n * 24 }, score
					end
				end
			end
		end
	end
	if best then return best[1], best[2], best[3] end
end

local function Fall(h, now, at)
	local _, up = Floor(at, h.rig.leg * 3)
	h.perch, h.normal, h.anchor, h.state = h.root, up or vector_up, nil, "writhe"
	h.stateAt, h.nextKick = now, now
end

local function Climb(h, now)
	if h.haul then Release(h) end
	h.prey = nil
	local pelvis = Part(h, "pelvis")
	local at = pelvis and pelvis:GetPos() or h.root
	local perch, normal = Ceiling(at, h.root.z)
	local base
	if not perch then perch, normal, base = Wall(at, h.root.z) end
	h.stateAt = now
	if not perch then return Fall(h, now, at) end
	h.perch, h.normal, h.base = perch, normal, base
	h.anchor = perch + normal * HANG
	if base then
		h.state = "climb"
	else
		h.state = "hoist"
		h.rag:SetNW2Vector(EvilFungus.ANCHOR_VAR, perch)
	end
end

local function Haul(h, f, r, dt)
	local hl = h.haul
	local hand = Part(h, "handr") or Part(h, "pelvis")
	local phys = IsValid(hl.rag) and hl.rag:GetPhysicsObjectNum(hl.phys)
	if not hand or not IsValid(phys) then return end
	phys:Wake()
	phys:ComputeShadowControl({
		secondstoarrive = 0.3, pos = hand:GetPos() - f * 4, angle = phys:GetAngles(),
		maxspeed = HAUL_PULL, maxspeeddamp = HAUL_PULL * 2, maxangular = 0, maxangulardamp = 0,
		dampfactor = DAMP, teleportdistance = 0, deltatime = dt,
	})
end

local function Hauling(h, now)
	local hl = h.haul
	local s = hl and IsValid(hl.rag) and EvilFungus.Sleepers[hl.rag]
	if not s or s ~= hl.s or s.stage ~= LOOSE or s.gripped or now >= hl.untilAt then return false end
	local hand = Part(h, "handr") or Part(h, "pelvis")
	local phys = hl.rag:GetPhysicsObjectNum(hl.phys)
	return hand and IsValid(phys) and phys:GetPos():DistToSqr(hand:GetPos()) < HAUL_SLIP * HAUL_SLIP
end

local function Grab(h, rag, now)
	local s = rag and EvilFungus.Sleepers[rag]
	if not s then return end
	s.hauler = h.rag
	local phys = 0
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		if string.find(string.lower(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)) or ""), "foot", 1, true) then
			phys = i
			break
		end
	end
	h.haul = { s = s, rag = rag, phys = phys, untilAt = now + HAUL_TIME }
	h.prey, h.nextScan = nil, 0
end

local function Shed(h, now)
	if now < h.nextShed then return end
	local rate = EvilFungus.Setting("spores")
	h.nextShed = now + math.Rand(SHED[1], SHED[2]) / math.max(0.1, rate * EvilFungus.TimeScale())
	if rate <= 0 then return end
	local pos, normal = Floor(h.root + vector_up * 8, 64)
	if pos then Plant(h, h.rag:GetPos(), pos, normal, SHED_MASS, SHED_CLEAR) end
end

local function Pass(h, now)
	h.tether, h.prey, h.grabbing = nil, nil, nil
	local pelvis = Part(h, "pelvis")
	Fall(h, now, pelvis and pelvis:GetPos() or h.root)
end

local function Walk(h, now, dt)
	if h.haul and not Hauling(h, now) then Release(h) end
	local head = Part(h, "head")
	local from = head and head:GetPos() or h.rag:GetPos()
	if now >= h.nextScan then
		h.nextScan = now + SCAN
		if h.haul then
			local node = Home(h.haul.rag:GetPos())
			if node then
				local past = Vector(node.x - h.root.x, node.y - h.root.y, 0)
				h.goal = past:LengthSqr() > 1 and node + past:GetNormalized() * HAUL_PAST or node
			else
				Release(h)
			end
		end
		if not h.haul then
			if not h.tether and (now >= h.dies or not Colony(h)) then
				Climb(h, now)
				return
			end
			if not (Prey(h.prey) and Within(h, h.prey) and h.prey:GetPos():DistToSqr(from) < SIGHT * SIGHT * 1.5) then h.prey = Pick(h, from) end
			h.goal = IsValid(h.prey) and h.prey:GetPos() or (h.tether and Pace(h, now) or Wander(h, now, from))
		end
	end

	local speed, reach = h.haul and HAUL_SPEED or SPEED, nil
	if h.prey and not (Prey(h.prey) and Within(h, h.prey)) then h.prey = nil end
	local prey = not h.haul and h.prey
	if IsValid(prey) then
		h.goal = prey:GetPos()
		local center = prey:WorldSpaceCenter()
		local d2 = center:DistToSqr(from)
		if d2 < LUNGE_RANGE * LUNGE_RANGE then speed = speed * LUNGE end
		if d2 < (REACH + h.rig.neck) ^ 2 then
			reach = center
			if not h.grabbing then
				h.grabbing = now
				h.rag:EmitSound(string.format(GRAB_SOUND, math.random(1, 2)), 70, math.random(70, 85))
			end
			if h.tether then
				if now - h.grabbing >= HAND_OFF then
					if h.tether.catch(h.rag, prey) then return Pass(h, now) end
					h.grabbing = now
				end
			else
				local dose = dt * EvilFungus.TimeScale() / (math.max(0.1, EvilFungus.Setting("sleep_time")) * DOSE)
				local under, rag = EvilFungus.Sedate(prey, dose, Colony(h))
				if under then
					h.grabbing = nil
					Grab(h, rag, now)
				end
			end
		else
			h.grabbing = nil
		end
	else
		h.grabbing = nil
	end

	Steer(h, h.goal, speed, now, dt)
	local f, r = Stance(h, now, dt, 1, reach, h.haul ~= nil)
	if h.haul then Haul(h, f, r, dt) end
	Shed(h, now)
end

local function Burst(h)
	local rag = h.rag
	local chest = Part(h, "chest")
	local at = chest and chest:GetPos() or rag:WorldSpaceCenter()
	for _, snd in ipairs(BURST_SOUNDS) do rag:EmitSound(snd, 80, math.random(85, 105)) end
	for _ = 1, 4 do
		local fx = EffectData()
		fx:SetOrigin(at + VectorRand() * 6)
		util.Effect("BloodImpact", fx, true, true)
	end
	util.Decal("Blood", h.perch + h.normal * 8, h.perch - h.normal * 8, rag)
	if not Plant(h, at, h.perch, h.normal, BURST_MASS, BURST_CLEAR) then
		local fx = EffectData()
		fx:SetStart(at)
		fx:SetOrigin(h.perch)
		fx:SetNormal(h.normal)
		util.Effect("evil_fungus_spore", fx, true, true)
	end
	Collapse(h)
end

local function Writhe(h, now, dt)
	if h.anchor then Push(h, "chest", h.anchor, ARRIVE, PULL, dt) end
	if now >= (h.nextKick or 0) then
		h.nextKick = now + math.Rand(WRITHE_KICK[1], WRITHE_KICK[2])
		local phys = h.rag:GetPhysicsObjectNum(math.random(0, h.rag:GetPhysicsObjectCount() - 1))
		if IsValid(phys) then
			phys:Wake()
			phys:ApplyForceCenter(VectorRand() * phys:GetMass() * WRITHE_FORCE)
		end
	end
	if now - h.stateAt >= WRITHE_TIME / EvilFungus.TimeScale() then Burst(h) end
end

local function Run(h, now, dt)
	if now >= h.nextGroan then
		h.nextGroan = now + math.Rand(GROAN[1], GROAN[2])
		h.rag:EmitSound(string.format(GROAN_SOUND, math.random(1, 2)), 65, math.random(70, 90))
	end
	local state = h.state
	if state == "rise" then
		local k = math.Clamp((now - h.stateAt) / RISE_TIME, 0, 1)
		Stance(h, now, dt, k * k * (3 - 2 * k))
		if k >= 1 then
			h.state, h.stateAt = h.resume or "walk", now
			h.resume = nil
		end
	elseif state == "walk" then
		Walk(h, now, dt)
	elseif state == "climb" then
		Steer(h, h.base, SPEED, now, dt)
		Stance(h, now, dt, 1)
		if Vector(h.base.x - h.root.x, h.base.y - h.root.y, 0):Length() < ARRIVED or now - h.stateAt > CLIMB_TIME then
			h.state, h.stateAt = "hoist", now
			h.rag:SetNW2Vector(EvilFungus.ANCHOR_VAR, h.perch)
		end
	elseif state == "hoist" then
		local chest = Part(h, "chest")
		Push(h, "chest", h.anchor, 0.4, HOIST_SPEED, dt)
		if not chest or chest:GetPos():DistToSqr(h.anchor) < HOIST_NEAR * HOIST_NEAR or now - h.stateAt > HOIST_TIME then
			h.state, h.stateAt, h.nextKick = "writhe", now, now
		end
	elseif state == "writhe" then
		Writhe(h, now, dt)
	end
end

function Hosts.Roll(s)
	local chance = EvilFungus.Setting("hosts")
	local rag = s.rag
	if chance <= 0 or not IsValid(rag) or rag.EvilFungusSpent or rag.EvilFungusBurnt or math.random() >= chance or not Rig(rag) then return false end
	return math.min(1, math.max((s.progress or 0) + 0.05, math.Rand(RISE_AT[1], RISE_AT[2])))
end

function Hosts.Rise(s, tether)
	local rag = s.rag
	local rig = Rig(rag)
	if not rig or not tether and Count() >= MAX_HOSTS then
		s.rise = false
		return false
	end
	local colony = IsValid(s.fungus) and s.fungus or nil
	EvilFungus.Sleep.Raise(s)
	EvilFungus.Foods[rag] = nil
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	rag:SetNW2Int(EvilFungus.STAGE_VAR, HOST)

	local now = CurTime()
	local h = {
		rag = rag, rig = rig, health = HEALTH, seed = math.Rand(0, 100),
		fungus = colony, mind = colony and colony.Mind, creator = colony and colony:GetCreator() or nil,
		state = "rise", stateAt = now, phase = 0, moving = 0,
		dies = now + EvilFungus.Setting("host_time") / EvilFungus.TimeScale(),
		nextScan = 0, nextShed = now + math.Rand(SHED[1], SHED[2]), nextGroan = now + math.Rand(GROAN[1], GROAN[2]),
		tether = tether, bound = tether ~= nil,
	}
	if tether then h.dies = math.huge end
	h.yaw = Facing(h)
	Reset(h)
	list[rag] = h
	Expose(h)
	if IsValid(h.creator) and cleanup then cleanup.Add(h.creator, "sents", rag) end
	rag:EmitSound(string.format(RISE_SOUND, math.random(1, 3)), 75, math.random(80, 95))
	return true
end

function Hosts.Unleash(rag)
	local h = list[rag]
	if not h or not h.tether then return end
	h.tether, h.prey, h.grabbing = nil, nil, nil
	h.dies = CurTime()
end

function Hosts.Clear()
	for rag in pairs(list) do SafeRemoveEntity(rag) end
end

hook.Add("Think", "EvilFungusHosts", function()
	if not next(list) then return end
	local now, dt = CurTime(), FrameTime()
	local off = EvilFungus.Setting("hosts") <= 0
	local limp = ai_disabled and ai_disabled:GetBool()
	for rag, h in pairs(list) do
		if not IsValid(rag) then
			list[rag] = nil
		elseif off and not h.bound or EvilFungus.CrawlerHas(rag) then
			Collapse(h)
		elseif limp then
			h.limp = true
		elseif not h.held then
			if h.limp then Rouse(h, now) end
			if rag:IsOnFire() then
				h.health = h.health - BURN_RATE * dt
				if h.health <= 0 then Collapse(h) end
			end
			if list[rag] then Run(h, now, dt) end
		end
	end
end)

hook.Add("EntityTakeDamage", "EvilFungusHosts", function(ent, dmg)
	local h = list[ent]
	if not h then return end
	local attacker = dmg:GetAttacker()
	if dmg:IsDamageType(DMG_CRUSH) and (not IsValid(attacker) or attacker == ent or attacker:IsWorld()) then return end
	local amount = dmg:GetDamage()
	if dmg:IsExplosionDamage() then
		amount = amount * BLAST_DAMAGE
	elseif dmg:IsDamageType(DMG_BURN) then
		amount = amount * BURN_DAMAGE
	end
	local head = Part(h, "head")
	local at = dmg:GetDamagePosition()
	if head and not at:IsZero() and at:DistToSqr(head:GetPos()) < HEAD_HIT * HEAD_HIT then amount = amount * HEAD_DAMAGE end
	h.health = h.health - amount
	if h.health <= 0 then Collapse(h) end
end)

hook.Add("OnPhysgunPickup", "EvilFungusHosts", function(_, ent)
	local h = list[ent]
	if h then h.held = true end
end)

hook.Add("PhysgunDrop", "EvilFungusHosts", function(_, ent)
	local h = list[ent]
	if not h then return end
	h.held = nil
	Rouse(h, CurTime())
end)

hook.Add("EntityRemoved", "EvilFungusHosts", function(ent)
	local h = list[ent]
	if not h then return end
	list[ent] = nil
	if h.haul then Release(h) end
end)

hook.Add("OnEntityCreated", "EvilFungusHosts", function(ent)
	if not next(list) or not ent:IsNPC() then return end
	timer.Simple(0, function()
		if not Hates(ent) then return end
		for _, h in pairs(list) do
			if IsValid(h.eye) then ent:AddEntityRelationship(h.eye, D_HT, 0) end
		end
	end)
end)
