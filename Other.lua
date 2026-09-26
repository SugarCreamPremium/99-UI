-- Version 12.36
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

    -- ============================================
    -- ProximityPrompt: กดทันที ไม่ต้องกดค้าง
    -- ============================================
    -- เกมตั้ง HoldDuration ไว้ก่อน Parent (ดู ChristmasDecorClient/BaseDefenderClass)
    -- แต่ Scavenger (4.4 วิ) กับ Explorer เขียนค่าทับทีหลัง -> ต้องดันซ้ำเป็นระยะ
    --
    -- เคยทำลูป workspace:GetDescendants() ทุก 0.5 วิ -> FPS ตกหนัก
    -- เพราะแมพมีหลักพัน instance และ GetDescendants สร้างตารางใหม่ทั้งหมดทุกครั้ง
    -- แก้เป็นจำเฉพาะ prompt ที่เจอ แล้ววนเฉพาะตัวเหล่านั้น (สองร้อยกว่าตัว ไม่ใช่ทั้งแมพ)
    local instantPrompts = false
    local promptRunning = false
    local promptConns = nil
    -- weak key: prompt ที่ถูกลบจะหลุดเอง ไม่ต้องคอยเช็คว่ายังมีอยู่ไหม
    local knownPrompts = setmetatable({}, {__mode = "k"})

    local function trackPrompt(p)
        if knownPrompts[p] then return end
        knownPrompts[p] = true
        pcall(function() p.HoldDuration = 0 end)
    end

    local function setInstantPrompts(value)
        instantPrompts = value
        if value then
            if not promptConns then
                -- สแกนรอบแรกครั้งเดียวตอนเปิด (เกมสร้าง prompt ตอนเล่นจริง ไม่ได้อยู่ตอนโหลด)
                pcall(function()
                    for _, obj in ipairs(workspace:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") then trackPrompt(obj) end
                    end
                end)
                -- จับตัวที่โผล่มาใหม่หลังจากนี้
                promptConns = {
                    workspace.DescendantAdded:Connect(function(obj)
                        if obj:IsA("ProximityPrompt") then trackPrompt(obj) end
                    end),
                }
            end
            if not promptRunning then
                promptRunning = true
                task.spawn(function()
                    while instantPrompts do
                        for p in pairs(knownPrompts) do
                            if p.Parent and p.HoldDuration ~= 0 then
                                pcall(function() p.HoldDuration = 0 end)
                            end
                        end
                        task.wait(0.5)
                    end
                    promptRunning = false
                end)
            end
        elseif promptConns then
            for _, c in ipairs(promptConns) do
                pcall(function() c:Disconnect() end)
            end
            promptConns = nil
        end
    end

    local promptSection = tab:Section({Title = "ปุ่มโต้ตอบ", Opened = true})
    if promptSection then
        promptSection:Toggle({
            Title = "กด ProximityPrompt ทันที",
            Desc = "ตัดเวลากดค้างทุกปุ่ม (ทำให้เปิดได้ทันที)",
            Value = false,
            Callback = setInstantPrompts,
        })
    end
end

return Other
