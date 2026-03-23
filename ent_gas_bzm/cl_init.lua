include("shared.lua")

local SHADOW_MODELS = { "models/combine_soldier.mdl", "models/combine_super_soldier.mdl", "models/police.mdl" }

-- ============================================================
-- Entity Visuals
-- ============================================================

function ENT:Draw()
    self:DrawModel()
end

-- ============================================================
-- Network Receivers and Screen Effect Hooks
-- ============================================================

local cl_highEnd, cl_exposeStart = 0, 0
local Hallucinations = {}
local TraumaLoop, ChaosVoice = nil, nil
local LastViewAngles = Angle(0, 0, 0)

net.Receive("NPCBZMGas_ApplyHigh", function()
    cl_highEnd = net.ReadFloat()
    cl_exposeStart = net.ReadFloat()
end)

net.Receive("NPCBZMGas_CloudEffect", function()
    local pos = net.ReadVector()
    local radius = net.ReadFloat()
    local emitter = ParticleEmitter(pos)
    
    if not emitter then return end
    
    for i = 1, 15 do
        local p = emitter:Add("particle/particle_smokegrenade", pos + VectorRand() * 40)
        if p then
            p:SetDieTime(math.Rand(10, 15))
            p:SetStartAlpha(80)
            p:SetEndAlpha(0)
            p:SetStartSize(100)
            p:SetEndSize(radius)
            p:SetColor(210, 220, 210)
        end
    end
    emitter:Finish()
end)

local function GetFactor()
    -- Sync with potential late-joins or clears
    if cl_highEnd == 0 then
        local ply = LocalPlayer()
        if not IsValid(ply) then return 0 end
        cl_highEnd = ply:GetNWFloat("npc_bzm_high_end", 0)
        cl_exposeStart = ply:GetNWFloat("npc_bzm_expose_start", 0)
    end

    if cl_highEnd <= CurTime() then return 0 end
    return math.Clamp((CurTime() - cl_exposeStart) / 18, 0, 1)
end

hook.Add("Think", "NPCBZMGas_MainThink", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local f = GetFactor()
    
    if f <= 0 then
        if TraumaLoop then TraumaLoop:Stop(); TraumaLoop = nil end
        if ChaosVoice then ChaosVoice:Stop(); ChaosVoice = nil end
        for _, v in pairs(Hallucinations) do 
            if IsValid(v.ent) then v.ent:Remove() end 
        end
        Hallucinations = {}
        return
    end

    -- 1. GANZ TRAUMA LOOP
    if not TraumaLoop then
        TraumaLoop = CreateSound(ply, "ambient/machines/wall_ambient_loop1.wav")
        TraumaLoop:PlayEx(0.1, 100)
    end
    TraumaLoop:ChangeVolume(f * 0.8, 0.1)
    TraumaLoop:ChangePitch(90 + (f * 30), 0.1)
    if not TraumaLoop:IsPlaying() then TraumaLoop:Play() end

    -- 2. CHAOS VOICE
    if f > 0.6 then
        if not ChaosVoice then
            ChaosVoice = CreateSound(ply, "ambient/levels/citadel/citadel_ambient_loop1.wav")
            ChaosVoice:PlayEx(0.1, 80)
        end
        ChaosVoice:ChangeVolume(f * 0.5, 0.2)
        ChaosVoice:ChangePitch(60 + (math.sin(CurTime() * 1.5) * 20), 0.1)
    end

    -- 3. GHOSTS
    if f > 0.7 and #Hallucinations < 7 and math.random() < 0.05 then
        local pos = ply:GetPos() + ply:GetForward() * 450 + ply:GetRight() * math.random(-400, 400)
        local mdl = ClientsideModel(SHADOW_MODELS[math.random(#SHADOW_MODELS)])
        if IsValid(mdl) then
            mdl:SetPos(pos)
            mdl:SetRenderMode(RENDERMODE_TRANSCOLOR)
            mdl:SetColor(Color(0,0,0,230))
            mdl:SetMaterial("models/debug/debugwhite")
            table.insert(Hallucinations, {ent = mdl, time = CurTime()})
        end
    end
    
    for i = #Hallucinations, 1, -1 do
        if CurTime() > Hallucinations[i].time + 3.2 then 
            Hallucinations[i].ent:Remove()
            table.remove(Hallucinations, i) 
        end
    end
end)

-- 4. TOTAL INVERSION (Movement + Mouse)
hook.Add("CreateMove", "NPCBZMGas_TotalInvert", function(cmd)
    if cl_highEnd <= CurTime() then
        LastViewAngles = cmd:GetViewAngles()
        return
    end

    -- Inverse WASD
    cmd:SetForwardMove(-cmd:GetForwardMove())
    cmd:SetSideMove(-cmd:GetSideMove())

    -- Inverse Mouse (Pitch and Yaw)
    local curAngles = cmd:GetViewAngles()
    local diff = curAngles - LastViewAngles

    -- Normalize the angle difference
    diff.p = math.NormalizeAngle(diff.p)
    diff.y = math.NormalizeAngle(diff.y)

    -- Apply the negative delta
    local newAngles = LastViewAngles - diff
    newAngles.p = math.Clamp(newAngles.p, -89, 89)
    newAngles.y = math.NormalizeAngle(newAngles.y)

    cmd:SetViewAngles(newAngles)
    LastViewAngles = newAngles
end)

-- 5. FOV & SWAY
hook.Add("CalcView", "NPCBZMGas_Drift", function(pl, origin, angles, fov)
    local f = GetFactor()
    if f <= 0 then return end
    
    local t = CurTime()
    local roll = math.sin(t * 0.4) * 7 * f
    local pitch = math.cos(t * 0.6 + 1.1) * 3 * f
    local waveA = math.sin(t * 0.13 * math.pi * 2) * 16
    local waveB = math.sin(t * 0.31 * math.pi * 2 + 1.3) * 10
    local fovDelta = ((waveA + waveB) / 26) * 24 * f
    
    return { 
        origin = origin, 
        angles = Angle(angles.p + pitch, angles.y, angles.r + roll), 
        fov = fov + fovDelta 
    }
end)

-- 6. SCREEN EFFECTS
hook.Add("RenderScreenspaceEffects", "NPCBZMGas_Visuals", function()
    local f = GetFactor()
    if f <= 0 then return end
    
    DrawColorModify({ 
        ["$pp_colour_brightness"] = -0.3 * f, 
        ["$pp_colour_contrast"] = 1 + (0.8 * f), 
        ["$pp_colour_colour"] = 1 - f 
    })
    DrawMotionBlur(0.1, 0.8 * f, 0.01)
end)

hook.Add("PostRender", "NPCBZMGasThrow_Reset", function()
    if cl_highEnd > 0 and cl_highEnd <= CurTime() then
        cl_highEnd = 0
        cl_exposeStart = 0
    end
end)
