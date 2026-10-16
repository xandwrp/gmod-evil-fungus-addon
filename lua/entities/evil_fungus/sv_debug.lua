local DRAW_INTERVAL = 0.2
local DRAW_RANGE = 2500
local LIFT = 2
local WAVE_BAND = 16
local D_SHOWN = 6

local MASS = Color(240, 160, 40)
local WAVE = Color(40, 220, 170)
local GOAL = Color(255, 0, 255)
local TARGET = Color(255, 255, 255)
local PREY = Color(255, 40, 40)

local cv_debug = CreateConVar("evil_fungus_debug", "0", 0, "Draw the mat, its body and footstep waves (needs developer 1)")

function ENT:Debugging()
	return cv_debug:GetBool()
end

function ENT:DebugDraw(now)
	if not cv_debug:GetBool() or now < (self.NextDraw or 0) then return end
	self.NextDraw = now + DRAW_INTERVAL
	local life = DRAW_INTERVAL + 0.05
	local mat = self.Mat
	local floor = EvilFungus.Mat.D_FLOOR

	local eyes = {}
	for _, ply in ipairs(player.GetHumans()) do eyes[#eyes + 1] = ply:EyePos() end
	local r2 = DRAW_RANGE * DRAW_RANGE
	local function Seen(pos)
		for _, eye in ipairs(eyes) do
			if eye:DistToSqr(pos) < r2 then return true end
		end
		return false
	end

	for _, node in pairs(mat.nodes) do
		if Seen(node.pos) then
			for _, e in ipairs(node.edges) do
				if e.a == node then
					local k = math.Clamp((mat:Conductance(e, now) - floor) / (D_SHOWN - floor), 0, 1)
					local c = Color(80 + 175 * k, 80 + 160 * k, 75 + 110 * k)
					debugoverlay.Line(e.a.pos + e.a.normal * LIFT, e.b.pos + e.b.normal * LIFT, life, c, true)
				end
			end
		end
	end

	for node in pairs(mat.full) do
		debugoverlay.Cross(node.pos + node.normal * (LIFT + 1), 1 + math.sqrt(node.m) * 3, life, MASS, true)
	end

	for _, w in ipairs(self.Waves) do
		local front = (now - w.start) * w.speed
		for node, d in pairs(w.dist) do
			if not node.dead and math.abs(d - front) < WAVE_BAND then
				debugoverlay.Cross(node.pos + node.normal * (LIFT + 2), 4, life, WAVE, true)
			end
		end
	end

	if self.Goal and not self.Goal.dead then debugoverlay.Cross(self.Goal.pos, 16, life, GOAL, true) end
	if self.Target then debugoverlay.Cross(self.Target, 10, life, TARGET, true) end
	if self.Hunting and IsValid(self.Prey) then
		debugoverlay.Line(self.Center, self.Prey:GetPos(), life, PREY, true)
	end
	local state = self.Eating and "feeding" or self.Hunting and "hunting" or self.Tending and "tending" or self.Resting and "resting" or "roaming"
	local at, r = self.Center + self.Up * 24, self.CostReport
	debugoverlay.EntityTextAtPosition(at, 0, ("%s  body %d  mat %d"):format(state, self.Body, mat.count), life, TARGET)
	debugoverlay.EntityTextAtPosition(at, 1, ("ms/s  decide %.2f  flow %.2f  grow %.2f  feel %.2f"):format(
		r.decide or 0, r.flow or 0, r.grow or 0, r.feel or 0), life, TARGET)
	local mind = self.Mind
	debugoverlay.EntityTextAtPosition(at, 2, ("mind %.2f  kept %.2f  wired %.2f"):format(mind:Level(), mind.kept, mind.wired), life, TARGET)
	local knows = {}
	for tactic in SortedPairs(EvilFungus.TACTICS) do knows[#knows + 1] = ("%s %.2f"):format(tactic, mind:Knows(tactic)) end
	debugoverlay.EntityTextAtPosition(at, 3, "knows  " .. table.concat(knows, "  "), life, TARGET)
end
