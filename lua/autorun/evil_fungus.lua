AddCSLuaFile("evil_fungus/sh_settings.lua")
AddCSLuaFile("evil_fungus/cl_settings.lua")
AddCSLuaFile("evil_fungus/sh_drag.lua")
AddCSLuaFile("evil_fungus/cl_mat.lua")
include("evil_fungus/sh_settings.lua")
include("evil_fungus/sh_drag.lua")
if CLIENT then
	include("evil_fungus/cl_settings.lua")
	include("evil_fungus/cl_mat.lua")
else
	include("evil_fungus/sv_creatures.lua")
	include("evil_fungus/sv_net.lua")
end
