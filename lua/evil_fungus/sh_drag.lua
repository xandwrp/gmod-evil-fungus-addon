EvilFungus = EvilFungus or {}

EvilFungus.DRAG_VAR = "EvilFungusDrag"

hook.Add("SetupMove", "EvilFungusDrag", function(ply, mv)
	local drag = ply:GetNW2Float(EvilFungus.DRAG_VAR, 0)
	if drag <= 0 then return end
	local keep = 1 - drag
	mv:SetMaxSpeed(mv:GetMaxSpeed() * keep)
	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * keep)
	if drag > 0.6 then mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP))) end
end)
