-- Version 2.53
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

    -- ============================================
    -- ภาพและแสง: ลดกราฟฟิก (ย้ายมาจาก FlatFPS.lua)
    -- แยกจาก "ลบหมอก" อีกตัว ตัวนี้ไม่ไปแตะ FogStart/FogEnd เลย จึงเปิด-ปิดกันได้อิสระ
    -- ============================================
    -- จำค่าเดิมไว้ก่อนทุกครั้งที่แก้ ปิด toggle แล้วกู้คืนได้
    -- ไม่มี Destroy ยกเว้น SurfaceAppearance (ตัวเดียวที่กู้ไม่ได้)
    local gfxSaved = {}

    local function gfxSet(obj, prop, value)
        local props = gfxSaved[obj]
        if not props then
            props = {}
            gfxSaved[obj] = props
        end
        if props[prop] == nil then
            -- ต้องอ่านใน pcall: TextureID/MaterialVariant มีแค่บางคลาส (MeshPart, WedgePart)
            -- Part ธรรมดาไม่มี -> อ่านโดยตรงจะ error หลุดออกมาถึงผู้เรียก
            local ok, old = pcall(function() return obj[prop] end)
            if not ok then return end
            props[prop] = old
        end
        pcall(function() obj[prop] = value end)
    end

    -- Material กลุ่มนี้มีลายสลักอยู่ในตัว Roblox เอง แม้ไม่มี Decal/Texture ก็ยังเห็นลาย
    local TEXTURED = {
        Wood = true, WoodPlanks = true, Marble = true, Slate = true, Concrete = true,
        Granite = true, Brick = true, Pebble = true, Cobblestone = true, Rock = true,
        Sand = true, Fabric = true, Ground = true, Asphalt = true, Salt = true,
        Mud = true, Carpet = true, CeramicTiles = true, ClayRoofTiles = true,
        RoofShingles = true, Leather = true, Plaster = true, DiamondPlate = true,
        CorrodedMetal = true, LeafyGrass = true, Pavement = true, CrackedLava = true,
        Aisle = true, Glitch = true,
    }

    local VFX_CLASSES = {
        ParticleEmitter = true, Smoke = true, Fire = true,
        Sparkles = true, Beam = true, Trail = true,
    }

    local function isPostFX(c)
        return c:IsA("Atmosphere") or c:IsA("BloomEffect") or c:IsA("DepthOfFieldEffect")
            or c:IsA("SunRaysEffect") or c:IsA("ColorCorrectionEffect")
            or c:IsA("CloudsTexture")
    end

    -- ข้ามตัวละครทุกคน (เรา + เพื่อน) เหลือแต่ฉากกับของ
    local function isCharacter(o)
        local p = o
        while p and p ~= workspace do
            if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then return true end
            p = p.Parent
        end
        return false
    end

    local function stripGraphics(o)
        if isCharacter(o) then return end
        local cn = o.ClassName

        if cn == "Decal" or cn == "Texture" then
            -- ซ่อนภาพที่ติดอยู่บนตัว เหลือสีของชิ้นส่วนล้วน
            gfxSet(o, "Transparency", 1)
        elseif cn == "SurfaceAppearance" then
            -- ลบแล้ว MeshPart จะวาดด้วย Color/TextureID แทน (ตัว mesh ยังทำงานปกติ)
            -- แต่กู้คืนไม่ได้
            pcall(function() o:Destroy() end)
        elseif o:IsA("SpecialMesh") then
            gfxSet(o, "TextureId", "")
        elseif o:IsA("BasePart") then
            gfxSet(o, "TextureID", "")
            gfxSet(o, "MaterialVariant", "")
            if TEXTURED[o.Material] then
                gfxSet(o, "Material", Enum.Material.Plastic)
            end
        elseif o:IsA("Sky") then
            gfxSet(o, "SkyboxBk", "")
            gfxSet(o, "SkyboxDn", "")
            gfxSet(o, "SkyboxFt", "")
            gfxSet(o, "SkyboxLf", "")
            gfxSet(o, "SkyboxRt", "")
            gfxSet(o, "SkyboxUp", "")
            gfxSet(o, "StarCount", 0)
        end

        if VFX_CLASSES[cn] then
            -- ปิดแทน Destroy: ได้ผลเดียวกันแต่กู้คืนได้
            gfxSet(o, "Enabled", false)
        end
    end

    local function applyLightingFloor()
        gfxSet(Lighting, "GlobalShadows", false)
        gfxSet(Lighting, "Brightness", 2)
        gfxSet(Lighting, "OutdoorAmbient", Color3.new(1, 1, 1))
        gfxSet(Lighting, "Ambient", Color3.new(1, 1, 1))
        gfxSet(Lighting, "EnvironmentDiffuseScale", 0)
        gfxSet(Lighting, "EnvironmentSpecularScale", 0.15)
        -- ชื่อเดิมคือ Forward แต่ Roblox เปลี่ยนเป็น Future แล้ว
        -- เอาไว้ใน pcall เพราะ Enum ถูกประเมินก่อนเข้า gfxSet
        pcall(function() gfxSet(Lighting, "Technology", Enum.Technology.Future) end)
    end

    local gfxConns = nil

    local function setFlatGraphics(value)
        if value then
            applyLightingFloor()
            -- สแกนครั้งเดียวตอนเปิด (แมพมีหลักพัน instance ห้ามวน GetDescendants เป็นลูป)
            pcall(function()
                for _, o in ipairs(workspace:GetDescendants()) do stripGraphics(o) end
            end)
            pcall(function()
                for _, o in ipairs(Lighting:GetChildren()) do
                    if isPostFX(o) then gfxSet(o, "Enabled", false) end
                end
            end)
            -- ตัวที่โผล่มาทีหลังระหว่างเล่น
            if not gfxConns then
                gfxConns = {
                    workspace.DescendantAdded:Connect(stripGraphics),
                    Lighting.ChildAdded:Connect(function(c)
                        if isPostFX(c) then gfxSet(c, "Enabled", false) end
                    end),
                }
            end
        else
            if gfxConns then
                for _, c in ipairs(gfxConns) do
                    pcall(function() c:Disconnect() end)
                end
                gfxConns = nil
            end
            for o, props in pairs(gfxSaved) do
                if o.Parent then
                    for prop, v in pairs(props) do
                        pcall(function() o[prop] = v end)
                    end
                end
            end
            gfxSaved = {}
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
        visSection:Toggle({
            Title = "ลดกราฟฟิก",
            Desc = "ลดรายละเอียดสิ่งของภายในเกม (ปิดแล้วจะกลับมาเหมือนเดิม)",
            Value = false,
            Callback = setFlatGraphics,
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
    -- เก็บค่า = HoldDuration เดิมที่เกมตั้งไว้ (เก็บตอนเจอครั้งแรก) ไว้กู้ตอนปิด toggle
    local knownPrompts = setmetatable({}, {__mode = "k"})

    local function trackPrompt(p)
        if knownPrompts[p] then return end
        knownPrompts[p] = p.HoldDuration
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
            -- กู้ HoldDuration เดิมของทุกตัวที่เราไปทับไว้ตอนเปิด
            for p, orig in pairs(knownPrompts) do
                if p.Parent then
                    pcall(function() p.HoldDuration = orig end)
                end
            end
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
