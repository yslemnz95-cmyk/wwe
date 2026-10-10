local passes, failures = 0, 0
local function check(name, cond) if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end end
local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players
Players.LocalPlayer = pl
Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
local remotes = mk("Folder", "Remotes", RS)
mk("RemoteEvent", "BasketDrop", mk("Folder", "Game", remotes))
mk("RemoteEvent", "Egg_12345", remotes); mk("RemoteEvent", "Egg_98765", remotes)
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local b = mk("TextButton", "Drop", sg); b.Text = "DROP 12"
local WS = M.getService(nil, "Workspace")
local plots = mk("Folder", "Plots", WS); mk("Model", "Plot", plots)
local pr = mk("ProximityPrompt", "Prompt", mk("Part", "Egg", WS)); pr.ActionText = "Pick Up"; pr.ObjectText = "Dino"; pr.HoldDuration = 0.2

local GameScan = loadScan()
local snap = GameScan.snapshot()
check("header", snap:find("#SNAPSHOT v1", 1, true) ~= nil and snap:find("#GAME", 1, true) ~= nil)
check("remote listed with a stable path", snap:find("REMOTE|RemoteEvent|RS/Remotes/Game/BasketDrop||1", 1, true) ~= nil)
check("ids normalised and duplicates counted", snap:find("REMOTE|RemoteEvent|RS/Remotes/Egg_#||2", 1, true) ~= nil)
check("button with normalised text", snap:find("BUTTON|TextButton|GUI/Main/Drop|DROP #|1", 1, true) ~= nil)
check("prompt with action, object and hold", snap:find("PROMPT|ProximityPrompt|WS/Egg/Prompt|Pick Up / Dino / hold=0.2|1", 1, true) ~= nil)
check("world levels", snap:find("WORLD|Folder|WS/Plots|", 1, true) ~= nil and snap:find("WORLD|Model|WS/Plots/Plot|", 1, true) ~= nil)
local lines = {}
for l in snap:gmatch("[^\n]+") do if l:sub(1, 1) ~= "#" then lines[#lines + 1] = l end end
local sorted = true
for i = 2, #lines do if lines[i - 1] > lines[i] then sorted = false end end
check("lines sorted (stable output)", sorted)
check("no player name in the snapshot", snap:find("Tester", 1, true) == nil)
print(string.format("Scan: %d ok, %d fail", passes, failures))
if failures > 0 then error("scan tests failed") end
