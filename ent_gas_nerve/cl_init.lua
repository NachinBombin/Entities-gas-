include("shared.lua")

function ENT:Draw()
    self:DrawModel()
end

-- ============================================================
-- Screen Effects
-- ============================================================

local GAS_HIGH_TRANSITION = 6
local GAS_HIGH_INTENSITY = 1

local cl_highStart = 0
local cl_highEnd = 0

net.Receive("NPCNerveGas_ApplyHigh", function()
    cl_highStart = net.ReadFloat()
    cl_highEnd = net.ReadFloat()
end)

local function DoNerveGasHigh()
    local pl = LocalPlayer()
    if not IsValid(pl) then return end

    local now = CurTime()

    local highStart = cl_highStart
    local highEnd = cl_highEnd

    if highStart == 0 then
        highStart = pl:GetNWFloat("npc_nervegas_high_start", 0)
        highEnd = pl:GetNWFloat("npc_nervegas_high_end", 0)
    end

    if highStart == 0 or highEnd <= now then return end

    local blurFactor = 0

    if highStart + GAS_HIGH_TRANSITION > now then
        local s = highStart
        local e = s + GAS_HIGH_TRANSITION
        blurFactor = ((now - s) / (e - s)) * GAS_HIGH_INTENSITY

    elseif highEnd - GAS_HIGH_TRANSITION < now then
        local e = highEnd
        local s = e - GAS_HIGH_TRANSITION
        blurFactor = (1 - (now - s) / (e - s)) * GAS_HIGH_INTENSITY

    else
        blurFactor = GAS_HIGH_INTENSITY
    end

    blurFactor = math.Clamp(blurFactor, 0, 1)

    DrawMotionBlur(0.03, blurFactor, 0)

    if blurFactor > 0 then
        render.SetColorModulation(
            0.6 + (1 - blurFactor) * 0.4,
            1,
            0.6 + (1 - blurFactor) * 0.4
        )
    end
end

hook.Add("RenderScreenspaceEffects", "NPCNerveGasThrow_High", DoNerveGasHigh)

hook.Add("PostRender", "NPCNerveGasThrow_HighReset", function()
    if cl_highEnd > 0 and cl_highEnd <= CurTime() then
        render.SetColorModulation(1, 1, 1)
        cl_highStart = 0
        cl_highEnd = 0
    end
end)
