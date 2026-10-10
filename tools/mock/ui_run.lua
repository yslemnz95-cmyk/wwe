-- Scenarios UI : une seule fenetre (onglets Steal / Event / Config), widgets, themes, partage de config
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

-- fake JSON: tables are kept in a registry and referenced by a short id
local reg = {}
local Http = M.getService(nil, "HttpService")
Http.JSONEncode = function(_, t) reg[#reg + 1] = t; return "J" .. #reg end
Http.JSONDecode = function(_, s)
	local id = tonumber(tostring(s):match("^J(%d+)$"))
	if id and reg[id] then return reg[id] end
	error("bad json")
end

local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end

local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
local function hasText(root, s) return find(root, function(d) return d.ClassName == "TextLabel" and d.Text == s end) ~= nil end

local lib = loadLib()
check("lib loaded", type(lib) == "table" and type(lib.CreateWindow) == "function")

local win = lib:CreateWindow({Name = "Sources Hub", DefaultTab = "Farm"})
local farm = win:GetDefaultTab()
local combat = win:CreateTab({Name = "Combat"})
local sec = farm:CreateSection({Name = "Auto Farming"})
local seen
local tg = sec:CreateToggle({Name = "Auto Steal", Default = false, Note = "demo", Callback = function(v) seen = v end})
sec:CreateToggle({Name = "Sub", Default = true, SubOf = tg})
local clicks = 0
local btn = sec:CreateButton({Name = "Run it", ButtonText = "Go", ConfirmText = "Done", Callback = function() clicks += 1 end})
local sl = sec:CreateSlider({Name = "Speed", Min = 0, Max = 100, Default = 20, Callback = function() end})
local dd = sec:CreateDropdown({Name = "Mode", Options = {"A", "B", "C"}, Default = "A"})
sec:CreateMultiDropdown({Name = "Rarities", Options = {"Common", "Rare"}, Default = {}})
sec:CreateText({Name = "Info", Text = "hello"})
local csec = combat:CreateSection({Name = "Hits"})
csec:CreateToggle({Name = "Hit Aura", Default = true})
-- a section that belongs to the Event tab
local evSec = farm:CreateSection({Name = "Dr Scramble Lab & Mech"})
evSec:CreateToggle({Name = "Auto Lab", Default = false})

-- the steal panel is built by the logic through NewToolWindow: it must become a tab, not a window
local steal = lib.NewToolWindow({name = "steal", tabName = "StealPanel", tabTitle = "Steal", title = "Steal Panel", w = 262, h = 410})
local marker = Instance.new("Frame"); marker.Name = "Hero"; marker.Parent = steal.content
lib:Finalize({MainTab = farm})
advance(0.5)

local gui = lib.Gui
local main = gui:FindFirstChild("Main")
check("main window exists", main ~= nil)
check("main window widened", main.Size.X.Offset >= 400)
check("no separate steal window", gui:FindFirstChild("SourcesHubSteal") == nil)
check("no separate events window", gui:FindFirstChild("SourcesHubEvents") == nil)
check("side tabs exist", find(main, function(d) return d.Name == "SideTabs" end) ~= nil)
check("bg moon image present", find(main, function(d) return d.ClassName == "ImageLabel" and d.Name == "Bg" and d.Image == "rbxassetid://111331179075915" end) ~= nil)
check("header moon icon", find(main, function(d) return d.ClassName == "ImageLabel" and d.Image == "rbxassetid://111331179075915" and d.Name ~= "Bg" end) ~= nil)

-- subtitle is the discord link, click copies it
check("subtitle is the discord link", hasText(main, "discord.gg/sourceshubs"))
check("old subtitle gone", not hasText(main, "Steal An Egg"))
local sub = find(main, function(d) return d.ClassName == "TextLabel" and d.Text == "discord.gg/sourceshubs" end)
local sb = find(sub, function(d) return d.ClassName == "TextButton" end)
sb.MouseButton1Click:Fire(); advance(0.2)
check("discord link copied on click", clip == "discord.gg/sourceshubs")

-- sidebar: Steal, Event and Config tabs with drawn icons, in a sensible order
local side = find(main, function(d) return d.Name == "SideTabs" end)
local function tabBtn(label)
	return find(side, function(d)
		return d.ClassName == "TextButton" and find(d, function(x) return x.ClassName == "TextLabel" and x.Text == label end) ~= nil
	end)
end
local bFarm, bSteal, bEvent, bConfig = tabBtn("Farm"), tabBtn("Steal"), tabBtn("Event"), tabBtn("Config")
check("tabs Farm/Steal/Event/Config present", bFarm and bSteal and bEvent and bConfig)
check("raw names are not shown", not hasText(side, "StealPanel") and not hasText(side, "Events"))
check("order Farm < Steal < Event < Config", bFarm.LayoutOrder < bSteal.LayoutOrder and bSteal.LayoutOrder < bEvent.LayoutOrder and bEvent.LayoutOrder < bConfig.LayoutOrder)
check("steal/event/config buttons have an icon", bSteal:FindFirstChild("Icon") and bEvent:FindFirstChild("Icon") and bConfig:FindFirstChild("Icon"))

-- steal tab content only shows while the tab is selected
check("steal content hidden on Farm", steal.content.Visible == false)
lib.mainWindow.Select("StealPanel"); advance(0.4)
check("steal content shown on Steal tab", steal.content.Visible == true and steal.tab.page.Visible == true)
lib.mainWindow.Select("Farm"); advance(0.4)
check("steal content hidden again", steal.content.Visible == false)
-- the logic can rebuild the panel: no duplicate tab, old holder removed
local steal2 = lib.NewToolWindow({name = "steal", tabName = "StealPanel", tabTitle = "Steal", title = "Steal Panel"})
local n = 0
for _, d in ipairs(side:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Steal" then n += 1 end end
check("rebuild keeps one Steal tab", n == 1)
check("old holder destroyed", steal.content.Parent == nil and steal2.content.Parent ~= nil)
check("steal window api", type(steal2.SetOpen) == "function" and steal2.frame == steal2.content and steal2.OnClose ~= nil)
local opened
steal2.OnClose.Connect(function(on) opened = on end)
steal2.SetOpen(true); advance(0.1)
check("SetOpen fires OnClose", opened == true)

-- event sections land in the Event tab
local evTab = lib.mainWindow.tabs.Events
check("event section placed in Events tab", evSec.body.Parent == evTab.page)

-- toggle: click the check box
local function toggleBtn(h) return find(h.Instance, function(d) return d.ClassName == "TextButton" and d.Text == "" and d.Parent and d.Parent.ClassName == "Frame" and d.Parent.Size and d.Parent.Size.X.Offset == 26 end) end
local tb = toggleBtn(tg)
check("toggle check box found", tb ~= nil)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle on + callback", tg.Get() == true and seen == true)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle off", tg.Get() == false and seen == false)

local bb = find(btn.Instance, function(d) return d.ClassName == "TextButton" end)
bb.MouseButton1Click:Fire(); advance(0.5)
check("button callback", clicks == 1)

sl:Set(55, true); check("slider value", sl.Get() == 55)
dd:Set("B", true); check("dropdown value", dd.Get() == "B")
local ddBox = find(dd.Instance, function(d) return d.ClassName == "TextButton" end)
ddBox.MouseButton1Click:Fire(); advance(0.2)
local ov = find(main, function(d) return d.ClassName == "Frame" and d.ZIndex == 300 end)
check("picker overlay opens", ov ~= nil and ov.Visible == true)
local cards = 0
for _, d in ipairs(ov:GetDescendants()) do if d.ClassName == "Frame" and d.Size and d.Size.Y.Offset == 30 then cards += 1 end end
check("picker shows 3 flat cards, no tree", cards == 3 and find(ov, function(d) return d.ClassName == "Frame" and d.Size and d.Size.X.Offset == 1 end) == nil)

lib.mainWindow.Select("Combat"); advance(0.4)
check("tab switched", lib.mainWindow.current == "Combat")
lib.mainWindow.Select("Farm"); advance(0.4)

-- config sharing: copy, then import into a "friend's" session
lib.mainWindow.Select("Config"); advance(0.3)
local cfgPage = lib.mainWindow.tabs.Config.page
local function pageButton(text)
	return find(cfgPage, function(d) return d.ClassName == "TextButton" and find(d, function(x) return x.ClassName == "TextLabel" and x.Text == text end) ~= nil end)
end
local copyB, importB = pageButton("Copy"), pageButton("Import")
check("config buttons present", copyB ~= nil and importB ~= nil)
clip = nil
copyB.MouseButton1Click:Fire(); advance(0.3)
check("config copied with SHCFG1 prefix", type(clip) == "string" and clip:sub(1, 7) == "SHCFG1:")
check("copy status shown", find(cfgPage, function(d) return d.ClassName == "TextLabel" and d.Text:find("Copied", 1, true) ~= nil end) ~= nil)

local box = find(cfgPage, function(d) return d.Name == "ConfigBox" end)
reg[#reg + 1] = {["Farm>Auto Farming>Speed"] = 77, ["Farm>Auto Farming>Auto Steal"] = true, ["Some>Other>Key"] = "x"}
box.Text = "SHCFG1:J" .. #reg
importB.MouseButton1Click:Fire(); advance(0.3)
check("import applies the slider live", sl.Get() == 77)
check("import applies the toggle live", tg.Get() == true and seen == true)
check("import reports 3 settings", hasText(cfgPage, "Imported 3 settings"))
check("import box cleared", box.Text == "")
box.Text = "garbage"
importB.MouseButton1Click:Fire(); advance(0.3)
check("invalid import is refused", hasText(cfgPage, "That is not a valid config"))
lib.mainWindow.Select("Farm"); advance(0.3)

-- themes
for _, name in ipairs(lib.ThemeNames) do lib.SetTheme(name); advance(0.2) end
lib.SetTheme("Gold")
check("original theme names kept", #lib.ThemeNames == 4 and lib.ThemeNames[1] == "Gold" and lib.ThemeName == "Gold")

-- main minimise / restore
lib.mainWindow.SetMinimized(true); advance(0.4)
lib.mainWindow.SetMinimized(false); advance(0.4)
check("main restored", main.Visible == true)

lib.Notify("t", "text", 1); lib.Banner("banner", 1); lib.RiskBadge("risk", "txt", 1)
lib.Splash({{Text = "ok", Ok = true}, {Text = "bad", Ok = false}})
advance(1.2)

check("no runtime warnings", #M.warnings == 0)
for _, wmsg in ipairs(M.warnings) do print(wmsg) end
print(string.format("UI: %d ok, %d fail", passes, failures))
if failures > 0 then error("UI tests failed") end
