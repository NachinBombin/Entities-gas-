AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars to preserve existing server configurations
local cv_cloud_min = CreateConVar("npc_chlorphos_gas_throw_cloud_min", "150", SHARED_FLAGS, "Minimum gas cloud radius in units.")
local cv_cloud_max = CreateConVar("npc_chlorphos_gas_throw_cloud_max", "300", SHARED_FLAGS, "Maximum gas cloud radius in units.")
local cv_high_min = CreateConVar("npc_chlorphos_gas_throw_high_min", "30", SHARED_FLAGS, "Minimum effect duration in seconds.")
local cv_high_max = CreateConVar("npc_chlorphos_gas_throw_high_max", "75", SHARED_FLAGS, "Maximum effect duration in seconds.")

local VIAL_MODEL = "models/healthvial.mdl"
local VIAL_MATERIAL = "models/weapons/gv/nerve_vial.vmt"

local IMPACT_SPEED = 80
local MIN_FLIGHT = 0.25
local MAX_VIAL_LIFE = 8

-- ============================================================
-- ChlorPhos "High" state
-- ============================================================

local playerHighEnd = {} 
local playerExposeStart = {} 
local playerDmgAccum = {} 

local function ApplyChlorPhosHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end
    if pl.GASMASK_Equiped then return end

    local now = CurTime()
    local uid = pl:UserID()
    local highDuration = math.Rand(cv_high_min:GetFloat(), cv_high_max:GetFloat())

    if (playerHighEnd[uid] or 0) > now then
        playerHighEnd[uid] = math.max(playerHighEnd[uid], now + highDuration)
        pl:SetNWFloat("npc_chlorphos_high_end", playerHighEnd[uid])
        return
    end

    playerHighEnd[uid] = now + highDuration

    if not playerExposeStart[uid] then
        playerExposeStart[uid] = now
    end

    net.Start("NPCChlorPhos_ApplyHigh")
    net.WriteFloat(now)
    net.WriteFloat(playerHighEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_chlorphos_high_start", now)
    pl:SetNWFloat("npc_chlorphos_high_end", playerHighEnd[uid])
end

-- ============================================================
-- Damage escalation
-- ============================================================

local function GetChlorPhosDPS(elapsed)
    if elapsed < 10 then return 0 end
    if elapsed < 30 then return math.Remap(elapsed, 10, 30, 0.0, 0.2) end
    if elapsed < 60 then return math.Remap(elapsed, 30, 60, 0.2, 1.0) end
    return math.min(math.Remap(elapsed, 60, 120, 1.0, 5.0), 5.0)
end

timer.Create("ChlorPhosDamageTick", 1, 0, function()
    local now = CurTime()
    for uid, expiry in pairs(playerHighEnd) do
        if expiry < now then continue end 

        local pl = player.GetByUniqueID and player.GetByUniqueID(uid)
        if not pl or not IsValid(pl) then
            for _, p in ipairs(player.GetAll()) do
                if p:UserID() == uid then pl = p; break end
            end
        end

        if not IsValid(pl) or not pl:Alive() then continue end

        local exposeStart = playerExposeStart[uid]
        if not exposeStart then continue end

        local elapsed = now - exposeStart
        local dps = GetChlorPhosDPS(elapsed)
        if dps <= 0 then continue end

        playerDmgAccum[uid] = (playerDmgAccum[uid] or 0) + dps

        local dmg = math.floor(playerDmgAccum[uid])
        if dmg >= 1 then
            playerDmgAccum[uid] = playerDmgAccum[uid] - dmg
            pl:TakeDamage(dmg, game.GetWorld(), game.GetWorld())
        end
    end
end)

hook.Add("PlayerDeath", "NPCChlorPhosGasThrow_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    playerHighEnd[uid] = nil
    playerExposeStart[uid] = nil
    playerDmgAccum[uid] = nil
    pl:SetNWFloat("npc_chlorphos_high_start", 0)
    pl:SetNWFloat("npc_chlorphos_high_end", 0)
    net.Start("NPCChlorPhos_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(pl)
end)

-- Global export so the antidote syringe still detects and clears the effect perfectly
function NPCChlorPhos_AntidoteClear(ply)
    if not IsValid(ply) then return end

    local uid = ply:UserID()
    playerHighEnd[uid] = nil
    playerExposeStart[uid] = nil
    playerDmgAccum[uid] = nil

    ply:SetNWFloat("npc_chlorphos_high_start", 0)
    ply:SetNWFloat("npc_chlorphos_high_end", 0)

    net.Start("NPCChlorPhos_ApplyHigh")
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

    net.Start("NPCChlorPhos_CloudEffect")
    net.WriteVector(pos)
    net.WriteFloat(cloudRadius)
    net.Broadcast()

    local GAS_DURATION = 18
    local GAS_TICK = 0.5
    local ticks = math.floor(GAS_DURATION / GAS_TICK)
    local timerName = "ChlorPhosGasDmg_" .. uid

    timer.Create(timerName, GAS_TICK, ticks, function()
        for _, ent in ipairs(ents.FindInSphere(pos, cloudRadius)) do
            if not IsValid(ent) then continue end
            if not ent:IsPlayer() then continue end 
            ApplyChlorPhosHigh(ent)
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
