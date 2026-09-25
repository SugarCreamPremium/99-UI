-- Version 5.31
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

    -- ============================================
    -- ภาพและแสง: ลบหมอก
    -- ============================================
    -- จาก Farm Map/Lighting: FogStart=20, FogEnd=150, FogColor ม่วงเข้ม
    -- ไม่มี Atmosphere เลย -> หมอกมาจาก Lighting.Fog* ล้วน ตัดที่นี่จบ
    -- เกมมี day/night cycle เขียนค่าหมอกกลับเอง -> ต้องวนดันซ้ำ ไม่ใช่ตั้งครั้งเดียว
    local Lighting = game:GetService("Lighting")
    local noFog = false
    local noFogRunning = false
    local fogOriginal = nil

    local function restoreFog()
        if not fogOriginal then return end
        pcall(function() Lighting.FogStart = fogOriginal.Start end)
        pcall(function() Lighting.FogEnd = fogOriginal.End end)
    end

    local function setNoFog(value)
        noFog = value
        if value then
            if not noFogRunning then
                noFogRunning = true
                task.spawn(function()
                    while noFog do
                        if not fogOriginal then
                            fogOriginal = {Start = Lighting.FogStart, End = Lighting.FogEnd}
                        end
                        pcall(function() Lighting.FogStart = 0 end)
                        pcall(function() Lighting.FogEnd = 1e9 end)
                        task.wait(0.5)
                    end
                    noFogRunning = false
                end)
            end
        else
            restoreFog()
        end
    end

    local visSection = tab:Section({Title = "ภาพและแสง", Opened = true})
    if visSection then
        visSection:Toggle({
            Title = "ลบหมอก",
            Desc = "ลบหมอกออกหมด เพื่อจะได้มองเห็นได้ชัด (ปิดแล้วจะมีหมอกเหมือนเดิม)",
            Value = false,
            Callback = setNoFog,
        })
    end
end

return Other
