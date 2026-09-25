-- Version 5.35
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
    -- เกมมี day/night cycle เขียนค่าหมอกกลับเอง -> ฟังด้วย GetPropertyChangedSignal
    -- แทนการวน: เกิดทันทีที่เกมเขียนค่า และไม่มีลูปคอยเหมือนแบบ poll (ไม่กินสเปคขณะเล่น)
    local Lighting = game:GetService("Lighting")
    local fogOriginal = nil
    local fogConns = nil

    local function removeFog()
        if not fogOriginal then
            fogOriginal = {Start = Lighting.FogStart, End = Lighting.FogEnd}
        end
        -- ตั้งค่าเดิมซ้ำ = Roblox ไม่ยิง signal กลับ -> ไม่เกิด recursion
        pcall(function() Lighting.FogStart = 0 end)
        pcall(function() Lighting.FogEnd = 1e9 end)
    end

    local function setNoFog(value)
        if value then
            removeFog()
            if not fogConns then
                fogConns = {
                    Lighting:GetPropertyChangedSignal("FogStart"):Connect(removeFog),
                    Lighting:GetPropertyChangedSignal("FogEnd"):Connect(removeFog),
                }
            end
        else
            if fogConns then
                for _, c in ipairs(fogConns) do
                    pcall(function() c:Disconnect() end)
                end
                fogConns = nil
            end
            if fogOriginal then
                pcall(function() Lighting.FogStart = fogOriginal.Start end)
                pcall(function() Lighting.FogEnd = fogOriginal.End end)
            end
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
