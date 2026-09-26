-- Version 3.35
local Player = {}

-- กันดาเมจพื้นฐาน (Melee + Projectile + กับดัก/สิ่งแวดล้อม): กลบ remote รายงานความเสียหายจาก client -> server
-- มีผลกับกระสุน NPC (ProjectileClass.lua เป็นคน FireServer) และ melee ระยะใกล้ (NPCModuleClient:740)
-- หมายเหตุ: ดาเมจที่ server หักเอง (เช่น Frog) กลบไม่ได้จาก client — วิธีนี้กันได้แค่ส่วนที่ทำงานผ่าน remote
local blockedDamage = {
    NPCProjectileDamagePlayer = true, -- กระสุนระยะไกล
    NPCProjectileDamagePet    = true, -- กระสุนโดนเพ็ท
    ClientTriggerNPCAttack    = true, -- melee ระยะใกล้ (wolf/bear/cultist ฯลฯ)
    JungleSpikeTrapDamage     = true, -- กับดักหนาม
    RamChargePlayer           = true, -- ถูกพุ่งชน (Ram/สัตว์ชน)
    CheckLightningDamage      = true, -- ไฟฟ้าฝน — WeatherEffectModule:616/619
    HitByBatScream            = true, -- ค้างคาวกรีด — BatClient:36
    OwlChasePlayer            = true, -- นกเค้าแมวโฉบ — OwlModuleClient:225
    TriggerArrowTrap          = true, -- กับดักลูกศรป่าดงดิบ — ArrowTrapClient:88
}

local oldNamecall
local blockEnabled = false -- ปิดเป็นค่าเริ่มต้น (เปิดเองตอนต้องการ)

-- เปิด/ปิดการกันดาเมจ (true = กัน, false = ปล่อยให้โจมตีปกติ)
function Player.setDamageBlock(v)
    blockEnabled = v
end

oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if blockEnabled and getnamecallmethod() == "FireServer"
        and self.ClassName == "RemoteEvent" and blockedDamage[self.Name] then
        return nil
    end
    return oldNamecall(self, ...)
end))

-- กันหนาว (client-side): สถานะ freeze มี 2 path ที่ apply ฝั่ง client
--   1. TemperatureClient.BarEmpty -> PlayerFrozen(true) -> debuff "Frozen" -13
--   2. WalkspeedController attribute listener: Temperature <= 0 -> debuff "ZeroTemperature" -13
-- server ส่ง Temperature มาเมื่อค่าเปลี่ยน -> เขียนค่าทับทันทีที่เห็น <= 0 (server จะกลับมาเป็น 0 ทุกครั้งที่มัน sync)
-- = debuff "Frozen"/"ZeroTemperature" ถอดออกเองทันทีที่ signal ทำงาน, แถบ UI ยังโชว์ค่าจริงตอนหนาวปกติ
local localPlayer = game:GetService("Players").LocalPlayer
local freezeEnabled = false
local freezeRunning = false

local function freezeLoop()
    while freezeEnabled do
        local t = localPlayer:GetAttribute("Temperature")
        if t ~= nil and t <= 0 then
            localPlayer:SetAttribute("Temperature", 100)
        end
        task.wait(0.15)
    end
    freezeRunning = false
end

function Player.setNoFreeze(value)
    freezeEnabled = value == true
    if freezeEnabled and not freezeRunning then
        freezeRunning = true
        task.spawn(freezeLoop)
    end
end

function Player.register(context)
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    local tab = context.Tab

    local dmgSection = tab:Section({Title = "God Mode", Opened = true})
    if dmgSection then
        dmgSection:Toggle({
            Title = "กันดาเมจเกือบทุกประเภท",
            Desc = "กันได้แทบจะทุกอย่างในเกมยกเว้น กบและการติดสถานะต่างๆ",
            Value = false,
            Callback = Player.setDamageBlock,
        })
        dmgSection:Toggle({
            Title = "กันหนาว (Freeze)",
            Desc = "ไม่ให้ติดสถานะหนาวจัดในโซนหิมะ (ทำให้วิ่งได้)",
            Value = false,
            Callback = Player.setNoFreeze,
        })
    end

    -- ============================================
    -- ความเร็ว: เดิน / กระโดด / บิน
    -- ============================================
    -- เกมมี WalkspeedController คำนวณ WalkSpeed ใหม่ทุกครั้งที่มีอะไรเปลี่ยน
    -- (UpdatePlayerSpeed: base 16 + รวมรายการ speed change ของคลาส/เขต/รถ)
    -- ถ้าเขียน Humanoid.WalkSpeed ตรงๆ จะโดนเขียนทับทันที -> ต้องใช้ AddSpeedChange ของเกม
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local WALK_ID = "SugarHubSpeed"

    local function getHumanoid()
        local char = player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function setWalkBonus(value)
        local controller = Client and Client.WalkspeedController
        if not controller then return end
        pcall(function()
            if value and value > 0 then
                -- Group ของเกมใช้ "Class"/"Vehicle"/... ใช้ชื่อของเราเองกันชน
                controller.AddSpeedChange(WALK_ID, "SugarHub", value, {Mode = "Walk"})
            else
                controller.RemoveSpeedChange(WALK_ID)
            end
        end)
    end

    -- เกมไม่ได้เขียน JumpPower/JumpHeight เอง (ดูแค่กับ NPC) ตั้งตรงๆได้เลย
    local jumpValue = nil

    local function setJump(value)
        jumpValue = (value and value > 0) and value or nil
        local hum = getHumanoid()
        if hum and jumpValue then
            pcall(function()
                hum.UseJumpPower = true
                hum.JumpPower = jumpValue
            end)
        end
    end

    -- ย้ายตอน respawn: ตัวละครใหม่ค่าจะกลับเป็นค่าเกม
    player.CharacterAdded:Connect(function()
        task.defer(function()
            if jumpValue then setJump(jumpValue) end
        end)
    end)

    -- เกมไม่มีระบบบินของผู้เล่น ต้องทำเอง
    local flySpeed = 100
    local flyConn = nil

    local function setFly(value)
        if not value then
            if flyConn then
                flyConn:Disconnect()
                flyConn = nil
            end
            local hum = getHumanoid()
            if hum then pcall(function() hum.PlatformStand = false end) end
            return
        end
        if flyConn then return end
        flyConn = RunService.RenderStepped:Connect(function()
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local cam = workspace.CurrentCamera
            if not hum or not hrp or not cam or hum.Health <= 0 then return end
            hum.PlatformStand = true

            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.C) then dir = dir - Vector3.yAxis end

            hrp.AssemblyLinearVelocity = dir.Magnitude > 0 and (dir.Unit * flySpeed) or Vector3.zero
        end)
    end

    local speedSection = tab:Section({Title = "ความเร็ว", Opened = true})
    if speedSection then
        speedSection:Slider({
            Title = "เพิ่มความเร็วเดิน",
            Desc = "ปกติ 16 (บวกโบนัสคลาส/เขตที่เกมให้) ตั้ง 0 = ใช้ค่าเกม",
            Value = {Min = 0, Max = 150, Default = 0},
            Step = 1,
            Callback = setWalkBonus,
        })
        speedSection:Slider({
            Title = "กระโดดสูง",
            Desc = "ปกติ 50 ตั้ง 0 = ใช้ค่าเกม",
            Value = {Min = 0, Max = 300, Default = 0},
            Step = 1,
            Callback = setJump,
        })
        speedSection:Toggle({
            Title = "บิน",
            Desc = "W/S หน้า-หลัง, A/D ซ้าย-ขวา, Space ขึ้น, C ลง",
            Value = false,
            Callback = setFly,
        })
        speedSection:Slider({
            Title = "ความเร็วบิน",
            Desc = "studs ต่อวินาที",
            Value = {Min = 10, Max = 500, Default = 100},
            Step = 5,
            Callback = function(value) flySpeed = value end,
        })
    end

    local section = tab:Section({Title = "กินอาหารอัตโนมัติ", Opened = true})
    if not section then return end
    local enabled = false
    local running = false
    local targetHunger = 100
    local DEFAULT_HUNGER = 100
    local MAX_HUNGER = 200

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getItemPos(item)
        if item:IsA("Model") then
            if item.PrimaryPart then return item.PrimaryPart.Position end
            local part = item:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position
        elseif item:IsA("BasePart") then
            return item.Position
        end
    end

    local function findClosestFood()
        local hrp = getHRP()
        local items = workspace:FindFirstChild("Items")
        if not hrp or not items then return nil end

        local closest, closestDist = nil, math.huge
        for _, item in ipairs(items:GetChildren()) do
            local restore = item:GetAttribute("RestoreHunger")
            local restoreHealth = item:GetAttribute("RestoreHealth")
            if restore and restore > 0 and (restoreHealth == nil or restoreHealth >= 0) then
                local owner = item:GetAttribute("Owner")
                local interaction = item:GetAttribute("Interaction")
                local skip = owner and owner ~= player.UserId
                    or interaction and interaction ~= "Item" and interaction ~= "Tool"
                    or player:GetAttribute("Class") == "Bunny" and item:GetAttribute("HasMeat")
                local pos = not skip and getItemPos(item)
                if pos then
                    local distance = (pos - hrp.Position).Magnitude
                    if distance < closestDist then
                        closest, closestDist = item, distance
                    end
                end
            end
        end
        return closest
    end

    local function consume(item)
        if not Client.PlayerHandler.Alive then return false end
        local parent = item.Parent
        item.Parent = ReplicatedStorage.TempStorage
        local result = Client.Events.RequestConsumeItem:InvokeServer(item)
        if not (result and result.Success) then item.Parent = parent return false end
        return true
    end

    local function pull(item)
        local hrp = getHRP()
        if not hrp then return false end
        return pcall(function()
            local events = ReplicatedStorage.RemoteEvents
            events.RequestStartDraggingItem:FireServer(item)
            task.wait(0.1)
            if item:IsA("Model") then item:PivotTo(CFrame.new(hrp.Position)) else item.CFrame = CFrame.new(hrp.Position) end
            task.wait(0.1)
            events.StopDraggingItem:FireServer(item)
        end)
    end

    local function loop()
        while enabled do
            if (player:GetAttribute("Hunger") or 100) < targetHunger then
                local food = findClosestFood()
                if food then pull(food) consume(food) task.wait(0.25) else task.wait(1) end
            else
                task.wait(1)
            end
        end
        running = false
    end

    local function setEnabled(value)
        enabled = value
        if enabled and not running then running = true task.spawn(loop) end
    end

    section:Toggle({
        Title = "กินอาหารอัตโนมัติ",
        Value = false,
        Callback = setEnabled,
    })
    section:Slider({
        Title = "กินจนถึงความหิว",
        Value = {Min = 1, Max = MAX_HUNGER, Default = DEFAULT_HUNGER},
        Step = 1,
        Callback = function(value)
            targetHunger = math.clamp(value, 1, MAX_HUNGER)
        end,
    })

end

return Player
