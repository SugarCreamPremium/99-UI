-- Version 4.57
local Other = {}

function Other.register(context)
    local tab = context.Tab
    if not tab then return end

    local section = tab:Section({Title = "จัดการสิ่งมีชีวิต", Opened = true})
    if not section then return end
    local enabled = false
    local running = false

    local function loop()
        while enabled do
            local chars = workspace:FindFirstChild("Characters")
            local deer = chars and chars:FindFirstChild("Deer")
            if deer then
                pcall(function()
                    local farPos
                    if deer:IsA("Model") then
                        farPos = deer:GetPivot().Position + Vector3.new(0, 5000, 0)
                        deer:PivotTo(CFrame.new(farPos))
                    else
                        local root = deer:FindFirstChild("HumanoidRootPart") or deer.PrimaryPart
                            or deer:FindFirstChildWhichIsA("BasePart")
                        if root then
                            farPos = root.Position + Vector3.new(0, 5000, 0)
                            root.CFrame = CFrame.new(farPos)
                        end
                    end
                end)
                task.wait(0.1)
                pcall(function() deer:Destroy() end)
            end
            task.wait(0.2)
        end
        running = false
    end

    local function setDeerWatcher(value)
        enabled = value
        if enabled and not running then
            running = true
            task.spawn(loop)
        end
    end

    section:Toggle({
        Title = "กำจัดกวางอัตโนมัติ (Deer)",
        Value = false,
        Callback = setDeerWatcher,
    })
end

return Other
