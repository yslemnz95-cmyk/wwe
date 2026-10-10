local passes, failures = 0, 0
local function check(name, cond) if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end end
tick = tick or os.clock
Vector2 = {new = function(x, y) return Vector3.new(x, y, 0) end}
ColorSequence = {new = function(a, b)
	if type(a) == "table" and a[1] and a[1].Time then return {Keypoints = a} end
	return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}}
end}
ColorSequenceKeypoint = ColorSequenceKeypoint or {new = function(t, v) return {Time = t, Value = v} end}
local udmt = {__add = function(a, b) return a or b end}
local _new, _off = UDim2.new, UDim2.fromOffset
UDim2.new = function(...) return setmetatable(_new(...), udmt) end
UDim2.fromOffset = function(...) return setmetatable(_off(...), udmt) end
UDim = UDim or {new = function(s, o) return {Scale = s, Offset = o} end}
local UIS = M.getService(nil, "UserInputService")
UIS.InputBegan = M.signal(); UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
M.getService(nil, "ReplicatedFirst"); M.getService(nil, "Lighting")
M.getService(nil, "MarketplaceService").GetProductInfo = function() return {Name = "Mock Game"} end
local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end

local files, clip = {}, nil
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end
local genvT = {}; getgenv = function() return genvT end
require = function(m) return m._data end

local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players; Players.LocalPlayer = pl; Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
mk("RemoteEvent", "BasketDrop", mk("Folder", "Game", mk("Folder", "Remotes", RS)))
local data = mk("Folder", "Data", RS)
local pets = mk("Folder", "Configs", mk("Folder", "Assets", data))
local dino = mk("ModuleScript", "Dino", pets); dino._data = {EarningRate = 12.5, Rarity = "Epic", Name = "Dino", Tags = {"a", "b"}}
local newpet = mk("ModuleScript", "Phoenix", pets); newpet._data = {EarningRate = 99, Rarity = "Secret"}
local bad = mk("ModuleScript", "Broken", data); bad._data = nil
require = function(m) if m.Name == "Broken" then error("boom") end return m._data end
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local drop = mk("TextButton", "Drop", sg); drop.Text = "DROP 12"
local ev = mk("TextLabel", "EventTitle", sg); ev.Text = "Halloween Dimension 2026"
local WS = M.getService(nil, "Workspace")
local egg = mk("Part", "Egg", WS)
local pr = mk("ProximityPrompt", "Prompt", egg); pr.ActionText = "Steal"; pr.ObjectText = "Egg"; pr.HoldDuration = 0

local A = loadAnalyzer()
advance(0.3)
local gui = find(pl.PlayerGui, function(d) return d.Name == "YslemAnalyzer" end) or find(M.getService(nil, "CoreGui"), function(d) return d.Name == "YslemAnalyzer" end)
check("window built", gui ~= nil)
local function btn(prefix) return find(gui, function(d) return d.ClassName == "TextButton" and d.Text:find(prefix, 1, true) ~= nil end) end
local function anyText(s) return find(gui, function(d) return d.ClassName == "TextLabel" and d.Text:find(s, 1, true) ~= nil end) ~= nil end
check("two step buttons", btn("Etape 1") ~= nil and btn("Etape 2") ~= nil)

-- etape 1
btn("Etape 1").MouseButton1Click:Fire(); advance(0.5)
check("step 1: prompt for Claude comes first", clip ~= nil and clip:sub(1, 26) == "GAME UPDATE - etape 1/2 (s")
check("step 1: structure inventory", clip:find("#SNAPSHOT v3", 1, true) and clip:find("#STEP 1/2", 1, true) and clip:find("REMOTE|RemoteEvent|RS/Remotes/Game/BasketDrop||1", 1, true) ~= nil)
check("step 1: button + prompt", clip:find("BUTTON|TextButton|GUI/Main/Drop|DROP #|1", 1, true) and clip:find("PROMPT|ProximityPrompt|WS/Egg/Prompt|Steal / Egg / hold=0|1", 1, true) ~= nil)
check("step 1: module names listed (new pets show up)", clip:find("SCRIPT|ModuleScript|RS/Data/Assets/Configs/Phoenix||1", 1, true) ~= nil)
check("step 1: badge says step 1 done", anyText("Etape 1 faite"))
check("step 1: file saved", files["yslem_analyzer_" .. game.PlaceId .. "_etape1.txt"] ~= nil)

-- etape 2
btn("Etape 2").MouseButton1Click:Fire(); advance(1)
check("step 2: prompt for Claude", clip:sub(1, 26) == "GAME UPDATE - etape 2/2 (c")
check("step 2: module data content", clip:find('DATA|Module|RS/Data/Assets/Configs/Dino|{EarningRate=12.5,Name="Dino",Rarity="Epic",Tags={1="a",2="b"}}|1', 1, true) ~= nil)
check("step 2: new pet data", clip:find('RS/Data/Assets/Configs/Phoenix|{EarningRate=99,Rarity="Secret"}', 1, true) ~= nil)
check("step 2: broken module reported, not fatal", clip:find("RS/Data/Broken|ERR", 1, true) ~= nil)
check("step 2: all texts (events)", clip:find("TEXT|TextLabel|GUI/Main/EventTitle|Halloween Dimension #|1", 1, true) ~= nil)
check("step 2: badge says step 2 done", anyText("Etape 2 faite"))
check("both steps done hint", anyText("Les 2 etapes sont faites"))
check("no player name in the dump", not A.step1:find("Tester", 1, true) and not A.step2:find("Tester", 1, true))

-- fermeture
check("stop function registered", type(genvT.YslemAnalyzerStop) == "function")
genvT.YslemAnalyzerStop()
check("window closed", gui.Parent == nil)
print(string.format("Analyzer: %d ok, %d fail", passes, failures))
if failures > 0 then error("analyzer tests failed") end
