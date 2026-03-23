AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Retained ConVars to preserve existing server configurations
local cv_cloud_min = CreateConVar("npc_adamsite_gas_throw_cloud_min", "150", SHARED_FLAGS, "Minimum gas cloud radius in units.")
local cv_cloud_max = CreateConVar("npc_adamsite_gas_throw_cloud_max", "300", SHARED_FLAGS, "Maximum gas cloud radius in units.")
local cv_high_min = CreateConVar("npc_adamsite_gas_throw_high_min", "60", SHARED_FLAGS, "Minimum effect duration in seconds.")
local cv_high_max = CreateConVar("npc_adamsite_gas_throw_high_max", "120", SHARED_FLAGS, "Maximum effect duration in seconds.")

local VIAL_MODEL = "models/healthvial.mdl"
local VIAL_MATERIAL = "models/weapons/gv/nerve_vial.vmt"

local IMPACT_SPEED = 80
local MIN_FLIGHT = 0.25
local MAX_VIAL_LIFE = 8

-- Precache required sounds and particles
util.PrecacheSound("vomit/vomiting.wav")
util.PrecacheSound("vomit1.wav")
util.PrecacheSound("vomit2.wav")
util.PrecacheSound("vomit3.wav")
util.PrecacheSound("sneeze1.wav")
util.PrecacheSound("sneeze2.wav")
util.PrecacheSound("sneeze3.wav")
util.PrecacheSound("sneeze4.wav")
util.PrecacheSound("sneeze5.wav")
util.PrecacheSound("sneeze6.wav")

game.AddParticles("particles/water_impact.pcf")
PrecacheParticleSystem("slime_splash_01_droplets")

local SNEEZE_SOUNDS = {
    "sneeze1.wav", "sneeze2.wav", "sneeze3.wav", "sneeze4.wav", "sneeze5.wav", "sneeze6.wav",
}

local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist = horizontal:Length()
    if dist < 1 then dist = 1 end
    horizontal:Normalize()
    local velH = horizontal * speed
    local velZ = dist * arcFactor + (to.z - from.z) * 0.3
    velZ = math.Clamp(velZ, -speed * 0.5, speed * 0.8)
    return Vector(velH.x, velH.y, velZ)
end

-- Player state tables
local playerHighEnd = {} 
local playerExposeStart = {} 
local playerVomitNext = {} 
local playerSneezeNext = {} 
local playerAcidNext = {} 
local playerBALStart = {} 

local VOMIT_DECALS = {
    "glassbreak", "antlion.splat", "birdpoop", "paintsplatgreen", "splash.large",
}

local function SpawnVomitSplatFX(pos, normal)
    local count = math.random(2, 3)
    for i = 1, count do
        local scatter = Vector(math.Rand(-22, 22), math.Rand(-22, 22), 0)
        local decalName = VOMIT_DECALS[math.random(#VOMIT_DECALS)]
        local from = pos + normal * 4 + scatter
        local to = pos - normal * 4 + scatter
        util.Decal(decalName, from, to)
    end
    net.Start("NPCAdamsite_VomitSplat")
    net.WriteVector(pos)
    net.WriteVector(normal)
    net.Broadcast()
end

local function TriggerAdamsiteVomit(pl)
    if not IsValid(pl) or not pl:Alive() then return end

    local aimVec = pl:GetAimVector()
    local shootPos = pl:GetShootPos()

    local function spawnOne()
        if not IsValid(pl) or not pl:Alive() then return end

        local ang = aimVec:Angle()
        local right = ang:Right()
        local up = ang:Up()

        local originOffset = right * math.Rand(-5, 5) + up * math.Rand(-5, 5)
        local spawnPos = shootPos + originOffset + aimVec * 8

        local wm = ents.Create("prop_physics")
        if not IsValid(wm) then return end

        wm:SetModel("models/props_junk/watermelon01.mdl")
        wm:SetPos(spawnPos)
        wm:SetAngles(Angle(math.random(0, 360), math.random(0, 360), math.random(0, 360)))
        wm:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        wm:Spawn()
        wm:Activate()

        local horzScale = math.Rand(7000, 11000)
        local breakForce = Vector(
            aimVec.x * horzScale + math.Rand(-800, 800),
            aimVec.y * horzScale + math.Rand(-800, 800),
            math.Rand(150, 600)
        )

        local dmgInfo = DamageInfo()
        dmgInfo:SetDamage(50000)
        dmgInfo:SetDamageType(DMG_CRUSH)
        dmgInfo:SetAttacker(pl)
        dmgInfo:SetInflictor(pl)
        dmgInfo:SetDamageForce(breakForce)
        dmgInfo:SetDamagePosition(spawnPos)
        
        timer.Simple(0, function()
            if IsValid(wm) then pcall(wm.TakeDamageInfo, wm, dmgInfo) end

            local groundTr = util.TraceLine({
                start = spawnPos,
                endpos = spawnPos - Vector(0, 0, 400),
                filter = pl,
                mask = MASK_SOLID_BRUSHONLY,
            })
            if groundTr.Hit then
                SpawnVomitSplatFX(groundTr.HitPos, groundTr.HitNormal)
            end
        end)

        local spreadVec = (aimVec + right * math.Rand(-0.45, 0.45) + up * math.Rand(-0.20, 0.35))
        local spreadAng = spreadVec:GetNormalized():Angle()

        local ent = ents.Create("ent_adamsite_vomit")
        if IsValid(ent) then
            ent:SetPos(shootPos + originOffset + spreadAng:Forward() * 3 + spreadAng:Up() * -4)
            ent:SetAngles(spreadAng)
            ent:SetOwner(pl)
            ent:Spawn()
            ent:Activate()

            local phys2 = ent:GetPhysicsObject()
            if IsValid(phys2) then
                phys2:ApplyForceCenter(aimVec:GetNormalized() * math.Rand(52, 70))
                phys2:ApplyForceCenter(spreadAng:Forward() * math.Rand(44, 58) + spreadAng:Up() * math.Rand(44, 58))
                phys2:Wake()
            end
        end
    end

    spawnOne()

    local VOMIT_SOUNDS = { "vomit/vomiting.wav", "vomit1.wav", "vomit2.wav", "vomit3.wav" }
    pl:EmitSound(VOMIT_SOUNDS[math.random(#VOMIT_SOUNDS)], 75, math.random(88, 112), 1.0)

    net.Start("NPCAdamsite_Vomit")
    net.Send(pl)
end

local function TriggerAdamsiteSneeze(pl)
    if not IsValid(pl) or not pl:Alive() then return end

    local clusterSize = math.random(2, 4)
    local pos = pl:GetPos()

    for i = 1, clusterSize do
        local delay = (i - 1) * math.Rand(0.30, 0.65)
        timer.Simple(delay, function()
            if not IsValid(pl) or not pl:Alive() then return end
            local sneezeSnd = SNEEZE_SOUNDS[math.random(#SNEEZE_SOUNDS)]
            pl:EmitSound(sneezeSnd, 90, math.random(85, 115), 1.0)
            util.ScreenShake(pl:GetPos(), 3, 8, 0.4, 0)
        end)
    end

    net.Start("NPCAdamsite_Sneeze")
    net.WriteInt(clusterSize, 4)
    net.Send(pl)
end

local function TriggerAdamsiteAcidVomit(pl)
    if not IsValid(pl) or not pl:Alive() then return end

    local shootPos = pl:GetShootPos()
    local aimVec = pl:GetAimVector()
    local playerPos = pl:GetPos()
    local flatFwd = Vector(aimVec.x, aimVec.y, 0):GetNormalized()

    local function spawnOneSpit(lateralOffset)
        if not IsValid(pl) or not pl:Alive() then return end

        local right = aimVec:Angle():Right()
        local spawnOrigin = shootPos + aimVec * 18 + right * lateralOffset

        local fwdDist = math.Rand(150, 400)
        local probeTop = playerPos + flatFwd * fwdDist + right * lateralOffset + Vector(0, 0, 80)
        local probeBot = probeTop - Vector(0, 0, 300)

        local tr = util.TraceLine({
            start = probeTop,
            endpos = probeBot,
            filter = pl,
            mask = MASK_SOLID_BRUSHONLY,
        })
        local targetPos = tr.Hit and tr.HitPos or (probeTop + probeBot) * 0.5
        local targetNrm = tr.Hit and tr.HitNormal or Vector(0, 0, 1)

        local spit = ents.Create("grenade_spit")
        if not IsValid(spit) then return end

        spit:SetPos(spawnOrigin)
        spit:SetOwner(pl)
        spit:SetAngles(aimVec:Angle())
        spit:Spawn()
        spit:Activate()

        local phys = spit:GetPhysicsObject()
        if IsValid(phys) then
            local vel = CalcLaunchVelocity(spit:GetPos(), targetPos, 320, 0.35)
            phys:SetVelocity(vel)
            phys:Wake()
        end

        timer.Simple(1.0, function()
            if not IsValid(pl) then return end
            SpawnVomitSplatFX(targetPos, targetNrm)
        end)
    end

    spawnOneSpit(0)
    timer.Simple(0.07, function() spawnOneSpit(math.Rand(-12, 12)) end)

    util.ScreenShake(playerPos, 4, 10, 0.35, 0)
    net.Start("NPCAdamsite_Vomit")
    net.Send(pl)

    timer.Simple(1.2, function()
        if not IsValid(pl) or not pl:Alive() then return end
        local dmg = DamageInfo()
        dmg:SetDamage(8)
        dmg:SetDamageType(DMG_POISON)
        dmg:SetAttacker(pl)
        dmg:SetInflictor(pl)
        dmg:SetDamagePosition(pl:GetPos())
        pcall(pl.TakeDamageInfo, pl, dmg)
    end)
end

local function ApplyAdamsiteHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end
    if pl.GASMASK_Equiped then return end

    local now = CurTime()
    local uid = pl:UserID()
    local highDuration = math.Rand(cv_high_min:GetFloat(), cv_high_max:GetFloat())

    if (playerHighEnd[uid] or 0) > now then
        playerHighEnd[uid] = math.max(playerHighEnd[uid], now + highDuration)
        pl:SetNWFloat("npc_adamsite_high_end", playerHighEnd[uid])
        return
    end

    playerHighEnd[uid] = now + highDuration

    if not playerExposeStart[uid] then
        playerExposeStart[uid] = now
    end

    if not playerVomitNext[uid] or playerVomitNext[uid] < now then
        playerVomitNext[uid] = now + math.Rand(1.5, 4)
    end
    if not playerSneezeNext[uid] or playerSneezeNext[uid] < now then
        playerSneezeNext[uid] = now + math.Rand(4, 12)
    end
    if not playerAcidNext[uid] or playerAcidNext[uid] < now then
        playerAcidNext[uid] = now + math.Rand(2, 6)
    end

    net.Start("NPCAdamsite_ApplyHigh")
    net.WriteFloat(now)
    net.WriteFloat(playerHighEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_adamsite_high_start", now)
    pl:SetNWFloat("npc_adamsite_high_end", playerHighEnd[uid])
    pl:SetNWFloat("npc_adamsite_expose_start", now)
end

-- Global ticker: applies queued afflictions to all currently affected players
timer.Create("AdamsiteEffectTick", 0.5, 0, function()
    local now = CurTime()
    for uid, expiry in pairs(playerHighEnd) do
        if expiry < now then continue end 

        local pl = nil
        for _, p in ipairs(player.GetAll()) do
            if p:UserID() == uid then pl = p; break end
        end

        if not IsValid(pl) or not pl:Alive() then continue end
        if (playerBALStart[uid] or 0) > 0 then continue end

        if now >= (playerVomitNext[uid] or 0) then
            TriggerAdamsiteVomit(pl)
            playerVomitNext[uid] = now + math.Rand(3, 7)
        end

        if now >= (playerAcidNext[uid] or 0) then
            TriggerAdamsiteAcidVomit(pl)
            playerAcidNext[uid] = now + math.Rand(4, 9)
        end

        if now >= (playerSneezeNext[uid] or 0) then
            TriggerAdamsiteSneeze(pl)
            playerSneezeNext[uid] = now + math.Rand(10, 25)
        end
    end
end)

hook.Add("PlayerDeath", "NPCAdamsiteGasThrow_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    playerHighEnd[uid] = nil
    playerExposeStart[uid] = nil
    playerVomitNext[uid] = nil
    playerSneezeNext[uid] = nil
    playerAcidNext[uid] = nil
    playerBALStart[uid] = nil
    pl:SetNWFloat("npc_adamsite_high_start", 0)
    pl:SetNWFloat("npc_adamsite_high_end", 0)
    pl:SetNWFloat("npc_adamsite_expose_start", 0)
    pl:SetNWFloat("npc_adamsite_bal_start", 0)
    net.Start("NPCAdamsite_ApplyHigh")
    net.WriteFloat(0)
    net.WriteFloat(0)
    net.Send(pl)
end)

-- Global export so BAL Antidote still detects and clears the effect perfectly
function NPCAdamsite_AntidoteClear(ply)
    if not IsValid(ply) then return end

    local uid = ply:UserID()
    local now = CurTime()
    
    playerBALStart[uid] = now
    ply:SetNWFloat("npc_adamsite_bal_start", now)

    playerVomitNext[uid] = now + 9999
    playerSneezeNext[uid] = now + 9999
    playerAcidNext[uid] = now + 9999

    timer.Simple(20, function()
        if not IsValid(ply) then return end
        local uid2 = ply:UserID()
        playerHighEnd[uid2] = nil
        playerExposeStart[uid2] = nil
        playerVomitNext[uid2] = nil
        playerSneezeNext[uid2] = nil
        playerAcidNext[uid2] = nil
        playerBALStart[uid2] = nil
        ply:SetNWFloat("npc_adamsite_high_start", 0)
        ply:SetNWFloat("npc_adamsite_high_end", 0)
        ply:SetNWFloat("npc_adamsite_expose_start", 0)
        ply:SetNWFloat("npc_adamsite_bal_start", 0)
        
        net.Start("NPCAdamsite_ApplyHigh")
        net.WriteFloat(0)
        net.WriteFloat(0)
        net.Send(ply)
    end)
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
        -- Imparts natural tumble and forward force similar to player throws
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

    net.Start("NPCAdamsite_CloudEffect")
    net.WriteVector(pos)
    net.WriteFloat(cloudRadius)
    net.Broadcast()

    local GAS_DURATION = 18
    local GAS_TICK = 0.5
    local ticks = math.floor(GAS_DURATION / GAS_TICK)
    local timerName = "AdamsiteGasCloud_" .. uid

    timer.Create(timerName, GAS_TICK, ticks, function()
        for _, ent in ipairs(ents.FindInSphere(pos, cloudRadius)) do
            if not IsValid(ent) then continue end
            if not ent:IsPlayer() then continue end 
            ApplyAdamsiteHigh(ent)
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
    
    -- Two consecutive slow ticks needed to filter out minor ground bounces
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
