AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars to preserve server config hooks
local cv_high_min = CreateConVar("npc_bzm_gas_throw_high_min", "60", SHARED_FLAGS)
local cv_high_max = CreateConVar("npc_bzm_gas_throw_high_max", "120", SHARED_FLAGS)

local VIAL_MODEL = "models/healthvial.mdl"

local IMPACT_SPEED = 80
local MIN_FLIGHT = 0.25
local MAX_VIAL_LIFE = 8

-- Antidote Clear Function (Global export for syringe compatibility)
function NPCBZMGas_AntidoteClear(ply)
    if not IsValid(ply) then return end
    ply:SetNWFloat("npc_bzm_high_end", 0)
    ply:SetNWFloat("npc_bzm_expose_start", 0)
    net.Start("NPCBZMGas_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(ply)
end

hook.Add("PlayerDeath", "NPCBZMGas_DeathReset", function(ply) 
    NPCBZMGas_AntidoteClear(ply) 
end)

-- ============================================================
-- Entity logic
-- ============================================================

function ENT:Initialize()
    self:SetModel(VIAL_MODEL)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        local spin = VectorRand():GetNormalized() * math.random(5, 10)
        local offset = self:LocalToWorld(self:OBBCenter()) + Vector(0, 0, math.random(10, 15))
        phys:ApplyForceOffset(spin, offset)
    end
    
    self.SpawnTime = CurTime()
    self.SlowTicks = 0
    self.Detonated = false
end

function ENT:Detonate()
    if self.Detonated then return end
    self.Detonated = true
    
    local pos = self:GetPos()
    local uid = self:EntIndex()

    net.Start("NPCBZMGas_CloudEffect")
    net.WriteVector(pos)
    net.WriteFloat(250)
    net.Broadcast()

    timer.Create("BZMGasCloud_" .. uid, 1, 15, function()
        for _, ent in ipairs(ents.FindInSphere(pos, 250)) do
            if IsValid(ent) and ent:IsPlayer() and ent:Alive() and not ent.GASMASK_Equiped then
                local now = CurTime()
                ent:SetNWFloat("npc_bzm_high_end", now + math.Rand(cv_high_min:GetFloat(), cv_high_max:GetFloat()))
                if ent:GetNWFloat("npc_bzm_expose_start", 0) == 0 then
                    ent:SetNWFloat("npc_bzm_expose_start", now)
                end
                net.Start("NPCBZMGas_ApplyHigh")
                net.WriteFloat(ent:GetNWFloat("npc_bzm_high_end"))
                net.WriteFloat(ent:GetNWFloat("npc_bzm_expose_start"))
                net.Send(ent)
            end
        end
    end)
    
    self:Remove()
end

function ENT:PhysicsCollide(data, phys)
    if self.Detonated then return end
    
    local age = CurTime() - self.SpawnTime
    local spd = data.OurOldVelocity:Length()
    
    if age > MIN_FLIGHT and spd > IMPACT_SPEED then
        self:Detonate()
    end
end

function ENT:Think()
    if self.Detonated then return end
    
    local age = CurTime() - self.SpawnTime
    if age > MAX_VIAL_LIFE then
        self:Detonate()
        return
    end
    
    local phys = self:GetPhysicsObject()
    local spd = IsValid(phys) and phys:GetVelocity():Length() or 0
    
    if age > MIN_FLIGHT and spd < IMPACT_SPEED then
        self.SlowTicks = self.SlowTicks + 1
        if self.SlowTicks >= 2 then
            self:Detonate()
        end
    else
        self.SlowTicks = 0
    end
    
    self:NextThink(CurTime() + 0.05)
    return true
end
