-- Version 12.10
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

    local function setEnabled(value)
        enabled = value
        if enabled and not running then running = true task.spawn(loop) end
    end

    section:CreateToggle("Kill Aura (1 Hit)", setEnabled)
    section:CreateInput("ระยะ (studs) / 80", "", function(value)
        range = math.clamp(tonumber(value) or MAX_RANGE, 1, MAX_RANGE)
    end)
    section:CreateParagraph("การใช้งาน", "ถืออาวุธเพื่อเริ่มโจมตีศัตรูในระยะที่กำหนด")
end

return Combat
