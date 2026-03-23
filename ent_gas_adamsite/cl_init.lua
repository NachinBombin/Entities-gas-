include("shared.lua")

local SMOKE_SPRITE_BASE = "particle/smokesprites_000"

-- ============================================================
-- Entity Tracer FX
-- ============================================================

function ENT:Initialize()
    self.Emitter = ParticleEmitter(self:GetPos(), false)
end

function ENT:OnRemove()
    if IsValid(self.Emitter) then
        self.Emitter:Finish()
    end
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    if not IsValid(self.Emitter) then return end
    
    local pos = self:GetPos()

    for i = 1, 2 do
        local p = self.Emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if p then
            p:SetVelocity(Vector(math.Rand(-8, 8), math.Rand(-8, 8), math.Rand(4, 14)))
            p:SetDieTime(math.Rand(0.3, 0.6))
            p:SetColor(175, 158, 95)
            p:SetStartAlpha(math.Rand(175, 215))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(3, 6))
            p:SetEndSize(math.Rand(14, 24))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.5, 0.5))
            p:SetAirResistance(70)
            p:SetGravity(Vector(0, 0, -6))
        end
    end

    if math.random() > 0.6 then
        local p = self.Emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if p then
            p:SetVelocity(Vector(math.Rand(-12, 12), math.Rand(-12, 12), math.Rand(6, 18)))
            p:SetDieTime(math.Rand(0.6, 1.1))
            p:SetColor(190, 180, 140)
            p:SetStartAlpha(math.Rand(60, 90))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(5, 9))
            p:SetEndSize(math.Rand(22, 38))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.3, 0.3))
            p:SetAirResistance(45)
            p:SetGravity(Vector(0, 0, -4))
        end
    end
    
    self:SetNextClientThink(CurTime() + 0.05)
    return true
end

-- ============================================================
-- Network Receivers and Screen Effect Hooks
-- ============================================================

net.Receive("NPCAdamsite_CloudEffect", function()
    local pos = net.ReadVector()
    local cloudRadius = net.ReadFloat()

    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end

    local count = math.floor(math.Clamp(cloudRadius / 5, 30, 120))

    for i = 1, count do
        local p = emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if not p then continue end

        local speed = math.Rand(cloudRadius * 0.3, cloudRadius * 1.0)
        p:SetVelocity(VectorRand():GetNormalized() * speed)

        if i <= math.floor(count * 0.1) then
            p:SetDieTime(18)
        else
            p:SetDieTime(math.Rand(8, 18))
        end

        local r = math.random(155, 195)
        local g = math.random(140, 175)
        local b = math.random(70, 110)
        p:SetColor(r, g, b)

        p:SetStartAlpha(math.Rand(40, 60))
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(40, 60))
        p:SetEndSize(math.Rand(180, 260))
        p:SetRoll(math.Rand(0, 360))
        p:SetRollDelta(math.Rand(-1, 1))
        p:SetAirResistance(100)
        p:SetCollide(true)
        p:SetBounce(1)
    end

    emitter:Finish()
end)

local cl_highStart = 0
local cl_highEnd = 0

net.Receive("NPCAdamsite_ApplyHigh", function()
    cl_highStart = net.ReadFloat()
    cl_highEnd = net.ReadFloat()
end)

local ADAMSITE_TRANSITION = 3 
local ADAMSITE_INTENSITY = 1

local function GetAdamsiteFactor(balOffset)
    balOffset = balOffset or 0
    local now = CurTime()

    local highStart = cl_highStart
    local highEnd = cl_highEnd

    if highStart == 0 then
        local ply = LocalPlayer()
        if not IsValid(ply) then return 0 end
        highStart = ply:GetNWFloat("npc_adamsite_high_start", 0)
        highEnd = ply:GetNWFloat("npc_adamsite_high_end", 0)
    end

    if highStart == 0 or highEnd <= now then return 0 end

    local factor
    if highStart + ADAMSITE_TRANSITION > now then
        local s = highStart
        local e = s + ADAMSITE_TRANSITION
        factor = ((now - s) / (e - s)) * ADAMSITE_INTENSITY
    elseif highEnd - ADAMSITE_TRANSITION < now then
        local e = highEnd
        local s = e - ADAMSITE_TRANSITION
        factor = (1 - (now - s) / (e - s)) * ADAMSITE_INTENSITY
    else
        factor = ADAMSITE_INTENSITY
    end

    local pl = LocalPlayer()
    if IsValid(pl) then
        local balStart = pl:GetNWFloat("npc_adamsite_bal_start", 0)
        if balStart > 0 then
            local balElapsed = now - balStart
            local balDuration = 20

            if balElapsed >= balOffset then
                local effectElapsed = balElapsed - balOffset
                local effectWindow = balDuration - balOffset
                if effectWindow > 0 then
                    factor = factor * math.max(0, 1 - (effectElapsed / effectWindow))
                else
                    factor = 0
                end
            end
        end
    end

    return math.Clamp(factor, 0, 1)
end

hook.Add("Think", "NPCAdamsite_BlinkForceUpdate", function()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    local f = GetAdamsiteFactor(0)

    if f <= 0 then
        AdamsiteBlinkForce = nil
        return
    end

    local blinkFreqMult = math.Remap(f, 0, 1, 2.0, 28.0)
    local blinkDurMult = math.Remap(f, 0, 1, 1.5, 6.0)

    AdamsiteBlinkForce = {
        freqMult = blinkFreqMult,
        durMult = blinkDurMult,
        isFatigue = (f > 0.15),
    }
end)

local cl_vomit_shake_ang = Angle(0, 0, 0)
local cl_vomit_shake_end = 0
local cl_vomit_shake_dur = 0.35

local VOMIT_MOUTH_EMITTERS = { "slime_splash_01_droplets" }
local VOMIT_GROUND_EMITTERS = { "slime_splash_01_droplets" }

net.Receive("NPCAdamsite_Vomit", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    ply:ViewPunch(Angle(math.Rand(7, 18), math.Rand(-10, 10), math.Rand(-8, 8)))

    cl_vomit_shake_dur = math.Rand(0.20, 0.55)
    cl_vomit_shake_ang = Angle(math.Rand(8, 22), math.Rand(-14, 14), math.Rand(-10, 10))
    cl_vomit_shake_end = CurTime() + cl_vomit_shake_dur

    local mouthPos = ply:GetShootPos()
    local mouthAng = Angle(0, ply:EyeAngles().y, 0)
    ParticleEffect(VOMIT_MOUTH_EMITTERS[math.random(#VOMIT_MOUTH_EMITTERS)], mouthPos, mouthAng)
    if math.random() > 0.4 then
        ParticleEffect(VOMIT_MOUTH_EMITTERS[math.random(#VOMIT_MOUTH_EMITTERS)], mouthPos, mouthAng)
    end
end)

net.Receive("NPCAdamsite_VomitSplat", function()
    local pos = net.ReadVector()
    local normal = net.ReadVector()

    local ang = Angle(0, 0, 0)
    ParticleEffect(VOMIT_GROUND_EMITTERS[math.random(#VOMIT_GROUND_EMITTERS)], pos, ang)

    if math.random() > 0.6 then
        local scatter = Vector(math.Rand(-14, 14), math.Rand(-14, 14), 0)
        ParticleEffect(VOMIT_GROUND_EMITTERS[math.random(#VOMIT_GROUND_EMITTERS)], pos + scatter, ang)
    end
end)

local sneezeQueue = {}

net.Receive("NPCAdamsite_Sneeze", function()
    local clusterSize = net.ReadInt(4)
    local now = CurTime()
    local ply = LocalPlayer()

    for i = 1, clusterSize do
        local delay = (i - 1) * math.Rand(0.22, 0.80)

        table.insert(sneezeQueue, {
            time = now + delay,
            punchAng = Angle(-math.Rand(12, 32), math.Rand(-18, 18), math.Rand(-12, 12)),
        })

        timer.Simple(delay, function()
            if not IsValid(ply) then return end

            local function fireEffect(extraDelay)
                timer.Simple(extraDelay, function()
                    if not IsValid(ply) then return end

                    local scale = 0.5
                    local aimDir = ply:GetAimVector()
                    local right = ply:GetRight()
                    local up = ply:GetUp()

                    local deflected = (aimDir + right * math.Rand(-0.6, 0.6) + up * math.Rand(-0.3, 0.5)):GetNormalized()
                    local originJitter = right * math.Rand(-4, 4) + up * math.Rand(-4, 4)

                    local edata = EffectData()
                    edata:SetOrigin(ply:GetShootPos() + originJitter)
                    edata:SetNormal(deflected * (6 - scale) / 2)
                    edata:SetScale(scale / 2)
                    util.Effect("StriderBlood", edata)
                end)
            end

            fireEffect(0)
            fireEffect(0.04)
            fireEffect(0.08)
        end)
    end
end)

local cl_sneeze_shake_ang = Angle(0, 0, 0)
local cl_sneeze_shake_end = 0
local cl_sneeze_shake_dur = 0.18

hook.Add("Think", "NPCAdamsite_SneezeProcess", function()
    if #sneezeQueue == 0 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local now = CurTime()
    local i = 1
    while i <= #sneezeQueue do
        local entry = sneezeQueue[i]
        if now >= entry.time then
            ply:ViewPunch(entry.punchAng)

            cl_sneeze_shake_dur = math.Rand(0.12, 0.38)
            cl_sneeze_shake_ang = entry.punchAng
            cl_sneeze_shake_end = now + cl_sneeze_shake_dur

            table.remove(sneezeQueue, i)
        else
            i = i + 1
        end
    end
end)

local tremorSeedR = math.random() * 100
local tremorSeedP = math.random() * 100 + 33
local tremorSeedY = math.random() * 100 + 66

hook.Add("CalcView", "NPCAdamsiteGasThrow_Tremor", function(pl, origin, angles, fov)
    if not IsValid(pl) then return end

    local f = GetAdamsiteFactor(10)
    local now = CurTime()

    local sneezePitch, sneezeYaw, sneezeRoll = 0, 0, 0
    if cl_sneeze_shake_end > now then
        local decay = (cl_sneeze_shake_end - now) / cl_sneeze_shake_dur
        sneezePitch = cl_sneeze_shake_ang.p * decay
        sneezeYaw = cl_sneeze_shake_ang.y * decay
        sneezeRoll = cl_sneeze_shake_ang.r * decay
    end

    local vomitPitch, vomitYaw, vomitRoll = 0, 0, 0
    if cl_vomit_shake_end > now then
        local decay = (cl_vomit_shake_end - now) / cl_vomit_shake_dur
        vomitPitch = cl_vomit_shake_ang.p * decay
        vomitYaw = cl_vomit_shake_ang.y * decay
        vomitRoll = cl_vomit_shake_ang.r * decay
    end

    if f <= 0 and sneezePitch == 0 and sneezeYaw == 0 and sneezeRoll == 0
       and vomitPitch == 0 and vomitYaw == 0 and vomitRoll == 0 then
        return
    end

    local t = CurTime()

    local roll = math.noise(tremorSeedR + t * 0.32) * 0.5 * f
    local pitch = math.noise(tremorSeedP + t * 0.41) * 0.3 * f
    local yaw = math.noise(tremorSeedY + t * 0.26) * 0.2 * f

    roll = roll + math.sin(t * 0.58) * 0.12 * f
    pitch = pitch + math.sin(t * 0.82 + 0.7) * 0.08 * f

    local newAngles = Angle(
        angles.p + pitch + sneezePitch + vomitPitch,
        angles.y + yaw + sneezeYaw + vomitYaw,
        angles.r + roll + sneezeRoll + vomitRoll
    )

    return { origin = origin, angles = newAngles, fov = fov }
end)

local lastForward = 0
local lastSide = 0

hook.Add("CreateMove", "NPCAdamsite_Malaise", function(cmd)
    local f = GetAdamsiteFactor(15)

    if f <= 0 then
        lastForward = 0
        lastSide = 0
        return
    end

    local lerpSpeed = 1 - (0.76 * f)

    lastForward = Lerp(lerpSpeed, lastForward, cmd:GetForwardMove())
    lastSide = Lerp(lerpSpeed, lastSide, cmd:GetSideMove())

    cmd:SetForwardMove(lastForward)
    cmd:SetSideMove(lastSide)
end)

local adamsiteColorModify = {
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, 
    ["$pp_colour_contrast"] = 1, 
    ["$pp_colour_colour"] = 1, 
}

hook.Add("RenderScreenspaceEffects", "NPCAdamsiteGasThrow_Visuals", function()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    local f = GetAdamsiteFactor(0)

    adamsiteColorModify["$pp_colour_brightness"] = -0.02 * f
    adamsiteColorModify["$pp_colour_colour"] = 1 - (0.08 * f)
    DrawColorModify(adamsiteColorModify)
end)

hook.Add("PostRender", "NPCAdamsiteGasThrow_Reset", function()
    if cl_highEnd > 0 and cl_highEnd <= CurTime() then
        adamsiteColorModify["$pp_colour_brightness"] = 0
        adamsiteColorModify["$pp_colour_colour"] = 1
        DrawColorModify(adamsiteColorModify)
        cl_highStart = 0
        cl_highEnd = 0
        AdamsiteBlinkForce = nil
        lastForward = 0
        lastSide = 0
        sneezeQueue = {}
    end
end)
