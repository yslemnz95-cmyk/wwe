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
local EGGS_TO_SHOW = 5
local REFRESH_TIME = 1.5
local ROW_HEIGHT = 34
local ROW_GAP = 2
local LIST_HEIGHT = EGGS_TO_SHOW * ROW_HEIGHT + (EGGS_TO_SHOW - 1) * ROW_GAP
local VOLCANO_HOVER = Vector3.new(-5103, 41465, -3490)
local LOGO_ID = "rbxassetid://130258290579194"
local DISCORD_TEXT = "discord.gg/Q7Q6mGbcg8"
local WAYPOINT_WAIT = 0.18

-- final flight into the plot: 700% of the walk speed, 40 studs above the plot
local FLY_FRACTION = 7
local FLY_HEIGHT = 40

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
-- state (the stop flag is only reset when a new job starts)
-- =====================================================================
local running = false
local stopFlag = false
local autoDip = false
local statusSetter = function(_) end -- replaced further down by the real label

local function setStatus(text)
    pcall(statusSetter, text)
end

-- =====================================================================
-- movement helpers
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
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
end

local function getPos(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        if inst.PrimaryPart then return inst.PrimaryPart.Position end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    if inst:IsA("Folder") then
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    return nil
end

-- Puts the character at a position (velocities cancelled): used to stand on an
-- egg to pick it up / retake it.
local function place(position)
    local h = getRoot()
    if not h or not position then return end
    h.CFrame = CFrame.new(position)
    zeroVelocity(h)
end

-- plain teleport (used for the volcano waypoints)
local function tpToPos(pos)
    local hrp = getRoot()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(pos)
    zeroVelocity(hrp)
    return true
end

-- Desync teleport: the CFrame write happens outside the main tick (avoids the
-- server movement validation running on the synchronized thread). Velocity is
-- cancelled to avoid any bounce, then the teleport is re-confirmed over a few
-- frames if a server correction sends us back.
local function tpTo(pos)
    local hrp = getRoot()
    if not hrp or not pos then return end
    local target = CFrame.new(pos + Vector3.new(0, 5, 0))

    local function apply()
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    local ok = pcall(function()
        task.desynchronize()
        apply()
        task.synchronize()
    end)
    if not ok then apply() end

    for _ = 1, 3 do
        task.wait()
        if stopFlag then break end
        if not (hrp and hrp.Parent) then break end
        if (hrp.Position - target.Position).Magnitude > 6 then
            local ok2 = pcall(function()
                task.desynchronize()
                apply()
                task.synchronize()
            end)
            if not ok2 then apply() end
        end
    end
end

-- The original CanCollide values are remembered and restored EXACTLY (setting
-- everything back to true left limbs stuck in the ground after a trip).
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

-- Gives control back to the player: no noclip, no PlatformStand, zero velocity,
-- walking state restored (a teleport can leave the humanoid in a
-- Physics/Ragdoll/FallingDown state with no control).
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

local function moveTo(pos)
    -- the stop flag is NOT reset here: only at the start of a new job
    tpTo(pos)
    restoreControl()
end

-- eggs: luck, image, prompt
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
-- carrying detection: the game's "Egg Will Break" bar and/or the basket
-- =====================================================================
local breakLabel = nil

local function guiShown(obj)
    local p = obj
    while p and p:IsA("GuiObject") do
        if not p.Visible then return false end
        p = p.Parent
    end
    local sg = obj:FindFirstAncestorOfClass("ScreenGui")
    return sg == nil or sg.Enabled
end

-- true / false, or nil if the bar does not exist yet
local function isCarrying()
    if not (breakLabel and breakLabel.Parent) then
        breakLabel = nil
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text and d.Text:lower():find("egg will break", 1, true) then
                    breakLabel = d
                    break
                end
            end
        end
    end
    if not breakLabel then return nil end
    return guiShown(breakLabel)
end

-- are we holding anything? bar OR basket content; nil when neither can tell
local function holdingAny()
    local c = isCarrying()
    local bc = basketCount()
    if c == true or (bc ~= nil and bc > 0) then return true end
    if c == nil and bc == nil then return nil end
    return false
end

-- everything we had is back in our hands
local function holdingAll(expected)
    local bc = basketCount()
    if expected and expected > 0 and bc ~= nil then
        return bc >= expected
    end
    return isCarrying() == true
end

-- =====================================================================
-- drop: the game's DROP button, then remotes / prompts / key, then (last
-- resort) a simulated mouse click
-- =====================================================================
local DROP_WORDS = {"drop", "release", "put down", "place"}
local CLICK_FALLBACK = true

local function trimLower(t)
    t = (t or ""):lower()
    t = t:gsub("^%s+", "")
    t = t:gsub("%s+$", "")
    return t
end

local function dropGuiCandidates()
    local list = {}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return list end

    -- exact path found by the analysis: Main.BasketTracker.Handler.EggFrame.Drop
    local node = pg
    for _, name in ipairs({"Main", "BasketTracker", "Handler", "EggFrame", "Drop"}) do
        node = node and node:FindFirstChild(name)
    end
    if node and node:IsA("GuiObject") then
        table.insert(list, node)
    end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiObject") and d ~= node and not d:FindFirstAncestor("ShinEggFarm") then
            local hit = false
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                hit = trimLower(d.Text) == "drop"
            end
            if not hit then
                local n = d.Name:lower()
                hit = (n == "drop" or n == "dropbutton" or n == "dropbtn" or n == "drop_button" or n == "dropegg")
            end
            if hit and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
                table.insert(list, d)
            end
        end
    end
    return list
end

-- "silent" press: only the button's signals, NO simulated mouse or touch
local function pressGuiSilent(obj)
    local btn = obj
    while btn and not btn:IsA("GuiButton") do
        btn = btn.Parent
        if btn and not btn:IsA("GuiObject") then btn = nil end
    end
    if not btn or typeof(firesignal) ~= "function" then return false end
    for _, sig in ipairs({"MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up"}) do
        pcall(function() firesignal(btn[sig]) end)
    end
    return true
end

local function pressGuiClick(obj)
    pcall(function()
        local vim    = game:GetService("VirtualInputManager")
        local inset  = game:GetService("GuiService"):GetGuiInset()
        local screen = obj:FindFirstAncestorOfClass("ScreenGui")
        local dy = (screen and screen.IgnoreGuiInset) and 0 or inset.Y
        local c = obj.AbsolutePosition + obj.AbsoluteSize / 2
        vim:SendMouseButtonEvent(c.X, c.Y + dy, 0, true, game, 0)
        task.wait(0.05)
        vim:SendMouseButtonEvent(c.X, c.Y + dy, 0, false, game, 0)
    end)
end

local function dropRemotes()
    local list = {}
    local seen = {}
    local exact = findRemote("BasketDrop")
    if exact then table.insert(list, exact); seen[exact] = true end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and not seen[d] and d.Name:lower():find("drop", 1, true) then
            table.insert(list, d)
            seen[d] = true
        end
    end
    return list
end

local function basketEggNames()
    local names = {}
    local b = getBasket()
    if b then
        for _, item in ipairs(b:GetChildren()) do
            local nm = item:GetAttribute("Egg")
            if type(nm) == "string" and nm ~= "" then names[#names + 1] = nm end
        end
    end
    return names
end

-- level 1: the DROP button's signals (silent); level 2: drop remotes, nearby
-- drop prompts and the default Roblox drop key (Backspace); level 3: simulated
-- mouse click (only if CLICK_FALLBACK).
local function dropEgg(level)
    local hrp = getRoot()
    if not hrp then return end

    if level == 1 then
        local n = 0
        for _, obj in ipairs(dropGuiCandidates()) do
            if guiShown(obj) then
                pressGuiSilent(obj)
                n = n + 1
                if n >= 3 then break end
            end
        end
        return
    end

    if level == 3 then
        if not CLICK_FALLBACK then return end
        for _, obj in ipairs(dropGuiCandidates()) do
            if guiShown(obj) then
                pressGuiClick(obj)
                return
            end
        end
        return
    end

    local names = basketEggNames()
    for _, r in ipairs(dropRemotes()) do
        pcall(function() r:FireServer() end)
        for _, nm in ipairs(names) do
            pcall(function() r:FireServer(nm) end)
        end
    end

    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Parent and not d:IsDescendantOf(LocalPlayer.Character) then
                local at = (d.ActionText or ""):lower()
                for _, w in ipairs(DROP_WORDS) do
                    if at:find(w, 1, true) then
                        local pos = getPos(d.Parent)
                        if pos and (pos - hrp.Position).Magnitude <= 40 then
                            firePrompt(d)
                        end
                        break
                    end
                end
            end
        end
    end)

    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
    end)
end

-- =====================================================================
-- pick-up prompts / dropped eggs near us
-- =====================================================================
local lastHeavyScan = 0

local function isPickupPrompt(d)
    local at = (d.ActionText or ""):lower()
    return at:find("pick", 1, true) or at:find("grab", 1, true) or at:find("take", 1, true)
end

local function nearbyPickups(radius)
    local list = {}
    local hrp = getRoot()
    if not hrp then return list end
    local center = hrp.Position

    -- 1) spatial query: only the parts around us (fast)
    pcall(function()
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character}
        for _, part in ipairs(workspace:GetPartBoundsInRadius(center, radius, params)) do
            for _, c in ipairs(part:GetChildren()) do
                if c:IsA("ProximityPrompt") then
                    if isPickupPrompt(c) then list[c] = true end
                elseif c:IsA("Attachment") then
                    for _, cc in ipairs(c:GetChildren()) do
                        if cc:IsA("ProximityPrompt") and isPickupPrompt(cc) then list[cc] = true end
                    end
                end
            end
        end
    end)

    -- 2) safety net: full scan, at most every 0.6 s, only if the query found nothing
    if next(list) == nil and os.clock() - lastHeavyScan > 0.6 then
        lastHeavyScan = os.clock()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Parent and isPickupPrompt(d) then
                local pos = getPos(d.Parent)
                if pos and (pos - center).Magnitude <= radius then
                    list[d] = true
                end
            end
        end
    end
    return list
end

-- eggs of the map folder (dropped eggs show up here as new children)
local function snapshotEggs()
    local set = {}
    local folder = workspace:FindFirstChild(FOLDER_NAME)
    if folder then
        for _, e in ipairs(folder:GetChildren()) do set[e] = true end
    end
    return set
end

local function eggWorldPos(e)
    local p = e:GetAttribute("Position")
    if typeof(p) == "Vector3" then return p end
    local ok, pv = pcall(function() return e:GetPivot().Position end)
    if ok then return pv end
    return nil
end

-- position of a map egg: its real pivot first (where the prompt is), the
-- "Position" attribute only as a fallback
local function eggPivotPos(e)
    local ok, pv = pcall(function() return e:GetPivot().Position end)
    if ok and pv and (pv.X ~= 0 or pv.Y ~= 0 or pv.Z ~= 0) then return pv end
    local pr = getPrompt(e)
    local pp = pr and getPos(pr.Parent)
    if pp then return pp end
    return eggWorldPos(e)
end

local function newEggsSince(snap)
    local out = {}
    local folder = workspace:FindFirstChild(FOLDER_NAME)
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if not snap[e] then out[#out + 1] = e end
        end
    end
    return out
end

-- =====================================================================
-- plot geometry: the player's plot is found by owner, never "the closest"
-- =====================================================================
local STAGE_BACK  = 20
local STAGE_TRIES = 5
local MAX_PLOT    = 300 -- a bigger container is not the plot

local function instBounds(inst)
    local minV, maxV = nil, nil
    local count = 0
    local function addPart(part)
        local cf, size = part.CFrame, part.Size
        local r = cf - cf.Position
        local ex = r:VectorToWorldSpace(Vector3.new(size.X / 2, 0, 0))
        local ey = r:VectorToWorldSpace(Vector3.new(0, size.Y / 2, 0))
        local ez = r:VectorToWorldSpace(Vector3.new(0, 0, size.Z / 2))
        local half = Vector3.new(
            math.abs(ex.X) + math.abs(ey.X) + math.abs(ez.X),
            math.abs(ex.Y) + math.abs(ey.Y) + math.abs(ez.Y),
            math.abs(ex.Z) + math.abs(ey.Z) + math.abs(ez.Z))
        local lo, hi = cf.Position - half, cf.Position + half
        if not minV then
            minV, maxV = lo, hi
        else
            minV = Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z))
            maxV = Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z))
        end
    end
    local function isPlayerPart(part)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character and part:IsDescendantOf(plr.Character) then return true end
        end
        return false
    end
    if inst:IsA("BasePart") then
        addPart(inst)
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") and not isPlayerPart(d) then
            addPart(d)
            count = count + 1
            if count > 4000 then break end
        end
    end
    return minV, maxV
end

local boundsCache = {}

local function plotBounds(inst)
    if not inst then return nil end
    local cached = boundsCache[inst]
    if cached and os.clock() - cached.at < 20 then return cached.lo, cached.hi end
    local bestMin, bestMax = instBounds(inst)
    local p = inst.Parent
    -- never climb into the shared "Plots" folder: it holds the other players' plots too
    if p and p.Name == "Plots" then p = nil end
    while p and p ~= workspace and (p:IsA("Model") or p:IsA("Folder")) do
        local lo, hi = instBounds(p)
        if not lo then break end
        if (hi.X - lo.X) > MAX_PLOT or (hi.Z - lo.Z) > MAX_PLOT then break end
        bestMin, bestMax = lo, hi
        p = p.Parent
    end
    boundsCache[inst] = {lo = bestMin, hi = bestMax, at = os.clock()}
    return bestMin, bestMax
end

-- waiting point: the plot's edge point closest to us, pushed STAGE_BACK studs
-- outward (so in front of the plot, never inside it)
local plotLo, plotHi, plotCenter = nil, nil, nil

local function stagePoint(ppos, inst)
    local hrp = getRoot()
    if not hrp then return nil end
    local me = hrp.Position

    local lo, hi = plotBounds(inst)
    plotLo, plotHi = lo, hi
    plotCenter = lo and Vector3.new((lo.X + hi.X) / 2, ppos.Y, (lo.Z + hi.Z) / 2) or ppos
    if not lo then
        local flat = Vector3.new(me.X - ppos.X, 0, me.Z - ppos.Z)
        local dir  = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, 1)
        return ppos + dir * (STAGE_BACK + 25)
    end

    local cx = math.clamp(me.X, lo.X, hi.X)
    local cz = math.clamp(me.Z, lo.Z, hi.Z)
    local away = Vector3.new(me.X - cx, 0, me.Z - cz)
    if away.Magnitude < 1 then
        -- already inside the box: leave through the nearest edge
        local dists = {
            {me.X - lo.X, Vector3.new(-1, 0, 0)},
            {hi.X - me.X, Vector3.new(1, 0, 0)},
            {me.Z - lo.Z, Vector3.new(0, 0, -1)},
            {hi.Z - me.Z, Vector3.new(0, 0, 1)},
        }
        table.sort(dists, function(a, b) return a[1] < b[1] end)
        away = dists[1][2]
        cx = math.clamp(me.X + away.X * dists[1][1], lo.X, hi.X)
        cz = math.clamp(me.Z + away.Z * dists[1][1], lo.Z, hi.Z)
    end
    return Vector3.new(cx, ppos.Y, cz) + away.Unit * STAGE_BACK
end

-- the player's plot: by owner (Plots.<n>.Data.Owner), position = top of its baseplate
local function findRanchPos()
    local p = findPlot()
    if not p then return nil end
    local top = getPlotTop()
    if not top then
        local pos = getPos(p)
        if not pos then return nil end
        top = pos
    end
    return top, p
end

-- =====================================================================
-- last step: FLY at 700% of walk speed above the fence, then land inside
-- =====================================================================
local RANCH_DEEPER = 15 -- extra studs past the plot centre

local function flyIntoRanch(pos, abortFn)
    local hrp = getRoot()
    local hum = getHum()
    if not hrp or not hum or not pos then return end

    local cruiseY = pos.Y + FLY_HEIGHT
    local aborted = false
    hum.PlatformStand = true

    pcall(function()
        local started = os.clock()
        local dt = 1 / 60
        while not stopFlag and hrp.Parent and os.clock() - started < 40 do
            setNoclip(true)
            if abortFn and abortFn() then aborted = true break end
            -- go all the way to the CENTRE of the plot (not only its edge)
            local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
            if flat.Magnitude < 6 then break end

            local speed = math.max(hum.WalkSpeed * FLY_FRACTION, 8)
            local vy = math.clamp((cruiseY - hrp.Position.Y) / 0.12, -speed * 0.5, speed * 0.5)
            local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
            local v = flat.Unit * math.min(horizontal, flat.Magnitude / math.max(dt, 1 / 240))
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
            dt = RunService.Heartbeat:Wait()
        end

        -- land on the ground inside the plot (not if interrupted: egg lost)
        if not stopFlag and not aborted and hrp.Parent then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {LocalPlayer.Character}
            params.IgnoreWater = true
            local origin = Vector3.new(hrp.Position.X, hrp.Position.Y + 5, hrp.Position.Z)
            local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
            if hit then
                hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0)) * hrp.CFrame.Rotation
            end
        end
    end)

    setNoclip(false)
    hum.PlatformStand = false
    restoreControl()
    return not aborted
end

-- =====================================================================
-- confirmed pick-up of a map egg: fire the prompt until the bar / basket
-- confirms we carry it, standing on the egg if we are far from it
-- =====================================================================
local function grabEgg(egg, timeout)
    local before = basketCount()
    local wasCarrying = isCarrying() == true
    local t0 = os.clock()

    local function confirmed()
        local now = basketCount()
        if before ~= nil and now ~= nil and now > before then return true end
        if not wasCarrying and isCarrying() == true then return true end
        return false
    end

    while os.clock() - t0 < timeout and not stopFlag do
        if confirmed() then return true end

        local prompt = (egg and egg.Parent) and getPrompt(egg) or nil
        if not (prompt and prompt.Parent) then
            -- the egg / prompt is gone: taken (by us or someone else); the bar decides
            task.wait(0.2)
            if confirmed() then return true end
            return isCarrying() == nil and before == nil
        end

        local hrp = getRoot()
        local pos = getPos(prompt.Parent) or eggWorldPos(egg)
        if hrp and pos and (pos - hrp.Position).Magnitude > 10 then
            place(pos + Vector3.new(0, 3, 0))
        end
        firePrompt(prompt)
        task.wait(0.08)
    end
    return confirmed()
end

-- =====================================================================
-- retake of the dropped egg(s): fire the pick-up until we CONFIRM we carry
-- everything again. "The prompt disappeared" is never enough when the bar
-- exists (that was the cause of flying to the plot without the egg).
-- =====================================================================
local function retakeEgg(before, hint, timeout, needCarry, expected, snap)
    local t0 = os.clock()
    local pickRem = findRemote("EggPickup")
    while os.clock() - t0 < timeout and not stopFlag do
        if needCarry and holdingAll(expected) then return true end

        local hrp = getRoot()
        if not hrp then return false end

        -- (a) eggs that just appeared in the map folder
        local target, targetPos, bestD = nil, nil, math.huge
        if snap then
            for _, e in ipairs(newEggsSince(snap)) do
                local p = eggWorldPos(e)
                if p then
                    local d = (p - hrp.Position).Magnitude
                    if d < bestD then target, targetPos, bestD = e, p, d end
                end
            end
        end
        if target then
            if bestD > 8 then place(targetPos + Vector3.new(0, 3, 0)) end
            firePrompt(getPrompt(target))
            if pickRem then pcall(function() pickRem:FireServer(target.Name) end) end
        else
            -- (b) pick-up prompts near us
            local pr = (hint and hint.Parent and hint:IsDescendantOf(workspace)) and hint or nil
            if not pr then
                local best, bestScore = nil, math.huge
                for prompt in pairs(nearbyPickups(60)) do
                    local pos = getPos(prompt.Parent)
                    if pos then
                        local score = (pos - hrp.Position).Magnitude - (before[prompt] and 0 or 1000)
                        if score < bestScore then best, bestScore = prompt, score end
                    end
                end
                pr = best
            end
            if pr then
                local pos = getPos(pr.Parent)
                if pos and (pos - hrp.Position).Magnitude > 8 then
                    place(pos + Vector3.new(0, 3, 0))
                end
                firePrompt(pr)
            elseif not needCarry then
                return true -- nothing left to pick up and no bar to confirm
            end
        end
        task.wait(0.06)
    end
    return needCarry and holdingAll(expected) or false
end

-- =====================================================================
-- plot return: tp in front of the plot (outside), drop the egg, retake it
-- (CONFIRMED), then fly into the plot. Returns false if we could not get in
-- position, otherwise (true, dropFailed, retakeFailed).
-- =====================================================================
local function goToRanchPos(ppos, pinst)
    local hrp0 = getRoot()
    if not hrp0 then return false end

    local stage = stagePoint(ppos, pinst)
    if not stage then return false end

    -- make sure we really arrived (the server may send us back)
    local arrived = false
    for _ = 1, STAGE_TRIES do
        moveTo(stage)
        if stopFlag then return true, false, false end
        task.wait(0.15)
        local h = getRoot()
        if h and (Vector3.new(h.Position.X - stage.X, 0, h.Position.Z - stage.Z)).Magnitude <= 12 then
            arrived = true
            break
        end
    end
    if not arrived then return false end

    -- drop: success if a new pick-up object / egg appears OR the carry state ends
    local carriedAtStart = holdingAny() == true
    local expected = basketCount()
    if expected ~= nil and expected < 1 then expected = nil end
    local before = nearbyPickups(30)
    local snap = snapshotEggs()
    local dropped, droppedPrompt = false, nil
    for level = 1, 3 do
        dropEgg(level)
        local waited = 0
        while waited < (level == 1 and 0.7 or 1.1) and not stopFlag do
            for prompt in pairs(nearbyPickups(30)) do
                if not before[prompt] then droppedPrompt = prompt; break end
            end
            if droppedPrompt or #newEggsSince(snap) > 0 or (carriedAtStart and holdingAny() == false) then
                dropped = true
                break
            end
            task.wait(0.05)
            waited = waited + 0.05
        end
        if dropped or stopFlag then break end
    end
    if stopFlag then return true, false, false end

    local dropFailed = not dropped
    if dropFailed then
        warn("[ShinEggFarm] Drop not detected: the egg stays in the hands, continuing to the plot.")
    else
        -- CONFIRMED retake: we do not leave until the egg is back
        if not retakeEgg(before, droppedPrompt, 6, carriedAtStart, expected, snap) then
            if stopFlag then return true, false, false end
            warn("[ShinEggFarm] Retake not confirmed: not leaving without the egg.")
            return true, false, true
        end
    end
    if stopFlag then return true, dropFailed, false end

    -- fly into the plot; if the egg is lost on the way we stop, retake it, then go again (3 tries)
    local function lost()
        return carriedAtStart and holdingAny() == false
    end
    -- aim a bit deeper than the plot centre, without leaving the plot's box
    local aim = plotCenter or ppos
    local toward = Vector3.new(aim.X - stage.X, 0, aim.Z - stage.Z)
    if toward.Magnitude > 1 then
        aim = aim + toward.Unit * RANCH_DEEPER
    end
    if plotLo and plotHi then
        aim = Vector3.new(
            math.clamp(aim.X, plotLo.X + 6, math.max(plotLo.X + 6, plotHi.X - 6)),
            aim.Y,
            math.clamp(aim.Z, plotLo.Z + 6, math.max(plotLo.Z + 6, plotHi.Z - 6)))
    end

    local retakeFailed = false
    for _ = 1, 3 do
        if stopFlag then break end
        if lost() and not retakeEgg(before, nil, 5, true, expected, snap) then
            retakeFailed = true
            break
        end
        if flyIntoRanch(aim, lost) then break end
    end
    return true, dropFailed, retakeFailed
end

-- =====================================================================
-- full sequence: [volcano] -> tp egg -> confirmed grab -> [dip] -> tp outside
-- the plot -> drop -> confirmed retake -> fly into the plot
-- =====================================================================
local function runSequenceInner(egg)
    local isVolcano = isVolcanoEgg(egg)

    if isVolcano then
        setStatus("volcano path")
        walkVolcanoPath()
        if stopFlag then return end
    end

    local epos = eggPivotPos(egg)
    if not epos then
        setStatus("egg gone")
        return
    end
    setStatus("tp to egg")
    moveTo(epos)
    if stopFlag then return end
    task.wait(0.15)

    setStatus("grabbing")
    if not grabEgg(egg, 6) then
        if not stopFlag then setStatus("egg not picked") end
        if isVolcano then exitVolcanoPath() end
        return
    end
    task.wait(0.1)
    if stopFlag then return end

    if isVolcano then
        setStatus("leaving volcano")
        exitVolcanoPath()
        if stopFlag then return end
    end

    if autoDip then
        setStatus("volcano dip")
        doVolcanoDip()
        if stopFlag then return end
    end

    local ppos, pinst = findRanchPos()
    if not ppos then
        setStatus("plot not found")
        return
    end

    setStatus("drop + retake")
    local reached, dropFailed, retakeFailed = goToRanchPos(ppos, pinst)
    if stopFlag then
        setStatus("stopped")
    elseif not reached then
        setStatus("can't reach plot")
    elseif retakeFailed then
        setStatus("egg not retaken")
    elseif dropFailed then
        setStatus("done (drop not detected)")
    else
        setStatus("done")
    end
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
        warn("[ShinEggFarm] error: " .. tostring(err))
        setStatus("error (see console)")
    end

    restoreControl()
    running = false
    setRunningUI(false)
end

local function stopSequence()
    stopFlag = true
    -- give control back right away (noclip / PlatformStand / velocity)
    task.defer(restoreControl)
end


-- =====================================================================
-- interface: yslemStyle in red / black
-- gradient strokes and texts that rotate, black theme, rounded shapes,
-- bright title bar with a black title
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

-- living stroke (bands rotating around the border)
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

-- living text (bands sweeping through the letters)
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

-- bright title bar, black title
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
    Text = "ready", TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center,
})
livingText(StatusLbl)
statusSetter = function(text) StatusLbl.Text = tostring(text) end

local DiscordLabel = newLabel(Main, {
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, BTN_Y + 28 + 5 + 26 + 4 + 14),
    Text = DISCORD_TEXT, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
})
livingText(DiscordLabel)

-- mini view --------------------------------------------------------
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

-- animation: every living gradient rotates (every other frame)
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

-- egg icons -----------------------------------------------------
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

-- egg list ----------------------------------------------------
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

-- window drag (title bar): follows the finger / mouse anywhere on screen
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

