local SEND_DELAY = 0.25
local SETTLE = 1

local function Send(s, value)
	s.pending = RealTime() + SEND_DELAY + SETTLE
	timer.Create("EvilFungusSetting_" .. s.name, SEND_DELAY, 1, function()
		if math.abs(GetConVar(s.convar):GetFloat() - value) < 1e-3 then return end
		net.Start("EvilFungusSetting")
		net.WriteString(s.convar)
		net.WriteString(tostring(value))
		net.SendToServer()
	end)
end

local function Settled(s)
	return RealTime() > (s.pending or 0)
end

local function Admin(control)
	local ply = LocalPlayer()
	local admin = IsValid(ply) and ply:IsSuperAdmin()
	if control:IsEnabled() ~= admin then control:SetEnabled(admin) end
end

local function Presets(panel)
	local row = vgui.Create("DPanel", panel)
	row:SetPaintBackground(false)
	row:SetTall(24)
	for _, preset in ipairs(EvilFungus.PRESETS) do
		local button = row:Add("DButton")
		button:SetText(preset.label)
		button.DoClick = function() RunConsoleCommand("evil_fungus_preset", preset.name) end
		button.Think = Admin
	end
	row.PerformLayout = function(self, w)
		local buttons = self:GetChildren()
		local gap = 4
		local bw = (w - gap * (#buttons - 1)) / #buttons
		for i, button in ipairs(buttons) do
			button:SetPos(math.floor((i - 1) * (bw + gap)), 0)
			button:SetSize(math.floor(bw), self:GetTall())
		end
	end
	panel:AddItem(row)
end

local function Build(panel)
	Presets(panel)
	for _, s in ipairs(EvilFungus.SETTINGS) do
		local cv = GetConVar(s.convar)
		local control
		if s.needs and not _G[s.needs] then
			-- Only matters with the other addon installed.
		elseif s.max == 1 and not s.decimals then
			control = panel:CheckBox(s.label)
			control:SetChecked(cv:GetBool())
			control.OnChange = function(_, on) Send(s, on and 1 or 0) end
			control.Think = function(self)
				Admin(self)
				if Settled(s) and self:GetChecked() ~= cv:GetBool() then self:SetChecked(cv:GetBool()) end
			end
		else
			control = panel:NumSlider(s.label, nil, s.min, s.max, s.decimals)
			control:SetValue(cv:GetFloat())
			control.OnValueChanged = function(_, value) Send(s, value) end
			control.Think = function(self)
				Admin(self)
				if Settled(s) and not self:IsEditing() and math.abs(self:GetValue() - cv:GetFloat()) > 1e-3 then self:SetValue(cv:GetFloat()) end
			end
		end
		if control then control:SetTooltip(s.help) end
	end
	panel:Button("Remove all fungus", "evil_fungus_clear").Think = Admin
end

hook.Add("PopulateToolMenu", "EvilFungusSettings", function()
	spawnmenu.AddToolMenuOption("Utilities", "Evil Fungus", "evil_fungus_settings", "Settings", "", "", Build)
end)
