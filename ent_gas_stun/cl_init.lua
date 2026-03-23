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
            p:SetColor(255, 120, 20)
            p:SetStartAlpha(math.Rand(180, 220))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(3, 6))
            p:SetEndSize(math.Rand(14, 24))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.5, 0.5))
            p:SetAirResistance(70)
            p:SetGravity(Vector(0, 0, -6))
        end
    end

    if math.random() > 0.55 then
        local p = self.Emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if p then
            p:SetVelocity(Vector(math.Rand(-14, 14), math.Rand(-14, 14), math.Rand(8, 20)))
            p:SetDieTime(math.Rand(0.7, 1.2))
            p:SetColor(240, 90, 10)
            p:SetStartAlpha(math.Rand(70, 110))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(6, 11))
            p:SetEndSize(math.Rand(28, 45))
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

net.Receive("NPCStunGas_CloudEffect", function()
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

        local r = math.random(220, 255)
        local g = math.random(70, 140)
        p:SetColor(r, g, 10)

        p:SetStartAlpha(math.Rand(45, 65))
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

local STUN_HIGH_TRANSITION = 6
local STUN_HIGH_INTENSITY = 1

local cl_highStart = 0
local cl_highEnd = 0

net.Receive("NPCStunGas_ApplyHigh", function()
    cl_highStart = net.ReadFloat()
    cl_highEnd = net.ReadFloat()
end)

local function GetStunBlurFactor()
    local now = CurTime()

    local highStart = cl_highStart
    local highEnd = cl_highEnd

    if highStart == 0 then
        local ply = LocalPlayer()
        if not IsValid(ply) then return 0 end
        highStart = ply:GetNWFloat("npc_stungas_high_start", 0)
        highEnd = ply:GetNWFloat("npc_stungas_high_end", 0)
    end

    if highStart == 0 or highEnd <= now then return 0 end

    local factor = 0

    if highStart + STUN_HIGH_TRANSITION > now then
        local s = highStart
        local e = s + STUN_HIGH_TRANSITION
        factor = ((now - s) / (e - s)) * STUN_HIGH_INTENSITY
    elseif highEnd - STUN_HIGH_TRANSITION < now then
        local e = highEnd
        local s = e - STUN_HIGH_TRANSITION
        factor = (1 - (now - s) / (e - s)) * STUN_HIGH_INTENSITY
    else
        factor = STUN_HIGH_INTENSITY
    end

    return math.Clamp(factor, 0, 1)
end

hook.Add("RenderScreenspaceEffects", "NPCStunGasThrow_High", function()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    local factor = GetStunBlurFactor()
    if factor <= 0 then return end

    DrawMotionBlur(0.03, factor, 0)

    render.SetColorModulation(
        1,
        0.7 + (1 - factor) * 0.3,
        0.4 + (1 - factor) * 0.6
    )
end)

hook.Add("CalcView", "NPCStunGasThrow_Sway", function(pl, origin, angles, fov)
    if not IsValid(pl) then return end

    local factor = GetStunBlurFactor()
    if factor <= 0 then return end

    local t = CurTime()

    local roll = math.sin(t * 0.9) * 8 * factor
    local pitch = math.sin(t * 1.6 + 1.2) * 3 * factor
    local yaw = math.sin(t * 0.5 + 0.7) * 1.5 * factor

    local newAngles = Angle(
        angles.p + pitch,
        angles.y + yaw,
        angles.r + roll
    )

    return { origin = origin, angles = newAngles, fov = fov }
end)

hook.Add("PostRender", "NPCStunGasThrow_HighReset", function()
    if cl_highEnd > 0 and cl_highEnd <= CurTime() then
        render.SetColorModulation(1, 1, 1)
        cl_highStart = 0
        cl_highEnd = 0
    end
end)
