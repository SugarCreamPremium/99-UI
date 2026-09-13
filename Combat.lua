-- Version 11.06
local Combat = {}

function Combat.register(section, context)
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
    local range, enabled, running = 80, false, false
    local MAX_RANGE = 80

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function weapon()
        local char = player.Character
        local handle = char and char:FindFirstChild("ToolHandle")
        local item = handle and handle:FindFirstChild("OriginalItem")
        return item and item.Value
    end

    local function attackable(npc)
        if not npc or npc:GetAttribute("NotAttackable") or npc:GetAttribute("Dead") or npc:GetAttribute("Tamed") then return false end
        local humanoid = npc:FindFirstChildOfClass("Humanoid")
        return humanoid and humanoid.Health > 0
    end

    local function loop()
        local damage = ReplicatedStorage.RemoteEvents.ToolDamageObject
        local ownerId = tostring(player.UserId) .. "_" .. player.UserId
        while enabled do
            local item, hrp = weapon(), getHRP()
            if item and hrp then
                local characters = workspace:FindFirstChild("Characters")
                if characters then
                    for _, npc in ipairs(characters:GetChildren()) do
                        local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                        if attackable(npc) and root and (root.Position - hrp.Position).Magnitude <= range then
                            pcall(function()
                                damage:InvokeServer(npc, item, ownerId, CFrame.lookAt(hrp.Position, root.Position), false)
                            end)
                        end
                    end
                end
                task.wait(0.18)
            else
                task.wait(0.5)
            end
        end
        running = false
    end

    local sectionFrame = rawget(section, "PageContainer")
    if not sectionFrame then return end
    local toggleFrame
    local function setToggleVisual(value)
        local toggle = toggleFrame
        local button = toggle and toggle:FindFirstChild("ToggleButton")
        local knob = button and button:FindFirstChild("CornerFrame")
        if button and knob then
            button.BackgroundColor3 = value and Color3.fromRGB(0, 120, 212) or Color3.fromRGB(150, 150, 150)
            knob.Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        end
    end

    local function setEnabled(value)
        enabled = value
        setToggleVisual(enabled)
        if enabled and not running then running = true task.spawn(loop) end
    end

    local createToggle = rawget(section, "CreateToggle")
    local createInput = rawget(section, "CreateInput")
    if not createToggle or not createInput then return end
    createToggle(section, "Kill Aura (1 Hit)", setEnabled)
    toggleFrame = sectionFrame and sectionFrame:FindFirstChild("Toggle")
    createInput(section, "ระยะ (studs) / 80", "", function(value)
        local nextRange = math.clamp(tonumber(value) or MAX_RANGE, 1, MAX_RANGE)
        if nextRange ~= range then
            range = nextRange
            if enabled then
                local click = toggleFrame and toggleFrame:FindFirstChild("ToggleInvisibleClick")
                if click then click:Activate() else setEnabled(false) end
            end
        end
    end)
end

return Combat
