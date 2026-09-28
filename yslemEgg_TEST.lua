-- yslemEgg diagnostic test -- run THIS FIRST, before the real script.
-- It does nothing except prove Delta can run a pasted script at all and
-- show you something on screen. If this doesn't show a green box with
-- "TEST OK", the problem is with Delta/your workflow, not with yslemEgg's
-- code -- and that's exactly what we need to know next.

print("[yslemEgg TEST] script started")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "yslemEgg TEST",
        Text = "If you see this notification, Delta can run scripts.",
        Duration = 6,
    })
end)

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "yslemEggTest"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or lp:WaitForChild("PlayerGui")

local box = Instance.new("Frame")
box.Size = UDim2.new(0, 300, 0, 120)
box.Position = UDim2.new(0.5, -150, 0.5, -60)
box.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
box.BorderSizePixel = 0
box.Active = true
box.Draggable = true
box.Parent = gui
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -16, 1, -50)
label.Position = UDim2.new(0, 8, 0, 8)
label.BackgroundTransparency = 1
label.Text = "TEST OK\n\nDelta can run scripts and build UI.\nDrag this box. Tap Close when done."
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 14
label.Font = Enum.Font.GothamBold
label.TextWrapped = true
label.Parent = box

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(1, -16, 0, 28)
closeBtn.Position = UDim2.new(0, 8, 1, -36)
closeBtn.BackgroundColor3 = Color3.fromRGB(10, 100, 10)
closeBtn.Text = "Close"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.Parent = box
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

print("[yslemEgg TEST] finished without error")
