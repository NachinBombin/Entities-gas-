ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "K-Aerosol Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCKAerosol_CloudEffect")
    util.AddNetworkString("NPCKAerosol_ApplyEffect")
    util.AddNetworkString("NPCKAerosol_WakeupDone")
end
