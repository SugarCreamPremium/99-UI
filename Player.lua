-- Version 12.01
local Player = {}

function Player.register(section, context)
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    local enabled = false
    local running = false
    local targetHunger = 150
    local MAX_HUNGER = 200

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getItemPos(item)
        if item:IsA("Model") then
            if item.PrimaryPart then return item.PrimaryPart.Position end
            local part = item:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position
        elseif item:IsA("BasePart") then
            return item.Position
        end
    end

    local function findClosestFood()
        local hrp = getHRP()
        local items = workspace:FindFirstChild("Items")
        if not hrp or not items then return nil end

        local closest, closestDist = nil, math.huge
        for _, item in ipairs(items:GetChildren()) do
            local restore = item:GetAttribute("RestoreHunger")
            local restoreHealth = item:GetAttribute("RestoreHealth")
            if restore and restore > 0 and (restoreHealth == nil or restoreHealth >= 0) then
                local owner = item:GetAttribute("Owner")
                local interaction = item:GetAttribute("Interaction")
                local skip = owner and owner ~= player.UserId
                    or interaction and interaction ~= "Item" and interaction ~= "Tool"
                    or player:GetAttribute("Class") == "Bunny" and item:GetAttribute("HasMeat")
                local pos = not skip and getItemPos(item)
                if pos then
                    local distance = (pos - hrp.Position).Magnitude
                    if distance < closestDist then
                        closest, closestDist = item, distance
                    end
                end
            end
        end
        return closest
    end

    local function consume(item)
        if not Client.PlayerHandler.Alive then return false end
        local parent = item.Parent
        item.Parent = ReplicatedStorage.TempStorage
        local result = Client.Events.RequestConsumeItem:InvokeServer(item)
        if not (result and result.Success) then item.Parent = parent return false end
        return true
    end

    local function pull(item)
        local hrp = getHRP()
        if not hrp then return false end
        return pcall(function()
            local events = ReplicatedStorage.RemoteEvents
            events.RequestStartDraggingItem:FireServer(item)
            task.wait(0.1)
            if item:IsA("Model") then item:PivotTo(CFrame.new(hrp.Position)) else item.CFrame = CFrame.new(hrp.Position) end
            task.wait(0.1)
            events.StopDraggingItem:FireServer(item)
        end)
    end

    local status
    local function loop()
        while enabled do
            if (player:GetAttribute("Hunger") or 100) < targetHunger then
                local food = findClosestFood()
                if food then pull(food) consume(food) task.wait(0.25) else task.wait(1) end
            else
                task.wait(1)
            end
        end
        running = false
        if not enabled then
            status.Text = "สถานะ Auto Eat: ปิดอยู่"
            status.TextColor3 = Color3.fromRGB(150, 150, 150)
        end
    end

    local sectionFrame = rawget(section, "PageContainer")
    if not sectionFrame or not sectionFrame:IsA("GuiObject") then return end
    status = Instance.new("TextLabel")
    status.Name = "AutoEatStatus"
    status.Size = UDim2.new(1, 0, 0, 24)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Nunito
    status.Text = "สถานะ Auto Eat: ปิดอยู่"
    status.TextColor3 = Color3.fromRGB(150, 150, 150)
    status.TextSize = 13
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.LayoutOrder = 99
    status.Parent = sectionFrame

    local function setEnabled(value)
        enabled = value
        status.Text = enabled and "สถานะ Auto Eat: เปิดอยู่" or "สถานะ Auto Eat: ปิดอยู่"
        status.TextColor3 = enabled and Color3.fromRGB(0, 120, 212) or Color3.fromRGB(150, 150, 150)
        if enabled and not running then running = true task.spawn(loop) end
    end

    section:CreateToggle("กินอาหารอัตโนมัติ", setEnabled)
    section:CreateInput("กินจนถึงความหิว", "150", function(value)
        local nextTarget = math.clamp(tonumber(value) or 150, 1, MAX_HUNGER)
        if nextTarget ~= targetHunger then
            targetHunger = nextTarget
            setEnabled(false)
        end
    end)
    section:CreateParagraph("สถานะความหิว", "ระบบจะหาและกินอาหารจนถึงค่าที่กำหนด (สูงสุด 200)")
end

return Player
