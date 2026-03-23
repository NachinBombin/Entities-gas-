AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars to preserve existing server configurations
local cv_cloud_min = CreateConVar("npc_nerve_gas_throw_cloud_min", "150", SHARED_FLAGS, "Minimum gas cloud radius in units.")
local cv_cloud_max = CreateConVar("npc_nerve_gas_throw_cloud_max", "300", SHARED_FLAGS, "Maximum gas cloud radius in units.")

local VIAL_MODEL = "models/healthvial.mdl"
local VIAL_MATERIAL = "models/weapons/gv/nerve_vial.vmt"

local IMPACT_SPEED = 80 
local MIN_FLIGHT = 0.25 
local MAX_VIAL_LIFE = 8 

-- ============================================================
-- Nerve Gas "High" state
-- ============================================================

local playerHighEnd = {}

local function ApplyNerveGasHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end

    local now = CurTime()
    local uid = pl:UserID()

    local highDuration = math.Rand(30, 75)

    if (playerHighEnd[uid] or 0) > now then
        playerHighEnd[uid] = math.max(playerHighEnd[uid], now + highDuration)
        pl:SetNWFloat("npc_nervegas_high_end", playerHighEnd[uid])
        return
    end

    playerHighEnd[uid] = now + highDuration

    net.Start("NPCNerveGas_ApplyHigh")
    net.WriteFloat(now)
    net.WriteFloat(playerHighEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_nervegas_high_start", now)
    pl:SetNWFloat("npc_nervegas_high_end", playerHighEnd[uid])

    local commands = { "left", "right", "moveleft", "moveright", "duck", "attack" }
    local numHits = math.random(1, 3)

    for i = 1, numHits do
        timer.Simple(math.Rand(2, 8), function()
            if not IsValid(pl) then return end
            if not pl:Alive() then return end
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
        if not IsValid(pl) then return end
        if not pl:Alive() then return end
        if (playerHighEnd[uid] or 0) < CurTime() then return end

        local cmd = commands[math.random(1, #commands)]
        pl:ConCommand("+" .. cmd)
        timer.Simple(math.Rand(0.4, 1.0), function()
            if not IsValid(pl) then return end
            pl:ConCommand("-" .. cmd)
        end)
    end)

    timer.Simple(highDuration * 0.75, function()
        if not IsValid(pl) then return end
        if not pl:Alive() then return end
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

hook.Add("PlayerDeath", "NPCNerveGasThrow_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    playerHighEnd[uid] = nil
    pl:SetNWFloat("npc_nervegas_high_start", 0)
    pl:SetNWFloat("npc_nervegas_high_end", 0)
    net.Start("NPCNerveGas_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(pl)
end)

function NPCNerveGas_NarcanClear(ply)
    if not IsValid(ply) then return end

    local uid = ply:UserID()
    playerHighEnd[uid] = nil

    ply:SetNWFloat("npc_nervegas_high_start", 0)
    ply:SetNWFloat("npc_nervegas_high_end", 0)

    net.Start("NPCNerveGas_ApplyHigh")
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
    
    local gas = EffectData()
    gas:SetOrigin(pos)
    gas:SetEntity(self:GetOwner() or game.GetWorld())
    gas:SetScale(1)
    util.Effect("m9k_released_nerve_gas", gas)

    local GAS_RADIUS = math.Rand(cv_cloud_min:GetFloat(), cv_cloud_max:GetFloat())
    local GAS_DURATION_FLEE = 18

    local function EmitDangerHint()
        local hint = ents.Create("ai_sound")
        if not IsValid(hint) then return end
        hint:SetPos(pos)
        hint:SetKeyValue("soundtype", "8")
        hint:SetKeyValue("exetime", "3")
        hint:SetKeyValue("radius", tostring(math.floor(GAS_RADIUS)))
        hint:Spawn()
        hint:Activate()
        hint:Fire("EmitAISound", "", 0)
        timer.Simple(3.1, function()
            if IsValid(hint) then hint:Remove() end
        end)
    end

    local fleeTimer = "NerveGasFlee_" .. uid
    local fleeTicks = math.floor(GAS_DURATION_FLEE / 3)
    EmitDangerHint()
    timer.Create(fleeTimer, 3, fleeTicks, function()
        EmitDangerHint()
    end)

    local GAS_DAMAGE = 70
    local GAS_DURATION = 18
    local GAS_TICK = 0.1
    local ticks = math.floor(GAS_DURATION / GAS_TICK)
    local timerName = "NerveGasDmg_" .. uid
    
    local attacker = self:GetOwner() 
    if not IsValid(attacker) then attacker = game.GetWorld() end

    timer.Create(timerName, GAS_TICK, ticks, function()
        local atk = IsValid(attacker) and attacker or game.GetWorld()

        for _, ent in ipairs(ents.FindInSphere(pos, GAS_RADIUS)) do
            if not IsValid(ent) then continue end
            if not ent:IsPlayer() and not ent:IsNPC() then continue end

            local dist = ent:GetPos():Distance(pos)
            local falloff = 1 - math.Clamp(dist / GAS_RADIUS, 0, 1)
            local dmgAmt = math.max(1, GAS_DAMAGE * falloff)

            local dmginfo = DamageInfo()
            dmginfo:SetDamage(dmgAmt)
            dmginfo:SetBaseDamage(dmgAmt)
            dmginfo:SetDamageType(DMG_BLAST)
            dmginfo:SetAttacker(atk)
            dmginfo:SetInflictor(game.GetWorld())
            dmginfo:SetDamagePosition(pos)
            dmginfo:SetDamageForce((ent:GetPos() - pos):GetNormalized() * dmgAmt * 8)
            ent:TakeDamageInfo(dmginfo)

            if ent:IsPlayer() and not ent.GASMASK_Equiped then
                ApplyNerveGasHigh(ent)
            end
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
