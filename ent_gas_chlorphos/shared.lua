ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Chlorine-Phosgene Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCChlorPhos_CloudEffect")
    util.AddNetworkString("NPCChlorPhos_ApplyHigh")
end
