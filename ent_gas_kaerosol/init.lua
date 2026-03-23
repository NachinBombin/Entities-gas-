AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars for existing server configurations
local cv_cloud_min = CreateConVar("npc_kaerosol_gas_throw_cloud_min", "150", SHARED_FLAGS, "Minimum gas cloud radius in units.")
local cv_cloud_max = CreateConVar("npc_kaerosol_gas_throw_cloud_max", "300", SHARED_FLAGS, "Maximum gas cloud radius in units.")
local cv_high_min = CreateConVar("npc_kaerosol_gas_throw_high_min", "25", SHARED_FLAGS, "Minimum effect duration in seconds.")
local cv_high_max = CreateConVar("npc_kaerosol_gas_throw_high_max", "60", SHARED_FLAGS, "Maximum effect duration in seconds.")

local VIAL_MODEL = "models/healthvial.mdl"

local IMPACT_SPEED = 80
local MIN_FLIGHT = 0.25
local MAX_VIAL_LIFE = 8

local PARALYSIS_ELAPSED = 15
local UNCONSCIOUS_DURATION = 5

-- ============================================================
-- State tables (all keyed by UserID)
-- ============================================================

local playerKAerosolEnd = {}
local playerKAerosolStart = {}
local playerOrigWalk = {}
local playerOrigRun = {}
local playerOrigFric = {} 
local playerDSPActive = {}
local playerUnconsciousArmed = {}
local playerWakeupTime = {} 
local FRICTION_RECOVERY_TIME = 1.5 

local function GetKAerosolMoveFactor(elapsed)
    if elapsed <= 0 then return 0 end
    if elapsed < 5 then return math.Remap(elapsed, 0, 5, 0.0, 0.6) end
    if elapsed < 15 then return math.Remap(elapsed, 5, 15, 0.6, 1.0) end
    return 1.0
end

local function ApplyKAerosolMovement(pl, factor)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    local origWalk = playerOrigWalk[uid] or 150
    local origRun = playerOrigRun[uid] or 200
    local origFric = playerOrigFric[uid] or 1

    pl:SetWalkSpeed(math.max(math.floor(origWalk * (1 - factor * 0.947)), 8))
    pl:SetRunSpeed(math.max(math.floor(origRun * (1 - factor * 0.950)), 10))
    pl:SetFriction(math.Remap(factor, 0, 1, origFric, 80))
end

local function RestoreKAerosolMovement(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()

    pl:SetWalkSpeed(playerOrigWalk[uid] or 150)
    pl:SetRunSpeed(playerOrigRun[uid] or 200)
    pl:SetFriction(playerOrigFric[uid] or 1)

    if playerDSPActive[uid] then
        pl:SetDSP(0, false)
        playerDSPActive[uid] = nil
    end

    local limeAnim = pl:GetNW2Entity("xen_teleport_effect")
    if IsValid(limeAnim) then
        limeAnim:Remove()
    end

    playerUnconsciousArmed[uid] = nil
    playerWakeupTime[uid] = nil
    playerOrigWalk[uid] = nil
    playerOrigRun[uid] = nil
    playerOrigFric[uid] = nil
end

local function TriggerKAerosolWakeupAnim(pl)
    if not IsValid(pl) then return end
    if IsValid(pl:GetNW2Entity("xen_teleport_effect")) then return end

    local tele = ents.Create("xen_teleport_intro")
    if not IsValid(tele) then return end 

    tele:SetPos(pl:GetPos())
    tele:SetOwner(pl)
    tele:Spawn()
    tele:Activate()
    tele.AnimType = "fall" 
    tele:StartIntro(pl)
end

-- ============================================================
-- Server-side movement + DSP tick
-- ============================================================

timer.Create("KAerosolMovementTick", 0.25, 0, function()
    local now = CurTime()

    for uid, expiry in pairs(playerKAerosolEnd) do
        local pl = nil
        for _, p in ipairs(player.GetAll()) do
            if p:UserID() == uid then pl = p; break end
        end

        if not IsValid(pl) then
            playerKAerosolEnd[uid] = nil
            playerKAerosolStart[uid] = nil
            playerOrigWalk[uid] = nil
            playerOrigRun[uid] = nil
            playerOrigFric[uid] = nil
            playerDSPActive[uid] = nil
            playerUnconsciousArmed[uid] = nil
            playerWakeupTime[uid] = nil
            continue
        end

        if expiry <= now then
            RestoreKAerosolMovement(pl)
            playerKAerosolEnd[uid] = nil
            playerKAerosolStart[uid] = nil
            pl:SetNWFloat("npc_kaerosol_start", 0)
            pl:SetNWFloat("npc_kaerosol_end", 0)
            net.Start("NPCKAerosol_ApplyEffect")
            net.WriteFloat(0)
            net.WriteFloat(0)
            net.Send(pl)
            continue
        end

        if not pl:Alive() then continue end

        local elapsed = now - (playerKAerosolStart[uid] or now)
        local moveFactor = GetKAerosolMoveFactor(elapsed)

        if playerWakeupTime[uid] then
            local wakeElapsed = now - playerWakeupTime[uid]
            local origFric = playerOrigFric[uid] or 1
            local origWalk = playerOrigWalk[uid] or 150
            local origRun = playerOrigRun[uid] or 200

            if wakeElapsed >= FRICTION_RECOVERY_TIME then
                pl:SetFriction(origFric)
                pl:SetWalkSpeed(origWalk)
                pl:SetRunSpeed(origRun)
            else
                local t = wakeElapsed / FRICTION_RECOVERY_TIME
                pl:SetFriction(math.Remap(t, 0, 1, 80, origFric))
                
                local impWalk = math.max(math.floor(origWalk * (1 - moveFactor * 0.947)), 8)
                local impRun = math.max(math.floor(origRun * (1 - moveFactor * 0.950)), 10)
                pl:SetWalkSpeed(math.floor(math.Remap(t, 0, 1, impWalk, origWalk)))
                pl:SetRunSpeed(math.floor(math.Remap(t, 0, 1, impRun, origRun)))
            end
        else
            ApplyKAerosolMovement(pl, moveFactor)
        end

        if elapsed >= PARALYSIS_ELAPSED then
            if not playerDSPActive[uid] then
                pl:SetDSP(31, false)
                playerDSPActive[uid] = true
            end

            if not playerUnconsciousArmed[uid] then
                playerUnconsciousArmed[uid] = true
                local plyRef = pl
                timer.Simple(UNCONSCIOUS_DURATION, function()
                    if not IsValid(plyRef) then return end
                    if not playerKAerosolEnd[plyRef:UserID()] then return end
                    TriggerKAerosolWakeupAnim(plyRef)
                end)
            end
        end
    end
end)

local function ApplyKAerosolHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end
    if pl.GASMASK_Equiped then return end

    local now = CurTime()
    local uid = pl:UserID()
    local duration = math.Rand(cv_high_min:GetFloat(), cv_high_max:GetFloat())

    if (playerKAerosolEnd[uid] or 0) > now then
        playerKAerosolEnd[uid] = math.max(playerKAerosolEnd[uid], now + duration)
        pl:SetNWFloat("npc_kaerosol_end", playerKAerosolEnd[uid])
        return
    end

    playerKAerosolEnd[uid] = now + duration

    if not playerKAerosolStart[uid] then
        playerKAerosolStart[uid] = now
    end

    if not playerOrigWalk[uid] then
        playerOrigWalk[uid] = pl:GetWalkSpeed()
        playerOrigRun[uid] = pl:GetRunSpeed()
        playerOrigFric[uid] = pl:GetFriction()
    end

    net.Start("NPCKAerosol_ApplyEffect")
    net.WriteFloat(playerKAerosolStart[uid])
    net.WriteFloat(playerKAerosolEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_kaerosol_start", playerKAerosolStart[uid])
    pl:SetNWFloat("npc_kaerosol_end", playerKAerosolEnd[uid])
end

net.Receive("NPCKAerosol_WakeupDone", function(len, pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    if not playerKAerosolEnd[uid] then return end
    playerWakeupTime[uid] = CurTime()
    if playerDSPActive[uid] then
        pl:SetDSP(0, false)
        playerDSPActive[uid] = nil
    end
end)

hook.Add("PlayerDeath", "NPCKAerosolGasThrow_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()

    RestoreKAerosolMovement(pl)
    playerKAerosolEnd[uid] = nil
    playerKAerosolStart[uid] = nil

    pl:SetNWFloat("npc_kaerosol_start", 0)
    pl:SetNWFloat("npc_kaerosol_end", 0)
    net.Start("NPCKAerosol_ApplyEffect")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(pl)
end)

-- Global export so Narcan still detects and clears the effect perfectly
function NPCKAerosol_NarcanClear(ply)
    if not IsValid(ply) then return end
    local uid = ply:UserID()

    RestoreKAerosolMovement(ply)
    playerKAerosolEnd[uid] = nil
    playerKAerosolStart[uid] = nil

    ply:SetNWFloat("npc_kaerosol_start", 0)
    ply:SetNWFloat("npc_kaerosol_end", 0)
    net.Start("NPCKAerosol_ApplyEffect")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(ply)
end

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
    local cloudRadius = math.Rand(cv_cloud_min:GetFloat(), cv_cloud_max:GetFloat())

    net.Start("NPCKAerosol_CloudEffect")
    net.WriteVector(pos)
    net.WriteFloat(cloudRadius)
    net.Broadcast()

    local GAS_DURATION = 18
    local GAS_TICK = 0.5
    local timerName = "KAerosolGasDmg_" .. uid

    timer.Create(timerName, GAS_TICK, math.floor(GAS_DURATION / GAS_TICK), function()
        for _, ent in ipairs(ents.FindInSphere(pos, cloudRadius)) do
            if not IsValid(ent) then continue end
            if not ent:IsPlayer() then continue end
            ApplyKAerosolHigh(ent)
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
