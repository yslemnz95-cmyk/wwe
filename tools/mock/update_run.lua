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
M.getService(nil, "ReplicatedFirst")
M.getService(nil, "MarketplaceService").GetProductInfo = function() return {Name = "Mock Game"} end
local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end

-- fichiers et presse-papiers
local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end
local genvT = {}; getgenv = function() return genvT end

-- monde
local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players; Players.LocalPlayer = pl; Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
local remotes = mk("Folder", "Remotes", RS)
local gameF = mk("Folder", "Game", remotes)
mk("RemoteEvent", "BasketDrop", gameF); mk("RemoteEvent", "Teleporting", gameF)
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local drop = mk("TextButton", "Drop", sg); drop.Text = "DROP"
local WS = M.getService(nil, "Workspace")
local egg = mk("Part", "Egg", WS)
local pr = mk("ProximityPrompt", "Prompt", egg); pr.ActionText = "Pick Up"; pr.ObjectText = "Dino"; pr.HoldDuration = 0.2

local U = loadUpdate()
advance(0.5)
local pid = tostring(game.PlaceId)
check("module returns version 2", U.Version == 2)
check("first run saves the baseline, latest and a dated copy", files["yslem_gameupdate_" .. pid .. "_baseline.txt"] ~= nil and files["yslem_gameupdate_" .. pid .. "_latest.txt"] ~= nil)
local dated = 0 for k in pairs(files) do if k:find("%d%d%d%d%-%d%d%-%d%d_%d+%.txt$") then dated += 1 end end
check("dated copy written", dated >= 1)
local gui = find(pl.PlayerGui, function(d) return d.Name == "YslemGameUpdate" end) or find(M.getService(nil, "CoreGui"), function(d) return d.Name == "YslemGameUpdate" end)
check("window built", gui ~= nil)
local function labels(root) local t = {} for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" then t[#t + 1] = d.Text end end return t end
local function anyText(root, s) for _, t in ipairs(labels(root)) do if t:find(s, 1, true) then return true end end return false end
check("status: reference created", gui and anyText(gui, "Reference creee"))
check("first run explains what happens next", anyText(gui, "Reference enregistree"))

-- le jeu change : drop deplace, Teleporting supprime, nouveau remote, bouton renomme, prompt plus long
local basket = find(RS, function(d) return d.Name == "BasketDrop" end); basket.Parent = mk("Folder", "Basket", remotes)
find(RS, function(d) return d.Name == "Teleporting" end):Destroy()
mk("RemoteEvent", "NewThing", gameF)
drop.Text = "DROP EGG"; pr.HoldDuration = 0.5
mk("Part", "Egg", WS); mk("Part", "Egg", WS)  -- plus d'oeufs : un simple changement de nombre ne compte pas
local function btn(text) return find(gui, function(d) return d.ClassName == "TextButton" and d.Text == text end) end
local scanBtn = btn("1  Scan")
check("step badges 1-2-3 exist", btn("1  Scan") ~= nil and btn("3  Copier") ~= nil and anyText(gui, "Changements"))
scanBtn.MouseButton1Click:Fire(); advance(0.5)
check("removed remote (SUPPRIME)", anyText(gui, "Remote : Teleporting") and anyText(gui, "RS/Remotes/Game/Teleporting"))
check("moved remote (DEPLACE) shows old and new path", anyText(gui, "RS/Remotes/Game/BasketDrop  ->  RS/Remotes/Basket/BasketDrop"))
check("added remote (NOUVEAU)", anyText(gui, "Remote : NewThing"))
check("button text change (MODIFIE)", anyText(gui, "'DROP' -> 'DROP EGG'"))
check("prompt hold change (MODIFIE)", anyText(gui, "hold=0.5"))
check("status says how many changes", anyText(gui, "5 changements"))
check("category badges show the counts", btn("NOUVEAU  1") ~= nil and btn("SUPPRIME  1") ~= nil and btn("DEPLACE  1") ~= nil and btn("MODIFIE  2") ~= nil)
check("step 1 is marked done once results are shown", anyText(gui, "OK"))
local function rows() local n = 0 for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text:find(" : ", 1, true) and d.TextSize == 12 then n += 1 end end return n end
check("all 5 changes listed", rows() == 5)
btn("NOUVEAU  1").MouseButton1Click:Fire(); advance(0.2)
check("badge filter keeps only NOUVEAU", rows() == 1 and anyText(gui, "Remote : NewThing") and not anyText(gui, "Remote : Teleporting"))
btn("NOUVEAU  1").MouseButton1Click:Fire(); advance(0.2)
check("second tap clears the filter", rows() == 5)

-- copie
btn("3  Copier").MouseButton1Click:Fire()
check("copy: report + full inventory", clip ~= nil and clip:find("Game Update v2", 1, true) ~= nil and clip:find("- [REMOTE] RS/Remotes/Game/Teleporting", 1, true) ~= nil and clip:find("INVENTAIRE COMPLET", 1, true) ~= nil and clip:find("#SNAPSHOT v2", 1, true) ~= nil)

-- nouvelle reference puis plus de changement
btn("Nouvelle ref.").MouseButton1Click:Fire()
check("baseline replaced by the latest scan", files["yslem_gameupdate_" .. pid .. "_baseline.txt"] == files["yslem_gameupdate_" .. pid .. "_latest.txt"])
scanBtn.MouseButton1Click:Fire(); advance(0.5)
check("after baseline: no change", anyText(gui, "Aucun changement"))

-- ancienne reference (format v1) : remplacee automatiquement
files["yslem_gameupdate_" .. pid .. "_baseline.txt"] = "#SNAPSHOT v1\n#GAME x\nREMOTE|RemoteEvent|RS/Old||1"
scanBtn.MouseButton1Click:Fire(); advance(0.5)
check("old-format baseline is replaced, not diffed", anyText(gui, "Ancienne reference remplacee") and files["yslem_gameupdate_" .. pid .. "_baseline.txt"]:find("#SNAPSHOT v2", 1, true) ~= nil)

-- logique pure
local m1, r1 = U.parse("#GAME A\nREMOTE|RemoteEvent|RS/X/Foo||1\nBUTTON|TextButton|GUI/B|a|b|2")
check("parse keeps '|' inside the extra text", r1["BUTTON|GUI/B"] and r1["BUTTON|GUI/B"].extra == "a|b" and r1["BUTTON|GUI/B"].n == 2)
check("player name never in the inventory", not U.lastSnapshot:find("Tester", 1, true))

-- fermeture
check("stop function registered", type(genvT.YslemGameUpdateStop) == "function")
genvT.YslemGameUpdateStop()
check("window closed", gui.Parent == nil)
print(string.format("Update: %d ok, %d fail", passes, failures))
if failures > 0 then error("update tests failed") end
