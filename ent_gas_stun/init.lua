AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars to preserve existing server configurations
local cv_cloud_min = CreateConVar("npc_stun_gas_throw_cloud_min", "150", SHARED_FLAGS, "Minimum stun gas cloud radius in units.")
local cv_cloud_max = CreateConVar("npc_stun_gas_throw_cloud_max", "300", SHARED_FLAGS, "Maximum stun gas cloud radius in units.")
local cv_high_min = CreateConVar("npc_stun_gas_throw_high_min", "30", SHARED_FLAGS, "Minimum stun effect duration in seconds.")
local cv_high_max = CreateConVar("npc_stun_gas_throw_high_max", "75", SHARED_FLAGS, "Maximum stun effect duration in seconds.")

local VIAL_MODEL = "models/healthvial.mdl"
local VIAL_MATERIAL = "models/weapons/gv/nerve_vial.vmt"

local IMPACT_SPEED = 80
local MIN_FLIGHT = 0.25
local MAX_VIAL_LIFE = 8

local playerHighEnd = {} 

local function ApplyStunHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end
    if pl.GASMASK_Equiped then return end

    local now = CurTime()
    local uid = pl:UserID()
    local highDuration = math.Rand(cv_high_min:GetFloat(), cv_high_max:GetFloat())

    if (playerHighEnd[uid] or 0) > now then
        playerHighEnd[uid] = math.max(playerHighEnd[uid], now + highDuration)
        pl:SetNWFloat("npc_stungas_high_end", playerHighEnd[uid])
        return
    end

    playerHighEnd[uid] = now + highDuration

    net.Start("NPCStunGas_ApplyHigh")
    net.WriteFloat(now)
    net.WriteFloat(playerHighEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_stungas_high_start", now)
    pl:SetNWFloat("npc_stungas_high_end", playerHighEnd[uid])

    local commands = { "left", "right", "moveleft", "moveright", "duck", "attack" }
    local numHits = math.random(1, 3)

    for i = 1, numHits do
        timer.Simple(math.Rand(2, 8), function()
            if not IsValid(pl) or not pl:Alive() then return end
            if (playerHighEnd[uid] or 0) < CurTime() then return end
            local cmd = commands[math.random(1, #commands)]
            pl:ConCommand("+" .. cmd)
            timer.Simple(math.Rand(0.3, 0.9), function()
                if not IsValid(pl) then return end
                pl:ConCommand("-" .. cmd)
            end)
        end)
    end

    timer.Simple(highDuration * 0.45, function()
        if not IsValid(pl) or not pl:Alive() then return end
        if (playerHighEnd[uid] or 0) < CurTime() then return end
        local cmd = commands[math.random(1, #commands)]
        pl:ConCommand("+" .. cmd)
        timer.Simple(math.Rand(0.4, 1.0), function()
            if not IsValid(pl) then return end
            pl:ConCommand("-" .. cmd)
        end)
    end)

    timer.Simple(highDuration * 0.75, function()
        if not IsValid(pl) or not pl:Alive() then return end
        if (playerHighEnd[uid] or 0) < CurTime() then return end
        local numLate = math.random(1, 2)
        for i = 1, numLate do
            local cmd = commands[math.random(1, #commands)]
            pl:ConCommand("+" .. cmd)
            timer.Simple(math.Rand(0.5, 1.2), function()
                if not IsValid(pl) then return end
                pl:ConCommand("-" .. cmd)
            end)
        end
    end)
end

hook.Add("PlayerDeath", "NPCStunGasThrow_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    playerHighEnd[uid] = nil
    pl:SetNWFloat("npc_stungas_high_start", 0)
    pl:SetNWFloat("npc_stungas_high_end", 0)
    net.Start("NPCStunGas_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(pl)
end)

-- Global export so Narcan still detects and clears the effect perfectly
function NPCStunGas_NarcanClear(ply)
    if not IsValid(ply) then return end
    local uid = ply:UserID()
    playerHighEnd[uid] = nil
    ply:SetNWFloat("npc_stungas_high_start", 0)
    ply:SetNWFloat("npc_stungas_high_end", 0)
    net.Start("NPCStunGas_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(ply)
end

-- ============================================================
-- Entity logic
-- ============================================================

function ENT:Initialize()
    self:SetModel(VIAL_MODEL)
    self:SetMaterial(VIAL_MATERIAL)
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
    local cloudRadius = math.Rand(cv_cloud_min:GetFloat(), cv_cloud_max:GetFloat())

    net.Start("NPCStunGas_CloudEffect")
    net.WriteVector(pos)
    net.WriteFloat(cloudRadius)
    net.Broadcast()

    local GAS_DURATION = 18
    local GAS_TICK = 0.5
    local ticks = math.floor(GAS_DURATION / GAS_TICK)
    local timerName = "StunGasDmg_" .. uid

    timer.Create(timerName, GAS_TICK, ticks, function()
        for _, ent in ipairs(ents.FindInSphere(pos, cloudRadius)) do
            if not IsValid(ent) then continue end
            if not ent:IsPlayer() then continue end
            ApplyStunHigh(ent)
        end
    end)
    
    self:Remove()
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
