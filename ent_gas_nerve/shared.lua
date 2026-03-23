ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Nerve Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCNerveGas_ApplyHigh")
end
