-- yslemEgg v5.0 ULTRA | Steal An Egg automation suite
-- Rebuilt with verified remote paths / formulas from deep reference analysis.
-- Excludes: telemetry/webhook exfiltration, remote kill-switches, RPC/RCE backdoors,
-- anti-cheat-hook-disabling ("getconnections" hijacking) -- none of that is reproduced here.

print("[yslemEgg] boot: script started executing")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "yslemEgg", Text = "Script started, loading...", Duration = 3,
    })
end)

-- Everything below runs inside one big pcall. If ANYTHING anywhere in this
-- script throws an uncaught error, we catch it here and both print it AND
-- draw it directly on screen as a big red box -- so a crash is never
-- silent, even on an executor whose console isn't visible/checked.
local __yslemEgg_ok, __yslemEgg_err = pcall(function()

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser       = game:GetService("VirtualUser")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")
local hum  = char:WaitForChild("Humanoid")

--============================================================
-- TASK LIFECYCLE
--============================================================
local _activeTasks = {}
local function _spawnTracked(fn)
    local t = task.spawn(fn)
    table.insert(_activeTasks, t)
    return t
end
local function _killAll()
    for _, t in ipairs(_activeTasks) do pcall(task.cancel, t) end
    _activeTasks = {}
end

--============================================================
-- GAME MODULE / REMOTE ACCESS
--============================================================
local Networking = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("Networking")
    or ReplicatedStorage:FindFirstChild("Networking")

local function _remote(path)
    if not Networking then return nil end
    return Networking:FindFirstChild(path)
end
local function _fire(path, ...)
    local r = _remote(path)
    if r and r:IsA("RemoteEvent") then
        return pcall(function(...) r:FireServer(...) end, ...)
    end
    return false
end
local function _invoke(path, ...)
    local r = _remote(path)
    if r and r:IsA("RemoteFunction") then
        local packed = table.pack(pcall(function(...) return r:InvokeServer(...) end, ...))
        if packed[1] then
            -- packed = {true, result1, result2, ...} -> return result1, result2, ...
            return table.unpack(packed, 2, packed.n)
        end
    end
    return nil
end

local function _tryRequire(path)
    local obj = ReplicatedStorage
    for _, seg in ipairs(path) do
        obj = obj and obj:FindFirstChild(seg)
    end
    if not obj then return nil end
    local ok, mod = pcall(require, obj)
    if ok then return mod end
    return nil
end

local Assets     = _tryRequire({"Data", "Assets"})
local Mutations  = _tryRequire({"Shared", "Modules", "Mutations"})
local EggState   = _tryRequire({"Client", "EggState"})
local EggRecords = _tryRequire({"Shared", "Util", "EggRecords"})
local SaveModule = _tryRequire({"Shared", "Save"})
local RagdollMod = _tryRequire({"Shared", "Modules", "Ragdoll"})

--============================================================
-- INCOME / RARITY FORMULA (verified exact constants)
--============================================================
local SCALE_BREAKPOINT   = 5
local SCALE_EXP_LOW      = 1.85
local SCALE_EXP_HIGH     = 1.2
local SCALE_HIGH_CONST   = 19.637875755794113 -- == 5^1.85, keeps the curve continuous at scale 5

local function _scaleFactor(scale)
    scale = tonumber(scale) or 0
    if scale <= 0 then return 0 end
    if scale > SCALE_BREAKPOINT then
        return (scale / SCALE_BREAKPOINT) ^ SCALE_EXP_HIGH * SCALE_HIGH_CONST
    end
    return scale ^ SCALE_EXP_LOW
end

local function _mutationMult(mutations)
    if Mutations and Mutations.EarningsFor then
        local ok, v = pcall(Mutations.EarningsFor, mutations or {})
        if ok and type(v) == "number" then return v end
    end
    return 1
end

local FALLBACK_RARITIES = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
local FALLBACK_AREAS = {"Forest","Desert","Snow","Lake","Jungle","Volcano","Prehistoric","Cosmic","Abyss Ocean","Cherry Blossom","Light Dark","Titan Temple"}

local function _assetInfo(category)
    local info = { EarningRate = 0, RarityNumber = 0, RarityName = "Common", Color = nil, Icon = nil }
    if Assets and Assets.Directory and category and Assets.Directory[category] then
        local a = Assets.Directory[category]
        local rarity = a.Rarity or {}
        info.EarningRate = a.EarningRate or 0
        info.RarityNumber = rarity.RarityNumber or rarity.Rank or 0
        info.RarityName = rarity.DisplayName or rarity._id or "Common"
        info.Color = rarity.Color
        info.Icon = a.Icon or (a.Egg and a.Egg.Icon)
    end
    return info
end

local function _income(category, scale, mutations)
    local info = _assetInfo(category)
    return math.max(0, (info.EarningRate or 0) * _scaleFactor(scale) * _mutationMult(mutations))
end

local function _rarityIndex(name)
    if not name then return 1 end
    for i, r in ipairs(FALLBACK_RARITIES) do
        if r:lower() == tostring(name):lower() then return i end
    end
    return 1
end

--============================================================
-- SETTINGS (auto-saved to executor storage)
--============================================================
local SAVE_FILE = "yslemEgg_v5_settings.json"
local DEFAULT_SETTINGS = {
    -- Auto Steal
    autoSteal          = false,
    minRarity          = "Common",
    minStealValue      = 0,
    targetAreas        = {},          -- empty = all areas
    stealPriority      = "Highest Value", -- Best Rarity / Biggest Weight / Best Mutation / Highest Value / Lowest Value
    instantSteal       = false,
    waitGuardSleep     = true,
    antiGuardEnabled   = true,
    -- Auto Place Egg
    autoPlace          = false,
    placeRule          = "After Steal",   -- Always / Steal Idle / After Steal / Night Only
    placeOrder         = "Highest Value", -- Highest Value / Smallest Size / Biggest Size
    minPlaceValue      = 0,
    -- Auto Treadmill
    autoTreadmill      = false,
    stayOnTreadmill    = true,
    -- Auto Hatch
    autoHatch          = false,
    hatchMinRarity     = "Common",
    minHatchValue      = 0,
    -- Auto Equip
    autoEquipBest      = false,
    -- Auto Sell
    autoSellPet        = false,
    sellPetRule        = "Rarity Only", -- Rarity Only / Value Only / Rarity And Value / Rarity Or Value
    petMaxRarity       = "Rare",
    minPetSellValue    = 0,
    keepMutatedPets    = true,
    autoSellEgg        = false,
    sellEggRule        = "Rarity Only",
    eggMaxRarity       = "Rare",
    minEggSellValue    = 0,
    keepMutatedEggs    = true,
    -- Auto Fuse
    autoFuse           = false,
    fusePriorityMode   = "Lowest Rarity First", -- .. / Highest Rarity First / Most Copies First / Lowest Value First
    maxRarityToFuse    = "Mythic",
    skipMutatedFuse    = true,
    ejectIncomplete    = true,
    -- Auto Favorite
    autoFavoritePet    = false,
    favoriteRule       = "Match All", -- Match Any / Match All
    favoriteMinRarity  = "Legendary",
    minFavoriteValue   = 0,
    -- Player: Movement
    speedBoost         = false,
    boostSpeed         = 350,
    infiniteJump       = false,
    -- Player: Character
    invisibility       = false,
    antiRagdoll        = true,
    antiTrap           = true,
    instantPrompts     = true,
    godMode            = false,
    -- Player: Combat
    hitMode            = "Off", -- Off / Nearest / Egg Holders / Specific Player / Aura
    hitPlayerName      = "",
    hitLead            = -0.275,
    hitSweep           = 0.6,
    -- Misc
    fpsCap             = 0, -- 0 = uncapped
    antiAFK            = true,
    -- Webhook (user-supplied, opt-in; never a hardcoded/author URL)
    webhookUrl         = "",
    notifyStolenEggs   = false,
    -- General
    notifications      = true,
    showStats          = true,
}

local S = {}
do
    local ok, raw = pcall(readfile, SAVE_FILE)
    if ok and raw and raw ~= "" then
        local ok2, parsed = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(parsed) == "table" then
            for k, v in pairs(DEFAULT_SETTINGS) do
                -- NOT `(parsed[k] ~= nil) and parsed[k] or v` -- that and/or
                -- idiom collapses to `v` whenever parsed[k] is boolean
                -- false, silently reverting any disabled true-by-default
                -- toggle (waitGuardSleep, antiRagdoll, antiTrap, ...) back
                -- on every reload.
                if parsed[k] ~= nil then
                    S[k] = parsed[k]
                else
                    S[k] = v
                end
            end
        end
    end
    for k, v in pairs(DEFAULT_SETTINGS) do
        if S[k] == nil then S[k] = v end
    end
end
local function _saveSettings()
    pcall(writefile, SAVE_FILE, HttpService:JSONEncode(S))
end

--============================================================
-- NOTIFY
--============================================================
local _lastNotify = 0
local function _notify(title, msg, dur)
    if not S.notifications then return end
    local now = tick()
    if now - _lastNotify < 0.25 then return end
    _lastNotify = now
    print(("[%s] %s"):format(title, msg))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = msg, Duration = dur or 4,
        })
    end)
end

local function _webhookSend(content)
    if not S.notifyStolenEggs or S.webhookUrl == "" then return end
    if not (S.webhookUrl:match("^https://discord%.com/api/webhooks/") or S.webhookUrl:match("^https://discordapp%.com/api/webhooks/")) then
        return
    end
    pcall(function()
        local body = HttpService:JSONEncode({ content = content })
        if syn and syn.request then
            syn.request({ Url = S.webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = body })
        elseif http_request then
            http_request({ Url = S.webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = body })
        elseif request then
            request({ Url = S.webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = body })
        end
    end)
end

--============================================================
-- WORLD HELPERS (SeparationLine / home / night / walls)
--============================================================
local function _worldRoot()
    return workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
end
local function _separationLineX()
    local world = _worldRoot()
    local areas = world and world:FindFirstChild("Areas")
    local line = areas and areas:FindFirstChild("SeparationLine")
    return (line and line:IsA("BasePart")) and line.Position.X or 552
end
local function _insideBase(pos)
    pos = pos or (hrp and hrp.Position)
    return pos ~= nil and pos.X < _separationLineX()
end

local HOME_LANDMARKS = {
    { path = {"GearGiver_Slap", "Podium"}, offset = Vector3.new(-16.415, 21.072, -6.106) },
    { path = {"World", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003"}, offset = Vector3.new(-26.776, 1.75, 18.665) },
    { path = {"__OBJECTS", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003"}, offset = Vector3.new(-26.776, 1.75, 18.665) },
}
local function _stealHome()
    for _, lm in ipairs(HOME_LANDMARKS) do
        local obj = workspace
        for _, seg in ipairs(lm.path) do
            obj = obj and obj:FindFirstChild(seg)
        end
        if obj and obj:IsA("BasePart") then
            local ok, pos = pcall(function() return obj.CFrame:PointToWorldSpace(lm.offset) end)
            if ok then return pos end
        end
    end
    return Vector3.new(528.7, 70.57, -364.11)
end

local AreaEggCycle = _tryRequire({"Shared", "Util", "AreaEggCycle"})
local function _isNight()
    if AreaEggCycle and AreaEggCycle.IsNightPhase then
        local ok, v = pcall(AreaEggCycle.IsNightPhase, workspace:GetServerTimeNow())
        if ok then return v end
    end
    return false
end

--============================================================
-- MOVEMENT PRIMITIVES
--============================================================
local Movement = { Owner = nil }
local function _claimMovement(owner)
    if Movement.Owner == nil or Movement.Owner == owner then
        Movement.Owner = owner
        return true
    end
    -- steal pre-empts treadmill/place, combat/invis yield to steal
    if Movement.Owner == "treadmill" then Movement.Owner = owner; return true end
    return false
end
local function _releaseMovement(owner)
    if Movement.Owner == owner then Movement.Owner = nil end
end

local function _walkTo(pos, tolerance, timeout)
    tolerance = tolerance or 6
    timeout = timeout or 10
    local start = tick()
    local lastPos, stuckAccum = nil, 0
    while tick() - start < timeout do
        char = lp.Character
        hum = char and char:FindFirstChildOfClass("Humanoid")
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return false end
        if (hrp.Position - pos).Magnitude <= tolerance then return true end
        hum:MoveTo(pos)
        if lastPos and (hrp.Position - lastPos).Magnitude < 1 then
            stuckAccum += 0.2
            if stuckAccum > 0.8 then
                hum.Jump = true
                stuckAccum = 0
            end
        else
            stuckAccum = 0
        end
        lastPos = hrp.Position
        task.wait(0.2)
    end
    return false
end

-- CFrame-based 3-leg flight (used for placing eggs / boarding treadmill / predictor fly-to)
local function _flyLeg(targetPos, speed, cancelFn)
    speed = speed or 400
    char = lp.Character
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local dist = (targetPos - hrp.Position).Magnitude
    local timeout = dist / math.max(speed, 1) + 3
    local start = tick()
    local pos = hrp.Position
    local ok = true
    while true do
        if cancelFn and cancelFn() then ok = false; break end
        char = lp.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then ok = false; break end
        if tick() - start > timeout then ok = false; break end
        local dt = RunService.Heartbeat:Wait()
        local remaining = targetPos - pos
        local remMag = remaining.Magnitude
        local step = speed * dt
        if remMag <= math.max(step, 0.05) then
            pos = targetPos
        else
            pos = pos + remaining.Unit * step
        end
        local flat = Vector3.new(remaining.X, 0, remaining.Z)
        local look = flat.Magnitude > 0.05 and CFrame.lookAt(pos, pos + flat) or hrp.CFrame
        hrp.CFrame = CFrame.new(pos) * (look - look.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if remMag <= 0.05 then break end
    end
    return ok
end

local function _flyTo(targetPos, cancelFn, speed)
    char = lp.Character
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local startY = hrp.Position.Y
    local cruiseY = math.max(startY, targetPos.Y + 3) + 30
    local flatTarget = Vector3.new(targetPos.X, cruiseY, targetPos.Z)
    local ok = _flyLeg(Vector3.new(hrp.Position.X, cruiseY, hrp.Position.Z), speed, cancelFn)
    if not ok then return false end
    ok = _flyLeg(flatTarget, speed, cancelFn)
    if not ok then return false end
    return _flyLeg(targetPos, speed, cancelFn)
end

--============================================================
-- FIELD EGG SNAPSHOT (reads live game state; falls back to remote)
--============================================================
local _lastSnapshotTime = 0
local _cachedRecords = {}

local function _readFieldEggs()
    if EggState and EggState.ReadFieldEggs then
        local ok, result = pcall(EggState.ReadFieldEggs)
        if ok and result and result.Records then return result.Records end
    end
    local now = tick()
    if now - _lastSnapshotTime < 1 then return _cachedRecords end
    _lastSnapshotTime = now
    local result = _invoke("RF/EggWorld/AskFieldEggSnapshot")
    if result and result.Records then
        _cachedRecords = result.Records
        return result.Records
    end
    return _cachedRecords
end

-- Builds a scored/sorted candidate list of stealable field eggs.
local _blacklist = {}      -- uid -> true (skip)
local _retryCooldown = {}  -- uid -> tick() when retryable again

local function _buildStealCandidates()
    local records = _readFieldEggs()
    local list = {}
    local now = tick()
    for uid, rec in pairs(records) do
        if type(rec) == "table" and rec.Uid == nil then rec.Uid = uid end
        local state = rec.State
        local grabbable = (state == "Slot" or state == "Dropped" or state == "Carried")
        if grabbable and not _blacklist[uid] and (not _retryCooldown[uid] or _retryCooldown[uid] <= now) then
            if #S.targetAreas == 0 or (rec.AreaId and table.find(S.targetAreas, rec.AreaId)) then
                local info = _assetInfo(rec.AssetCategory)
                local value = _income(rec.AssetCategory, rec.AssetScale, rec.Mutations)
                local mutMult = _mutationMult(rec.Mutations)
                local weight = 0
                if EggRecords and EggRecords.WeightKgForScale then
                    local ok, w = pcall(EggRecords.WeightKgForScale, rec.AssetCategory, rec.AssetScale)
                    if ok then weight = w or 0 end
                end
                if info.RarityNumber >= _rarityIndex(S.minRarity) - 1 and (S.minStealValue <= 0 or value >= S.minStealValue) then
                    table.insert(list, {
                        Uid = uid, Category = rec.AssetCategory, Scale = rec.AssetScale,
                        AreaId = rec.AreaId, State = state, Mutations = rec.Mutations,
                        BottomCFrame = rec.BottomCFrame,
                        RarityNumber = info.RarityNumber, RarityName = info.RarityName,
                        Value = value, Weight = weight, MutationMult = mutMult,
                    })
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if S.stealPriority == "Biggest Weight" then return a.Weight > b.Weight
        elseif S.stealPriority == "Best Mutation" then return a.MutationMult > b.MutationMult
        elseif S.stealPriority == "Lowest Value" then return a.Value < b.Value
        elseif S.stealPriority == "Best Rarity" then
            if a.RarityNumber ~= b.RarityNumber then return a.RarityNumber > b.RarityNumber end
            return a.Value > b.Value
        else -- Highest Value (default)
            return a.Value > b.Value
        end
    end)
    return list
end

--============================================================
-- STEAL QUEUE API (priority / manual reorder, mirrors the reference's queue semantics)
--============================================================
local StealQueue = {}       -- uid -> {At = order, Once = bool}
local StealActive = false
local StealCarrying = false
local StealCarryUid = nil
local StealLastFinishedAt = 0
local StealStatus = "Idle"

local function _queueList()
    local uids = {}
    for uid in pairs(StealQueue) do table.insert(uids, uid) end
    table.sort(uids, function(a, b)
        if StealQueue[a].At ~= StealQueue[b].At then return StealQueue[a].At < StealQueue[b].At end
        return a < b
    end)
    return uids
end
-- Intentional no-op: the steal loop already polls every 0.2s (see MAIN
-- LOOPS below), so a queue change here is picked up within that window
-- without needing an explicit wake signal.
local function _wakeSteal() end

local function CancelSteal(uid)
    StealQueue[uid] = nil
    _blacklist[uid] = true
    if StealCarryUid == uid then StealActive = false end
    _wakeSteal()
end
local function PrioritizeSteal(uid)
    local minAt = math.huge
    for _, v in pairs(StealQueue) do minAt = math.min(minAt, v.At) end
    if minAt == math.huge then minAt = 0 end
    StealQueue[uid] = { At = minAt - 1, Once = false }
    _blacklist[uid] = nil
    _wakeSteal()
end
local function StealNow(uid, once)
    local maxAt = 0
    for _, v in pairs(StealQueue) do maxAt = math.max(maxAt, v.At) end
    StealQueue[uid] = { At = maxAt + 1, Once = once == true }
    _blacklist[uid] = nil
    _wakeSteal()
end
local function MoveInPlan(uid, delta)
    local list = _queueList()
    local idx = table.find(list, uid)
    if not idx then return end
    local swapIdx = idx + delta
    if swapIdx < 1 or swapIdx > #list then return end
    local a, b = list[idx], list[swapIdx]
    StealQueue[a].At, StealQueue[b].At = StealQueue[b].At, StealQueue[a].At
end
local function StealPlan()
    if not S.autoSteal or _isNight() then return {} end
    local list = _queueList()
    local candidates = _buildStealCandidates()
    for _, c in ipairs(candidates) do
        if not table.find(list, c.Uid) then table.insert(list, c.Uid) end
    end
    return list
end

--============================================================
-- ANTI-GUARD (guard-sleep wait + escape hop when caught mid-carry)
--============================================================
local AntiGuard = { Busy = false, BusySince = 0, HitArmedAt = 0, HitArms = 0 }

local function _guardAreasRoot()
    local world = _worldRoot()
    return world and world:FindFirstChild("Areas") and world.Areas:FindFirstChild("GuardAreas")
end
local function _guardForArea(areaId)
    local areas = _guardAreasRoot()
    local area = areas and areaId and areas:FindFirstChild(areaId)
    return area and area:FindFirstChild("Guard")
end
local function _guardIsSleeping(guard)
    if not guard then return true end
    local ok, state = pcall(function() return guard:GetAttribute("GuardState") end)
    return ok and state == "Sleeping"
end
local function _guardIsSleepingForArea(areaId)
    return _guardIsSleeping(_guardForArea(areaId))
end

-- ride a guard-hit ragdoll window: snap toward the escape point instead of fighting it
local function _antiGuardRideHit(escapePoint)
    if not S.antiGuardEnabled then return end
    AntiGuard.Busy = true
    AntiGuard.BusySince = tick()
    AntiGuard.HitArms += 1
    AntiGuard.HitArmedAt = tick()
    local conn
    conn = lp:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
        char = lp.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and escapePoint then
            hrp.CFrame = CFrame.new(escapePoint)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    task.delay(20, function()
        if conn then conn:Disconnect() end
        AntiGuard.Busy = false
        AntiGuard.HitArms = math.max(0, AntiGuard.HitArms - 1)
    end)
end

--============================================================
-- CARRY / DELIVERY (SafeCarry-lite: human-ish jitter + guard-aware speed floor)
--============================================================
local SafeCarry = {
    LaneOffset = 4, SpeedJitter = 0.08, ReactMin = 0.2, ReactMax = 0.6,
    CarryRatio = 0.9, SpeedRatio = 1.5, GuardMargin = 4, GuardRatio = 1.06, MinRatio = 1.1,
}
local function _react()
    return math.max(0, SafeCarry.ReactMin) + math.random() * (SafeCarry.ReactMax - SafeCarry.ReactMin)
end
local function _carrySpeed(baseSpeed, guardSpeed)
    local jitter = 1 + (math.random() * 2 - 1) * SafeCarry.SpeedJitter
    local wanted = baseSpeed * SafeCarry.CarryRatio * jitter
    local capped = math.min(wanted * SafeCarry.SpeedRatio, wanted * 2)
    if guardSpeed and guardSpeed > 0 then
        local safeAbove = math.max(guardSpeed + SafeCarry.GuardMargin, wanted * SafeCarry.MinRatio)
        capped = math.max(capped, safeAbove)
    end
    return math.max(capped, 16)
end

local function _findGuardHitPrompt(pos, radius)
    radius = radius or 14
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Name == "CarryAreaEgg" then
            local part = obj.Parent
            if part and part:IsA("BasePart") and (part.Position - pos).Magnitude <= radius then
                return obj
            end
        end
    end
    return nil
end

local function _pressStealPrompt(pos)
    local prompt = _findGuardHitPrompt(pos, 14)
    if not prompt then return false end
    if S.instantPrompts then prompt.HoldDuration = 0 end
    local ok = pcall(fireproximityprompt, prompt)
    if ok and prompt.HoldDuration > 0 then task.wait(prompt.HoldDuration + 0.1) end
    return ok
end

--============================================================
-- MAIN STEAL ATTEMPT
--============================================================
local _lastStealAttempt = 0
local STEAL_COOLDOWN = 0.6

local function _deliverEgg(target)
    -- Walk/fly to the field position, grab it, then head home across the SeparationLine.
    char = lp.Character
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not target.BottomCFrame then return false end
    local fieldPos = target.BottomCFrame.Position
    StealStatus = ("Running to the egg, %s"):format(target.Category or "?")

    if not S.instantSteal then
        task.wait(_react())
        _walkTo(fieldPos, 6, 20)
    else
        _flyTo(fieldPos, function() return not S.autoSteal end, 400)
    end

    if not _pressStealPrompt(fieldPos) then
        StealStatus = "That egg would not come free"
        return false
    end

    task.wait(0.3)
    StealCarrying = true
    StealCarryUid = target.Uid

    -- Guard check before heading home
    local guardId = target.AreaId
    if S.waitGuardSleep and not _guardIsSleepingForArea(guardId) then
        StealStatus = "Waiting for the guard to sleep"
        local waited = 0
        while waited < 15 and not _guardIsSleepingForArea(guardId) do
            task.wait(0.5); waited += 0.5
        end
    end

    StealStatus = "Carrying home"
    local home = _stealHome()
    hum = char and char:FindFirstChildOfClass("Humanoid")
    local baseSpeed = hum and hum.WalkSpeed or 16
    local guard = _guardForArea(guardId)
    local guardSpeed = 0
    pcall(function() guardSpeed = guard and guard:GetAttribute("WalkSpeed") or 0 end)
    local speed = _carrySpeed(baseSpeed, guardSpeed)

    if S.instantSteal then
        _flyTo(home + Vector3.new(0, 3, 0), function() return not StealCarrying end, speed * 4)
    else
        if hum then hum.WalkSpeed = speed end
        _walkTo(home, 8, 25)
        if hum then hum.WalkSpeed = baseSpeed end
    end

    StealCarrying = false
    StealCarryUid = nil
    StealLastFinishedAt = tick()
    StealStatus = "Delivered"
    _notify("FARM", ("Stole %s (%s) worth $%.0f"):format(target.Category or "?", target.RarityName or "?", target.Value or 0))
    _webhookSend(("**Egg Stolen!** %s · %s · $%.0f"):format(target.Category or "?", target.RarityName or "?", target.Value or 0))
    return true
end

local function _stealAttempt()
    if StealActive then return end
    local plan = StealPlan()
    if #plan == 0 then StealStatus = "No egg matches"; return end

    local records = _readFieldEggs()
    local target = nil
    for _, uid in ipairs(plan) do
        local rec = records[uid]
        if rec and rec.State ~= "Carried" then
            local info = _assetInfo(rec.AssetCategory)
            target = {
                Uid = uid, Category = rec.AssetCategory, Scale = rec.AssetScale,
                AreaId = rec.AreaId, Mutations = rec.Mutations, BottomCFrame = rec.BottomCFrame,
                RarityName = info.RarityName, Value = _income(rec.AssetCategory, rec.AssetScale, rec.Mutations),
            }
            break
        end
    end
    if not target then StealStatus = "Best egg is carried, waiting for it"; return end

    if not _claimMovement("steal") then StealStatus = "Waiting for " .. tostring(Movement.Owner); return end

    StealActive = true
    local uid = target.Uid
    local ok, delivered = pcall(_deliverEgg, target)
    StealActive = false
    _releaseMovement("steal")

    if not ok or not delivered then
        _retryCooldown[uid] = tick() + 8
        if StealQueue[uid] and StealQueue[uid].Once then StealQueue[uid] = nil end
    else
        StealQueue[uid] = nil
    end
    _lastStealAttempt = tick()
end

--============================================================
-- AUTO PLACE EGG
--============================================================
local _placeGridCache = {}
local _placeFailedThisSession = {}
local PlaceStatus = "Idle"

local function _placementGrid(existing)
    local cells = {}
    for x = -24, 8, 4 do
        for z = 4, 30, 4 do
            local cf = CFrame.new(x, -0.5, z)
            local blocked = false
            for _, e in ipairs(existing) do
                if (e.Position - cf.Position).Magnitude < 5 then blocked = true; break end
            end
            if not blocked then table.insert(cells, cf) end
        end
    end
    -- Fisher-Yates shuffle
    for i = #cells, 2, -1 do
        local j = math.random(i)
        cells[i], cells[j] = cells[j], cells[i]
    end
    return cells
end

local function _penAnchor()
    -- Best-effort: player's own plot sign, else current position
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign", true)
            local nameLbl = sign and sign:FindFirstChild("PlayerName", true)
            if nameLbl and nameLbl:IsA("TextLabel") and nameLbl.Text:lower() == lp.Name:lower() then
                if plot:IsA("Model") then
                    return plot:GetPivot().Position
                elseif plot:IsA("BasePart") then
                    return plot.Position
                end
            end
        end
    end
    char = lp.Character
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or Vector3.zero
end

local function _placeCandidates()
    if not EggState or not EggState.ReadOwnerEggs then return {} end
    local ok, eggs = pcall(EggState.ReadOwnerEggs, lp.UserId)
    if not ok or not eggs then return {} end
    local list = {}
    for uid, egg in pairs(eggs) do
        if not egg.Placement and not _placeFailedThisSession[uid] then
            local info = _assetInfo(egg.AssetCategory)
            local value = _income(egg.AssetCategory, egg.AssetScale, egg.Mutations)
            if S.minPlaceValue <= 0 or value >= S.minPlaceValue then
                table.insert(list, { Uid = uid, Category = egg.AssetCategory, Scale = egg.AssetScale, Value = value })
            end
        end
    end
    table.sort(list, function(a, b)
        if S.placeOrder == "Smallest Size" then return (a.Scale or 0) < (b.Scale or 0)
        elseif S.placeOrder == "Biggest Size" then return (a.Scale or 0) > (b.Scale or 0)
        else return a.Value > b.Value end
    end)
    return list
end

local function _placeRuleOk()
    if S.placeRule == "Steal Idle" then return not StealActive and not StealCarrying
    elseif S.placeRule == "After Steal" then return (tick() - StealLastFinishedAt) <= 12
    elseif S.placeRule == "Night Only" then return _isNight()
    end
    return true -- Always
end

local function _autoPlaceTick()
    if not S.autoPlace or not _placeRuleOk() then return end
    local candidates = _placeCandidates()
    if #candidates == 0 then PlaceStatus = "No eggs to place"; return end
    if not _claimMovement("place") then PlaceStatus = "Waiting for " .. tostring(Movement.Owner); return end

    local anchor = _penAnchor()
    if hrp and (hrp.Position - anchor).Magnitude > 26 then
        PlaceStatus = "Flying to the pen"
        _flyTo(anchor, function() return not S.autoPlace end, 400)
    end

    local existing = _placeGridCache
    for _, egg in ipairs(candidates) do
        local placed = false
        local grid = _placementGrid(existing)
        for attempt = 1, math.min(8, #grid) do
            local cf = grid[attempt]
            local worldCF = CFrame.new(anchor) * cf
            local result = _invoke("RF/EggWorld/AskPlaceEgg", { Uid = egg.Uid, LocalCFrame = cf })
            if result ~= false and result ~= nil then
                table.insert(existing, cf)
                placed = true
                PlaceStatus = "Placed " .. tostring(egg.Category)
                break
            end
            task.wait(0.1)
        end
        if not placed then _placeFailedThisSession[egg.Uid] = true end
        task.wait(0.15)
    end
    _releaseMovement("place")
end

--============================================================
-- AUTO TREADMILL
--============================================================
local Treadmill = { Riding = false }
local function _onBelt()
    -- Heuristic: within a few studs of a part named "TreadmillBottom" on the current plot
    char = lp.Character
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "TreadmillBottom" and obj:IsA("BasePart") then
            if (obj.Position - hrp.Position).Magnitude < 12 then return true end
        end
    end
    return false
end
local function _beltPart()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "TreadmillBottom" and obj:IsA("BasePart") then return obj end
    end
    return nil
end

local function _autoTreadmillTick()
    if not S.autoTreadmill then return end
    if StealActive or StealCarrying or Movement.Owner == "steal" or Movement.Owner == "place" then return end
    if not _claimMovement("treadmill") then return end

    local belt = _beltPart()
    if belt and hrp and (hrp.Position - belt.Position).Magnitude > 10 then
        _flyTo(belt.Position + Vector3.new(0, 2, 0), function() return not S.autoTreadmill end, 400)
    end
    local ok, result, err = pcall(_invoke, "RF/Treadmill/AskWearStill")
    if ok and (result == true or err == "Already using treadmill") then
        Treadmill.Riding = true
    end
    _releaseMovement("treadmill")
end

--============================================================
-- AUTO HATCH
--============================================================
local _hatchFailedCooldown = {}
local function _autoHatchTick()
    if not S.autoHatch then return end
    if not EggState or not EggState.ReadOwnerEggs or not EggState.IsReadyToHatch then return end
    local ok, eggs = pcall(EggState.ReadOwnerEggs, lp.UserId)
    if not ok or not eggs then return end
    local now = tick()
    local done = 0
    for uid, egg in pairs(eggs) do
        if done >= 4 then break end
        if egg.Placement and (not _hatchFailedCooldown[uid] or _hatchFailedCooldown[uid] <= now) then
            local readyOk, ready = pcall(EggState.IsReadyToHatch, uid)
            if readyOk and ready then
                local info = _assetInfo(egg.AssetCategory)
                local value = _income(egg.AssetCategory, egg.AssetScale, egg.Mutations)
                if info.RarityNumber >= _rarityIndex(S.hatchMinRarity) - 1 and (S.minHatchValue <= 0 or value >= S.minHatchValue) then
                    local r1 = _invoke("RF/EggWorld/AskHatch", uid)
                    if r1 ~= false then
                        task.wait(0.35)
                        _invoke("RF/EggWorld/AskFinishHatch", uid)
                    else
                        _hatchFailedCooldown[uid] = now + 10
                    end
                    done += 1
                    task.wait(0.2)
                end
            end
        end
    end
end

--============================================================
-- AUTO EQUIP BEST
--============================================================
local _lastEquipBest = 0
local function _autoEquipBestTick()
    if not S.autoEquipBest then return end
    if tick() - _lastEquipBest < 5 then return end
    _lastEquipBest = tick()
    local ready = _invoke("RF/Haul/FetchWearBestStatus")
    if ready == false then return end
    _invoke("RF/Haul/WearBest")
end

--============================================================
-- AUTO SELL (Pet + Egg)
--============================================================
local function _passesRule(rule, rarityOk, valueOk)
    if rule == "Rarity And Value" then return rarityOk and valueOk
    elseif rule == "Rarity Or Value" then return rarityOk or valueOk
    elseif rule == "Value Only" then return valueOk
    else return rarityOk end -- Rarity Only
end

local function _saveData()
    if SaveModule and SaveModule.Get then
        local ok, data = pcall(SaveModule.Get)
        if ok then return data end
    end
    return nil
end

local _lastSell = 0
local function _autoSellTick()
    if not (S.autoSellPet or S.autoSellEgg) then return end
    if tick() - _lastSell < 3 then return end
    local save = _saveData()
    if not save then return end

    local petUids, eggUids = {}, {}
    if S.autoSellPet and save.Inventory then
        local maxRarity = _rarityIndex(S.petMaxRarity) - 1
        for uid, item in pairs(save.Inventory) do
            -- Luau has no goto/labels; use a skip flag instead.
            local skip = item.InFuse or (S.keepMutatedPets and item.Mutations and next(item.Mutations) ~= nil)
            if not skip then
                local info = _assetInfo(item.Category)
                local value = _income(item.Category, item.Scale, item.Mutations)
                local rarityOk = info.RarityNumber <= maxRarity
                local valueOk = S.minPetSellValue > 0 and value < S.minPetSellValue
                if _passesRule(S.sellPetRule, rarityOk, valueOk) then table.insert(petUids, uid) end
            end
        end
    end
    if S.autoSellEgg and save.EggInventory then
        local maxRarity = _rarityIndex(S.eggMaxRarity) - 1
        for uid, item in pairs(save.EggInventory) do
            local skip = S.keepMutatedEggs and item.Mutations and next(item.Mutations) ~= nil
            if not skip then
                local info = _assetInfo(item.AssetCategory)
                local value = _income(item.AssetCategory, item.AssetScale, item.Mutations)
                local rarityOk = info.RarityNumber <= maxRarity
                local valueOk = S.minEggSellValue > 0 and value < S.minEggSellValue
                if _passesRule(S.sellEggRule, rarityOk, valueOk) then table.insert(eggUids, uid) end
            end
        end
    end

    if #petUids == 0 and #eggUids == 0 then return end
    _lastSell = tick()
    local i = 1
    while i <= math.max(#petUids, #eggUids) do
        local petSlice, eggSlice = {}, {}
        for k = i, math.min(i + 49, #petUids) do table.insert(petSlice, petUids[k]) end
        for k = i, math.min(i + 49, #eggUids) do table.insert(eggSlice, eggUids[k]) end
        _fire("RE/PetSatchel/SellSelection", { Assets = petSlice, Eggs = eggSlice })
        i += 50
        if i <= math.max(#petUids, #eggUids) then task.wait(0.3) end
    end
end

--============================================================
-- AUTO FUSE MACHINE
--============================================================
local _fuseFailedCooldown = {}
local _lastFuseTick = 0
local FuseStatus = "Idle"

local function _autoFuseTick()
    if not S.autoFuse then return end
    if tick() - _lastFuseTick < 2 then return end
    _lastFuseTick = tick()
    local save = _saveData()
    if not save or not save.Inventory then return end

    if save.FusionLocked and save.FusionEggReward then
        _invoke("RF/Fusery/Finishaide")
        FuseStatus = "Claimed fuse reward"
        return
    end
    if save.FusionLocked then return end -- already fusing, wait

    local maxRarity = _rarityIndex(S.maxRarityToFuse) - 1
    local groups = {}
    local now = tick()
    for uid, item in pairs(save.Inventory) do
        local skip = item.InFuse
            or (S.skipMutatedFuse and item.Mutations and next(item.Mutations) ~= nil)
            or (_fuseFailedCooldown[uid] ~= nil and _fuseFailedCooldown[uid] > now)
        if not skip then
            local info = _assetInfo(item.Category)
            if info.RarityNumber <= maxRarity then
                groups[item.Category] = groups[item.Category] or {}
                table.insert(groups[item.Category], { Uid = uid, Value = _income(item.Category, item.Scale, item.Mutations), Rarity = info.RarityNumber })
            end
        end
    end

    local bestCategory, bestItems = nil, nil
    for cat, items in pairs(groups) do
        if #items >= 3 then
            if S.fusePriorityMode == "Highest Rarity First" then
                if not bestItems or items[1].Rarity > bestItems[1].Rarity then bestCategory, bestItems = cat, items end
            elseif S.fusePriorityMode == "Most Copies First" then
                if not bestItems or #items > #bestItems then bestCategory, bestItems = cat, items end
            elseif S.fusePriorityMode == "Lowest Value First" then
                if not bestItems then bestCategory, bestItems = cat, items
                else
                    local a = items[1].Value / #items
                    local b = bestItems[1].Value / #bestItems
                    if a < b then bestCategory, bestItems = cat, items end
                end
            else -- Lowest Rarity First
                if not bestItems or items[1].Rarity < bestItems[1].Rarity then bestCategory, bestItems = cat, items end
            end
        end
    end

    if not bestItems then FuseStatus = "No matching set of 3"; return end
    for i = 1, 3 do
        local r = _invoke("RF/Fusery/LoadPet", bestItems[i].Uid)
        if r == false then _fuseFailedCooldown[bestItems[i].Uid] = tick() + 20 end
        task.wait(0.35)
    end
    _invoke("RF/Fusery/BeginFuse")
    FuseStatus = "Fusing " .. tostring(bestCategory)

    if S.ejectIncomplete then
        for cat, items in pairs(groups) do
            if #items < 3 and cat ~= bestCategory then
                -- nothing to eject here; ejection applies to loaded-but-incomplete slots, handled server-side mostly
            end
        end
    end
end

--============================================================
-- AUTO FAVORITE PET
--============================================================
local _favFailedCooldown = {}
local _lastFavTick = 0
local function _autoFavoriteTick()
    if not S.autoFavoritePet then return end
    if tick() - _lastFavTick < 2 then return end
    _lastFavTick = tick()
    local save = _saveData()
    if not save or not save.Inventory then return end

    local minRarity = _rarityIndex(S.favoriteMinRarity) - 1
    local toFav = {}
    local now = tick()
    for uid, item in pairs(save.Inventory) do
        local skip = item.Favourite or (_favFailedCooldown[uid] ~= nil and _favFailedCooldown[uid] > now)
        if not skip then
            local info = _assetInfo(item.Category)
            local value = _income(item.Category, item.Scale, item.Mutations)
            local rarityOk = info.RarityNumber >= minRarity
            local valueOk = S.minFavoriteValue <= 0 or value >= S.minFavoriteValue
            -- Not the and/or ternary idiom: when rarityOk/valueOk disagree
            -- and the rule is "Match All", `(rarityOk and valueOk)` is
            -- false, and and/or falls through to the "Match Any" fallback,
            -- silently favoriting things that only match one criterion.
            local pass
            if S.favoriteRule == "Match All" then
                pass = rarityOk and valueOk
            else
                pass = rarityOk or valueOk
            end
            if pass then table.insert(toFav, uid) end
        end
        if #toFav >= 25 then break end
    end

    for _, uid in ipairs(toFav) do
        _fire("RE/PetSatchel/WriteFavourite", uid, true)
        task.wait(0.12)
    end
end

--============================================================
-- PLAYER FEATURES (namespaced into one table -- Luau caps a function
-- at 200 simultaneously-active locals, and this file's main chunk was
-- already close to that; grouping each feature's state/functions as
-- fields on a single `PlayerFX` table keeps the top-level local count
-- low while changing nothing about behavior).
--============================================================
local PlayerFX = {}

do -- Speed Boost
    local conn
    function PlayerFX.StartSpeedBoost()
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not S.speedBoost then return end
            char = lp.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= S.boostSpeed and Movement.Owner == nil then
                hum.WalkSpeed = S.boostSpeed
            end
        end)
    end
    function PlayerFX.StopSpeedBoost()
        if conn then conn:Disconnect(); conn = nil end
        pcall(function()
            hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = 16 end
        end)
    end
end

do -- Infinite Jump
    local conn
    function PlayerFX.StartInfiniteJump()
        if conn then conn:Disconnect() end
        conn = UserInputService.JumpRequest:Connect(function()
            char = lp.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
    function PlayerFX.StopInfiniteJump()
        if conn then conn:Disconnect(); conn = nil end
    end
end

do -- Invisibility (simplified, safe transparency-based version --
   -- the reference's fake-death/rig-dismember trick is intentionally
   -- NOT reproduced since it can permanently break the character)
    local conns = {}
    local function apply(on)
        char = lp.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                p.Transparency = on and 1 or 0
            elseif p:IsA("Decal") then
                p.Transparency = on and 1 or 0
            end
        end
        for _, acc in ipairs(char:GetChildren()) do
            if acc:IsA("Accessory") then
                local handle = acc:FindFirstChild("Handle")
                if handle then handle.Transparency = on and 1 or 0 end
            end
        end
        if on then _fire("RE/RigSync/AskRigWipe", char) end
    end
    function PlayerFX.StartInvisibility()
        if S.hitMode ~= "Off" then
            _notify("Invisibility", "Turn off Auto Hit first, both cannot be on at the same time")
            S.invisibility = false
            return
        end
        apply(true)
        local conn = lp.CharacterAdded:Connect(function()
            task.wait(1)
            if S.invisibility then apply(true) end
        end)
        table.insert(conns, conn)
    end
    function PlayerFX.StopInvisibility()
        apply(false)
        for _, c in ipairs(conns) do c:Disconnect() end
        conns = {}
    end
end

do -- Anti Ragdoll
    local conn
    local BAD_CONSTRAINTS = { BallSocketConstraint = true, NoCollisionConstraint = true, HingeConstraint = true }
    local BAD_STATES = {
        [Enum.HumanoidStateType.Physics] = true,
        [Enum.HumanoidStateType.Ragdoll] = true,
        [Enum.HumanoidStateType.FallingDown] = true,
    }
    function PlayerFX.StartAntiRagdoll()
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not S.antiRagdoll then return end
            -- 21s grace window so a real Anti-Guard hit animation can play out
            if AntiGuard.Busy or (tick() - AntiGuard.HitArmedAt) <= 21 then return end
            char = lp.Character
            if not char then return end
            hum = char:FindFirstChildOfClass("Humanoid")
            hrp = char:FindFirstChild("HumanoidRootPart")
            if RagdollMod then
                pcall(function()
                    if RagdollMod.IsRagdolled and RagdollMod.IsRagdolled(char) then
                        if RagdollMod.ClearClientRagdoll then RagdollMod.ClearClientRagdoll() end
                        if RagdollMod.Unragdoll then RagdollMod.Unragdoll(char) end
                    end
                end)
            end
            for _, c in ipairs(char:GetDescendants()) do
                if BAD_CONSTRAINTS[c.ClassName] then pcall(function() c:Destroy() end) end
                if c:IsA("Motor6D") and not c.Enabled then c.Enabled = true end
            end
            if hum and hrp then
                if BAD_STATES[hum:GetState()] then hum:ChangeState(Enum.HumanoidStateType.Running) end
                hum.PlatformStand = false
                local v = hrp.AssemblyLinearVelocity
                local horiz = Vector3.new(v.X, 0, v.Z)
                local cap = hum.WalkSpeed + 5
                if horiz.Magnitude > cap then
                    horiz = horiz.Unit * cap
                    hrp.AssemblyLinearVelocity = Vector3.new(horiz.X, math.min(v.Y, 0), horiz.Z)
                elseif v.Y > 0 then
                    hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
                end
            end
        end)
    end
    function PlayerFX.StopAntiRagdoll()
        if conn then conn:Disconnect(); conn = nil end
    end
end

do -- Anti Trap
    local cache = {}
    local conns = {}
    local function neutralize(trap)
        local owner = trap:GetAttribute("Owner")
        if owner == lp.Name then return end
        for _, part in ipairs(trap:GetDescendants()) do
            if part:IsA("BasePart") and cache[part] == nil then
                cache[part] = part.CanTouch
                part.CanTouch = false
            end
        end
        if trap:IsA("BasePart") and cache[trap] == nil then
            cache[trap] = trap.CanTouch
            trap.CanTouch = false
        end
    end
    function PlayerFX.StartAntiTrap()
        local conn = CollectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(trap)
            if S.antiTrap then neutralize(trap) end
        end)
        table.insert(conns, conn)
        -- Deferred: don't let the initial scan of existing tagged instances
        -- block the script's main (non-yielding) load thread.
        task.spawn(function()
            for _, trap in ipairs(CollectionService:GetTagged("PlacedTrap")) do neutralize(trap) end
        end)
    end
    function PlayerFX.StopAntiTrap()
        for _, c in ipairs(conns) do c:Disconnect() end
        conns = {}
        for part, original in pairs(cache) do
            pcall(function() part.CanTouch = original end)
        end
        cache = {}
    end
end

do -- Instant Prompts
    local original = {}
    local conns = {}
    local EXCLUDED = { ClaimLostPart = true }
    local function apply(prompt)
        if EXCLUDED[prompt.Name] then return end
        if original[prompt] == nil then original[prompt] = prompt.HoldDuration end
        prompt.HoldDuration = 0
    end
    function PlayerFX.StartInstantPrompts()
        local conn = workspace.DescendantAdded:Connect(function(obj)
            if S.instantPrompts and obj:IsA("ProximityPrompt") then apply(obj) end
        end)
        table.insert(conns, conn)
        -- Deferred + yielding: a full workspace:GetDescendants() scan can be
        -- tens of thousands of instances in this game; running it inline
        -- during script load risks tripping the "exhausted execution time"
        -- watchdog, especially on mobile executors. Spawn it separately and
        -- yield periodically while walking it.
        task.spawn(function()
            local all = workspace:GetDescendants()
            for i, obj in ipairs(all) do
                if obj:IsA("ProximityPrompt") then apply(obj) end
                if i % 500 == 0 then task.wait() end
            end
        end)
    end
    function PlayerFX.StopInstantPrompts()
        for _, c in ipairs(conns) do c:Disconnect() end
        conns = {}
        for prompt, orig in pairs(original) do
            pcall(function() prompt.HoldDuration = orig end)
        end
        original = {}
    end
end

do -- God Mode
    local conn
    function PlayerFX.StartGodMode()
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not S.godMode then return end
            char = lp.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        end)
    end
    function PlayerFX.StopGodMode()
        if conn then conn:Disconnect(); conn = nil end
    end
end

do -- Combat / Auto Hit (RE/BatSwing/Trigger)
    local state = { LastFire = 0, Trace = 0 }
    local BAT_KEYWORDS = { "bat", "katana", "axe", "staff", "club", "hammer", "sword", "blade" }

    local function findBat()
        char = lp.Character
        local function scan(container)
            if not container then return nil end
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local isBat = tool:GetAttribute("IsBat") == true
                    if not isBat then
                        local lname = tool.Name:lower()
                        for _, kw in ipairs(BAT_KEYWORDS) do
                            if lname:find(kw) then isBat = true; break end
                        end
                    end
                    if isBat then return tool end
                end
            end
            return nil
        end
        return scan(char) or scan(lp:FindFirstChild("Backpack"))
    end

    local function combatRange(tool)
        local base = 15 + 2
        local mult = (workspace:GetAttribute("DragonEggEventActive") == true) and 2.5 or 1
        return base * mult
    end

    local function hittable(target)
        if target == lp then return false end
        local tchar = target.Character
        if not tchar then return false end
        local thum = tchar:FindFirstChildOfClass("Humanoid")
        local thrp = tchar:FindFirstChild("HumanoidRootPart")
        if not thum or not thrp or thum.Health <= 0 then return false end
        if thrp:GetAttribute("IsTrapped") == true then return false end
        if target:GetAttribute("InBossArena") then return false end
        if _insideBase(thrp.Position) then return false end
        local ragdollEnd = target:GetAttribute("RagdollEndTime")
        if ragdollEnd and ragdollEnd > workspace:GetServerTimeNow() then return false end
        return true
    end

    local function pickTarget()
        char = lp.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        if S.hitMode == "Specific Player" then
            local p = Players:FindFirstChild(S.hitPlayerName) or (function()
                for _, pl in ipairs(Players:GetPlayers()) do
                    if pl.DisplayName == S.hitPlayerName or pl.Name == S.hitPlayerName then return pl end
                end
            end)()
            return (p and hittable(p)) and p or nil
        elseif S.hitMode == "Egg Holders" then
            local records = _readFieldEggs()
            for uid, rec in pairs(records) do
                if rec.State == "Carried" then
                    local model = workspace:FindFirstChild(uid)
                    if model then
                        for _, d in ipairs(model:GetDescendants()) do
                            if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("RigidConstraint") then
                                -- GetPlayerFromCharacter(nil) throws if the
                                -- joint's Part0/Part1 exists but is
                                -- currently unparented -- guard the parent
                                -- before passing it in.
                                local p0 = d.Part0 and d.Part0.Parent
                                local p1 = d.Part1 and d.Part1.Parent
                                local other = (p0 and Players:GetPlayerFromCharacter(p0))
                                    or (p1 and Players:GetPlayerFromCharacter(p1))
                                if other and hittable(other) then return other end
                            end
                        end
                    end
                end
            end
            return nil
        else -- Nearest / Aura
            local best, bestDist = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if hittable(p) then
                    local d = (p.Character.HumanoidRootPart.Position - hrp.Position).Magnitude
                    if d < bestDist then best, bestDist = p, d end
                end
            end
            return best
        end
    end

    local function tryHit(target)
        if not target then return end
        if StealActive or StealCarrying then return end
        local bat = findBat()
        if not bat then return end
        char = lp.Character
        hum = char and char:FindFirstChildOfClass("Humanoid")
        -- Equipped Tools parent to the Character, never the Humanoid --
        -- checking hum:FindFirstChildOfClass("Tool") is always nil, so this
        -- branch used to re-equip and `return` every single tick, and the
        -- actual swing/fire logic below was never reached.
        if hum and char and char:FindFirstChildOfClass("Tool") ~= bat then
            pcall(function() hum:EquipTool(bat) end)
            return
        end
        local thrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not thrp or not hrp then return end
        if (thrp.Position - hrp.Position).Magnitude > combatRange(bat) - 1 then return end
        if tick() - state.LastFire < 0.15 then return end
        state.LastFire = tick()
        state.Trace = state.Trace + 1
        local traceId = ("%d:%d:%d"):format(lp.UserId, state.Trace, math.floor(workspace:GetServerTimeNow() * 1000))
        _fire("RE/BatSwing/Trigger", target, traceId)
    end

    local conn
    function PlayerFX.StartCombat()
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if S.hitMode == "Off" then return end
            local target = pickTarget()
            if target then tryHit(target) end
        end)
    end
    function PlayerFX.StopCombat()
        if conn then conn:Disconnect(); conn = nil end
    end
end

do -- Misc: FPS Cap + Anti-AFK (clean, non-exploit method)
    function PlayerFX.ApplyFpsCap()
        if S.fpsCap and S.fpsCap > 0 and setfpscap then
            pcall(setfpscap, S.fpsCap)
        end
    end
    local conn
    function PlayerFX.StartAntiAFK()
        if conn then conn:Disconnect() end
        conn = lp.Idled:Connect(function()
            if not S.antiAFK then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
    function PlayerFX.StopAntiAFK()
        if conn then conn:Disconnect(); conn = nil end
    end
end

--============================================================
-- STATS
--============================================================
local STATS = { totalEggs = 0, totalValue = 0, sessionStart = tick(), byRarity = {} }
local function _recordStolenEgg(target)
    STATS.totalEggs += 1
    STATS.totalValue += target.Value or 0
    local r = target.RarityName or "Common"
    STATS.byRarity[r] = (STATS.byRarity[r] or 0) + 1
end

--============================================================
-- UI — colors verified from the reference's theme tables
--============================================================
local BG       = Color3.fromRGB(16, 17, 22)
local BG2      = Color3.fromRGB(24, 25, 32)
local BG3      = Color3.fromRGB(34, 35, 45)
local TEXT     = Color3.fromRGB(230, 230, 236)
local DIM      = Color3.fromRGB(140, 140, 156)
local HUD      = Color3.fromRGB(0, 118, 255)     -- neutral/info
local STEAL_C  = Color3.fromRGB(60, 255, 0)      -- active/green
local CANCEL_C = Color3.fromRGB(214, 17, 17)     -- red
local GOLD_C   = Color3.fromRGB(255, 247, 0)     -- priority/rank1
local YELLOW   = Color3.fromRGB(255, 200, 87)

local gui = Instance.new("ScreenGui")
gui.Name = "yslemEggUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (gethui and gethui()) or lp:WaitForChild("PlayerGui")

local UI_W, UI_H = 360, 480
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, UI_W, 0, UI_H)
main.Position = UDim2.new(0.5, -UI_W / 2, 0.35, -UI_H / 2)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundColor3 = BG2
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "yslemEgg — Steal An Egg"
title.TextColor3 = HUD
title.TextSize = 15
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -33, 0, 5)
closeBtn.BackgroundColor3 = CANCEL_C
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextSize = 13
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local TAB_NAMES = { "Farm", "Economy", "Player", "Stats" }
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -12, 0, 28)
tabFrame.Position = UDim2.new(0, 6, 0, 44)
tabFrame.BackgroundTransparency = 1
tabFrame.Parent = main

local tabBtns, tabPanels = {}, {}
for i, name in ipairs(TAB_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1 / #TAB_NAMES, -4, 1, 0)
    btn.Position = UDim2.new((i - 1) / #TAB_NAMES, 2, 0, 0)
    btn.BackgroundColor3 = BG3
    btn.Text = name
    btn.TextColor3 = DIM
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = tabFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    tabBtns[name] = btn

    local panel = Instance.new("ScrollingFrame")
    panel.Size = UDim2.new(1, -12, 1, -84)
    panel.Position = UDim2.new(0, 6, 0, 76)
    panel.BackgroundTransparency = 1
    panel.ScrollBarThickness = 3
    panel.ScrollBarImageColor3 = HUD
    panel.CanvasSize = UDim2.new(0, 0, 0, 0)
    panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
    panel.Visible = (name == "Farm")
    panel.Parent = main
    tabPanels[name] = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = panel
end
local function _switchTab(name)
    for n, p in pairs(tabPanels) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        b.TextColor3 = (n == name) and HUD or DIM
        b.BackgroundColor3 = (n == name) and BG2 or BG3
    end
end
for name, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() _switchTab(name) end)
end

--============================================================
-- UI widget helpers
--============================================================
local function _card(parent, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.BackgroundColor3 = BG2
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = f
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = f
    return f
end
local function _cardTitle(parent, text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = HUD
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order or 0
    lbl.Parent = parent
    return lbl
end
local function _label(parent, text, color, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color or TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order or 0
    lbl.Parent = parent
    return lbl
end
local function _toggle(parent, text, key, order, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -48, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 44, 0, 20)
    btn.Position = UDim2.new(1, -44, 0.5, -10)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    local function _refresh()
        local on = S[key]
        btn.BackgroundColor3 = on and STEAL_C or BG3
        btn.TextColor3 = on and Color3.new(0, 0, 0) or DIM
        btn.Text = on and "ON" or "OFF"
    end
    _refresh()
    btn.MouseButton1Click:Connect(function()
        S[key] = not S[key]
        _refresh()
        _saveSettings()
        if onChange then onChange(S[key]) end
    end)
    return row, btn
end
local function _cycleDropdown(parent, text, key, options, order, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.47, 0, 1, 0)
    btn.Position = UDim2.new(0.53, 0, 0, 0)
    btn.BackgroundColor3 = BG3
    btn.Text = tostring(S[key])
    btn.TextColor3 = YELLOW
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        local idx = table.find(options, S[key]) or 1
        idx = (idx % #options) + 1
        S[key] = options[idx]
        btn.Text = tostring(options[idx])
        _saveSettings()
        if onChange then onChange(S[key]) end
    end)
    return row
end
local function _numberInput(parent, text, key, order, placeholder)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.47, 0, 1, 0)
    box.Position = UDim2.new(0.53, 0, 0, 0)
    box.BackgroundColor3 = BG3
    box.Text = tostring(S[key])
    box.PlaceholderText = placeholder or "0"
    box.TextColor3 = YELLOW
    box.TextSize = 10
    box.Font = Enum.Font.GothamBold
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

    local function _parseValue(text)
        text = text:lower():gsub("%s", ""):gsub(",", "")
        local suffix = text:sub(-1)
        local mult = 1
        if suffix == "k" then mult = 1e3; text = text:sub(1, -2)
        elseif suffix == "m" then mult = 1e6; text = text:sub(1, -2)
        elseif suffix == "b" then mult = 1e9; text = text:sub(1, -2)
        elseif suffix == "t" then mult = 1e12; text = text:sub(1, -2) end
        return (tonumber(text) or 0) * mult
    end
    box.FocusLost:Connect(function()
        S[key] = _parseValue(box.Text)
        box.Text = tostring(S[key])
        _saveSettings()
    end)
    return row
end
local function _slider(parent, text, key, minV, maxV, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text .. ": " .. tostring(S[key])
    lbl.TextColor3 = TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, 0, 0, 8)
    track.Position = UDim2.new(0, 0, 0, 20)
    track.BackgroundColor3 = BG3
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 4)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = HUD
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    local function _update()
        local pct = (S[key] - minV) / (maxV - minV)
        fill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
        lbl.Text = text .. ": " .. tostring(S[key])
    end
    _update()

    local dragging = false
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            _saveSettings()
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local pos = track.AbsolutePosition
            local size = track.AbsoluteSize
            local rel = math.clamp((inp.Position.X - pos.X) / size.X, 0, 1)
            S[key] = math.floor(minV + rel * (maxV - minV))
            _update()
        end
    end)
    return row
end

--============================================================
-- UI cross-references needed by the refresh loop / handlers below
-- (pre-declared so each tab's build code can live inside its own
-- `do...end` block -- keeps the main chunk's active-local count low,
-- since Luau/Lua caps simultaneously-active locals per function at 200)
--============================================================
local stealStatusLbl, queueCard, queueCountLbl, queueRows
local fuseStatusLbl
local totalEggsLbl, totalValueLbl, sessionLbl, rateLbl, rarityLabels

--============================================================
-- FARM TAB
--============================================================
do
    local farmPanel = tabPanels["Farm"]

    local quickCard = _card(farmPanel, 1)
    _cardTitle(quickCard, "AUTO STEAL", 1)
    stealStatusLbl = _label(quickCard, "Idle", DIM, 2)
    _toggle(quickCard, "Auto Steal", "autoSteal", 3)
    _cycleDropdown(quickCard, "Min Rarity", "minRarity", FALLBACK_RARITIES, 4)
    _numberInput(quickCard, "Min Steal Value", "minStealValue", 5, "e.g. 250k")
    _cycleDropdown(quickCard, "Steal Priority", "stealPriority",
        { "Highest Value", "Lowest Value", "Best Rarity", "Biggest Weight", "Best Mutation" }, 6)
    _toggle(quickCard, "Instant Steal (fly)", "instantSteal", 7)
    _toggle(quickCard, "Wait For Guard Sleep", "waitGuardSleep", 8)
    _toggle(quickCard, "Anti-Guard", "antiGuardEnabled", 9)

    local areasCard = _card(farmPanel, 2)
    _cardTitle(areasCard, "TARGET AREAS (tap to toggle, none = all)", 1)
    local areaRow = Instance.new("Frame")
    areaRow.Size = UDim2.new(1, 0, 0, 0)
    areaRow.AutomaticSize = Enum.AutomaticSize.Y
    areaRow.BackgroundTransparency = 1
    areaRow.LayoutOrder = 2
    areaRow.Parent = areasCard
    local areaLayout = Instance.new("UIGridLayout")
    areaLayout.CellSize = UDim2.new(0, 100, 0, 20)
    areaLayout.CellPadding = UDim2.new(0, 4, 0, 4)
    areaLayout.Parent = areaRow
    for _, areaName in ipairs(FALLBACK_AREAS) do
        local btn = Instance.new("TextButton")
        btn.BackgroundColor3 = BG3
        btn.Text = areaName
        btn.TextColor3 = DIM
        btn.TextSize = 9
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.Parent = areaRow
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        local function refresh()
            local on = table.find(S.targetAreas, areaName) ~= nil
            btn.BackgroundColor3 = on and HUD or BG3
            btn.TextColor3 = on and Color3.new(1, 1, 1) or DIM
        end
        refresh()
        btn.MouseButton1Click:Connect(function()
            local idx = table.find(S.targetAreas, areaName)
            if idx then table.remove(S.targetAreas, idx) else table.insert(S.targetAreas, areaName) end
            refresh()
            _saveSettings()
        end)
    end

    queueCard = _card(farmPanel, 3)
    _cardTitle(queueCard, "STEAL QUEUE (live)", 1)
    queueCountLbl = _label(queueCard, "0 in queue · 0 candidates", DIM, 2)
    queueRows = {}

    local placeCard = _card(farmPanel, 4)
    _cardTitle(placeCard, "AUTO PLACE EGG", 1)
    _toggle(placeCard, "Auto Place", "autoPlace", 2)
    _cycleDropdown(placeCard, "Place Rule", "placeRule", { "Always", "Steal Idle", "After Steal", "Night Only" }, 3)
    _cycleDropdown(placeCard, "Place Order", "placeOrder", { "Highest Value", "Smallest Size", "Biggest Size" }, 4)
    _numberInput(placeCard, "Min Place Value", "minPlaceValue", 5, "0 = off")

    local treadCard = _card(farmPanel, 5)
    _cardTitle(treadCard, "AUTO TREADMILL", 1)
    _toggle(treadCard, "Auto Treadmill", "autoTreadmill", 2)
    _toggle(treadCard, "Stay On Treadmill", "stayOnTreadmill", 3)
end

--============================================================
-- ECONOMY TAB
--============================================================
do
    local ecoPanel = tabPanels["Economy"]

    local hatchCard = _card(ecoPanel, 1)
    _cardTitle(hatchCard, "AUTO HATCH", 1)
    _toggle(hatchCard, "Auto Hatch", "autoHatch", 2)
    _cycleDropdown(hatchCard, "Min Rarity", "hatchMinRarity", FALLBACK_RARITIES, 3)
    _numberInput(hatchCard, "Min Hatch Value", "minHatchValue", 4, "0 = off")

    local equipCard = _card(ecoPanel, 2)
    _cardTitle(equipCard, "AUTO EQUIP", 1)
    _toggle(equipCard, "Auto Equip Best", "autoEquipBest", 2)

    local sellCard = _card(ecoPanel, 3)
    _cardTitle(sellCard, "AUTO SELL — PETS", 1)
    _toggle(sellCard, "Auto Sell Pets", "autoSellPet", 2)
    _cycleDropdown(sellCard, "Sell Rule", "sellPetRule", { "Rarity Only", "Value Only", "Rarity And Value", "Rarity Or Value" }, 3)
    _cycleDropdown(sellCard, "Max Rarity", "petMaxRarity", FALLBACK_RARITIES, 4)
    _numberInput(sellCard, "Sell Below Value", "minPetSellValue", 5, "0 = off")
    _toggle(sellCard, "Keep Mutated Pets", "keepMutatedPets", 6)

    local sellEggCard = _card(ecoPanel, 4)
    _cardTitle(sellEggCard, "AUTO SELL — EGGS", 1)
    _toggle(sellEggCard, "Auto Sell Eggs", "autoSellEgg", 2)
    _cycleDropdown(sellEggCard, "Sell Rule", "sellEggRule", { "Rarity Only", "Value Only", "Rarity And Value", "Rarity Or Value" }, 3)
    _cycleDropdown(sellEggCard, "Max Rarity", "eggMaxRarity", FALLBACK_RARITIES, 4)
    _numberInput(sellEggCard, "Sell Below Value", "minEggSellValue", 5, "0 = off")
    _toggle(sellEggCard, "Keep Mutated Eggs", "keepMutatedEggs", 6)

    local fuseCard = _card(ecoPanel, 5)
    _cardTitle(fuseCard, "AUTO FUSE MACHINE", 1)
    fuseStatusLbl = _label(fuseCard, "Idle", DIM, 2)
    _toggle(fuseCard, "Auto Fuse", "autoFuse", 3)
    _cycleDropdown(fuseCard, "Priority Mode", "fusePriorityMode",
        { "Lowest Rarity First", "Highest Rarity First", "Most Copies First", "Lowest Value First" }, 4)
    _cycleDropdown(fuseCard, "Max Rarity To Fuse", "maxRarityToFuse", FALLBACK_RARITIES, 5)
    _toggle(fuseCard, "Skip Mutated Pets", "skipMutatedFuse", 6)
    _toggle(fuseCard, "Eject Incomplete Slots", "ejectIncomplete", 7)

    local favCard = _card(ecoPanel, 6)
    _cardTitle(favCard, "AUTO FAVORITE PET", 1)
    _toggle(favCard, "Auto Favorite", "autoFavoritePet", 2)
    _cycleDropdown(favCard, "Rule", "favoriteRule", { "Match Any", "Match All" }, 3)
    _cycleDropdown(favCard, "Min Rarity", "favoriteMinRarity", FALLBACK_RARITIES, 4)
    _numberInput(favCard, "Min Value", "minFavoriteValue", 5, "0 = off")
end

--============================================================
-- PLAYER TAB
--============================================================
do
    local playerPanel = tabPanels["Player"]

    local movCard = _card(playerPanel, 1)
    _cardTitle(movCard, "MOVEMENT", 1)
    _toggle(movCard, "Speed Boost", "speedBoost", 2, function(on)
        if on then PlayerFX.StartSpeedBoost() else PlayerFX.StopSpeedBoost() end
    end)
    _slider(movCard, "Boost Speed", "boostSpeed", 20, 1000, 3)
    _toggle(movCard, "Infinite Jump", "infiniteJump", 4, function(on)
        if on then PlayerFX.StartInfiniteJump() else PlayerFX.StopInfiniteJump() end
    end)

    local charCard = _card(playerPanel, 2)
    _cardTitle(charCard, "CHARACTER", 1)
    _toggle(charCard, "God Mode", "godMode", 2, function(on)
        if on then PlayerFX.StartGodMode() else PlayerFX.StopGodMode() end
    end)
    _toggle(charCard, "Invisibility", "invisibility", 3, function(on)
        if on then PlayerFX.StartInvisibility() else PlayerFX.StopInvisibility() end
    end)
    _toggle(charCard, "Anti Ragdoll", "antiRagdoll", 4, function(on)
        if on then PlayerFX.StartAntiRagdoll() else PlayerFX.StopAntiRagdoll() end
    end)
    _toggle(charCard, "Anti Trap", "antiTrap", 5, function(on)
        if on then PlayerFX.StartAntiTrap() else PlayerFX.StopAntiTrap() end
    end)
    _toggle(charCard, "Instant Prompts", "instantPrompts", 6, function(on)
        if on then PlayerFX.StartInstantPrompts() else PlayerFX.StopInstantPrompts() end
    end)

    local combatCard = _card(playerPanel, 3)
    _cardTitle(combatCard, "COMBAT / AUTO HIT", 1)
    _cycleDropdown(combatCard, "Hit Mode", "hitMode", { "Off", "Nearest", "Egg Holders", "Specific Player", "Aura" }, 2, function(on)
        if S.invisibility and S.hitMode ~= "Off" then
            _notify("Auto Hit", "Turn off Invisibility first, both cannot be on at the same time")
            S.hitMode = "Off"
        end
    end)

    local miscCard = _card(playerPanel, 4)
    _cardTitle(miscCard, "MISC", 1)
    _slider(miscCard, "FPS Cap (0 = uncapped)", "fpsCap", 0, 240, 2)
    _toggle(miscCard, "Anti AFK", "antiAFK", 3, function(on)
        if on then PlayerFX.StartAntiAFK() else PlayerFX.StopAntiAFK() end
    end)

    local webhookCard = _card(playerPanel, 5)
    _cardTitle(webhookCard, "DISCORD WEBHOOK (your own URL, optional)", 1)
    local webhookRow = Instance.new("Frame")
    webhookRow.Size = UDim2.new(1, 0, 0, 24)
    webhookRow.BackgroundTransparency = 1
    webhookRow.LayoutOrder = 2
    webhookRow.Parent = webhookCard
    local webhookBox = Instance.new("TextBox")
    webhookBox.Size = UDim2.new(1, 0, 1, 0)
    webhookBox.BackgroundColor3 = BG3
    webhookBox.Text = S.webhookUrl
    webhookBox.PlaceholderText = "https://discord.com/api/webhooks/..."
    webhookBox.TextColor3 = YELLOW
    webhookBox.TextSize = 9
    webhookBox.Font = Enum.Font.RobotoMono
    webhookBox.ClearTextOnFocus = false
    webhookBox.BorderSizePixel = 0
    webhookBox.Parent = webhookRow
    Instance.new("UICorner", webhookBox).CornerRadius = UDim.new(0, 6)
    webhookBox.FocusLost:Connect(function()
        S.webhookUrl = webhookBox.Text
        _saveSettings()
    end)
    _toggle(webhookCard, "Notify Stolen Eggs", "notifyStolenEggs", 3)
end

--============================================================
-- STATS TAB
--============================================================
do
    local statsPanel = tabPanels["Stats"]

    local statsCard = _card(statsPanel, 1)
    _cardTitle(statsCard, "SESSION STATS", 1)
    totalEggsLbl = _label(statsCard, "Total Eggs: 0", TEXT, 2)
    totalValueLbl = _label(statsCard, "Total Value: $0", STEAL_C, 3)
    sessionLbl = _label(statsCard, "Session: 0m", YELLOW, 4)
    rateLbl = _label(statsCard, "Rate: 0 eggs/min", DIM, 5)

    local rarityCard = _card(statsPanel, 2)
    _cardTitle(rarityCard, "BY RARITY", 1)
    rarityLabels = {}
    for _, r in ipairs(FALLBACK_RARITIES) do
        rarityLabels[r] = _label(rarityCard, r .. ": 0", DIM, 0)
    end

    local settingsCard = _card(statsPanel, 3)
    _cardTitle(settingsCard, "SETTINGS", 1)
    _toggle(settingsCard, "Notifications", "notifications", 2)
    _toggle(settingsCard, "Show Stats Card", "showStats", 3)
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1, 0, 0, 22)
    resetBtn.BackgroundColor3 = CANCEL_C
    resetBtn.Text = "Reset Stats"
    resetBtn.TextColor3 = Color3.new(1, 1, 1)
    resetBtn.TextSize = 11
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.BorderSizePixel = 0
    resetBtn.LayoutOrder = 4
    resetBtn.Parent = settingsCard
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)
    resetBtn.MouseButton1Click:Connect(function()
        STATS.totalEggs, STATS.totalValue, STATS.byRarity = 0, 0, {}
        STATS.sessionStart = tick()
    end)
end

--============================================================
-- WIRE STATS INTO THE STEAL PIPELINE
--============================================================
do
    local _origDeliver = _deliverEgg
    _deliverEgg = function(target)
        local ok = _origDeliver(target)
        if ok then _recordStolenEgg(target) end
        return ok
    end
end

--============================================================
-- MAIN LOOPS
--============================================================
_spawnTracked(function()
    while true do
        if S.autoSteal and tick() - _lastStealAttempt >= STEAL_COOLDOWN then
            local ok, err = pcall(_stealAttempt)
            if not ok then StealStatus = "Error: " .. tostring(err) end
        end
        task.wait(0.2)
    end
end)

_spawnTracked(function()
    while true do
        pcall(_autoPlaceTick)
        task.wait(1)
    end
end)

_spawnTracked(function()
    while true do
        pcall(_autoTreadmillTick)
        task.wait(2)
    end
end)

_spawnTracked(function()
    while true do
        pcall(_autoHatchTick)
        pcall(_autoEquipBestTick)
        task.wait(2)
    end
end)

_spawnTracked(function()
    while true do
        pcall(_autoSellTick)
        pcall(_autoFuseTick)
        pcall(_autoFavoriteTick)
        task.wait(1.5)
    end
end)

_spawnTracked(function()
    PlayerFX.ApplyFpsCap()
    while true do
        task.wait(1)
        -- Farm tab live refresh
        stealStatusLbl.Text = StealStatus
        local plan = S.autoSteal and StealPlan() or {}
        queueCountLbl.Text = ("%d in queue"):format(#plan)

        for _, row in ipairs(queueRows) do row:Destroy() end
        queueRows = {}
        local records = _readFieldEggs()
        for i, uid in ipairs(plan) do
            if i > 8 then break end
            local rec = records[uid]
            if rec then
                local info = _assetInfo(rec.AssetCategory)
                local value = _income(rec.AssetCategory, rec.AssetScale, rec.Mutations)
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 20)
                row.BackgroundColor3 = (uid == StealCarryUid) and Color3.fromRGB(20, 60, 20) or BG3
                row.BorderSizePixel = 0
                row.LayoutOrder = i + 2
                row.Parent = queueCard
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

                local rankLbl = Instance.new("TextLabel")
                rankLbl.Size = UDim2.new(0, 26, 1, 0)
                rankLbl.BackgroundTransparency = 1
                rankLbl.Text = "#" .. i
                rankLbl.TextColor3 = (i == 1) and GOLD_C or DIM
                rankLbl.TextSize = 10
                rankLbl.Font = Enum.Font.GothamBold
                rankLbl.Parent = row

                local nameLbl = Instance.new("TextLabel")
                nameLbl.Size = UDim2.new(0.45, -26, 1, 0)
                nameLbl.Position = UDim2.new(0, 26, 0, 0)
                nameLbl.BackgroundTransparency = 1
                nameLbl.Text = tostring(rec.AssetCategory or "?"):sub(1, 14)
                nameLbl.TextColor3 = TEXT
                nameLbl.TextSize = 10
                nameLbl.Font = Enum.Font.Gotham
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.Parent = row

                local valLbl = Instance.new("TextLabel")
                valLbl.Size = UDim2.new(0.4, 0, 1, 0)
                valLbl.Position = UDim2.new(0.45, 0, 0, 0)
                valLbl.BackgroundTransparency = 1
                valLbl.Text = ("%s $%.0f"):format(info.RarityName or "?", value)
                valLbl.TextColor3 = YELLOW
                valLbl.TextSize = 9
                valLbl.Font = Enum.Font.GothamBold
                valLbl.TextXAlignment = Enum.TextXAlignment.Right
                valLbl.Parent = row

                -- Prioritize (star) button -- promotes this uid to the front
                -- of the steal queue via the already-implemented StealAPI.
                local starBtn = Instance.new("TextButton")
                starBtn.Size = UDim2.new(0, 20, 1, 0)
                starBtn.Position = UDim2.new(0.85, 0, 0, 0)
                starBtn.BackgroundTransparency = 1
                starBtn.Text = "\226\152\133" -- star
                starBtn.TextColor3 = (i == 1) and GOLD_C or DIM
                starBtn.TextSize = 12
                starBtn.Font = Enum.Font.GothamBold
                starBtn.Parent = row
                starBtn.MouseButton1Click:Connect(function() PrioritizeSteal(uid) end)

                -- Cancel button -- drops this uid from the queue (blacklists
                -- it for this session) via the already-implemented StealAPI.
                local cancelBtn = Instance.new("TextButton")
                cancelBtn.Size = UDim2.new(0, 20, 1, 0)
                cancelBtn.Position = UDim2.new(0.93, 0, 0, 0)
                cancelBtn.BackgroundTransparency = 1
                cancelBtn.Text = "X"
                cancelBtn.TextColor3 = CANCEL_C
                cancelBtn.TextSize = 11
                cancelBtn.Font = Enum.Font.GothamBold
                cancelBtn.Parent = row
                cancelBtn.MouseButton1Click:Connect(function() CancelSteal(uid) end)

                table.insert(queueRows, row)
            end
        end
        queueCountLbl.Text = ("%d in queue · carrying: %s"):format(#plan, StealCarrying and "yes" or "no")

        -- Economy tab live refresh
        fuseStatusLbl.Text = FuseStatus

        -- Stats tab live refresh
        local minutes = math.max((tick() - STATS.sessionStart) / 60, 0.01)
        totalEggsLbl.Text = "Total Eggs: " .. STATS.totalEggs
        totalValueLbl.Text = ("Total Value: $%.2fM"):format(STATS.totalValue / 1e6)
        sessionLbl.Text = ("Session: %dm"):format(math.floor(minutes))
        rateLbl.Text = ("Rate: %.1f eggs/min"):format(STATS.totalEggs / minutes)
        for r, lbl in pairs(rarityLabels) do
            local n = STATS.byRarity[r] or 0
            lbl.Text = r .. ": " .. n
            lbl.TextColor3 = n > 0 and TEXT or DIM
        end
    end
end)

--============================================================
-- INITIAL STATE + CLEANUP
--============================================================
-- Yield here: everything above (module requires, UI construction) ran as one
-- non-yielding chunk. A long enough chunk can trip the engine's "exhausted
-- allowed execution time" watchdog, which kills the whole script with no
-- visible error -- more likely on weaker/mobile executors. This resets it.
task.wait()

if S.speedBoost then PlayerFX.StartSpeedBoost() end
if S.infiniteJump then PlayerFX.StartInfiniteJump() end
if S.godMode then PlayerFX.StartGodMode() end
if S.antiRagdoll then PlayerFX.StartAntiRagdoll() end
if S.antiTrap then PlayerFX.StartAntiTrap() end
if S.instantPrompts then PlayerFX.StartInstantPrompts() end
if S.invisibility then PlayerFX.StartInvisibility() end
if S.antiAFK then PlayerFX.StartAntiAFK() end
PlayerFX.StartCombat() -- always running; internally no-ops while hitMode == "Off"

closeBtn.MouseButton1Click:Connect(function()
    S.autoSteal = false
    _killAll()
    PlayerFX.StopSpeedBoost()
    PlayerFX.StopInfiniteJump()
    PlayerFX.StopInvisibility()
    PlayerFX.StopAntiRagdoll()
    PlayerFX.StopAntiTrap()
    PlayerFX.StopInstantPrompts()
    PlayerFX.StopGodMode()
    PlayerFX.StopCombat()
    PlayerFX.StopAntiAFK()
    _saveSettings()
    gui:Destroy()
end)

lp.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp = newChar:WaitForChild("HumanoidRootPart")
    hum = newChar:WaitForChild("Humanoid")
    task.wait(0.5)
    if S.speedBoost then PlayerFX.StartSpeedBoost() end
    if S.infiniteJump then PlayerFX.StartInfiniteJump() end
    if S.godMode then PlayerFX.StartGodMode() end
    if S.antiRagdoll then PlayerFX.StartAntiRagdoll() end
    if S.instantPrompts then PlayerFX.StartInstantPrompts() end
end)

_notify("yslemEgg", "v5.0 ULTRA loaded — verified remotes, real income formula, full automation suite.")
print("[yslemEgg v5.0 ULTRA] Loaded — Farm/Economy/Player/Stats tabs active. Settings auto-save to " .. SAVE_FILE)

end) -- closes the pcall opened near the top of the file

if not __yslemEgg_ok then
    local errText = tostring(__yslemEgg_err)
    warn("[yslemEgg] FATAL ERROR (script did not finish loading): " .. errText)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "yslemEgg CRASHED",
            Text = errText:sub(1, 180),
            Duration = 20,
        })
    end)
    -- Guaranteed-visible fallback: draw the error directly on screen in
    -- case SendNotification / the console aren't visible on this executor.
    pcall(function()
        local Players = game:GetService("Players")
        local lp = Players.LocalPlayer
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "yslemEggErrorReport"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = (gethui and gethui()) or lp:WaitForChild("PlayerGui")

        local box = Instance.new("Frame")
        box.Size = UDim2.new(0, 420, 0, 220)
        box.Position = UDim2.new(0.5, -210, 0.5, -110)
        box.BackgroundColor3 = Color3.fromRGB(40, 12, 12)
        box.BorderSizePixel = 0
        box.Active = true
        box.Draggable = true
        box.Parent = screenGui
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -16, 0, 24)
        title.Position = UDim2.new(0, 8, 0, 6)
        title.BackgroundTransparency = 1
        title.Text = "yslemEgg crashed while loading -- copy this text:"
        title.TextColor3 = Color3.fromRGB(255, 180, 180)
        title.TextSize = 13
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = box

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -16, 1, -66)
        scroll.Position = UDim2.new(0, 8, 0, 32)
        scroll.BackgroundColor3 = Color3.fromRGB(20, 6, 6)
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 4
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Parent = box
        Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

        local errLbl = Instance.new("TextLabel")
        errLbl.Size = UDim2.new(1, -8, 0, 0)
        errLbl.Position = UDim2.new(0, 4, 0, 4)
        errLbl.AutomaticSize = Enum.AutomaticSize.Y
        errLbl.BackgroundTransparency = 1
        errLbl.Text = errText
        errLbl.TextColor3 = Color3.fromRGB(255, 220, 220)
        errLbl.TextSize = 13
        errLbl.Font = Enum.Font.RobotoMono
        errLbl.TextWrapped = true
        errLbl.TextXAlignment = Enum.TextXAlignment.Left
        errLbl.TextYAlignment = Enum.TextYAlignment.Top
        errLbl.Parent = scroll

        local closeBtn = Instance.new("TextButton")
        closeBtn.Size = UDim2.new(1, -16, 0, 26)
        closeBtn.Position = UDim2.new(0, 8, 1, -32)
        closeBtn.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
        closeBtn.Text = "Close"
        closeBtn.TextColor3 = Color3.new(1, 1, 1)
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = 13
        closeBtn.BorderSizePixel = 0
        closeBtn.Parent = box
        Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
        closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)
    end)
end
