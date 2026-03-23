ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Stun Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCStunGas_CloudEffect")
    util.AddNetworkString("NPCStunGas_ApplyHigh")
end
