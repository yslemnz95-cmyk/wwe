local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local guiParent = nil
pcall(function()
    if typeof(gethui) == "function" then
        local h = gethui()
        if typeof(h) == "Instance" then guiParent = h end
    end
end)
if not guiParent then
    pcall(function() guiParent = game:GetService("CoreGui") end)
end
if not guiParent then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end

local FOLDER_NAME = "RenderedEggs"
local EGG_OFFSET = Vector3.new(0, 2, 0)
local EGGS_TO_SHOW = 5
local REFRESH_TIME = 1.5
local ROW_HEIGHT = 34
local ROW_GAP = 2
local LIST_HEIGHT = EGGS_TO_SHOW * ROW_HEIGHT + (EGGS_TO_SHOW - 1) * ROW_GAP
local VOLCANO_HOVER = Vector3.new(-5103, 41465, -3490)
local LOGO_ID = "rbxassetid://130258290579194"
local DISCORD_TEXT = "discord.gg/Q7Q6mGbcg8"
local WAYPOINT_WAIT = 0.18

-- vol final vers le plot : 700% de la vitesse de marche, a 40 studs au-dessus du plot
local FLY_FRACTION = 7
local FLY_HEIGHT = 40
local DROP_SIDE_MARGIN = 25

local VOLCANO_PATH = {
    Vector3.new(-4920.68, 41284.93, -3701.18),
    Vector3.new(-4947.31, 41274.73, -3675.38),
    Vector3.new(-5105.09, 41249.06, -3517.70),
    Vector3.new(-5110.03, 41156.23, -3517.93),
    Vector3.new(-5162.28, 41153.67, -3593.98),
    Vector3.new(-5246.20, 41138.63, -3568.38),
    Vector3.new(-5262.41, 41147.28, -3584.27),
    Vector3.new(-5262.41, 41041.91, -3584.27),
    Vector3.new(-5267.18, 41036.93, -3672.98),
    Vector3.new(-5162.87, 41037.66, -3626.96),
    Vector3.new(-5123.74, 41037.74, -3498.45),
    Vector3.new(-4986.11, 41052.28, -3404.48),
    Vector3.new(-4903.67, 41023.70, -3438.91),
    Vector3.new(-4912.29, 40978.33, -3546.03),
    Vector3.new(-5011.79, 40935.81, -3647.93),
    Vector3.new(-5092.64, 40926.96, -3670.55),
    Vector3.new(-5250.27, 40911.21, -3658.40),
    Vector3.new(-5320.89, 40912.45, -3570.67),
}

local EGGS_DATA = {}
pcall(function()
    local gd = ReplicatedStorage:WaitForChild("GameData", 10)
    if gd then
        local eg = gd:WaitForChild("Eggs", 10)
        if eg then EGGS_DATA = require(eg) end
    end
end)
if type(EGGS_DATA) ~= "table" then EGGS_DATA = {} end

-- =====================================================================
-- etat (le drapeau d'arret n'est remis a zero qu'au debut d'un trajet)
-- =====================================================================
local running = false
local stopFlag = false
local autoDip = false
local statusSetter = function(_) end -- remplace plus bas par le vrai label

local function setStatus(text)
    pcall(statusSetter, text)
end

-- =====================================================================
-- deplacement
-- =====================================================================
local function getRoot()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c:FindFirstChildOfClass("Humanoid")
end

local function zeroVelocity(hrp)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function tpToPos(pos)
    local hrp = getRoot()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(pos)
    zeroVelocity(hrp)
    return true
end

local function tpToObj(obj, offset)
    local hrp = getRoot()
    if not hrp then return false end
    if not obj or not obj.Parent then return false end
    local cf
    if obj:IsA("BasePart") then
        cf = obj.CFrame
    elseif obj:IsA("Model") then
        local ok, c = pcall(function() return obj:GetPivot() end)
        if ok then cf = c end
    end
    if not cf then return false end
    if offset then hrp.CFrame = cf + offset else hrp.CFrame = cf end
    zeroVelocity(hrp)
    return true
end

-- Les valeurs CanCollide d'origine sont memorisees et restaurees EXACTEMENT
-- (tout remettre a true bloquait les membres dans le sol apres un vol).
local savedCollide = {}

local function setNoclip(state)
    local c = LocalPlayer.Character
    if not c then return end
    if state then
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then
                if savedCollide[d] == nil then savedCollide[d] = d.CanCollide end
                d.CanCollide = false
            end
        end
    else
        for part, original in pairs(savedCollide) do
            if part and part.Parent then part.CanCollide = original end
        end
        savedCollide = {}
    end
end

-- Rend la main au joueur : plus de noclip, plus de PlatformStand, vitesse nulle,
-- etat de marche retabli.
local function restoreControl()
    setNoclip(false)
    local hum = getHum()
    local hrp = getRoot()
    if hum then
        hum.PlatformStand = false
        pcall(function() hum:Move(Vector3.new(0, 0, 0), false) end)
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
            or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.PlatformStanding then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end
    if hrp then zeroVelocity(hrp) end
end

-- =====================================================================
-- oeufs : luck, image, prompt
-- =====================================================================
local function parseLuck(txt)
    if not txt then return 0 end
    local cleaned = tostring(txt):upper():gsub("%s", ""):gsub(",", "")
    local num, suf = cleaned:match("([%d%.]+)([KMBTQ]?)")
    if not num then return 0 end
    local n = tonumber(num) or 0
    if suf == "K" then return n * 1e3 end
    if suf == "M" then return n * 1e6 end
    if suf == "B" then return n * 1e9 end
    if suf == "T" then return n * 1e12 end
    if suf == "Q" then return n * 1e15 end
    return n
end

local function formatLuck(v)
    if v >= 1e15 then return string.format("%.1fQ", v / 1e15) end
    if v >= 1e12 then return string.format("%.1fT", v / 1e12) end
    if v >= 1e9  then return string.format("%.1fB", v / 1e9) end
    if v >= 1e6  then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3  then return string.format("%.1fK", v / 1e3) end
    return tostring(math.floor(v))
end

local function eggKeyName(egg)
    if not egg then return "" end
    local a = egg:GetAttribute("Egg")
    if type(a) == "string" and a ~= "" then return a end
    local n = tostring(egg.Name)
    n = n:gsub("%s*%[[^%]]+%]%s*$", "")
    n = n:gsub("%s*%([^%)]*%)%s*$", "")
    return n
end

local function eggDataFor(name)
    if type(EGGS_DATA) ~= "table" or name == "" then return nil end
    local d = EGGS_DATA[name]
    if type(d) ~= "table" then
        local lower = string.lower(name)
        for k, v in pairs(EGGS_DATA) do
            if string.lower(tostring(k)) == lower then d = v break end
        end
    end
    if type(d) == "table" then return d end
    return nil
end

local function eggImage(egg)
    if not egg then return "" end
    local d = eggDataFor(eggKeyName(egg))
    if not d then return "" end
    local img = d.Image
    if type(img) == "number" then
        return "rbxassetid://" .. tostring(img)
    elseif type(img) == "string" and img ~= "" then
        if string.find(img, "rbxassetid://", 1, true) or string.find(img, "rbxasset://", 1, true) then
            return img
        end
        return "rbxassetid://" .. img
    end
    return ""
end

local function dataLuck(name)
    local d = eggDataFor(name)
    if d then
        local l = tonumber(d.Luck)
        if l and l > 0 then return l end
    end
    return nil
end

local function eggLuck(egg)
    if not egg then return 0 end
    local h = egg:FindFirstChild("Handle")
    if h then
        local el = h:FindFirstChild("EggLuck")
        if el then
            local l = el:FindFirstChild("Luck")
            if l then
                local ok, txt = pcall(function() return l.Text end)
                if ok and txt then
                    local v = parseLuck(txt)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    local v = dataLuck(eggKeyName(egg))
    if v then return v end
    return 0
end

local function isVolcanoEgg(egg)
    if not egg then return false end
    local key = string.lower(eggKeyName(egg))
    if key:find("volcanic", 1, true) then return true end
    local nm = string.lower(tostring(egg.Name))
    return nm:find("volcanic", 1, true) ~= nil
end

local function getPrompt(egg)
    if not egg then return nil end
    local p = egg:FindFirstChildOfClass("ProximityPrompt")
    if p then return p end
    local h = egg:FindFirstChild("Handle")
    if h then
        local p2 = h:FindFirstChildOfClass("ProximityPrompt")
        if p2 then return p2 end
    end
    for _, d in ipairs(egg:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function firePrompt(p)
    if not p then return end
    pcall(function()
        p.HoldDuration = 0
        p.RequiresLineOfSight = false
        p.MaxActivationDistance = 1000
        p.Enabled = true
    end)
    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, p)
    elseif typeof(firesignal) == "function" then
        pcall(function()
            firesignal(p.PromptButtonHoldBegan)
            firesignal(p.PromptButtonHoldEnded)
            firesignal(p.Triggered)
        end)
    end
end

-- =====================================================================
-- plot
-- =====================================================================
local cachedPlot, cachedPlotBase = nil, nil

local function findPlot()
    if cachedPlot and cachedPlot.Parent then return cachedPlot end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, p in ipairs(plots:GetChildren()) do
        local data = p:FindFirstChild("Data")
        local owner = data and data:FindFirstChild("Owner")
        if owner then
            local ok, val = pcall(function() return owner.Value end)
            if ok and val == LocalPlayer then
                cachedPlot = p
                cachedPlotBase = p:FindFirstChild("Baseplate")
                return p
            end
        end
    end
    return nil
end

local function getPlotBase()
    if cachedPlotBase and cachedPlotBase.Parent then return cachedPlotBase end
    local p = findPlot()
    if not p then return nil end
    cachedPlotBase = p:FindFirstChild("Baseplate")
    return cachedPlotBase
end

local function getPlotTop()
    local bp = getPlotBase()
    if not bp then return nil end
    return bp.Position + Vector3.new(0, bp.Size.Y / 2, 0)
end

-- Point juste a l'EXTERIEUR du plot (du cote ou on se trouve) pour lacher puis reprendre l'oeuf.
local function outsideDropPoint()
    local bp = getPlotBase()
    if not bp then return nil end
    local hrp = getRoot()
    if not hrp then return nil end
    local ok, localPos = pcall(function() return bp.CFrame:PointToObjectSpace(hrp.Position) end)
    if not ok or not localPos then return nil end
    local side = 1
    if localPos.X < 0 then side = -1 end
    local halfX = bp.Size.X / 2
    local targetLocal = Vector3.new(side * (halfX + DROP_SIDE_MARGIN), 0, 0)
    local ok2, world = pcall(function() return bp.CFrame:PointToWorldSpace(targetLocal) end)
    if not ok2 or not world then return nil end
    return world
end

local function getBasket()
    return LocalPlayer:FindFirstChild("Basket")
end

local function basketCount()
    local b = getBasket()
    if not b then return nil end
    return #b:GetChildren()
end

local function hasUndipped()
    local b = getBasket()
    if not b then return false end
    for _, c in ipairs(b:GetChildren()) do
        if c:GetAttribute("VolcanoDipped") ~= true and c:GetAttribute("VolcanoUntil") == nil then
            return true
        end
    end
    return false
end

local function isDipping()
    local b = getBasket()
    if not b then return false end
    for _, c in ipairs(b:GetChildren()) do
        if c:GetAttribute("VolcanoUntil") ~= nil then return true end
    end
    return false
end

-- =====================================================================
-- remotes
-- =====================================================================
local remoteCache = {}

local function findRemote(name)
    if remoteCache[name] and remoteCache[name].Parent then return remoteCache[name] end
    local pk = ReplicatedStorage:FindFirstChild("packages")
    local net = pk and pk:FindFirstChild("Net")
    if net then
        local r = net:FindFirstChild(name) or net:FindFirstChild("RE/" .. name)
        if r and r:IsA("RemoteEvent") then
            remoteCache[name] = r
            return r
        end
    end
    local direct = ReplicatedStorage:FindFirstChild(name)
    if direct and direct:IsA("RemoteEvent") then
        remoteCache[name] = direct
        return direct
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local r2 = remotes:FindFirstChild(name)
        if r2 and r2:IsA("RemoteEvent") then
            remoteCache[name] = r2
            return r2
        end
    end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and (d.Name == name or d.Name == "RE/" .. name) then
            remoteCache[name] = d
            return d
        end
    end
    return nil
end

local function getVolcanoRemote()
    local pk = ReplicatedStorage:FindFirstChild("packages")
    local net = pk and pk:FindFirstChild("Net")
    if not net then return nil end
    return net:FindFirstChild("RE/VolcanoDip")
end

-- =====================================================================
-- volcan
-- =====================================================================
local function doVolcanoDip()
    local rem = getVolcanoRemote()
    if not rem then return end
    if not hasUndipped() then return end
    tpToPos(VOLCANO_HOVER)
    task.wait(0.2)
    for _ = 1, 4 do
        if stopFlag then break end
        if not hasUndipped() then break end
        pcall(function() rem:FireServer() end)
        local start = os.clock()
        while os.clock() - start < 14 do
            if stopFlag then break end
            local hrp = getRoot()
            if hrp then
                hrp.CFrame = CFrame.new(VOLCANO_HOVER)
                zeroVelocity(hrp)
            end
            RunService.Heartbeat:Wait()
            if os.clock() - start > 1 and not isDipping() then break end
        end
    end
end

local function walkVolcanoPath()
    if #VOLCANO_PATH == 0 then return end
    tpToPos(VOLCANO_PATH[1])
    task.wait(WAYPOINT_WAIT)
    for i = 2, #VOLCANO_PATH do
        if stopFlag then return end
        tpToPos(VOLCANO_PATH[i])
        task.wait(WAYPOINT_WAIT)
    end
end

local function exitVolcanoPath()
    if #VOLCANO_PATH == 0 then return end
    for i = #VOLCANO_PATH, 2, -1 do
        if stopFlag then return end
        tpToPos(VOLCANO_PATH[i])
        task.wait(WAYPOINT_WAIT)
    end
    tpToPos(VOLCANO_PATH[1])
    task.wait(WAYPOINT_WAIT)
end

-- =====================================================================
-- prise de l'oeuf CONFIRMEE (le panier se remplit) ; sans panier on se fie a la disparition
-- =====================================================================
local function grabEgg(egg)
    if not egg or not egg.Parent then return false end
    local before = basketCount()
    local deadline = os.clock() + 5
    local gone = false

    while os.clock() < deadline do
        if stopFlag then return false end
        local now = basketCount()
        if before ~= nil and now ~= nil and now > before then return true end

        if not egg.Parent then
            -- l'oeuf a disparu du monde : pris par nous (le panier le confirme) ou par un autre
            if before == nil then return true end
            if not gone then
                gone = true
                deadline = math.min(deadline, os.clock() + 0.6)
            end
        else
            local hrp = getRoot()
            local ok, pivot = pcall(function() return egg:GetPivot().Position end)
            if hrp and ok and (hrp.Position - pivot).Magnitude > 12 then
                tpToObj(egg, EGG_OFFSET)
            end
            firePrompt(getPrompt(egg))
        end
        task.wait(0.08)
    end

    local now = basketCount()
    return before ~= nil and now ~= nil and now > before
end

-- =====================================================================
-- vol final : 700% de la vitesse de marche jusqu'au centre du plot, puis pose au sol
-- =====================================================================
local function flyIntoPlot()
    local hrp = getRoot()
    local hum = getHum()
    local top = getPlotTop()
    if not hrp or not hum or not top then return false end

    local cruiseY = top.Y + FLY_HEIGHT
    local aborted = false
    hum.PlatformStand = true

    pcall(function()
        local started = os.clock()
        local dt = 1 / 60
        while not stopFlag and hrp.Parent and os.clock() - started < 40 do
            setNoclip(true)
            local flat = Vector3.new(top.X - hrp.Position.X, 0, top.Z - hrp.Position.Z)
            if flat.Magnitude < 6 then break end

            local speed = math.max(hum.WalkSpeed * FLY_FRACTION, 8)
            local vy = math.clamp((cruiseY - hrp.Position.Y) / 0.12, -speed * 0.5, speed * 0.5)
            local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
            local v = flat.Unit * math.min(horizontal, flat.Magnitude / math.max(dt, 1 / 240))
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
            dt = RunService.Heartbeat:Wait()
        end
        aborted = stopFlag

        if not aborted and hrp.Parent then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {LocalPlayer.Character}
            params.IgnoreWater = true
            local origin = Vector3.new(hrp.Position.X, hrp.Position.Y + 5, hrp.Position.Z)
            local hit = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
            local ground = hit and hit.Position or top
            hrp.CFrame = CFrame.new(ground + Vector3.new(0, 4, 0))
        end
    end)

    setNoclip(false)
    hum.PlatformStand = false
    restoreControl()
    return not aborted
end

-- =====================================================================
-- tp dehors du plot -> drop -> reprise confirmee -> vol dans le plot
-- =====================================================================
local function eggsNear(folder, point, radius, known)
    local out = {}
    if not folder or not folder.Parent then return out end
    for _, e in ipairs(folder:GetChildren()) do
        local pos = e:GetAttribute("Position")
        if typeof(pos) == "Vector3" and not (known and known[e]) then
            local dx = pos.X - point.X
            local dz = pos.Z - point.Z
            if math.sqrt(dx * dx + dz * dz) < radius then
                out[#out + 1] = e
            end
        end
    end
    return out
end

local function pickUpDropped(eggList, dropPoint, pickRem)
    local hrp
    for _, egg in ipairs(eggList) do
        if stopFlag then return end
        local lastPos = egg:GetAttribute("Position") or dropPoint
        local deadline = os.clock() + 3
        local nextFire = 0
        local before = basketCount()

        while egg.Parent ~= nil and os.clock() < deadline do
            if stopFlag then return end
            local now = basketCount()
            if before ~= nil and now ~= nil and now > before then break end

            hrp = getRoot()
            if hrp then
                local eggPos = egg:GetAttribute("Position") or lastPos
                lastPos = eggPos
                local dx = hrp.Position.X - eggPos.X
                local dz = hrp.Position.Z - eggPos.Z
                if math.sqrt(dx * dx + dz * dz) > 12 then
                    hrp.CFrame = CFrame.new(eggPos + Vector3.new(0, 3, 0))
                    zeroVelocity(hrp)
                end
            end
            if os.clock() >= nextFire then
                nextFire = os.clock() + 0.1
                firePrompt(getPrompt(egg))
                pcall(function() pickRem:FireServer(egg.Name) end)
            end
            RunService.Heartbeat:Wait()
        end
    end
end

-- renvoie true si tout le panier est repris (ou si le panier n'est pas lisible)
local function outsideDropAndSteal()
    local basket = getBasket()
    if not basket then return true end

    local basketEggNames = {}
    for _, item in ipairs(basket:GetChildren()) do
        local nm = item:GetAttribute("Egg")
        if type(nm) == "string" and nm ~= "" then
            basketEggNames[#basketEggNames + 1] = nm
        end
    end
    local expected = #basket:GetChildren()
    if #basketEggNames == 0 then return expected > 0 end

    local dropPoint = outsideDropPoint()
    if not dropPoint then return true end

    -- tp instantane juste dehors du plot
    local hrp = getRoot()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(dropPoint + Vector3.new(0, 3, 0))
    zeroVelocity(hrp)
    RunService.Heartbeat:Wait()
    RunService.Heartbeat:Wait()
    if stopFlag then return false end

    -- oeufs deja presents avant le drop
    local folder = workspace:FindFirstChild(FOLDER_NAME)
    local existing = {}
    if folder then
        for _, e in ipairs(folder:GetChildren()) do existing[e] = true end
    end

    local dropRem = findRemote("BasketDrop")
    local pickRem = findRemote("EggPickup")
    if not dropRem or not pickRem then return true end

    setStatus("drop")
    for _, nm in ipairs(basketEggNames) do
        pcall(function() dropRem:FireServer(nm) end)
    end

    -- les oeufs lâches : nouveaux objets avec OriginPosition + Position
    local dropped = {}
    local spawnDeadline = os.clock() + 3
    while os.clock() < spawnDeadline do
        if stopFlag then return false end
        if folder and folder.Parent then
            for _, e in ipairs(folder:GetChildren()) do
                if not existing[e] and e:GetAttribute("OriginPosition") ~= nil
                    and typeof(e:GetAttribute("Position")) == "Vector3" then
                    existing[e] = true
                    dropped[#dropped + 1] = e
                end
            end
        end
        if #dropped >= #basketEggNames then break end
        RunService.Heartbeat:Wait()
    end
    if stopFlag then return false end

    -- repli : oeufs proches du point de drop
    if #dropped == 0 then
        dropped = eggsNear(folder, dropPoint, 90, nil)
    end

    setStatus("reprise")
    pickUpDropped(dropped, dropPoint, pickRem)

    -- reprise CONFIRMEE : deux tours de rattrapage si le panier n'est pas plein
    for _ = 1, 2 do
        if stopFlag then return false end
        local count = basketCount()
        if count == nil or count >= expected then break end
        local rest = eggsNear(folder, dropPoint, 120, nil)
        if #rest == 0 then break end
        pickUpDropped(rest, dropPoint, pickRem)
    end

    local count = basketCount()
    return count == nil or count >= expected
end

local function runSequenceInner(egg)
    local isVolcano = isVolcanoEgg(egg)

    if isVolcano then
        setStatus("volcan")
        walkVolcanoPath()
        if stopFlag then return end
    end

    -- tp sur l'oeuf + prise confirmee
    setStatus("tp oeuf")
    if not tpToObj(egg, EGG_OFFSET) then
        setStatus("oeuf disparu")
        return
    end
    task.wait(0.12)
    if stopFlag then return end

    setStatus("prise")
    if not grabEgg(egg) then
        if not stopFlag then setStatus("oeuf non pris") end
        if isVolcano then exitVolcanoPath() end
        return
    end
    task.wait(0.1)
    if stopFlag then return end

    if isVolcano then
        setStatus("sortie volcan")
        exitVolcanoPath()
        if stopFlag then return end
    end

    if autoDip then
        setStatus("dip volcan")
        doVolcanoDip()
        if stopFlag then return end
    end

    -- tp dehors du plot, drop, reprise confirmee
    local ok = outsideDropAndSteal()
    if stopFlag then return end
    if not ok then
        setStatus("oeuf non repris")
        return
    end

    -- vol jusque dans le plot
    setStatus("vol")
    flyIntoPlot()
    if not stopFlag then setStatus("termine") end
end

local setRunningUI = function(_) end

local function runSequence(egg)
    if running then return end
    if not egg or not egg.Parent then return end
    running = true
    stopFlag = false
    setRunningUI(true)

    local ok, err = pcall(runSequenceInner, egg)
    if not ok then
        warn("[ShinEggFarm] erreur : " .. tostring(err))
        setStatus("erreur")
    end

    restoreControl()
    running = false
    setRunningUI(false)
end

local function stopSequence()
    stopFlag = true
    task.defer(restoreControl)
end

-- =====================================================================
-- interface : yslemStyle aux couleurs rouge / noir
-- contours et textes en degrade qui tourne, theme noir, formes arrondies,
-- barre de titre vive a titre noir
-- =====================================================================
local RED       = Color3.fromRGB(255, 30, 30)
local RED_LIGHT = Color3.fromRGB(255, 120, 120)
local RED_MID   = Color3.fromRGB(200, 0, 0)
local RED_DARK  = Color3.fromRGB(90, 0, 0)
local BLACK     = Color3.fromRGB(0, 0, 0)
local WHITE_T   = Color3.fromRGB(235, 235, 235)

pcall(function()
    local old = guiParent:FindFirstChild("ShinEggFarm")
    if old then old:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ShinEggFarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
local okParent = pcall(function() ScreenGui.Parent = guiParent end)
if not okParent or not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local living = {}

local function bands(a, b)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.25, b), ColorSequenceKeypoint.new(0.5, a),
        ColorSequenceKeypoint.new(0.75, b), ColorSequenceKeypoint.new(1, a),
    })
end

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
    return c
end

-- contour vivant (bandes qui tournent autour de la bordure)
local function livingStroke(inst, thickness, bright)
    local st = Instance.new("UIStroke")
    st.Thickness = thickness or 1
    st.Color = Color3.new(1, 1, 1)
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st.Parent = inst
    local g = Instance.new("UIGradient")
    g.Rotation = 45
    g.Color = bands(bright and RED or RED_MID, RED_DARK)
    g.Parent = st
    living[#living + 1] = g
    return st, g
end

-- texte vivant (bandes qui traversent les lettres)
local function livingText(inst)
    local g = Instance.new("UIGradient")
    g.Color = bands(RED, RED_LIGHT)
    g.Parent = inst
    living[#living + 1] = g
    return g
end

local function newLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextSize = 11
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function makeButton(text)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = BLACK
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 12
    b.AutoButtonColor = false
    corner(b, 8)
    livingStroke(b, 1.2, true)
    livingText(b)
    return b
end

local function pressFx(btn)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3 = RED_DARK}):Play()
    end)
    local function release()
        TweenService:Create(btn, TweenInfo.new(0.14), {BackgroundColor3 = BLACK}):Play()
    end
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

local MAIN_W, MAIN_H = 220, 316

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
Main.AnchorPoint = Vector2.new(0.5, 0)
Main.Position = UDim2.new(0.5, 0, 0, 20)
Main.BackgroundColor3 = BLACK
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.Parent = ScreenGui
corner(Main, 14)
livingStroke(Main, 1.5, true)

-- barre de titre vive, titre noir
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, -8, 0, 30)
TitleBar.Position = UDim2.new(0, 4, 0, 4)
TitleBar.BackgroundColor3 = RED
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main
corner(TitleBar, 10)
do
    local g = Instance.new("UIGradient")
    g.Color = bands(RED, RED_MID)
    g.Parent = TitleBar
    living[#living + 1] = g
end

local Logo = Instance.new("ImageLabel")
Logo.Size = UDim2.new(0, 24, 0, 24)
Logo.Position = UDim2.new(0, 6, 0, 3)
Logo.BackgroundTransparency = 1
Logo.Image = LOGO_ID
Logo.ScaleType = Enum.ScaleType.Fit
Logo.ZIndex = 3
Logo.Parent = TitleBar

local Title = newLabel(TitleBar, {
    Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 36, 0, 0),
    Text = "SHIN HUB", TextSize = 15, TextColor3 = BLACK, TextXAlignment = Enum.TextXAlignment.Left,
})

local MinimizeBtn = makeButton("-")
MinimizeBtn.Size = UDim2.new(0, 22, 0, 20)
MinimizeBtn.Position = UDim2.new(1, -26, 0, 5)
MinimizeBtn.TextSize = 15
MinimizeBtn.Parent = TitleBar

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -12, 0, LIST_HEIGHT)
List.Position = UDim2.new(0, 6, 0, 40)
List.BackgroundColor3 = Color3.fromRGB(8, 0, 0)
List.BorderSizePixel = 0
List.CanvasSize = UDim2.new(0, 0, 0, LIST_HEIGHT)
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = RED_MID
List.ScrollingEnabled = false
List.Parent = Main
corner(List, 10)
livingStroke(List, 1, false)

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, ROW_GAP)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

local BTN_Y = 40 + LIST_HEIGHT + 6

local GoBtn = makeButton("GO")
GoBtn.Size = UDim2.new(1, -12, 0, 28)
GoBtn.Position = UDim2.new(0, 6, 0, BTN_Y)
GoBtn.Parent = Main

local DipBtn = makeButton("Auto Volcano Dip: OFF")
DipBtn.Size = UDim2.new(1, -12, 0, 26)
DipBtn.Position = UDim2.new(0, 6, 0, BTN_Y + 28 + 5)
DipBtn.TextSize = 11
DipBtn.Parent = Main

local StatusLbl = newLabel(Main, {
    Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, BTN_Y + 28 + 5 + 26 + 4),
    Text = "pret", TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center,
})
livingText(StatusLbl)
statusSetter = function(text) StatusLbl.Text = tostring(text) end

local DiscordLabel = newLabel(Main, {
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, BTN_Y + 28 + 5 + 26 + 4 + 14),
    Text = DISCORD_TEXT, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
})
livingText(DiscordLabel)

-- vue reduite --------------------------------------------------------
local Mini = Instance.new("Frame")
Mini.Size = UDim2.new(0, 220, 0, 150)
Mini.AnchorPoint = Vector2.new(0.5, 0)
Mini.Position = UDim2.new(0.5, 0, 0, 20)
Mini.BackgroundColor3 = BLACK
Mini.BorderSizePixel = 0
Mini.ClipsDescendants = true
Mini.Visible = false
Mini.Active = true
Mini.Parent = ScreenGui
corner(Mini, 14)
livingStroke(Mini, 1.5, true)

local MiniTitleBar = Instance.new("Frame")
MiniTitleBar.Size = UDim2.new(1, -8, 0, 30)
MiniTitleBar.Position = UDim2.new(0, 4, 0, 4)
MiniTitleBar.BackgroundColor3 = RED
MiniTitleBar.BorderSizePixel = 0
MiniTitleBar.Parent = Mini
corner(MiniTitleBar, 10)
do
    local g = Instance.new("UIGradient")
    g.Color = bands(RED, RED_MID)
    g.Parent = MiniTitleBar
    living[#living + 1] = g
end

local MiniLogo = Instance.new("ImageLabel")
MiniLogo.Size = UDim2.new(0, 24, 0, 24)
MiniLogo.Position = UDim2.new(0, 6, 0, 3)
MiniLogo.BackgroundTransparency = 1
MiniLogo.Image = LOGO_ID
MiniLogo.ScaleType = Enum.ScaleType.Fit
MiniLogo.ZIndex = 3
MiniLogo.Parent = MiniTitleBar

newLabel(MiniTitleBar, {
    Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 36, 0, 0),
    Text = "SHIN HUB", TextSize = 15, TextColor3 = BLACK, TextXAlignment = Enum.TextXAlignment.Left,
})

local MiniExpandBtn = makeButton("+")
MiniExpandBtn.Size = UDim2.new(0, 22, 0, 20)
MiniExpandBtn.Position = UDim2.new(1, -26, 0, 5)
MiniExpandBtn.TextSize = 15
MiniExpandBtn.Parent = MiniTitleBar

local MiniPreviewHolder = Instance.new("Frame")
MiniPreviewHolder.Size = UDim2.new(0, 44, 0, 44)
MiniPreviewHolder.Position = UDim2.new(0, 8, 0, 42)
MiniPreviewHolder.BackgroundColor3 = Color3.fromRGB(14, 0, 0)
MiniPreviewHolder.BorderSizePixel = 0
MiniPreviewHolder.Parent = Mini
corner(MiniPreviewHolder, 8)
livingStroke(MiniPreviewHolder, 1, false)

local MiniTag = newLabel(Mini, {
    Size = UDim2.new(0, 40, 0, 12), Position = UDim2.new(0, 60, 0, 42),
    Text = "BEST", TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left,
})
livingText(MiniTag)

local MiniBestLbl = newLabel(Mini, {
    Size = UDim2.new(1, -140, 0, 16), Position = UDim2.new(0, 60, 0, 54),
    Text = "no eggs", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
livingText(MiniBestLbl)

local MiniLuckLbl = newLabel(Mini, {
    Size = UDim2.new(1, -140, 0, 14), Position = UDim2.new(0, 60, 0, 70),
    Text = "LUCK 0", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
})
livingText(MiniLuckLbl)

local MiniGoBtn = makeButton("GO")
MiniGoBtn.Size = UDim2.new(0, 62, 0, 26)
MiniGoBtn.Position = UDim2.new(1, -70, 0, 52)
MiniGoBtn.TextSize = 11
MiniGoBtn.Parent = Mini

local MiniDipBtn = makeButton("Auto Volcano Dip: OFF")
MiniDipBtn.Size = UDim2.new(1, -16, 0, 24)
MiniDipBtn.Position = UDim2.new(0, 8, 0, 94)
MiniDipBtn.TextSize = 11
MiniDipBtn.Parent = Mini

local MiniDiscordLabel = newLabel(Mini, {
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 126),
    Text = DISCORD_TEXT, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
})
livingText(MiniDiscordLabel)

for _, b in ipairs({MinimizeBtn, GoBtn, DipBtn, MiniExpandBtn, MiniGoBtn, MiniDipBtn}) do pressFx(b) end

-- animation : tous les degrades vivants tournent (une image sur deux)
do
    local clock, tick = 0, 0
    RunService.Heartbeat:Connect(function(dt)
        clock = clock + dt
        tick = tick + 1
        if tick % 2 ~= 0 then return end
        local rot = (clock * 72) % 360
        for i = #living, 1, -1 do
            local g = living[i]
            if g.Parent then
                g.Rotation = g.Parent:IsA("UIStroke") and (45 + rot) % 360 or rot
            else
                table.remove(living, i)
            end
        end
    end)
end

-- GO <-> STOP --------------------------------------------------------
setRunningUI = function(state)
    local label = state and "STOP" or "GO"
    GoBtn.Text = label
    MiniGoBtn.Text = label
end

local function updateDipBtn()
    local t = autoDip and "Auto Volcano Dip: ON" or "Auto Volcano Dip: OFF"
    DipBtn.Text = t
    MiniDipBtn.Text = t
end

local function toggleDip()
    autoDip = not autoDip
    updateDipBtn()
end

DipBtn.MouseButton1Click:Connect(toggleDip)
MiniDipBtn.MouseButton1Click:Connect(toggleDip)
updateDipBtn()

-- icones d'oeufs -----------------------------------------------------
local function cleanClone(clone)
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
            d.Massless = true
        elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            pcall(function() d:Destroy() end)
        elseif d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
            or d:IsA("Highlight") or d:IsA("ParticleEmitter") or d:IsA("Trail")
            or d:IsA("Beam") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
            pcall(function() d:Destroy() end)
        end
    end
end

local function makeViewport(parent, egg, zoom)
    zoom = zoom or 1
    local vp = Instance.new("ViewportFrame")
    vp.Size = UDim2.new(1, 0, 1, 0)
    vp.Position = UDim2.new(0, 0, 0, 0)
    vp.BackgroundTransparency = 1
    vp.BorderSizePixel = 0
    vp.Ambient = Color3.fromRGB(255, 255, 255)
    vp.LightColor = Color3.fromRGB(255, 255, 255)
    vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
    vp.Parent = parent

    local cam = Instance.new("Camera")
    cam.FieldOfView = 60
    cam.Parent = vp
    vp.CurrentCamera = cam

    local ok, clone = pcall(function() return egg:Clone() end)
    if not ok or not clone then return vp end
    pcall(cleanClone, clone)

    local basePart
    if clone:IsA("BasePart") then
        basePart = clone
    elseif clone:IsA("Model") then
        basePart = clone.PrimaryPart or clone:FindFirstChild("Handle") or clone:FindFirstChildWhichIsA("BasePart")
    end
    if not basePart then
        pcall(function() clone:Destroy() end)
        return vp
    end

    local center, sz
    if clone:IsA("Model") then
        pcall(function() clone.PrimaryPart = basePart end)
        local ok2, c, s = pcall(function() return clone:GetBoundingBox() end)
        if ok2 and c and s then center, sz = c.Position, s end
    end
    if not center then
        center = basePart.Position
        sz = basePart.Size
    end

    local radius = math.max(sz.Magnitude, 2) * 0.5
    local dist = radius / math.tan(math.rad(cam.FieldOfView * 0.5)) * 1.15 * zoom
    cam.CFrame = CFrame.new(center + Vector3.new(dist * 0.4, dist * 0.35, dist), center)

    clone.Parent = vp
    return vp
end

local function makeEggIcon(parent, egg, zoom)
    zoom = zoom or 1
    local img = eggImage(egg)
    if img ~= "" then
        local il = Instance.new("ImageLabel")
        il.Size = UDim2.new(1, 0, 1, 0)
        il.Position = UDim2.new(0, 0, 0, 0)
        il.BackgroundTransparency = 1
        il.Image = img
        il.ScaleType = Enum.ScaleType.Fit
        il.Parent = parent
        return il
    end
    return makeViewport(parent, egg, zoom)
end

-- liste des oeufs ----------------------------------------------------
local function scanEggs()
    local folder = workspace:FindFirstChild(FOLDER_NAME)
    if not folder then
        for _, d in ipairs(workspace:GetChildren()) do
            local ln = string.lower(d.Name)
            if ln == "renderedeggs" or ln == "rendered_eggs" or ln:find("renderedegg", 1, true) then
                folder = d
                break
            end
        end
    end
    if not folder then return {} end
    local list = {}
    for _, e in ipairs(folder:GetChildren()) do
        if e:IsA("Model") or e:IsA("BasePart") then
            list[#list + 1] = e
        end
    end
    return list
end

local function getTopEggs(n)
    local all = scanEggs()
    local data = {}
    for _, e in ipairs(all) do
        local ok, luck = pcall(eggLuck, e)
        data[#data + 1] = {model = e, luck = ok and luck or 0}
    end
    table.sort(data, function(a, b) return a.luck > b.luck end)
    local out = {}
    for i = 1, math.min(n, #data) do out[i] = data[i] end
    return out
end

local selectedEgg = nil
local selectedEggName = nil
local rowMeta = {}
local cachedModelRefs = {}
local miniCachedModel = nil
local miniCurrentBestEgg = nil

local function applySelected(btn)
    local m = rowMeta[btn]
    if not m then return end
    m.stroke.Thickness = 2.2
    m.glow.Visible = true
    btn.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
end

local function applyUnselected(btn)
    local m = rowMeta[btn]
    if not m then return end
    m.stroke.Thickness = 1
    m.glow.Visible = false
    btn.BackgroundColor3 = Color3.fromRGB(14, 0, 0)
end

local function refreshOutlines()
    for btn, m in pairs(rowMeta) do
        if btn.Parent then
            if m.model == selectedEgg then
                applySelected(btn)
            else
                applyUnselected(btn)
            end
        end
    end
end

local function sameModels(top)
    if #top ~= #cachedModelRefs then return false end
    for i = 1, #top do
        if top[i].model ~= cachedModelRefs[i] then return false end
    end
    return true
end

local function rebuildList()
    if selectedEgg and not selectedEgg.Parent then selectedEgg = nil end
    local top = getTopEggs(EGGS_TO_SHOW)

    if selectedEgg == nil and selectedEggName then
        for _, entry in ipairs(top) do
            if entry.model.Name == selectedEggName and entry.model.Parent then
                selectedEgg = entry.model
                break
            end
        end
    end

    if sameModels(top) then
        for btn, m in pairs(rowMeta) do
            if btn.Parent and m.luckLbl then
                local ok, lk = pcall(eggLuck, m.model)
                if ok then m.luckLbl.Text = "LUCK " .. formatLuck(lk) end
            end
        end
        refreshOutlines()
        return
    end

    cachedModelRefs = {}
    for i = 1, #top do cachedModelRefs[i] = top[i].model end

    for _, c in ipairs(List:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") or c:IsA("Frame")
            or c:IsA("ViewportFrame") or c:IsA("ImageLabel") then
            c:Destroy()
        end
    end
    rowMeta = {}

    if #top == 0 then
        local empty = newLabel(List, {
            Size = UDim2.new(1, 0, 0, 26), Font = Enum.Font.Gotham, Text = "no eggs found",
            TextColor3 = Color3.fromRGB(150, 150, 150), TextSize = 11, LayoutOrder = 1,
        })
        List.CanvasSize = UDim2.new(0, 0, 0, LIST_HEIGHT)
        return
    end

    if not selectedEgg then
        selectedEgg = top[1].model
        selectedEggName = top[1].model.Name
    end

    for idx, entry in ipairs(top) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        btn.BackgroundColor3 = Color3.fromRGB(14, 0, 0)
        btn.BorderSizePixel = 0
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.LayoutOrder = idx
        btn.Parent = List
        corner(btn, 9)

        local glow = Instance.new("Frame")
        glow.Size = UDim2.new(1, 4, 1, 4)
        glow.Position = UDim2.new(0, -2, 0, -2)
        glow.BackgroundColor3 = RED
        glow.BackgroundTransparency = 0.8
        glow.BorderSizePixel = 0
        glow.Visible = false
        glow.ZIndex = 0
        glow.Parent = btn
        corner(glow, 11)

        local st = livingStroke(btn, 1, false)

        local m = {model = entry.model, stroke = st, glow = glow, luckLbl = nil}
        rowMeta[btn] = m

        local iconFrame = Instance.new("Frame")
        iconFrame.Size = UDim2.new(0, 30, 0, 30)
        iconFrame.Position = UDim2.new(0, 3, 0, 2)
        iconFrame.BackgroundTransparency = 1
        iconFrame.ZIndex = 2
        iconFrame.Active = false
        iconFrame.Parent = btn
        pcall(makeEggIcon, iconFrame, entry.model, 1)

        local rankLbl = newLabel(btn, {
            Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(0, 36, 0, 0),
            Text = tostring(idx), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
        })
        livingText(rankLbl)

        local nameLbl = newLabel(btn, {
            Size = UDim2.new(0, 92, 1, 0), Position = UDim2.new(0, 54, 0, 0),
            Font = Enum.Font.GothamSemibold, Text = entry.model.Name, TextColor3 = WHITE_T,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
        })

        local luckLbl = newLabel(btn, {
            Size = UDim2.new(0, 58, 1, 0), Position = UDim2.new(1, -62, 0, 0),
            Text = "LUCK " .. formatLuck(entry.luck), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2,
        })
        livingText(luckLbl)
        m.luckLbl = luckLbl

        btn.MouseButton1Click:Connect(function()
            selectedEgg = entry.model
            selectedEggName = entry.model.Name
            refreshOutlines()
        end)

        if selectedEgg == entry.model then applySelected(btn) else applyUnselected(btn) end
    end

    List.CanvasSize = UDim2.new(0, 0, 0, LIST_HEIGHT)
end

local function updateMini()
    local top = getTopEggs(1)
    if #top == 0 then
        MiniBestLbl.Text = "no eggs"
        MiniLuckLbl.Text = "LUCK 0"
        miniCurrentBestEgg = nil
        if miniCachedModel then
            for _, c in ipairs(MiniPreviewHolder:GetChildren()) do
                if c:IsA("ViewportFrame") or c:IsA("ImageLabel") then c:Destroy() end
            end
            miniCachedModel = nil
        end
        return
    end
    local entry = top[1]
    miniCurrentBestEgg = entry.model
    MiniBestLbl.Text = entry.model.Name
    MiniLuckLbl.Text = "LUCK " .. formatLuck(entry.luck)
    if miniCachedModel ~= entry.model then
        for _, c in ipairs(MiniPreviewHolder:GetChildren()) do
            if c:IsA("ViewportFrame") or c:IsA("ImageLabel") then c:Destroy() end
        end
        miniCachedModel = entry.model
        pcall(makeEggIcon, MiniPreviewHolder, entry.model, 1.3)
    end
end

-- GO / STOP ----------------------------------------------------------
local function pressGo(target)
    if running then
        stopSequence()
        return
    end
    if not target or not target.Parent then
        local top = getTopEggs(1)
        if #top > 0 then target = top[1].model end
    end
    if target then task.spawn(runSequence, target) end
end

GoBtn.MouseButton1Click:Connect(function() pressGo(selectedEgg) end)
MiniGoBtn.MouseButton1Click:Connect(function() pressGo(miniCurrentBestEgg) end)

MinimizeBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    Mini.Visible = true
    miniCachedModel = nil
    updateMini()
end)

MiniExpandBtn.MouseButton1Click:Connect(function()
    Mini.Visible = false
    Main.Visible = true
    rebuildList()
end)

task.spawn(function()
    while ScreenGui.Parent do
        task.wait(REFRESH_TIME)
        if not running then
            pcall(rebuildList)
            if Mini.Visible then pcall(updateMini) end
        end
    end
end)

-- deplacement de la fenetre (barre de titre) : suit le doigt / la souris partout a l'ecran
do
    local dragging = false
    local dragStart, startPos, startInput

    local function begin(frame)
        return function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                startInput = input
            end
        end
    end
    TitleBar.InputBegan:Connect(begin(Main))
    MiniTitleBar.InputBegan:Connect(begin(Mini))

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = input.Position - dragStart
        local pos = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        Main.Position = pos
        Mini.Position = pos
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function()
    stopSequence()
end)

pcall(findPlot)
pcall(rebuildList)
pcall(updateMini)
