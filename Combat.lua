-- Version 11.51
local Combat = {}

function Combat.register(section, context)
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
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

    local function setEnabled(value)
        enabled = value
        if enabled and not running then
            running = true
            task.spawn(loop)
        end
    end

    local createToggle = section.CreateToggle
    local createSlider = section.CreateSlider
    if not createToggle or not createSlider then return end
    createToggle(section, "Kill Aura 1 Hit (ต้องถืออาวุธระยะใกล้ด้วย)", setEnabled)
    createSlider(section, "ระยะ (พื้นฐาน 25 / สูงสุด 80)", 1, MAX_RANGE, DEFAULT_RANGE, function(value)
        range = math.clamp(value, 1, MAX_RANGE)
    end)
end

return Combat
