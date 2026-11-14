-- CouchLights: a pixel bridge from WoW to the room lights (govee-wow on the PC).
--
-- WoW Forever restricts the combat log for addons, and the combat log FILE is written in
-- bursts (1-3 s late). So the game state is drawn as 8 tiny solid-color cells (8x8 screen
-- pixels each) in the very top-left corner; govee-wow reads them from the screen capture
-- ~20 times a second. Each cell carries 3 bits: red = 1, green = 2, blue = 4.
--
--   cell 0  marker (magenta)            cell 4  event code (see EV)
--   cell 1  combat | boss | dead        cell 5  event detail (0-7)
--   cell 2  mounted | resting | instance cell 6  event counter (0-7, new event = changed)
--   cell 3  health 0-7 (7 = full)       cell 7  end marker (cyan)
--
-- /lights        status          /lights off|on     hide/show the strip (lights go calm)

local CELL_PX, CELLS = 8, 8
local EV = { cast = 1, kill = 2, hurt = 3, heal = 4, levelup = 5, reward = 6, target = 7 }
local BIG = {   -- big cooldowns: detail 1 = power-up show
    ["Bestial Wrath"] = true, ["Trueshot"] = true, ["Coordinated Assault"] = true,
    ["Aspect of the Wild"] = true, ["Call of the Wild"] = true, ["Rapid Fire"] = true,
    ["Bloodlust"] = true, ["Heroism"] = true, ["Primal Rage"] = true, ["Time Warp"] = true,
}
local IGNORE = { [75] = true }  -- Auto Shot: fires every 2-3 s by itself, not a "move"

local strip = CreateFrame("Frame", "CouchLightsStrip", WorldFrame)
strip:SetFrameStrata("TOOLTIP")
strip:SetFrameLevel(9999)
strip:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
local cells = {}
for i = 0, CELLS - 1 do
    local t = strip:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0, 0, 0, 1)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    cells[i] = t
end

local function layout()
    -- exact physical pixels whatever the UI scale: 1 px = (768 / screen height) UI units
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH <= 0 then return end
    local unit = (768 / physH) / strip:GetEffectiveScale()
    local s = CELL_PX * unit
    strip:SetSize(s * CELLS, s)
    for i = 0, CELLS - 1 do
        cells[i]:ClearAllPoints()
        cells[i]:SetPoint("TOPLEFT", strip, "TOPLEFT", i * s, 0)
        cells[i]:SetSize(s, s)
    end
end

local function put(i, v)
    cells[i]:SetColorTexture(bit.band(v, 1) > 0 and 1 or 0, bit.band(v, 2) > 0 and 1 or 0,
                             bit.band(v, 4) > 0 and 1 or 0, 1)
end

local function secret(v) return issecretvalue and issecretvalue(v) end

local function healthFrac()
    local ok, frac = pcall(function()
        local h, m = UnitHealth("player"), UnitHealthMax("player")
        if secret(h) or secret(m) or not m or m <= 0 then return nil end
        return h / m
    end)
    return ok and frac or nil
end

local function flag(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or secret(v) then return false end
    return v and true or false
end

-- ---- state -------------------------------------------------------------------------------
local inCombat, inBoss, queue, seq, showing, showUntil = false, false, {}, 0, nil, 0
local lastHP, targetGUID, targetDead = nil, nil, false

local function emit(code, detail)
    if #queue >= 6 then            -- under a flood keep the important ones, drop plain casts
        for i = #queue, 1, -1 do
            if queue[i][1] == EV.cast and queue[i][2] == 0 then table.remove(queue, i); break end
        end
        if #queue >= 6 then table.remove(queue, 1) end
    end
    table.insert(queue, { code, detail or 0 })
end

local function stateBits()
    local dead = flag(UnitIsDeadOrGhost, "player")
    local a = (inCombat and 1 or 0) + (inBoss and 2 or 0) + (dead and 4 or 0)
    local inst = flag(IsInInstance)
    local b = (flag(IsMounted) and 1 or 0) + (flag(IsResting) and 2 or 0) + (inst and 4 or 0)
    local hp = healthFrac()
    return a, b, hp and math.min(7, math.floor(hp * 8)) or 7, hp
end

local elapsed = 0
strip:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.033 then return end
    elapsed = 0
    local now = GetTime()
    local a, b, hpBucket, hp = stateBits()

    -- health swings: big hits taken / big heals
    if hp and lastHP then
        local d = hp - lastHP
        if d <= -0.06 then emit(EV.hurt, math.min(7, math.floor(-d * 20)))
        elseif d >= 0.08 and inCombat then emit(EV.heal, math.min(7, math.floor(d * 20))) end
    end
    lastHP = hp

    -- kills: the hostile target we were fighting just died
    local guid = UnitGUID("target")
    if secret(guid) then guid = nil end
    local dead = guid and flag(UnitIsDead, "target") and flag(UnitCanAttack, "player", "target")
    if guid and guid == targetGUID and dead and not targetDead then emit(EV.kill) end
    targetGUID, targetDead = guid, dead

    -- hold each event >= 0.12 s so the 20 fps capture can't miss it
    if now >= showUntil then
        showing = table.remove(queue, 1)
        if showing then
            seq = (seq + 1) % 8
            showUntil = now + 0.12
        else
            showUntil = 0
        end
    end
    put(1, a); put(2, b); put(3, hpBucket)
    put(4, showing and showing[1] or 0)
    put(5, showing and showing[2] or 0)
    put(6, seq)
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("ACHIEVEMENT_EARNED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        CouchLightsDB = CouchLightsDB or {}
        put(0, 5); put(7, 6)                      -- magenta start, cyan end
        layout()
        strip:SetShown(CouchLightsDB.off ~= true)
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        layout()
    elseif event == "PLAYER_REGEN_DISABLED" then inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false
    elseif event == "ENCOUNTER_START" then inBoss = true
    elseif event == "ENCOUNTER_END" then
        inBoss = false
        local success = select(5, ...)
        if success == 1 or success == true then emit(EV.reward, 7) end
    elseif event == "PLAYER_LEVEL_UP" then emit(EV.levelup)
    elseif event == "QUEST_TURNED_IN" then emit(EV.reward, 0)
    elseif event == "ACHIEVEMENT_EARNED" then emit(EV.reward, 1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        if flag(UnitCanAttack, "player", "target") and not flag(UnitIsDead, "target") then
            emit(EV.target)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if secret(spellID) or IGNORE[spellID] then return end
        local name
        pcall(function() name = C_Spell.GetSpellName(spellID) end)
        if secret(name) then name = nil end
        emit(EV.cast, (name and BIG[name]) and 1 or 0)
    end
end)

SLASH_COUCHLIGHTS1 = "/lights"
SlashCmdList.COUCHLIGHTS = function(input)
    local arg = strtrim(input or ""):lower()
    if arg == "off" then CouchLightsDB.off = true; strip:Hide()
    elseif arg == "on" then CouchLightsDB.off = false; strip:Show(); layout() end
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4fd8CouchLights|r room-light bridge " ..
        (strip:IsShown() and "ON (8 px strip, top-left corner)" or "OFF") .. "  - /lights on|off")
end
