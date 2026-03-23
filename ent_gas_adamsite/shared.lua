ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Adamsite Gas Grenade"
ENT.Category = "Gas Grenades"
ENT.Spawnable = true

if SERVER then
    util.AddNetworkString("NPCAdamsite_CloudEffect")
    util.AddNetworkString("NPCAdamsite_ApplyHigh")
    util.AddNetworkString("NPCAdamsite_Vomit")
    util.AddNetworkString("NPCAdamsite_Sneeze")
    util.AddNetworkString("NPCAdamsite_VomitSplat")
end
