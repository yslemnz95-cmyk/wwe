-- yslemEgg COMPLETE v4.0 | All Chilli Hub features + yslem optimizations
-- Auto-save, multi-tab UI, anti-guard, auto-everything

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local HttpService    = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp            = Players.LocalPlayer
local char          = lp.Character or lp.CharacterAdded:Wait()
local hrp           = char:WaitForChild("HumanoidRootPart")
local hum           = char:WaitForChild("Humanoid")

-- ─── Task tracker ──────────────────────────────────────────────────────────
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

-- ─── RemoteEvent / RemoteFunction helpers ──────────────────────────────────
local function _re(path)
    local obj = ReplicatedStorage
    for _, seg in ipairs(path:split("/")) do
        obj = obj:FindFirstChild(seg)
        if not obj then return nil end
    end
    return obj
end
local function _fireRE(path, ...)
    local r = _re(path)
    if r and r:IsA("RemoteEvent") then r:FireServer(...) end
end
local function _invokeRF(path, ...)
    local r = _re(path)
    if r and r:IsA("RemoteFunction") then
        local ok, res = pcall(r.InvokeServer, r, ...)
        if ok then return res end
    end
    return nil
end

-- ─── Settings (auto-saved) ─────────────────────────────────────────────────
local SAVE_KEY = "yslemEgg_v4_settings"
local DEFAULT_SETTINGS = {
    -- Farm tab
    autoSteal        = false,
    minRarity        = "common",
    minValue         = 0,
    waitGuardSleep   = true,
    antiGuard        = false,
    -- Place tab
    autoPlace        = false,
    placeRule        = "AfterSteal",  -- Always / StealIdle / AfterSteal / NightOnly
    -- Hatch tab
    autoHatch        = false,
    hatchMinRarity   = "common",
    -- Equip tab
    autoEquip        = false,
    -- Sell tab
    autoSell         = false,
    sellMinRarity    = "common",
    keepMutated      = true,
    -- Fuse tab
    autoFuse         = false,
    -- Favorite tab
    autoFav          = false,
    favMinRarity     = "legendary",
    -- Treadmill
    autoTreadmill    = false,
    -- Player tab
    speedBoost       = false,
    speedValue       = 50,
    infiniteJump     = false,
    invisibility     = false,
    antiRagdoll      = false,
    antiTrap         = false,
    instantPrompts   = false,
    godMode          = false,
    autoCombat       = false,
    -- Notifications
    notifications    = true,
    showStats        = true,
}

local S = {}
do
    local ok, raw = pcall(readfile, SAVE_KEY)
    if ok and raw and raw ~= "" then
        local ok2, parsed = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(parsed) == "table" then
            for k, v in pairs(DEFAULT_SETTINGS) do
                S[k] = (parsed[k] ~= nil) and parsed[k] or v
            end
        else
            for k, v in pairs(DEFAULT_SETTINGS) do S[k] = v end
        end
    else
        for k, v in pairs(DEFAULT_SETTINGS) do S[k] = v end
    end
end

local function _saveSettings()
    pcall(writefile, SAVE_KEY, HttpService:JSONEncode(S))
end

-- ─── Stats ─────────────────────────────────────────────────────────────────
local STATS = {
    totalEggs   = 0,
    totalValue  = 0,
    sessionStart= tick(),
    eggsPerMin  = 0,
    valuePerMin = 0,
    eggsByRarity= {},
    lastEggTime = 0,
}

-- ─── Rarity ordering ───────────────────────────────────────────────────────
local RARITY_ORDER = {
    common=1, uncommon=2, rare=3, epic=4,
    legendary=5, mythic=6, ancient=7, golden=8,
    secret=9, prismatic=10
}
local function _rarityVal(r) return RARITY_ORDER[r:lower()] or 1 end
local function _rarityPasses(r, minR)
    return _rarityVal(r) >= _rarityVal(minR)
end

-- ─── Notification ──────────────────────────────────────────────────────────
local _lastNotify = 0
local function _notify(title, msg)
    if not S.notifications then return end
    local now = tick()
    if now - _lastNotify < 0.3 then return end
    _lastNotify = now
    print(string.format("[%s] %s", title, msg))
    -- In-game notification via StarterGui if available
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = msg, Duration = 3
        })
    end)
end

-- ─── Egg scan / cache ──────────────────────────────────────────────────────
local _promptCache  = {}
local _cachedEggs   = {}
local _lastScanTime = 0
local _scanning     = false

local function _readLabels(obj)
    local tags, weight = {}, 0
    if not obj then return tags, weight end
    pcall(function()
        for _, lbl in ipairs(obj:GetDescendants()) do
            if lbl:IsA("BillboardGui") or lbl:IsA("TextLabel") then
                local t = lbl.Text or ""
                local rarity = t:lower():match("(common|uncommon|rare|epic|legendary|mythic|ancient|golden|secret|prismatic)")
                if rarity then table.insert(tags, rarity) end
            end
        end
    end)
    return tags, weight
end

local function _extractValue(obj)
    if not obj then return "", 0 end
    local txt, num = "", 0
    pcall(function()
        for _, lbl in ipairs(obj:GetDescendants()) do
            if lbl:IsA("TextLabel") then
                local t = lbl.Text or ""
                local n = t:match("%$([%d,%.]+[KMBkmb]?)")
                if n then
                    txt = n
                    local raw = n:gsub(",", "")
                    local mult = 1
                    if raw:sub(-1):lower() == "k" then mult = 1e3; raw = raw:sub(1,-2)
                    elseif raw:sub(-1):lower() == "m" then mult = 1e6; raw = raw:sub(1,-2)
                    elseif raw:sub(-1):lower() == "b" then mult = 1e9; raw = raw:sub(1,-2) end
                    num = (tonumber(raw) or 0) * mult
                end
            end
        end
    end)
    return txt, num
end

local function _promptOwnerModel(prompt)
    if not prompt or not prompt.Parent then return nil, nil end
    local part = prompt.Parent
    if not part or not part:IsA("BasePart") then return nil, nil end
    local model = part.Parent
    if model and model:IsA("Model") then return part, model end
    return part, nil
end

local function _scoreEgg(entry)
    local rv = _rarityVal(entry.rarity or "common")
    local val = entry.value or 0
    return rv * 1000 + val / 1e6
end

local function _doScan()
    if _scanning then return end
    _scanning = true
    local newCache = {}
    local eggs = {}
    pcall(function()
        for _, plot in ipairs(workspace:GetChildren()) do
            if plot.Name:lower():find("plot") or plot.Name:lower():find("egg") then
                for _, desc in ipairs(plot:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.ActionText:lower():find("steal") then
                        local part, model = _promptOwnerModel(desc)
                        if part then
                            local uid = tostring(desc)
                            newCache[uid] = {prompt=desc, part=part, model=model}
                            local tags = _readLabels(model or part)
                            local vtxt, vnum = _extractValue(model or part)
                            local rarity = tags[1] or "common"
                            local cat = (model and model.Name ~= "Model" and model.Name)
                                     or desc.ObjectText
                                     or part.Name
                            table.insert(eggs, {
                                uid    = uid,
                                prompt = desc,
                                part   = part,
                                pos    = part.Position,
                                cat    = cat,
                                rarity = rarity,
                                tags   = tags,
                                value  = vnum,
                                valueTxt = vtxt,
                            })
                        end
                    end
                end
            end
        end
    end)
    _promptCache = newCache
    table.sort(eggs, function(a,b) return _scoreEgg(a) > _scoreEgg(b) end)
    _cachedEggs = eggs
    _lastScanTime = tick()
    _scanning = false
end

-- ─── Teleport / Steal ──────────────────────────────────────────────────────
local _lastTpTime   = 0
local _tpCooldown   = 0.5
local _farmActive   = false
local _farmJustStole = false

local function _findNearest(pos)
    local best, bestDist = nil, 15
    for uid, data in pairs(_promptCache) do
        if data.prompt and data.prompt.Parent and data.part then
            local d = (data.part.Position - pos).Magnitude
            if d < bestDist then bestDist = d; best = data.prompt end
        end
    end
    return best
end

local function _firePrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    pcall(function()
        if S.instantPrompts then prompt.HoldDuration = 0 end
        local vpf = game:GetService("VirtualInputManager")
        if vpf then
            vpf:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        end
    end)
    -- Also try direct fire
    pcall(function()
        local pe = prompt.Parent and prompt.Parent:FindFirstChildOfClass("ProximityPrompt")
        if pe then
            fireproximityprompt(pe)
        else
            fireproximityprompt(prompt)
        end
    end)
    return true
end

local function _teleportTo(entry)
    if not entry or not entry.pos then return false end
    local now = tick()
    if now - _lastTpTime < _tpCooldown then return false end
    _lastTpTime = now
    char = lp.Character
    hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    hrp.CFrame = CFrame.new(entry.pos + Vector3.new(0, 3, 0))
    task.wait(0.15)
    local target = (entry.prompt and entry.prompt.Parent) and entry.prompt
                or _findNearest(hrp.Position)
    if target then
        _firePrompt(target)
        return true
    end
    return false
end

local function _updateStats(entry)
    if not entry then return end
    STATS.totalEggs  += 1
    STATS.totalValue += (entry.value or 0)
    local r = entry.rarity or "common"
    STATS.eggsByRarity[r] = (STATS.eggsByRarity[r] or 0) + 1
    STATS.lastEggTime = tick()
    _notify("FARM", string.format("Egg: %s (%s) +$%s", entry.cat or "?", r, entry.valueTxt or "?"))
end

-- ─── Guard detection ───────────────────────────────────────────────────────
local function _guardNearby(pos)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local gh = p.Character:FindFirstChild("HumanoidRootPart")
            if gh and (gh.Position - pos).Magnitude < 20 then
                -- Check if named "Guard" or NPC pattern
                local name = p.Name:lower()
                if name:find("guard") or name:find("npc") or name:find("cop") then
                    return true, p
                end
            end
        end
    end
    -- Also check NPC models
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name:lower():find("guard") then
            local root = obj:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - pos).Magnitude < 20 then
                return true, obj
            end
        end
    end
    return false, nil
end

local function _hitGuard(guardObj)
    if not guardObj then return end
    pcall(function()
        _fireRE("RE/BatSwing/Trigger", guardObj)
    end)
end

-- ─── Anti-Trap ─────────────────────────────────────────────────────────────
local _antiTrapConn
local function _startAntiTrap()
    if _antiTrapConn then _antiTrapConn:Disconnect() end
    _antiTrapConn = workspace.DescendantAdded:Connect(function(obj)
        if obj.Name:lower():find("trap") or obj.Name:lower():find("cage") then
            pcall(function() obj.CanTouch = false end)
            pcall(function()
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("BasePart") then d.CanTouch = false end
                end
            end)
        end
    end)
end
local function _stopAntiTrap()
    if _antiTrapConn then _antiTrapConn:Disconnect(); _antiTrapConn = nil end
end

-- ─── Anti-Ragdoll ──────────────────────────────────────────────────────────
local _ragdollConn
local function _startAntiRagdoll()
    if _ragdollConn then _ragdollConn:Disconnect() end
    _ragdollConn = RunService.Heartbeat:Connect(function()
        char = lp.Character
        if not char then return end
        for _, c in ipairs(char:GetDescendants()) do
            if c:IsA("BallSocketConstraint") or c:IsA("HingeConstraint") then
                pcall(function() c:Destroy() end)
            end
            if c:IsA("Motor6D") and not c.Enabled then
                c.Enabled = true
            end
        end
    end)
end
local function _stopAntiRagdoll()
    if _ragdollConn then _ragdollConn:Disconnect(); _ragdollConn = nil end
end

-- ─── Instant Prompts ───────────────────────────────────────────────────────
local function _applyInstantPrompts()
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") then
            p.HoldDuration = 0
        end
    end
    workspace.DescendantAdded:Connect(function(p)
        if p:IsA("ProximityPrompt") then
            p.HoldDuration = 0
        end
    end)
end

-- ─── Speed Boost ───────────────────────────────────────────────────────────
local _speedConn
local function _startSpeedBoost()
    if _speedConn then _speedConn:Disconnect() end
    _speedConn = RunService.Heartbeat:Connect(function()
        char = lp.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = S.speedValue end
    end)
end
local function _stopSpeedBoost()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    pcall(function()
        hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end)
end

-- ─── Infinite Jump ─────────────────────────────────────────────────────────
local _jumpConn
local function _startInfiniteJump()
    if _jumpConn then _jumpConn:Disconnect() end
    _jumpConn = UserInputService.JumpRequest:Connect(function()
        char = lp.Character
        hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function _stopInfiniteJump()
    if _jumpConn then _jumpConn:Disconnect(); _jumpConn = nil end
end

-- ─── Invisibility ──────────────────────────────────────────────────────────
local function _goInvisible()
    _fireRE("RE/RigSync/AskRigWipe")
    pcall(function()
        char = lp.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                p.Transparency = 1
            end
        end
    end)
end
local function _goVisible()
    pcall(function()
        char = lp.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                p.Transparency = 0
            end
        end
    end)
end

-- ─── God Mode ──────────────────────────────────────────────────────────────
local _godConn
local function _startGodMode()
    if _godConn then _godConn:Disconnect() end
    _godConn = RunService.Heartbeat:Connect(function()
        char = lp.Character
        hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = hum.MaxHealth end
    end)
end
local function _stopGodMode()
    if _godConn then _godConn:Disconnect(); _godConn = nil end
end

-- ─── Auto Combat ───────────────────────────────────────────────────────────
local _combatConn
local function _startAutoCombat()
    if _combatConn then _combatConn:Disconnect() end
    _combatConn = RunService.Heartbeat:Connect(function()
        char = lp.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                local ph = p.Character:FindFirstChild("HumanoidRootPart")
                if ph and (ph.Position - hrp.Position).Magnitude < 10 then
                    _fireRE("RE/BatSwing/Trigger", p.Character)
                end
            end
        end
    end)
end
local function _stopAutoCombat()
    if _combatConn then _combatConn:Disconnect(); _combatConn = nil end
end

-- ─── Auto Hatch ────────────────────────────────────────────────────────────
local function _doAutoHatch()
    local eggs = _invokeRF("RF/EggWorld/AskHatch") or {}
    for _, egg in ipairs(eggs) do
        local rarity = (egg.tags and egg.tags[1]) or "common"
        if _rarityPasses(rarity, S.hatchMinRarity) then
            _invokeRF("RF/EggWorld/AskFinishHatch", egg.id or egg)
            task.wait(0.5)
        end
    end
end

-- ─── Auto Equip Best ───────────────────────────────────────────────────────
local function _doAutoEquip()
    _invokeRF("RF/Haul/WearBest")
end

-- ─── Auto Sell ─────────────────────────────────────────────────────────────
local SELL_BATCH = 50
local function _doAutoSell()
    local pets = _invokeRF("RF/PetSatchel/ReadPets") or {}
    local toSell = {}
    for _, pet in ipairs(pets) do
        local rarity = (pet.tags and pet.tags[1]) or pet.rarity or "common"
        local isMutated = pet.mutated or false
        if S.keepMutated and isMutated then
            -- skip
        elseif _rarityPasses(rarity, S.sellMinRarity) then
            -- skip (above threshold, keep)
        else
            table.insert(toSell, pet.id or pet)
            if #toSell >= SELL_BATCH then
                _fireRE("RE/PetSatchel/SellSelection", toSell)
                toSell = {}
                task.wait(0.3)
            end
        end
    end
    if #toSell > 0 then
        _fireRE("RE/PetSatchel/SellSelection", toSell)
    end
end

-- ─── Auto Fuse ─────────────────────────────────────────────────────────────
local function _doAutoFuse()
    local pets = _invokeRF("RF/PetSatchel/ReadPets") or {}
    local byKind = {}
    for _, pet in ipairs(pets) do
        local k = pet.kind or pet.cat or pet.name or tostring(pet)
        if not byKind[k] then byKind[k] = {} end
        table.insert(byKind[k], pet.id or pet)
    end
    for kind, ids in pairs(byKind) do
        if #ids >= 3 then
            local slots = {ids[1], ids[2], ids[3]}
            for i, id in ipairs(slots) do
                _invokeRF("RF/Fusery/LoadPet", i, id)
                task.wait(0.1)
            end
            _invokeRF("RF/Fusery/BeginFuse")
            task.wait(1)
            _invokeRF("RF/Fusery/Finishaide")
            task.wait(0.3)
        end
    end
end

-- ─── Auto Favorite ─────────────────────────────────────────────────────────
local FAV_BATCH = 25
local function _doAutoFav()
    local pets = _invokeRF("RF/PetSatchel/ReadPets") or {}
    local toFav = {}
    for _, pet in ipairs(pets) do
        local rarity = (pet.tags and pet.tags[1]) or pet.rarity or "common"
        if _rarityPasses(rarity, S.favMinRarity) then
            table.insert(toFav, pet.id or pet)
            if #toFav >= FAV_BATCH then
                _fireRE("RE/PetSatchel/WriteFavourite", toFav)
                toFav = {}
                task.wait(0.3)
            end
        end
    end
    if #toFav > 0 then
        _fireRE("RE/PetSatchel/WriteFavourite", toFav)
    end
end

-- ─── Auto Place Egg ────────────────────────────────────────────────────────
local function _doAutoPlace(entry)
    if not entry then return end
    _invokeRF("RF/EggWorld/AskPlaceEgg", entry.id or entry)
end

-- ─── Auto Treadmill ────────────────────────────────────────────────────────
local function _doAutoTreadmill()
    _invokeRF("RF/Treadmill/AskWearStill")
end

-- ─── Farm loop ─────────────────────────────────────────────────────────────
local function _farmLoop()
    while _farmActive do
        _doScan()
        if #_cachedEggs == 0 then
            task.wait(1)
        else
            local entry = nil
            for _, e in ipairs(_cachedEggs) do
                if _rarityPasses(e.rarity, S.minRarity) and e.value >= S.minValue then
                    entry = e
                    break
                end
            end
            if entry then
                local guardNear, guardObj = _guardNearby(entry.pos)
                if guardNear and S.waitGuardSleep then
                    task.wait(2)
                elseif guardNear and S.antiGuard then
                    _hitGuard(guardObj)
                    task.wait(0.5)
                else
                    local ok = _teleportTo(entry)
                    if ok then
                        _updateStats(entry)
                        _farmJustStole = true
                        if S.autoPlace then
                            task.wait(0.5)
                            _doAutoPlace(entry)
                        end
                    end
                    task.wait(0.75)
                end
            else
                task.wait(1)
            end
        end
    end
end

-- ─── One-shot teleport ─────────────────────────────────────────────────────
local function _oneTP()
    _doScan()
    if #_cachedEggs > 0 then
        local entry = _cachedEggs[1]
        _teleportTo(entry)
        _updateStats(entry)
    else
        _notify("TP", "No eggs found")
    end
end

-- ─── UI ────────────────────────────────────────────────────────────────────
local UI_W, UI_H = 340, 460
local GREEN  = Color3.fromRGB(80, 220, 100)
local RED    = Color3.fromRGB(220, 80, 80)
local ORANGE = Color3.fromRGB(255, 165, 0)
local YELLOW = Color3.fromRGB(255, 200, 87)
local BG     = Color3.fromRGB(18, 18, 24)
local BG2    = Color3.fromRGB(28, 28, 36)
local BG3    = Color3.fromRGB(38, 38, 50)
local TEXT   = Color3.fromRGB(230, 230, 230)
local DIM    = Color3.fromRGB(130, 130, 150)
local ACCENT = Color3.fromRGB(70, 180, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "yslemEggUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = lp.PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, UI_W, 0, UI_H)
main.Position = UDim2.new(0.5, -UI_W/2, 0.35, -UI_H/2)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = BG2
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡ YSLEM HUB v4.0 ⚡"
title.TextColor3 = ACCENT
title.TextSize = 15
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundColor3 = RED
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Tab buttons
local TAB_NAMES = {"Farm", "Player", "Auto", "Stats"}
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -12, 0, 28)
tabFrame.Position = UDim2.new(0, 6, 0, 40)
tabFrame.BackgroundTransparency = 1
tabFrame.Parent = main

local tabBtns = {}
local tabPanels = {}
local activeTab = "Farm"

for i, name in ipairs(TAB_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1/#TAB_NAMES, -4, 1, 0)
    btn.Position = UDim2.new((i-1)/#TAB_NAMES, 2, 0, 0)
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
    panel.Size = UDim2.new(1, -12, 1, -80)
    panel.Position = UDim2.new(0, 6, 0, 72)
    panel.BackgroundTransparency = 1
    panel.ScrollBarThickness = 3
    panel.ScrollBarImageColor3 = ACCENT
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
    activeTab = name
    for n, p in pairs(tabPanels) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        b.TextColor3 = (n == name) and ACCENT or DIM
        b.BackgroundColor3 = (n == name) and BG2 or BG3
    end
end
for name, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() _switchTab(name) end)
end

-- UI Helper functions
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
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = f
    return f
end

local function _cardTitle(parent, text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = ACCENT
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

local function _toggle(parent, text, settingKey, order, onChange)
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
        local on = S[settingKey]
        btn.BackgroundColor3 = on and GREEN or BG3
        btn.TextColor3 = on and Color3.new(0,0,0) or DIM
        btn.Text = on and "ON" or "OFF"
    end
    _refresh()

    btn.MouseButton1Click:Connect(function()
        S[settingKey] = not S[settingKey]
        _refresh()
        _saveSettings()
        if onChange then onChange(S[settingKey]) end
    end)

    return row, btn
end

local function _sliderRow(parent, text, settingKey, minV, maxV, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text .. ": " .. tostring(S[settingKey])
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
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    local function _updateSlider()
        local pct = (S[settingKey] - minV) / (maxV - minV)
        fill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
        lbl.Text = text .. ": " .. tostring(S[settingKey])
    end
    _updateSlider()

    local dragging = false
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            _saveSettings()
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = track.AbsolutePosition
            local size = track.AbsoluteSize
            local rel = math.clamp((inp.Position.X - pos.X) / size.X, 0, 1)
            S[settingKey] = math.floor(minV + rel * (maxV - minV))
            _updateSlider()
        end
    end)

    return row
end

local function _rarityDropdown(parent, text, settingKey, order)
    local rarities = {"common","uncommon","rare","epic","legendary","mythic","ancient","golden","secret","prismatic"}
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.55, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = TEXT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.42, 0, 1, 0)
    btn.Position = UDim2.new(0.57, 0, 0, 0)
    btn.BackgroundColor3 = BG3
    btn.Text = S[settingKey]
    btn.TextColor3 = YELLOW
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        local cur = S[settingKey]
        local idx = 1
        for i, r in ipairs(rarities) do
            if r == cur then idx = i; break end
        end
        idx = (idx % #rarities) + 1
        S[settingKey] = rarities[idx]
        btn.Text = rarities[idx]
        _saveSettings()
    end)
    return row
end

-- ═══════════════════════════════════════════════════════════════════
-- FARM TAB
-- ═══════════════════════════════════════════════════════════════════
local farmPanel = tabPanels["Farm"]

-- Quick actions card
local quickCard = _card(farmPanel, 1)
_cardTitle(quickCard, "⚡ QUICK ACTIONS", 1)

local oneTpBtn = Instance.new("TextButton")
oneTpBtn.Size = UDim2.new(1, 0, 0, 28)
oneTpBtn.BackgroundColor3 = ACCENT
oneTpBtn.Text = "ONE TELEPORT"
oneTpBtn.TextColor3 = Color3.new(0,0,0)
oneTpBtn.TextSize = 13
oneTpBtn.Font = Enum.Font.GothamBold
oneTpBtn.BorderSizePixel = 0
oneTpBtn.LayoutOrder = 2
oneTpBtn.Parent = quickCard
Instance.new("UICorner", oneTpBtn).CornerRadius = UDim.new(0, 6)
oneTpBtn.MouseButton1Click:Connect(_oneTP)

local farmBtn = Instance.new("TextButton")
farmBtn.Size = UDim2.new(1, 0, 0, 28)
farmBtn.BackgroundColor3 = GREEN
farmBtn.Text = "▶ FARM LOOP"
farmBtn.TextColor3 = Color3.new(0,0,0)
farmBtn.TextSize = 13
farmBtn.Font = Enum.Font.GothamBold
farmBtn.BorderSizePixel = 0
farmBtn.LayoutOrder = 3
farmBtn.Parent = quickCard
Instance.new("UICorner", farmBtn).CornerRadius = UDim.new(0, 6)
farmBtn.MouseButton1Click:Connect(function()
    _farmActive = not _farmActive
    if _farmActive then
        farmBtn.Text = "⏹ STOP FARM"
        farmBtn.BackgroundColor3 = RED
        S.autoSteal = true
        _spawnTracked(_farmLoop)
    else
        farmBtn.Text = "▶ FARM LOOP"
        farmBtn.BackgroundColor3 = GREEN
        S.autoSteal = false
    end
end)

-- Egg list card
local eggListCard = _card(farmPanel, 2)
_cardTitle(eggListCard, "🥚 DETECTED EGGS", 1)
local eggCountLbl = _label(eggListCard, "Scanning...", DIM, 2)
local eggListItems = {}

local function _refreshEggList()
    for _, c in ipairs(eggListItems) do c:Destroy() end
    eggListItems = {}
    local shown = 0
    for i, e in ipairs(_cachedEggs) do
        if shown >= 8 then break end
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BackgroundColor3 = BG3
        row.BorderSizePixel = 0
        row.LayoutOrder = i + 2
        row.Parent = eggListCard
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(0.6, 0, 1, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = (e.cat or "?"):sub(1, 18)
        nameLbl.TextColor3 = TEXT
        nameLbl.TextSize = 10
        nameLbl.Font = Enum.Font.Gotham
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.Parent = row

        local rarLbl = Instance.new("TextLabel")
        rarLbl.Size = UDim2.new(0.4, 0, 1, 0)
        rarLbl.Position = UDim2.new(0.6, 0, 0, 0)
        rarLbl.BackgroundTransparency = 1
        rarLbl.Text = (e.rarity or "?") .. " $" .. (e.valueTxt or "0")
        rarLbl.TextColor3 = YELLOW
        rarLbl.TextSize = 10
        rarLbl.Font = Enum.Font.GothamBold
        rarLbl.TextXAlignment = Enum.TextXAlignment.Right
        rarLbl.Parent = row

        local entry = e
        row.MouseButton1Click:Connect(function()
            _teleportTo(entry)
            _updateStats(entry)
        end)

        table.insert(eggListItems, row)
        shown += 1
    end
    eggCountLbl.Text = #_cachedEggs .. " eggs available"
end

-- Farm settings card
local farmSetCard = _card(farmPanel, 3)
_cardTitle(farmSetCard, "⚙️ FARM SETTINGS", 1)
_rarityDropdown(farmSetCard, "Min Rarity", "minRarity", 2)
_toggle(farmSetCard, "Wait for Guard Sleep", "waitGuardSleep", 3)
_toggle(farmSetCard, "Anti-Guard (Hit)", "antiGuard", 4)
_toggle(farmSetCard, "Instant Prompts", "instantPrompts", 5, function(on)
    if on then _applyInstantPrompts() end
end)

-- ═══════════════════════════════════════════════════════════════════
-- PLAYER TAB
-- ═══════════════════════════════════════════════════════════════════
local playerPanel = tabPanels["Player"]

local movCard = _card(playerPanel, 1)
_cardTitle(movCard, "🏃 MOVEMENT", 1)
_toggle(movCard, "Speed Boost", "speedBoost", 2, function(on)
    if on then _startSpeedBoost() else _stopSpeedBoost() end
end)
_sliderRow(movCard, "Speed", "speedValue", 16, 500, 3)
_toggle(movCard, "Infinite Jump", "infiniteJump", 4, function(on)
    if on then _startInfiniteJump() else _stopInfiniteJump() end
end)

local charCard = _card(playerPanel, 2)
_cardTitle(charCard, "🛡️ CHARACTER", 1)
_toggle(charCard, "God Mode", "godMode", 2, function(on)
    if on then _startGodMode() else _stopGodMode() end
end)
_toggle(charCard, "Invisibility", "invisibility", 3, function(on)
    if on then _goInvisible() else _goVisible() end
end)
_toggle(charCard, "Anti-Ragdoll", "antiRagdoll", 4, function(on)
    if on then _startAntiRagdoll() else _stopAntiRagdoll() end
end)
_toggle(charCard, "Anti-Trap", "antiTrap", 5, function(on)
    if on then _startAntiTrap() else _stopAntiTrap() end
end)
_toggle(charCard, "Auto Combat", "autoCombat", 6, function(on)
    if on then _startAutoCombat() else _stopAutoCombat() end
end)

-- ═══════════════════════════════════════════════════════════════════
-- AUTO TAB
-- ═══════════════════════════════════════════════════════════════════
local autoPanel = tabPanels["Auto"]

local hatchCard = _card(autoPanel, 1)
_cardTitle(hatchCard, "🐣 AUTO HATCH", 1)
_toggle(hatchCard, "Auto Hatch", "autoHatch", 2)
_rarityDropdown(hatchCard, "Min Rarity", "hatchMinRarity", 3)

local equipCard = _card(autoPanel, 2)
_cardTitle(equipCard, "🎒 AUTO EQUIP", 1)
_toggle(equipCard, "Auto Equip Best", "autoEquip", 2)
local equipNowBtn = Instance.new("TextButton")
equipNowBtn.Size = UDim2.new(1, 0, 0, 22)
equipNowBtn.BackgroundColor3 = BG3
equipNowBtn.Text = "Equip Best Now"
equipNowBtn.TextColor3 = ACCENT
equipNowBtn.TextSize = 11
equipNowBtn.Font = Enum.Font.GothamBold
equipNowBtn.BorderSizePixel = 0
equipNowBtn.LayoutOrder = 3
equipNowBtn.Parent = equipCard
Instance.new("UICorner", equipNowBtn).CornerRadius = UDim.new(0, 6)
equipNowBtn.MouseButton1Click:Connect(_doAutoEquip)

local sellCard = _card(autoPanel, 3)
_cardTitle(sellCard, "💰 AUTO SELL", 1)
_toggle(sellCard, "Auto Sell", "autoSell", 2)
_rarityDropdown(sellCard, "Sell Below", "sellMinRarity", 3)
_toggle(sellCard, "Keep Mutated", "keepMutated", 4)
local sellNowBtn = Instance.new("TextButton")
sellNowBtn.Size = UDim2.new(1, 0, 0, 22)
sellNowBtn.BackgroundColor3 = BG3
sellNowBtn.Text = "Sell Now"
sellNowBtn.TextColor3 = GREEN
sellNowBtn.TextSize = 11
sellNowBtn.Font = Enum.Font.GothamBold
sellNowBtn.BorderSizePixel = 0
sellNowBtn.LayoutOrder = 5
sellNowBtn.Parent = sellCard
Instance.new("UICorner", sellNowBtn).CornerRadius = UDim.new(0, 6)
sellNowBtn.MouseButton1Click:Connect(_doAutoSell)

local fuseCard = _card(autoPanel, 4)
_cardTitle(fuseCard, "🔮 AUTO FUSE", 1)
_toggle(fuseCard, "Auto Fuse", "autoFuse", 2)
local fuseNowBtn = Instance.new("TextButton")
fuseNowBtn.Size = UDim2.new(1, 0, 0, 22)
fuseNowBtn.BackgroundColor3 = BG3
fuseNowBtn.Text = "Fuse Now"
fuseNowBtn.TextColor3 = ORANGE
fuseNowBtn.TextSize = 11
fuseNowBtn.Font = Enum.Font.GothamBold
fuseNowBtn.BorderSizePixel = 0
fuseNowBtn.LayoutOrder = 3
fuseNowBtn.Parent = fuseCard
Instance.new("UICorner", fuseNowBtn).CornerRadius = UDim.new(0, 6)
fuseNowBtn.MouseButton1Click:Connect(_doAutoFuse)

local favCard = _card(autoPanel, 5)
_cardTitle(favCard, "⭐ AUTO FAVORITE", 1)
_toggle(favCard, "Auto Favorite", "autoFav", 2)
_rarityDropdown(favCard, "Fav Min Rarity", "favMinRarity", 3)

local placeCard = _card(autoPanel, 6)
_cardTitle(placeCard, "🏠 AUTO PLACE", 1)
_toggle(placeCard, "Auto Place", "autoPlace", 2)

local treadCard = _card(autoPanel, 7)
_cardTitle(treadCard, "🏃 AUTO TREADMILL", 1)
_toggle(treadCard, "Auto Treadmill", "autoTreadmill", 2)
local treadNowBtn = Instance.new("TextButton")
treadNowBtn.Size = UDim2.new(1, 0, 0, 22)
treadNowBtn.BackgroundColor3 = BG3
treadNowBtn.Text = "Treadmill Now"
treadNowBtn.TextColor3 = YELLOW
treadNowBtn.TextSize = 11
treadNowBtn.Font = Enum.Font.GothamBold
treadNowBtn.BorderSizePixel = 0
treadNowBtn.LayoutOrder = 3
treadNowBtn.Parent = treadCard
Instance.new("UICorner", treadNowBtn).CornerRadius = UDim.new(0, 6)
treadNowBtn.MouseButton1Click:Connect(_doAutoTreadmill)

-- ═══════════════════════════════════════════════════════════════════
-- STATS TAB
-- ═══════════════════════════════════════════════════════════════════
local statsPanel = tabPanels["Stats"]

local statsCard = _card(statsPanel, 1)
_cardTitle(statsCard, "📊 SESSION STATS", 1)
local totalEggsLbl  = _label(statsCard, "Total Eggs: 0", TEXT, 2)
local totalValueLbl = _label(statsCard, "Total Value: $0", GREEN, 3)
local sessionLbl    = _label(statsCard, "Session: 0m", YELLOW, 4)
local rateLbl       = _label(statsCard, "Rate: 0 eggs/min", DIM, 5)
local bestEggLbl    = _label(statsCard, "Best Egg: None", ACCENT, 6)

local rarityCard = _card(statsPanel, 2)
_cardTitle(rarityCard, "🎯 BY RARITY", 1)
local rarityLabels = {}
for _, r in ipairs({"common","uncommon","rare","epic","legendary","mythic","ancient","golden","secret","prismatic"}) do
    rarityLabels[r] = _label(rarityCard, r .. ": 0", DIM, 0)
end

local notifCard = _card(statsPanel, 3)
_cardTitle(notifCard, "🔔 SETTINGS", 1)
_toggle(notifCard, "Notifications", "notifications", 2)
_toggle(notifCard, "Show Stats", "showStats", 3)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, 0, 0, 22)
resetBtn.BackgroundColor3 = RED
resetBtn.Text = "Reset Stats"
resetBtn.TextColor3 = Color3.new(1,1,1)
resetBtn.TextSize = 11
resetBtn.Font = Enum.Font.GothamBold
resetBtn.BorderSizePixel = 0
resetBtn.LayoutOrder = 4
resetBtn.Parent = notifCard
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)
resetBtn.MouseButton1Click:Connect(function()
    STATS.totalEggs = 0
    STATS.totalValue = 0
    STATS.eggsByRarity = {}
    STATS.sessionStart = tick()
end)

-- ─── Update loops ──────────────────────────────────────────────────────────

-- Scan loop
_spawnTracked(function()
    while true do
        _doScan()
        task.wait(0.75)
    end
end)

-- UI refresh loop
_spawnTracked(function()
    while true do
        task.wait(1)
        -- Refresh egg list
        _refreshEggList()

        -- Refresh stats
        local elapsed = tick() - STATS.sessionStart
        local minutes = math.max(elapsed / 60, 0.01)
        local epmin = STATS.totalEggs / minutes
        local vpmin = STATS.totalValue / minutes

        totalEggsLbl.Text = "Total Eggs: " .. STATS.totalEggs
        totalValueLbl.Text = string.format("Total Value: $%.2fM", STATS.totalValue / 1e6)
        sessionLbl.Text = string.format("Session: %dm | %d eggs available",
            math.floor(minutes), #_cachedEggs)
        rateLbl.Text = string.format("Rate: %.1f eggs/min | $%.1fM/min", epmin, vpmin/1e6)

        -- Best egg
        if #_cachedEggs > 0 then
            local b = _cachedEggs[1]
            bestEggLbl.Text = string.format("Best: %s (%s) $%s", b.cat or "?", b.rarity or "?", b.valueTxt or "0")
        end

        -- Rarity breakdown
        for r, lbl in pairs(rarityLabels) do
            lbl.Text = r .. ": " .. (STATS.eggsByRarity[r] or 0)
            lbl.TextColor3 = (STATS.eggsByRarity[r] or 0) > 0 and TEXT or DIM
        end
    end
end)

-- Auto actions loop
_spawnTracked(function()
    while true do
        task.wait(3)
        if S.autoHatch    then _doAutoHatch() end
        if S.autoEquip    then _doAutoEquip() end
        if S.autoSell     then _doAutoSell() end
        if S.autoFuse     then _doAutoFuse() end
        if S.autoFav      then _doAutoFav() end
        if S.autoTreadmill then _doAutoTreadmill() end
    end
end)

-- Apply saved state for player features
if S.speedBoost    then _startSpeedBoost() end
if S.infiniteJump  then _startInfiniteJump() end
if S.godMode       then _startGodMode() end
if S.antiRagdoll   then _startAntiRagdoll() end
if S.antiTrap      then _startAntiTrap() end
if S.autoCombat    then _startAutoCombat() end
if S.instantPrompts then _applyInstantPrompts() end
if S.invisibility  then _goInvisible() end

-- Close handler
closeBtn.MouseButton1Click:Connect(function()
    _farmActive = false
    _killAll()
    if _antiTrapConn then _antiTrapConn:Disconnect() end
    if _ragdollConn   then _ragdollConn:Disconnect() end
    if _speedConn     then _speedConn:Disconnect() end
    if _jumpConn      then _jumpConn:Disconnect() end
    if _godConn       then _godConn:Disconnect() end
    if _combatConn    then _combatConn:Disconnect() end
    _stopSpeedBoost()
    _saveSettings()
    gui:Destroy()
end)

-- Character respawn handler
lp.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp  = newChar:WaitForChild("HumanoidRootPart")
    hum  = newChar:WaitForChild("Humanoid")
    task.wait(0.5)
    if S.speedBoost    then _startSpeedBoost() end
    if S.infiniteJump  then _startInfiniteJump() end
    if S.godMode       then _startGodMode() end
    if S.antiRagdoll   then _startAntiRagdoll() end
    if S.invisibility  then _goInvisible() end
    if S.instantPrompts then _applyInstantPrompts() end
end)

_notify("yslemEgg", "v4.0 COMPLETE loaded — All features active!")
print("[yslemEgg v4.0 COMPLETE] Loaded — Farm, AntiGuard, AutoAll, Stats, AutoSave")
