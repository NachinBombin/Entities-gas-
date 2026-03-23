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
            p:SetVelocity(Vector(math.Rand(-7, 7), math.Rand(-7, 7), math.Rand(5, 16)))
            p:SetDieTime(math.Rand(0.25, 0.55))
            p:SetColor(235, 238, 242)
            p:SetStartAlpha(math.Rand(200, 240))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(2, 5))
            p:SetEndSize(math.Rand(12, 22))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.4, 0.4))
            p:SetAirResistance(65)
            p:SetGravity(Vector(0, 0, -5))
        end
    end

    if math.random() > 0.60 then
        local p = self.Emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if p then
            p:SetVelocity(Vector(math.Rand(-12, 12), math.Rand(-12, 12), math.Rand(10, 22)))
            p:SetDieTime(math.Rand(0.6, 1.1))
            p:SetColor(220, 224, 230)
            p:SetStartAlpha(math.Rand(90, 130))
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(5, 10))
            p:SetEndSize(math.Rand(26, 44))
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

net.Receive("NPCKAerosol_CloudEffect", function()
    local pos = net.ReadVector()
    local cloudRadius = net.ReadFloat()

    local emitter = ParticleEmitter(pos, false)
    if not emitter then return end

    local count = math.floor(math.Clamp(cloudRadius / 4, 35, 130))

    for i = 1, count do
        local p = emitter:Add(SMOKE_SPRITE_BASE .. math.random(1, 9), pos)
        if not p then continue end

        p:SetVelocity(VectorRand():GetNormalized() * math.Rand(cloudRadius * 0.3, cloudRadius * 1.0))
        p:SetDieTime(i <= math.floor(count * 0.1) and 16 or math.Rand(7, 16))

        local shade = math.random(210, 245)
        p:SetColor(shade, shade, shade + math.random(0, 8))
        p:SetStartAlpha(math.Rand(50, 70))
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(35, 55))
        p:SetEndSize(math.Rand(170, 250))
        p:SetRoll(math.Rand(0, 360))
        p:SetRollDelta(math.Rand(-0.8, 0.8))
        p:SetAirResistance(90)
        p:SetCollide(true)
        p:SetBounce(1)
    end

    emitter:Finish()
end)

local cl_effectStart = 0
local cl_effectEnd = 0
local cl_wakeupDone = false
local cl_limaWasActive = false

net.Receive("NPCKAerosol_ApplyEffect", function()
    cl_effectStart = net.ReadFloat()
    cl_effectEnd = net.ReadFloat()
    if cl_effectStart == 0 then
        cl_wakeupDone = false
        cl_limaWasActive = false
        render.SetColorModulation(1, 1, 1)
    end
end)

local function GetKAerosolElapsed()
    local now = CurTime()
    local effStart = cl_effectStart
    local effEnd = cl_effectEnd

    if effStart == 0 then
        local lp = LocalPlayer()
        if not IsValid(lp) then return -1 end
        effStart = lp:GetNWFloat("npc_kaerosol_start", 0)
        effEnd = lp:GetNWFloat("npc_kaerosol_end", 0)
    end

    if effStart == 0 or effEnd <= now then return -1 end
    return now - effStart
end

local function GetKAerosolRemaining()
    local effEnd = cl_effectEnd
    if effEnd == 0 then
        local lp = LocalPlayer()
        if not IsValid(lp) then return 0 end
        effEnd = lp:GetNWFloat("npc_kaerosol_end", 0)
    end
    return math.max(effEnd - CurTime(), 0)
end

local KAEROSOL_PARALYSIS_ELAPSED = 15

local function IsFullyParalyzed(elapsed)
    return elapsed >= KAEROSOL_PARALYSIS_ELAPSED
end

local function LimaAnimIsActive()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end

    local active = IsValid(lp:GetNW2Entity("xen_teleport_effect"))

    if active and not cl_limaWasActive then
        cl_limaWasActive = true
    end

    if not active and cl_limaWasActive then
        cl_wakeupDone = true
        cl_limaWasActive = false
        render.SetColorModulation(1, 1, 1)
        net.Start("NPCKAerosol_WakeupDone")
        net.SendToServer()
    end

    return active
end

local function GetCollapseFactor(elapsed)
    if elapsed < 5 then return 0 end
    if elapsed < 14 then return math.Remap(elapsed, 5, 14, 0.0, 1.0) end
    return 1.0
end

local BLACKOUT_RAMPOUT = 4

local function GetBlackoutPulseFactor(elapsed, remaining)
    if elapsed < 5 then return 0 end

    local inFactor = elapsed < 13 and math.Remap(elapsed, 5, 13, 0.0, 1.0) or 1.0
    local outFactor = 1.0
    
    if remaining < BLACKOUT_RAMPOUT then
        outFactor = remaining / BLACKOUT_RAMPOUT
    end

    return math.Clamp(inFactor * outFactor, 0, 1)
end

hook.Add("RenderScreenspaceEffects", "NPCKAerosolGasThrow_PostProcess", function()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    if LimaAnimIsActive() or cl_wakeupDone then return end

    local elapsed = GetKAerosolElapsed()
    if elapsed < 0 then return end

    local cf = GetCollapseFactor(elapsed)
    if cf <= 0 then return end

    local contrast = cf <= 0.5
        and math.Remap(cf, 0, 0.5, 1.0, 2.2)
        or math.Remap(cf, 0.5, 1.0, 2.2, 0.35)

    local brightness = cf <= 0.5
        and math.Remap(cf, 0, 0.5, 0.0, -0.15)
        or math.Remap(cf, 0.5, 1.0, -0.15, -0.92)

    local saturation = math.Remap(cf, 0, 1, 1.0, 0.0)

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = brightness,
        ["$pp_colour_contrast"] = contrast,
        ["$pp_colour_colour"] = saturation,
    })
end)

hook.Add("HUDPaint", "NPCKAerosolGasThrow_Blackout", function()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    if LimaAnimIsActive() or cl_wakeupDone then return end

    local elapsed = GetKAerosolElapsed()
    if elapsed < 0 then return end

    local sw, sh = ScrW(), ScrH()

    if IsFullyParalyzed(elapsed) then
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, sw, sh)
        return
    end

    local remaining = GetKAerosolRemaining()
    local bfactor = GetBlackoutPulseFactor(elapsed, remaining)
    if bfactor <= 0 then return end

    local t = CurTime()
    local pulse = math.sin(t * 2.5 * math.pi) * 0.5 + 0.5 
    local base = math.floor(bfactor * 175)
    local swing = math.floor(bfactor * pulse * 70)

    surface.SetDrawColor(0, 0, 0, math.Clamp(base + swing, 0, 245))
    surface.DrawRect(0, 0, sw, sh)
end)

hook.Add("CreateMove", "NPCKAerosolGasThrow_Paralysis", function(cmd)
    if LimaAnimIsActive() or cl_wakeupDone then return end

    local elapsed = GetKAerosolElapsed()
    if elapsed < 0 then return end
    if not IsFullyParalyzed(elapsed) then return end

    cmd:ClearButtons()
    cmd:SetForwardSpeed(0)
    cmd:SetSideSpeed(0)
    cmd:SetUpSpeed(0)
end)

hook.Add("PostRender", "NPCKAerosolGasThrow_Reset", function()
    if cl_effectEnd > 0 and cl_effectEnd <= CurTime() then
        render.SetColorModulation(1, 1, 1)
        cl_effectStart = 0
        cl_effectEnd = 0
    end
end)
