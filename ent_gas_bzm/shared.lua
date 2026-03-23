ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "BZ-M Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCBZMGas_CloudEffect")
    util.AddNetworkString("NPCBZMGas_ApplyHigh")
end
