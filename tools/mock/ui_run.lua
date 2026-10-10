-- Scenarios UI : fenetre, onglets, widgets, themes, panneau de steal, effets
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end
tick = tick or os.clock
game.IsLoaded = function() return true end
task.delay = function(t, fn, ...) local a = {...}; task.spawn(function() task.wait(t); fn(table.unpack(a)) end) end
Vector2 = {new = function(x, y) return Vector3.new(x, y, 0) end}
NumberSequence = {new = function(...) return {...} end}
NumberSequenceKeypoint = {new = function(t, v) return {Time = t, Value = v} end}
ColorSequence = {new = function(a, b)
	if type(a) == "table" and a[1] and a[1].Time then return {Keypoints = a} end
	return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}}
end}
local _inew = Instance.new
Instance.new = function(c, p)
	local o = _inew(c, p)
	if c == "UIGradient" then o.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)) end
	return o
end
local udmt = {__add = function(a, b) return a or b end}
local _new, _off = UDim2.new, UDim2.fromOffset
UDim2.new = function(...) return setmetatable(_new(...), udmt) end
UDim2.fromOffset = function(...) return setmetatable(_off(...), udmt) end
local UIS = M.getService(nil, "UserInputService")
UIS.InputBegan = M.signal(); UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
local pl = M.newInst("Player"); pl.Character = M.newInst("Model"); pl.PlayerGui = M.newInst("Folder")
M.getService(nil, "Players").LocalPlayer = pl
local files = {}
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
setclipboard = function() end

local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
local lib = loadLib()
check("lib loaded", type(lib) == "table" and type(lib.CreateWindow) == "function")

local win = lib:CreateWindow({Name = "Sources Hub", DefaultTab = "Farm"})
local farm = win:GetDefaultTab()
local combat = win:CreateTab({Name = "Combat"})
local sec = farm:CreateSection({Name = "Auto Farming"})
local seen
local tg = sec:CreateToggle({Name = "Auto Steal", Default = false, Note = "demo", Callback = function(v) seen = v end})
local sub = sec:CreateToggle({Name = "Sub", Default = true, SubOf = tg})
local clicks = 0
local btn = sec:CreateButton({Name = "Run it", ButtonText = "Go", ConfirmText = "Done", Callback = function() clicks += 1 end})
local sl = sec:CreateSlider({Name = "Speed", Min = 0, Max = 100, Default = 20, Callback = function() end})
local dd = sec:CreateDropdown({Name = "Mode", Options = {"A", "B", "C"}, Default = "A"})
local md = sec:CreateMultiDropdown({Name = "Rarities", Options = {"Common", "Rare"}, Default = {}})
sec:CreateText({Name = "Info", Text = "hello"})
local csec = combat:CreateSection({Name = "Hits"})
csec:CreateToggle({Name = "Hit Aura", Default = true})
lib:Finalize({MainTab = farm})
advance(0.5)

local gui = lib.Gui
local main = gui:FindFirstChild("Main")
check("main window exists", main ~= nil)
check("main window widened", main.Size.X.Offset >= 400)
check("side tabs exist", find(main, function(d) return d.Name == "SideTabs" end) ~= nil)
check("bg moon image present", find(main, function(d) return d.ClassName == "ImageLabel" and d.Name == "Bg" and d.Image == "rbxassetid://111331179075915" end) ~= nil)
check("header moon icon", find(main, function(d) return d.ClassName == "ImageLabel" and d.Image == "rbxassetid://111331179075915" and d.Name ~= "Bg" end) ~= nil)
check("subtitle shown", find(main, function(d) return d.ClassName == "TextLabel" and d.Text == "Steal An Egg" end) ~= nil)

-- toggle: click the check box button inside the toggle row
local function toggleBtn(h) return find(h.Instance, function(d) return d.ClassName == "TextButton" and d.Text == "" and d.Parent and d.Parent.ClassName == "Frame" and d.Parent.Size and d.Parent.Size.X.Offset == 26 end) end
local tb = toggleBtn(tg)
check("toggle check box found", tb ~= nil)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle on + callback", tg.Get() == true and seen == true)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle off", tg.Get() == false and seen == false)

-- button
local bb = find(btn.Instance, function(d) return d.ClassName == "TextButton" end)
bb.MouseButton1Click:Fire(); advance(0.5)
check("button callback", clicks == 1)

-- slider api
sl:Set(55, true)
check("slider value", sl.Get() == 55)
-- dropdown + picker
dd:Set("B", true); check("dropdown value", dd.Get() == "B")
local ddBox = find(dd.Instance, function(d) return d.ClassName == "TextButton" end)
ddBox.MouseButton1Click:Fire(); advance(0.2)
local ov = find(main, function(d) return d.ClassName == "Frame" and d.ZIndex == 300 end)
check("picker overlay opens", ov ~= nil and ov.Visible == true)

-- tab switch
lib.mainWindow.Select("Combat"); advance(0.4)
check("tab switched", lib.mainWindow.current == "Combat")
lib.mainWindow.Select("Farm"); advance(0.4)

-- themes
for _, name in ipairs(lib.ThemeNames) do lib.SetTheme(name); advance(0.2) end
lib.SetTheme("Gold")
check("original theme names kept", #lib.ThemeNames == 4 and lib.ThemeNames[1] == "Gold" and lib.ThemeName == "Gold")

-- tool window (steal panel style) incl. open / minimise / reopen
local tool = lib.NewToolWindow({name = "steal", tabName = "StealPanel", frameName = "SourcesHubSteal", title = "Steal Panel", w = 262, h = 410,
	pos = UDim2.new(0, 12, 0.5, -205)})
tool.SetOpen(true); advance(0.6)
check("tool window starts folded in the tray", tool.frame.Visible == false)
tool.SetMinimized(false); advance(0.6)
check("tool window unfolds", tool.frame.Visible == true)
local tsec = tool.tab:CreateSection({Name = "Filters"})
local otg = tsec:CreateToggle({Name = "Only rare", Default = true})
check("tool panel keeps the original pill switch", find(otg.Instance, function(d) return d.ClassName == "Frame" and d.Size and d.Size.X.Offset == 40 end) ~= nil)
check("tool panel keeps the original upper-case section titles", find(tool.frame, function(d) return d.ClassName == "TextLabel" and d.Text == "FILTERS" end) ~= nil)
check("tool panel has no side tabs or background image", find(tool.frame, function(d) return d.Name == "SideTabs" or d.Name == "Bg" end) == nil)
tool.SetMinimized(true); advance(0.6)
check("tool window folds again", tool.frame.Visible == false)
tool.SetMinimized(false); advance(0.6)
check("tool window reopened", tool.frame.Visible == true)

-- main minimise / restore
lib.mainWindow.SetMinimized(true); advance(0.4)
lib.mainWindow.SetMinimized(false); advance(0.4)
check("main restored", main.Visible == true)

-- notifications and badges
lib.Notify("t", "text", 1); lib.Banner("banner", 1); lib.RiskBadge("risk", "txt", 1)
lib.Splash({{Text = "ok", Ok = true}, {Text = "bad", Ok = false}})
advance(1.2)

check("no runtime warnings", #M.warnings == 0)
for _, wmsg in ipairs(M.warnings) do print(wmsg) end
print(string.format("UI: %d ok, %d fail", passes, failures))
if failures > 0 then error("UI tests failed") end
