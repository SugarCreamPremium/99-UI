-- Version 9.31
local Other = {}

function Other.register(context)
    local tab = context.Tab
    if not tab then return end

    local section = tab:Section({Title = "จัดการสิ่งมีชีวิต", Opened = true})
    if not section then
        tab:Paragraph({
            Title = "จัดการสิ่งมีชีวิต",
            Desc = "ไม่สามารถสร้างส่วนควบคุมได้",
        })
        return
    end
    local enabledAnimals = {}
    local running = false

    local function moveAndDestroy(name)
        local chars = workspace:FindFirstChild("Characters")
        local animal = chars and chars:FindFirstChild(name)
        if not animal then return end
        pcall(function()
            local farPos
            if animal:IsA("Model") then
                farPos = animal:GetPivot().Position + Vector3.new(0, 5000, 0)
                animal:PivotTo(CFrame.new(farPos))
            else
                local root = animal:FindFirstChild("HumanoidRootPart") or animal.PrimaryPart
                    or animal:FindFirstChildWhichIsA("BasePart")
                if root then
                    farPos = root.Position + Vector3.new(0, 5000, 0)
                    root.CFrame = CFrame.new(farPos)
                end
            end
        end)
        task.wait(0.1)
        pcall(function() animal:Destroy() end)
    end

    local function loop()
        while next(enabledAnimals) do
            for name in pairs(enabledAnimals) do
                moveAndDestroy(name)
            end
            task.wait(0.2)
        end
        running = false
    end

    local function setWatcher(name, value)
        enabledAnimals[name] = value or nil
        if value and not running then
            running = true
            task.spawn(loop)
        end
    end

    local ANIMALS = {
        {Name = "Deer", Thai = "กวาง"},
        {Name = "Ram", Thai = "แพะ"},
        {Name = "Cat", Thai = "แมว"},
        {Name = "Owl", Thai = "นกฮูก"},
    }
    for _, animal in ipairs(ANIMALS) do
        section:Toggle({
            Title = "กำจัด" .. animal.Thai .. "อัตโนมัติ (" .. animal.Name .. ")",
            Value = false,
            Callback = function(value) setWatcher(animal.Name, value) end,
        })
    end
end

return Other
