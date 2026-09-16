-- Version 4.58
local Player = {}

function Player.register(context)
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    local tab = context.Tab
    local section = tab:Section({Title = "กินอาหารอัตโนมัติ", Opened = true})
    if not section then return end
    local enabled = false
    local running = false
    local targetHunger = 100
    local DEFAULT_HUNGER = 100
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
    end

    local function setEnabled(value)
        enabled = value
        if enabled and not running then running = true task.spawn(loop) end
    end

    local shieldPart = nil
    local function setShield(value)
        local hrp = getHRP()
        if value and hrp then
            if not shieldPart then
                shieldPart = Instance.new("Part")
                shieldPart.Name = "ProjectileShield"
                shieldPart.Size = Vector3.new(20, 20, 20)
                shieldPart.Transparency = 1
                shieldPart.CanCollide = false
                shieldPart.CanTouch = false
                shieldPart.CanQuery = false
                shieldPart.Anchored = false
                shieldPart.Massless = true
                shieldPart.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
                shieldPart.Material = Enum.Material.ForceField
                shieldPart.Color = Color3.fromRGB(0, 170, 255)
                shieldPart.CFrame = hrp.CFrame
                shieldPart.Parent = hrp.Parent

                local weld = Instance.new("WeldConstraint")
                weld.Part0 = shieldPart
                weld.Part1 = hrp
                weld.Parent = shieldPart
                shieldPart.AssemblyLinearVelocity = Vector3.zero
                shieldPart.AssemblyAngularVelocity = Vector3.zero
            end
            task.spawn(function()
                while shieldPart and shieldPart.Parent do
                    local currentHRP = getHRP()
                    local projectiles = workspace:FindFirstChild("Projectiles")
                    if currentHRP and projectiles then
                        for _, obj in ipairs(projectiles:GetChildren()) do
                            if obj:IsA("BasePart") and (obj.Position - currentHRP.Position).Magnitude <= 10 then
                                pcall(function() obj:Destroy() end)
                            end
                        end
                    end
                    task.wait(0.1)
                end
            end)
        elseif shieldPart then
            shieldPart:Destroy()
            shieldPart = nil
        end
    end

    section:Toggle({
        Title = "กินอาหารอัตโนมัติ",
        Value = false,
        Callback = setEnabled,
    })
    section:Slider({
        Title = "กินจนถึงความหิว",
        Value = {Min = 1, Max = MAX_HUNGER, Default = DEFAULT_HUNGER},
        Step = 1,
        Callback = function(value)
            targetHunger = math.clamp(value, 1, MAX_HUNGER)
        end,
    })

    local shieldSection = tab:Section({Title = "โล่ป้องกันอาวุธระยะไกล", Opened = true})
    shieldSection:Toggle({
        Title = "โล่ป้องกัน (ระยะ 10 studs)",
        Value = false,
        Callback = setShield,
    })

    if not shieldSection then return end

end

return Player
