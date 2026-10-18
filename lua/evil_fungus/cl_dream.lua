local DEFAULT_COLOR = Vector(62 / 255, 88 / 255, 106 / 255)
local SETTLE = 4
local FADE_IN = 3

local shown, dreamStart = 0, nil

hook.Add("RenderScreenspaceEffects", "EvilFungusDream", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local asleep = ply:GetNW2Bool(EvilFungus.ASLEEP_VAR, false) and not ply:Alive()
	if asleep then
		dreamStart = dreamStart or RealTime()
		local k = math.Clamp((RealTime() - dreamStart) / FADE_IN, 0, 1)
		DrawColorModify({
			["$pp_colour_addr"] = 0.06 * k, ["$pp_colour_addg"] = 0.03 * k, ["$pp_colour_addb"] = 0,
			["$pp_colour_brightness"] = Lerp(k, -1, 0.04), ["$pp_colour_contrast"] = Lerp(k, 1, 0.9),
			["$pp_colour_colour"] = Lerp(k, 0, 1.6),
			["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
		})
		DrawBloom(0.55, 2.2 * k, 9, 9, 1, 1, 1, 0.9, 0.75)
		DrawToyTown(3, ScrH() * 0.7)
		DrawMotionBlur(0.08, 0.7, 0.02)
		return
	end
	dreamStart = nil

	local d = ply:GetNW2Float(EvilFungus.DROWSY_VAR, 0)
	shown = shown + (d - shown) * math.min(1, FrameTime() * SETTLE)
	if shown < 0.01 then return end
	DrawColorModify({
		["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.25 * shown * shown, ["$pp_colour_contrast"] = 1 - 0.25 * shown,
		["$pp_colour_colour"] = 1 - 0.6 * shown,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
	DrawMotionBlur(0.1 + 0.2 * (1 - shown), 0.85 * shown, 0.01)
	if shown > 0.4 then DrawToyTown(2, ScrH() * (shown - 0.4)) end
end)

hook.Add("HUDPaint", "EvilFungusDream", function()
	local ply = LocalPlayer()
	if not dreamStart or not IsValid(ply) or EvilFungus.Setting("give_up") == 0 then return end
	local k = math.Clamp((RealTime() - dreamStart - FADE_IN) / FADE_IN, 0, 1)
	if k <= 0 then return end
	local key = string.upper(input.LookupBinding("+jump") or "space")
	draw.SimpleText("Press " .. key .. " to give up", "Trebuchet24", ScrW() / 2, ScrH() * 0.85, Color(255, 255, 255, 160 * k), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

local SWAY = { pitch = { 3, 0.7 }, yaw = { 4, 0.43 }, roll = { 8, 0.55 }, fov = { 6, 0.37 } }

local function Sway(k, t)
	return SWAY[k][1] * math.sin(t * SWAY[k][2])
end

-- Watching yourself sleep from somewhere just above, and not quite steady.
hook.Add("CalcView", "EvilFungusDream", function(ply, origin, angles, fov)
	if ply:Alive() or not ply:GetNW2Bool(EvilFungus.ASLEEP_VAR, false) then return end
	local t = RealTime()
	return {
		origin = origin,
		angles = Angle(angles.p + Sway("pitch", t), angles.y + Sway("yaw", t), angles.r + Sway("roll", t)),
		fov = fov + Sway("fov", t),
	}
end)

hook.Add("OnEntityCreated", "EvilFungusDream", function(ent)
	if ent:GetClass() ~= "prop_ragdoll" or ent.GetPlayerColor then return end
	function ent:GetPlayerColor()
		return self:GetNW2Vector(EvilFungus.COLOR_VAR, DEFAULT_COLOR)
	end
end)
