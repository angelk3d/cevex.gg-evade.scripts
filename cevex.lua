repeat task.wait() until game:IsLoaded()
if not _G.CEVEX_SESSION_TOKEN or not _G.CEVEX_HWID then
    error("Cevex Script Error: This script must be launched through Cevex Loader")
    return
end

local API_BASE = "https://cevex-keys-i7h8.vercel.app"

local function verifySession()
    local url = API_BASE .. "/api/checkSession?token=" .. _G.CEVEX_SESSION_TOKEN .. "&hwid=" .. _G.CEVEX_HWID
    
    local success, response = pcall(function()
        return game:HttpGet(url, true)
    end)
    
    if not success then
        error("Cevex Script Error: Session verification failed")
        return false
    end
    
    local data
    success, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(response)
    end)
    
    if not success or not data.valid then
        error("Cevex Script Error: Invalid session. Please use Cevex Loader to activate.")
        return false
    end
    
    return true
end

if not verifySession() then
    return
end

_G.CEVEX_SESSION_TOKEN = nil
_G.CEVEX_HWID = nil

local function checkDebug()
    if not debug.getinfo then
        error("Cevex Script Error: Script execution blocked")
        return false
    end
    return true
end

if not checkDebug() then
    return
end

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local CevexScript = {
    Enabled = false,
    ActiveConnections = {},
    ActiveToggles = {},
    OriginalSettings = {}
}

CevexScript.OriginalSettings.Brightness = game.Lighting.Brightness
CevexScript.OriginalSettings.OutdoorAmbient = game.Lighting.OutdoorAmbient
CevexScript.OriginalSettings.Ambient = game.Lighting.Ambient
CevexScript.OriginalSettings.GlobalShadows = game.Lighting.GlobalShadows
CevexScript.OriginalSettings.FogEnd = game.Lighting.FogEnd
CevexScript.OriginalSettings.FogStart = game.Lighting.FogStart
CevexScript.OriginalSettings.Gravity = Workspace.Gravity

local CevexUI = {
    Enabled = true,
    MainColor = Color3.fromRGB(255, 255, 255),
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    TextColor = Color3.fromRGB(255, 255, 255),
    AccentColor = Color3.fromRGB(30, 30, 30),
    Position = UDim2.new(0.5, -200, 0.5, -200)
}

local ValueSpeed = 26
local ActiveCFrameSpeedBoost = false
local cframeSpeedConnection = nil
local IsHoldingSpace = false
local bhopEnabled = false
local autoReviveEnabled = false
local ActiveEspPlayers = false
local ActiveEspBots = false
local ActiveDistanceEsp = false
local playerAddedConnection = nil
local botLoopConnection = nil
local lastCheckTime = 0
local checkInterval = 5

local function CompleteShutdown()
    for _, connection in pairs(CevexScript.ActiveConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    if cframeSpeedConnection then cframeSpeedConnection:Disconnect() end
    if playerAddedConnection then playerAddedConnection:Disconnect() end
    if botLoopConnection then botLoopConnection:Disconnect() end
    
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character and plr.Character:FindFirstChild("Head") then
            RemoveEsp(plr.Character, plr.Character.Head)
        end
    end
    
    local botsFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Players")
    if botsFolder then
        for _, bot in pairs(botsFolder:GetChildren()) do
            if bot:IsA("Model") and bot:FindFirstChild("Hitbox") then
                bot.Hitbox.Transparency = 1
                RemoveEsp(bot, bot.Hitbox)
            end
        end
    end
    
    game.Lighting.Brightness = CevexScript.OriginalSettings.Brightness
    game.Lighting.OutdoorAmbient = CevexScript.OriginalSettings.OutdoorAmbient
    game.Lighting.Ambient = CevexScript.OriginalSettings.Ambient
    game.Lighting.GlobalShadows = CevexScript.OriginalSettings.GlobalShadows
    game.Lighting.FogEnd = CevexScript.OriginalSettings.FogEnd
    game.Lighting.FogStart = CevexScript.OriginalSettings.FogStart
    Workspace.Gravity = CevexScript.OriginalSettings.Gravity
    
    CevexScript.ActiveConnections = {}
    CevexScript.ActiveToggles = {}
    
    ActiveCFrameSpeedBoost = false
    bhopEnabled = false
    autoReviveEnabled = false
    ActiveEspPlayers = false
    ActiveEspBots = false
end

local function RemoveEsp(Char, ParentPart)
    if Char then
        local highlight = Char:FindFirstChild("ESP_Highlight")
        if highlight then highlight:Destroy() end
    end
    if ParentPart then
        local billboard = ParentPart:FindFirstChild("ESP")
        if billboard then billboard:Destroy() end
    end
end

local function CreateEsp(Char, Color, Text, ParentPart, YOffset)
    if not Char or not ParentPart or not ParentPart:IsA("BasePart") then return end
    if Char:FindFirstChild("ESP_Highlight") and ParentPart:FindFirstChild("ESP") then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.Adornee = Char
    highlight.FillColor = Color
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.Parent = Char

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP"
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.AlwaysOnTop = true
    billboard.StudsOffset = Vector3.new(0, YOffset, 0)
    billboard.Adornee = ParentPart
    billboard.Enabled = true
    billboard.Parent = ParentPart

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(Text) or ""
    label.TextColor3 = Color
    label.TextScaled = true
    label.Font = Enum.Font.SourceSansBold
    label.Parent = billboard

    local distanceUpdateConnection
    distanceUpdateConnection = RunService.Heartbeat:Connect(function()
        if not highlight.Parent or not billboard.Parent or not ParentPart.Parent then
            distanceUpdateConnection:Disconnect()
            return
        end
        
        local Camera = Workspace.CurrentCamera
        if Camera then
            local cameraPosition = Camera.CFrame.Position
            local distance = (cameraPosition - ParentPart.Position).Magnitude
            local safeText = tostring(Text) or ""
            if ActiveDistanceEsp then
                label.Text = safeText .. " " .. tostring(math.floor(distance + 0.5)) .. "m"
            else
                label.Text = safeText
            end
        end
    end)
    
    table.insert(CevexScript.ActiveConnections, distanceUpdateConnection)
end

local function SavePosition(position)
    if writefile then
        pcall(function()
            writefile("cevex_position.txt", tostring(position.X.Scale) .. "," .. tostring(position.X.Offset) .. "," .. tostring(position.Y.Scale) .. "," .. tostring(position.Y.Offset))
        end)
    end
end

local function LoadPosition()
    if readfile and isfile("cevex_position.txt") then
        local success, data = pcall(function()
            local content = readfile("cevex_position.txt")
            local values = {}
            for value in content:gmatch("([^,]+)") do
                table.insert(values, tonumber(value))
            end
            if #values == 4 then
                return UDim2.new(values[1], values[2], values[3], values[4])
            end
        end)
        if success and data then
            return data
        end
    end
    return CevexUI.Position
end

local function CreateLoadingAnimation()
    local LoadingGui = Instance.new("ScreenGui")
    LoadingGui.Name = "CevexLoading"
    LoadingGui.ResetOnSpawn = false
    LoadingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    local LoadingText = Instance.new("TextLabel")
    LoadingText.Size = UDim2.new(0, 500, 0, 150)
    LoadingText.Position = UDim2.new(0.5, -250, 0.5, -75)
    LoadingText.BackgroundTransparency = 1
    LoadingText.Text = "cevex"
    LoadingText.TextColor3 = Color3.fromRGB(255, 255, 255)
    LoadingText.TextSize = 80
    LoadingText.Font = Enum.Font.GothamBold
    LoadingText.TextTransparency = 1
    
    LoadingText.Parent = LoadingGui
    LoadingGui.Parent = game.CoreGui
    
    local tweenIn = TweenService:Create(LoadingText, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})
    local tweenOut = TweenService:Create(LoadingText, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
    
    tweenIn:Play()
    tweenIn.Completed:Wait()
    wait(0.5)
    tweenOut:Play()
    tweenOut.Completed:Wait()
    
    LoadingGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CevexGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 450, 0, 500)
MainFrame.Position = LoadPosition()
MainFrame.BackgroundColor3 = CevexUI.BackgroundColor
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.BackgroundTransparency = 1

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 40)
Header.Position = UDim2.new(0, 0, 0, 0)
Header.BackgroundColor3 = CevexUI.AccentColor
Header.BorderSizePixel = 0
Header.BackgroundTransparency = 1

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "cevex.gg"
Title.TextColor3 = CevexUI.MainColor
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left

local CloseButton = Instance.new("TextButton")
CloseButton.Name = "CloseButton"
CloseButton.Size = UDim2.new(0, 25, 0, 25)
CloseButton.Position = UDim2.new(1, -30, 0, 7)
CloseButton.BackgroundTransparency = 1
CloseButton.TextColor3 = CevexUI.MainColor
CloseButton.Text = "×"
CloseButton.TextSize = 24
CloseButton.Font = Enum.Font.GothamBold
CloseButton.BorderSizePixel = 0

local TabContainer = Instance.new("Frame")
TabContainer.Name = "TabContainer"
TabContainer.Size = UDim2.new(1, -20, 0, 35)
TabContainer.Position = UDim2.new(0, 10, 0, 45)
TabContainer.BackgroundColor3 = CevexUI.AccentColor
TabContainer.BorderSizePixel = 0
TabContainer.BackgroundTransparency = 1

local TabCorner = Instance.new("UICorner")
TabCorner.CornerRadius = UDim.new(0, 6)
TabCorner.Parent = TabContainer

local ContentContainer = Instance.new("Frame")
ContentContainer.Name = "ContentContainer"
ContentContainer.Size = UDim2.new(1, -15, 1, -90)
ContentContainer.Position = UDim2.new(0, 10, 0, 85)
ContentContainer.BackgroundTransparency = 1
ContentContainer.ClipsDescendants = true

local Elements = {}

local function CreateTab(name)
    local TabButton = Instance.new("TextButton")
    TabButton.Name = name .. "Tab"
    TabButton.Size = UDim2.new(0.25, -5, 1, -6)
    TabButton.Position = UDim2.new((#Elements * 0.25), 5, 0, 3)
    TabButton.BackgroundColor3 = CevexUI.BackgroundColor
    TabButton.TextColor3 = CevexUI.MainColor
    TabButton.Text = name
    TabButton.TextSize = 12
    TabButton.Font = Enum.Font.GothamBold
    
    local TabButtonCorner = Instance.new("UICorner")
    TabButtonCorner.CornerRadius = UDim.new(0, 4)
    TabButtonCorner.Parent = TabButton
    
    local ContentFrame = Instance.new("ScrollingFrame")
    ContentFrame.Name = name .. "Content"
    ContentFrame.Size = UDim2.new(1, 0, 1, 0)
    ContentFrame.Position = UDim2.new(0, 0, 0, 0)
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.ScrollBarThickness = 2
    ContentFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
    ContentFrame.ScrollBarImageTransparency = 0.8
    ContentFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    ContentFrame.VerticalScrollBarInset = Enum.ScrollBarInset.Always
    ContentFrame.Visible = #Elements == 0
    ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Padding = UDim.new(0, 8)
    UIListLayout.Parent = ContentFrame
    
    TabButton.MouseButton1Click:Connect(function()
        for _, tab in pairs(TabContainer:GetChildren()) do
            if tab:IsA("TextButton") then
                tab.BackgroundColor3 = CevexUI.BackgroundColor
                tab.TextColor3 = CevexUI.MainColor
            end
        end
        for _, content in pairs(ContentContainer:GetChildren()) do
            if content:IsA("ScrollingFrame") then
                content.Visible = false
            end
        end
        TabButton.BackgroundColor3 = CevexUI.MainColor
        TabButton.TextColor3 = CevexUI.BackgroundColor
        ContentFrame.Visible = true
    end)
    
    if #Elements == 0 then
        TabButton.BackgroundColor3 = CevexUI.MainColor
        TabButton.TextColor3 = CevexUI.BackgroundColor
    end
    
    TabButton.Parent = TabContainer
    ContentFrame.Parent = ContentContainer
    
    table.insert(Elements, {
        Tab = TabButton,
        Content = ContentFrame
    })
    
    return ContentFrame
end

local function CreateToggle(parent, config)
    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Size = UDim2.new(1, -20, 0, 30)
    ToggleFrame.Position = UDim2.new(0, 10, 0, 0)
    ToggleFrame.BackgroundTransparency = 1
    ToggleFrame.LayoutOrder = #parent:GetChildren()
    
    local ToggleButton = Instance.new("TextButton")
    ToggleButton.Size = UDim2.new(0, 45, 0, 22)
    ToggleButton.Position = UDim2.new(0, 0, 0, 4)
    ToggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    ToggleButton.Text = ""
    
    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(0, 11)
    ToggleCorner.Parent = ToggleButton
    
    local ToggleIndicator = Instance.new("Frame")
    ToggleIndicator.Size = UDim2.new(0, 18, 0, 18)
    ToggleIndicator.Position = UDim2.new(0, 2, 0, 2)
    ToggleIndicator.BackgroundColor3 = CevexUI.MainColor
    
    local IndicatorCorner = Instance.new("UICorner")
    IndicatorCorner.CornerRadius = UDim.new(0, 9)
    IndicatorCorner.Parent = ToggleIndicator
    
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -50, 1, 0)
    Label.Position = UDim2.new(0, 50, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = config.Name
    Label.TextColor3 = CevexUI.TextColor
    Label.TextSize = 13
    Label.Font = Enum.Font.Gotham
    Label.TextXAlignment = Enum.TextXAlignment.Left
    
    local function UpdateToggle(state)
        config.CurrentValue = state
        local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        if state then
            local tween = TweenService:Create(ToggleIndicator, tweenInfo, {Position = UDim2.new(0, 25, 0, 2)})
            tween:Play()
            ToggleButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        else
            local tween = TweenService:Create(ToggleIndicator, tweenInfo, {Position = UDim2.new(0, 2, 0, 2)})
            tween:Play()
            ToggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        end
        if config.Callback then
            config.Callback(state)
        end
    end
    
    ToggleButton.MouseButton1Click:Connect(function()
        UpdateToggle(not config.CurrentValue)
    end)
    
    UpdateToggle(config.CurrentValue or false)
    
    ToggleIndicator.Parent = ToggleButton
    ToggleButton.Parent = ToggleFrame
    Label.Parent = ToggleFrame
    ToggleFrame.Parent = parent
    
    table.insert(CevexScript.ActiveToggles, {
        Update = UpdateToggle,
        CurrentValue = config.CurrentValue
    })
    
    return {
        Update = UpdateToggle
    }
end

local function CreateSlider(parent, config)
    local SliderFrame = Instance.new("Frame")
    SliderFrame.Size = UDim2.new(1, -20, 0, 35)
    SliderFrame.Position = UDim2.new(0, 10, 0, 0)
    SliderFrame.BackgroundTransparency = 1
    SliderFrame.LayoutOrder = #parent:GetChildren()
    
    local TopPanel = Instance.new("Frame")
    TopPanel.Size = UDim2.new(1, 0, 0, 16)
    TopPanel.Position = UDim2.new(0, 0, 0, 0)
    TopPanel.BackgroundTransparency = 1
    TopPanel.Parent = SliderFrame
    
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.65, 0, 1, 0)
    Label.Position = UDim2.new(0, 0, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = config.Name
    Label.TextColor3 = CevexUI.TextColor
    Label.TextSize = 12
    Label.Font = Enum.Font.GothamSemibold
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = TopPanel
    
    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(0.35, 0, 1, 0)
    ValueLabel.Position = UDim2.new(0.65, 0, 0, 0)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Text = tostring(config.CurrentValue)
    ValueLabel.TextColor3 = CevexUI.MainColor
    ValueLabel.TextSize = 12
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
    ValueLabel.Parent = TopPanel
    
    local SliderContainer = Instance.new("Frame")
    SliderContainer.Size = UDim2.new(1, 0, 0, 16)
    SliderContainer.Position = UDim2.new(0, 0, 0, 18)
    SliderContainer.BackgroundTransparency = 1
    SliderContainer.Parent = SliderFrame
    
    local SliderTrack = Instance.new("Frame")
    SliderTrack.Size = UDim2.new(1, 0, 0, 3)
    SliderTrack.Position = UDim2.new(0, 0, 0.5, -1.5)
    SliderTrack.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    SliderTrack.BorderSizePixel = 0
    
    local TrackCorner = Instance.new("UICorner")
    TrackCorner.CornerRadius = UDim.new(1, 0)
    TrackCorner.Parent = SliderTrack
    
    local SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new((config.CurrentValue - config.Range[1]) / (config.Range[2] - config.Range[1]), 0, 1, 0)
    SliderFill.Position = UDim2.new(0, 0, 0, 0)
    SliderFill.BackgroundColor3 = CevexUI.MainColor
    SliderFill.BorderSizePixel = 0
    
    local FillCorner = Instance.new("UICorner")
    FillCorner.CornerRadius = UDim.new(1, 0)
    FillCorner.Parent = SliderFill
    
    local SliderButton = Instance.new("TextButton")
    SliderButton.Size = UDim2.new(0, 10, 0, 10)
    SliderButton.Position = UDim2.new(SliderFill.Size.X.Scale, -5, 0.5, -5)
    SliderButton.BackgroundColor3 = CevexUI.MainColor
    SliderButton.Text = ""
    SliderButton.ZIndex = 2
    SliderButton.AutoButtonColor = false
    
    local ButtonCorner = Instance.new("UICorner")
    ButtonCorner.CornerRadius = UDim.new(1, 0)
    ButtonCorner.Parent = SliderButton
    
    local function UpdateSlider(value)
        value = math.clamp(value, config.Range[1], config.Range[2])
        value = math.floor(value / config.Increment) * config.Increment
        
        local fillWidth = (value - config.Range[1]) / (config.Range[2] - config.Range[1])
        SliderFill.Size = UDim2.new(fillWidth, 0, 1, 0)
        SliderButton.Position = UDim2.new(fillWidth, -5, 0.5, -5)
        ValueLabel.Text = tostring(value)
        
        if config.Callback then
            config.Callback(value)
        end
    end
    
    local dragging = false
    
    local function updateFromMouse()
        if dragging then
            local mousePos = UserInputService:GetMouseLocation()
            local trackPos = SliderTrack.AbsolutePosition
            local trackSize = SliderTrack.AbsoluteSize
            local relativeX = math.clamp((mousePos.X - trackPos.X) / trackSize.X, 0, 1)
            local value = config.Range[1] + relativeX * (config.Range[2] - config.Range[1])
            UpdateSlider(value)
        end
    end
    
    SliderButton.MouseButton1Down:Connect(function()
        dragging = true
    end)
    
    local TrackButton = Instance.new("TextButton")
    TrackButton.Size = UDim2.new(1, 0, 1, 0)
    TrackButton.Position = UDim2.new(0, 0, 0, 0)
    TrackButton.BackgroundTransparency = 1
    TrackButton.Text = ""
    TrackButton.ZIndex = 1
    TrackButton.Parent = SliderTrack
    
    TrackButton.MouseButton1Down:Connect(function()
        dragging = true
        updateFromMouse()
    end)
    
    local connection
    connection = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    table.insert(CevexScript.ActiveConnections, connection)
    
    local connection2
    connection2 = UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromMouse()
        end
    end)
    table.insert(CevexScript.ActiveConnections, connection2)
    
    SliderFill.Parent = SliderTrack
    SliderButton.Parent = SliderContainer
    SliderTrack.Parent = SliderContainer
    
    UpdateSlider(config.CurrentValue)
    SliderFrame.Parent = parent
    
    return {
        Update = UpdateSlider
    }
end

local function CreateButton(parent, config)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, -20, 0, 35)
    Button.Position = UDim2.new(0, 10, 0, 0)
    Button.BackgroundColor3 = CevexUI.AccentColor
    Button.TextColor3 = CevexUI.TextColor
    Button.Text = config.Name
    Button.TextSize = 13
    Button.Font = Enum.Font.GothamBold
    Button.LayoutOrder = #parent:GetChildren()
    
    local ButtonCorner = Instance.new("UICorner")
    ButtonCorner.CornerRadius = UDim.new(0, 6)
    ButtonCorner.Parent = Button
    
    Button.MouseButton1Click:Connect(function()
        if config.Callback then
            config.Callback()
        end
    end)
    
    Button.Parent = parent
end

Header.Parent = MainFrame
Title.Parent = Header
CloseButton.Parent = Header
TabContainer.Parent = MainFrame
ContentContainer.Parent = MainFrame
MainFrame.Parent = ScreenGui

local dragging = false
local dragInput, dragStart, startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

local dragConnection
dragConnection = UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        SavePosition(MainFrame.Position)
    end
end)
table.insert(CevexScript.ActiveConnections, dragConnection)

CloseButton.MouseButton1Click:Connect(function()
    CevexUI.Enabled = false
    ScreenGui.Enabled = false
    CompleteShutdown()
end)

local toggleConnection
toggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.RightControl then
        CevexUI.Enabled = not CevexUI.Enabled
        ScreenGui.Enabled = CevexUI.Enabled
        
        if CevexUI.Enabled then
            MainFrame.BackgroundTransparency = 1
            Header.BackgroundTransparency = 1
            TabContainer.BackgroundTransparency = 1
            
            local tweenMain = TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
            local tweenHeader = TweenService:Create(Header, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
            local tweenTab = TweenService:Create(TabContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
            
            tweenMain:Play()
            tweenHeader:Play()
            tweenTab:Play()
        end
    end
end)
table.insert(CevexScript.ActiveConnections, toggleConnection)

ScreenGui.Parent = game.CoreGui
ScreenGui.Enabled = false

local spaceBeganConnection
spaceBeganConnection = UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
    if InputObject.KeyCode == Enum.KeyCode.Space and not GameProcessedEvent then
        IsHoldingSpace = true
    end
end)
table.insert(CevexScript.ActiveConnections, spaceBeganConnection)

local spaceEndedConnection
spaceEndedConnection = UserInputService.InputEnded:Connect(function(InputObject, GameProcessedEvent)
    if InputObject.KeyCode == Enum.KeyCode.Space then
        IsHoldingSpace = false
    end
end)
table.insert(CevexScript.ActiveConnections, spaceEndedConnection)

local function ConnectBhop(Humanoid)
    local bhopConnection
    bhopConnection = Humanoid.StateChanged:Connect(function(_, NewState)
        if NewState == Enum.HumanoidStateType.Landed then
            if IsHoldingSpace and bhopEnabled then
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)
    table.insert(CevexScript.ActiveConnections, bhopConnection)
end

if LocalPlayer.Character then
    local Humanoid = LocalPlayer.Character:WaitForChild("Humanoid")
    ConnectBhop(Humanoid)
end

local characterAddedConnection
characterAddedConnection = LocalPlayer.CharacterAdded:Connect(function(NewCharacter)
    local Humanoid = NewCharacter:WaitForChild("Humanoid")
    ConnectBhop(Humanoid)
end)
table.insert(CevexScript.ActiveConnections, characterAddedConnection)

local function applyFullBrightness()
    game.Lighting.Brightness = 2
    game.Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    game.Lighting.Ambient = Color3.fromRGB(255, 255, 255)
    game.Lighting.GlobalShadows = false
end

local function applyNoFog()
    game.Lighting.FogEnd = 1000000
    game.Lighting.FogStart = 999999
end

local function applyColorBoost()
    if not game.Lighting:FindFirstChild("ColorCorrection") then
        local colorCorrection = Instance.new("ColorCorrectionEffect")
        colorCorrection.Parent = game.Lighting
    end
    game.Lighting.ColorCorrection.Enabled = true
    game.Lighting.ColorCorrection.Saturation = 0.8
    game.Lighting.ColorCorrection.Contrast = 0.4
end

local function handlePlayerEsp(player)
    if player ~= LocalPlayer and player.Character then
        local function createPlayerEspOnCharacter(character)
            if ActiveEspPlayers and character:FindFirstChild("Head") then
                CreateEsp(character, Color3.new(0.8, 0.8, 0.8), player.Name, character.Head, 1)
            end
        end

        createPlayerEspOnCharacter(player.Character)

        local charAddedConnection
        charAddedConnection = player.CharacterAdded:Connect(function(newCharacter)
            task.wait(0.1)
            createPlayerEspOnCharacter(newCharacter)
        end)
        table.insert(CevexScript.ActiveConnections, charAddedConnection)

        local charRemovingConnection
        charRemovingConnection = player.CharacterRemoving:Connect(function(oldCharacter)
            if oldCharacter:FindFirstChild("Head") then
                RemoveEsp(oldCharacter, oldCharacter.Head)
            end
        end)
        table.insert(CevexScript.ActiveConnections, charRemovingConnection)
    end
end

local MainTab = CreateTab("Main")
local AuticTab = CreateTab("Autic")
local WhTab = CreateTab("Wh")
local SetsTab = CreateTab("Sets")

local speedSlider = CreateSlider(MainTab, {
    Name = "Speed Value",
    Range = {20, 50},
    Increment = 1,
    CurrentValue = 26,
    Callback = function(Value)
        ValueSpeed = Value
        if ActiveCFrameSpeedBoost and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = ValueSpeed
        end
    end,
})

CreateToggle(MainTab, {
    Name = "Speed Multiplayer",
    CurrentValue = false,
    Callback = function(Value)
        ActiveCFrameSpeedBoost = Value
        if ActiveCFrameSpeedBoost then
            if cframeSpeedConnection then
                cframeSpeedConnection:Disconnect()
                cframeSpeedConnection = nil
            end

            cframeSpeedConnection = RunService.RenderStepped:Connect(function()
                local character = LocalPlayer.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local hrp = character and character:FindFirstChild("HumanoidRootPart")

                if character and humanoid and hrp then
                    local moveDir = humanoid.MoveDirection
                    if moveDir.Magnitude > 0 then
                        hrp.CFrame = hrp.CFrame + moveDir * math.max(ValueSpeed, 1) * 0.080
                    end
                end
            end)
            table.insert(CevexScript.ActiveConnections, cframeSpeedConnection)
        else
            if cframeSpeedConnection then
                cframeSpeedConnection:Disconnect()
                cframeSpeedConnection = nil
            end
        end
    end,
})

CreateToggle(MainTab, {
    Name = "Bhop",
    CurrentValue = false,
    Callback = function(Value)
        bhopEnabled = Value
    end,
})

local gravitySlider = CreateSlider(MainTab, {
    Name = "Gravity",
    Range = {0, 192},
    Increment = 1,
    CurrentValue = 50,
    Callback = function(Value)
        Workspace.Gravity = Value
    end,
})

CreateButton(MainTab, {
    Name = "Reset Gravity",
    Callback = function()
        Workspace.Gravity = 50
        gravitySlider:Update(50)
    end,
})

CreateButton(AuticTab, {
    Name = "Revive",
    Callback = function()
        local player = LocalPlayer
        local character = player.Character
        if character and character:GetAttribute("Downed") then
            local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
            if eventsFolder then
                local playerFolder = eventsFolder:WaitForChild("Player", 10)
                if playerFolder then
                    local changeModeEvent = playerFolder:WaitForChild("ChangePlayerMode", 10)
                    if changeModeEvent then
                        changeModeEvent:FireServer(true)
                    end
                end
            end
        end
    end,
})

CreateToggle(AuticTab, {
    Name = "Auto Revive Yourself",
    CurrentValue = false,
    Callback = function(Value)
        autoReviveEnabled = Value
    end,
})

CreateToggle(WhTab, {
    Name = "Players Wh",
    CurrentValue = false,
    Callback = function(Value)
        ActiveEspPlayers = Value
        if ActiveEspPlayers then
            for _, plr in pairs(Players:GetPlayers()) do
                handlePlayerEsp(plr)
            end

            playerAddedConnection = Players.PlayerAdded:Connect(function(newPlayer)
                handlePlayerEsp(newPlayer)
            end)
            table.insert(CevexScript.ActiveConnections, playerAddedConnection)
        else
            if playerAddedConnection then
                playerAddedConnection:Disconnect()
                playerAddedConnection = nil
            end
            
            for _, plr in pairs(Players:GetPlayers()) do
                if plr.Character and plr.Character:FindFirstChild("Head") then
                    RemoveEsp(plr.Character, plr.Character.Head)
                end
            end
        end
    end,
})

CreateToggle(WhTab, {
    Name = "Bots Wh",
    CurrentValue = false,
    Callback = function(Value)
        ActiveEspBots = Value
        if ActiveEspBots then
            botLoopConnection = RunService.Heartbeat:Connect(function()
                local botsFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Players")
                if botsFolder then
                    for _, bot in pairs(botsFolder:GetChildren()) do
                        if bot:IsA("Model") and bot:FindFirstChild("Hitbox") then
                            bot.Hitbox.Transparency = 0.5
                            CreateEsp(bot, Color3.new(0.8, 0.8, 0.8), bot.Name, bot.Hitbox, -2)
                        end
                    end
                end
            end)
            table.insert(CevexScript.ActiveConnections, botLoopConnection)
        else
            if botLoopConnection then
                botLoopConnection:Disconnect()
                botLoopConnection = nil
            end
            local botsFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Players")
            if botsFolder then
                for _, bot in pairs(botsFolder:GetChildren()) do
                    if bot:IsA("Model") and bot:FindFirstChild("Hitbox") then
                        bot.Hitbox.Transparency = 1
                        RemoveEsp(bot, bot.Hitbox)
                    end
                end
            end
        end
    end,
})

CreateToggle(WhTab, {
    Name = "Distance Wh",
    CurrentValue = false,
    Callback = function(Value)
        ActiveDistanceEsp = Value
    end,
})

CreateToggle(SetsTab, {
    Name = "Full Brightness",
    CurrentValue = false,
    Callback = function(Value)
        if Value then
            applyFullBrightness()
        else
            game.Lighting.Brightness = CevexScript.OriginalSettings.Brightness
            game.Lighting.OutdoorAmbient = CevexScript.OriginalSettings.OutdoorAmbient
            game.Lighting.Ambient = CevexScript.OriginalSettings.Ambient
            game.Lighting.GlobalShadows = CevexScript.OriginalSettings.GlobalShadows
        end
    end,
})

CreateToggle(SetsTab, {
    Name = "No Fog",
    CurrentValue = false,
    Callback = function(Value)
        if Value then
            applyNoFog()
        else
            game.Lighting.FogEnd = CevexScript.OriginalSettings.FogEnd
            game.Lighting.FogStart = CevexScript.OriginalSettings.FogStart
        end
    end,
})

CreateToggle(SetsTab, {
    Name = "Color Boost",
    CurrentValue = false,
    Callback = function(Value)
        if Value then
            applyColorBoost()
        else
            if game.Lighting:FindFirstChild("ColorCorrection") then
                game.Lighting.ColorCorrection.Enabled = false
            end
        end
    end,
})

CreateToggle(SetsTab, {
    Name = "Anti-AFK",
    CurrentValue = true,
    Callback = function(Value)
        afk = Value
        if Value then
            local afkConnection
            afkConnection = RunService.Heartbeat:Connect(function()
                if afk then
                    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end
            end)
            table.insert(CevexScript.ActiveConnections, afkConnection)
        end
    end,
})

local reviveConnection
reviveConnection = RunService.Heartbeat:Connect(function()
    if autoReviveEnabled then
        if tick() - lastCheckTime >= checkInterval then
            lastCheckTime = tick()
            local player = LocalPlayer
            local character = player.Character
            if character and character:GetAttribute("Downed") then
                local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
                if eventsFolder then
                    local playerFolder = eventsFolder:WaitForChild("Player", 10)
                    if playerFolder then
                        local changeModeEvent = playerFolder:WaitForChild("ChangePlayerMode", 10)
                        if changeModeEvent then
                            changeModeEvent:FireServer(true)
                        end
                    end
                end
            end
        end
    end
end)
table.insert(CevexScript.ActiveConnections, reviveConnection)

spawn(function()
    CreateLoadingAnimation()
    
    ScreenGui.Enabled = true
    
    local tweenMain = TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
    local tweenHeader = TweenService:Create(Header, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
    local tweenTab = TweenService:Create(TabContainer, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
    
    tweenMain:Play()
    tweenHeader:Play()
    tweenTab:Play()
end)
