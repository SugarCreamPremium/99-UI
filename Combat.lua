-- Version 10.56
local Combat = {}

function Combat.register(context)
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
    local tab = context.Tab
    local section = tab:CreateSection("Kill Aura 1 Hit")
    local range, enabled, running = 25, false, false
    local DEFAULT_RANGE = 25
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
                        if not npc:GetAttribute("NotAttackable") and not npc:GetAttribute("Tamed") then
                            local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                            local humanoid = npc:FindFirstChildOfClass("Humanoid")
                            if root and humanoid and (root.Position - hrp.Position).Magnitude <= range then
                                pcall(function()
                                    humanoid.Health = 0
                                    damage:InvokeServer(npc, item, ownerId, CFrame.lookAt(hrp.Position, root.Position), false)
                                end)
                            end
                        end
                    end
                end
                task.wait(0.1)
            else
                task.wait(0.5)
            end
        end
        running = false
    end

    local function setEnabled(value)
        enabled = value
        if enabled and not running then
            running = true
            task.spawn(loop)
        end
    end

    local createToggle = rawget(section, "CreateToggle")
    if not createToggle or not tab then return end
    createToggle(section, "Kill Aura 1 Hit (ต้องถืออาวุธระยะใกล้ด้วย)", setEnabled)

    tab:CreateSlider("ระยะ (ค่าพื้นฐาน 25)", 1, MAX_RANGE, DEFAULT_RANGE, function(value)
        range = math.clamp(value, 1, MAX_RANGE)
    end)
end

return Combat
