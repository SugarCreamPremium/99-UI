-- Version 5.32
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
    -- เดิมใช้ WalkspeedController.AddSpeedChange (บวกเข้า base 16) แต่ตอนนี้ต้องการ
    -- ตั้งค่าตรงๆ ตามตัวเลขที่เลื่อน จึงเปลี่ยนมาเขียน Humanoid.WalkSpeed เอง
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    local function getHumanoid()
        local char = player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    -- ตั้งค่าตรงๆ ไม่ผ่าน WalkspeedController เพราะโจทย์คือ "ค่านี้เท่านี้เป๊ะ"
    -- แต่เกมเขียน WalkSpeed ใหม่ทุกครั้ง -> ฟัง GetPropertyChangedSignal แล้วเขียนทับกลับ
    -- (ตั้งค่าเดิมซ้ำ = Roblox ไม่ยิง signal กลับ -> ไม่เกิด recursion)
    -- ไม่มีสถานะ "ปิด" แล้ว ต่ำสุดคือ 16/50 และเซลล์ว่าง = ยังไม่แตะ = เกมคุมเอง
    local walkValue = nil
    local walkConn = nil

    local function applyWalk()
        local hum = getHumanoid()
        if hum and walkValue and hum.WalkSpeed ~= walkValue then
            pcall(function() hum.WalkSpeed = walkValue end)
        end
    end

    local function setWalk(value)
        walkValue = value
        if not walkValue then return end
        if not walkConn then
            local hum = getHumanoid()
            if hum then
                walkConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(applyWalk)
            end
        end
        applyWalk()
    end

    -- เกมไม่ได้เขียน JumpPower/JumpHeight เอง (ดูแค่กับ NPC) ตั้งตรงๆได้เลย
    local jumpValue = nil

    local function setJump(value)
        jumpValue = value
        local hum = getHumanoid()
        if hum and jumpValue then
            pcall(function()
                hum.UseJumpPower = true
                hum.JumpPower = jumpValue
            end)
        end
    end

    -- ย้ายตอน respawn: ตัวละครใหม่ค่าจะกลับเป็นค่าเกม
    player.CharacterAdded:Connect(function(char)
        task.defer(function()
            if jumpValue then setJump(jumpValue) end
            if walkConn then
                walkConn:Disconnect()
                walkConn = nil
            end
            if walkValue then
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    walkConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(applyWalk)
                end
                applyWalk()
            end
        end)
    end)

    -- เกมไม่มีระบบบินของผู้เล่น ต้องทำเอง
    -- ห้ามเขียน hrp.CFrame เด็ดขาด นั่นคือการสั่งเทเลพอร์ ฝืนฟิสิกส์ตรงๆ
    -- ผลคือทะลุกำแพง (ไม่มีการชนเลย) และตัวสั่นรัว (ฟิสิกส์ดันออก แล้วเราเขียนกลับที่เดิมทุกเฟรม)
    -- ห้ามใช้ PlatformStand ด้วย เพราะมันไปยึดตัวละครไว้กับที่ = ลอยได้แต่ขยับไม่ได้
    -- ใช้ constraint ที่ดึงด้วยแรงแทน: AlignPosition ขยับ, AlignOrientation หมุนหน้า
    -- แรงไม่จำกัด = กำแพงหยุดไม่ได้ (ทะลุ) แรงจำกัด = กำแพงหยุดได้
    local flySpeed = 100
    local flyConn = nil
    local flyRig = nil
    local flyTarget = nil

    local function clearFlyRig()
        if flyRig then
            for _, o in ipairs(flyRig) do pcall(function() o:Destroy() end) end
            flyRig = nil
        end
        flyTarget = nil
    end

    local function buildFlyRig(hrp)
        local pivot = Instance.new("Attachment")
        pivot.Name = "FlyPivot"
        pivot.Parent = hrp

        local pos = Instance.new("AlignPosition")
        pos.Mode = Enum.PositionAlignmentMode.OneAttachment
        pos.MaxForce = 1e6
        pos.Responsiveness = 20
        pos.Attachment0 = pivot
        pos.Parent = hrp

        local rot = Instance.new("AlignOrientation")
        rot.Mode = Enum.OrientationAlignmentMode.OneAttachment
        rot.MaxTorque = 1e6
        rot.Responsiveness = 20
        rot.RigidityEnabled = false
        rot.Attachment0 = pivot
        rot.Parent = hrp

        flyRig = {pivot, pos, rot}
    end

    local function setFly(value)
        if not value then
            if flyConn then
                flyConn:Disconnect()
                flyConn = nil
            end
            clearFlyRig()
            local hum = getHumanoid()
            if hum then
                pcall(function() hum.AutoRotate = true end)
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
            return
        end
        if flyConn then return end
        flyConn = RunService.RenderStepped:Connect(function(dt)
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local cam = workspace.CurrentCamera
            if not hum or not hrp or not cam or hum.Health <= 0 then
                clearFlyRig()
                return
            end
            hum.AutoRotate = false -- หันหน้าให้ constraint จัด ถ้าให้เกมหมุนตามด้วยจะสั่น
            if not flyRig or flyRig[1].Parent ~= hrp then
                clearFlyRig()
                buildFlyRig(hrp)
            end

            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.C) then dir = dir - Vector3.yAxis end

            local unit = dir.Magnitude > 0 and dir.Unit or Vector3.zero
            local step = flySpeed * dt
            -- เดินเป้าหมายไปข้างหน้าตามความเร็ว แต่ห้ามห่างจากตัวจริงเกิน 2 เฟรม
            -- (ถ้าไม่จำกัด: ชนกำแพง เป้าหมายวิ่งไปข้างหลังกำแพง พอปล่อยปุ่มตัวกระโดดทะลุ)
            if not flyTarget or (flyTarget - hrp.Position).Magnitude > step * 2 then
                flyTarget = hrp.Position
            end
            flyTarget = flyTarget + unit * step

            flyRig[2].Position = flyTarget
            flyRig[3].CFrame = CFrame.lookAt(Vector3.zero, cam.CFrame.LookVector)
        end)
    end

    -- ============================================
    -- Noclip: แยกจากบิน เพราะเกมนี้มีประตู/กำแพง/หลังคา ทะลุได้บางที่ ไม่ได้ทั้งหมด
    -- ============================================
    local noclipConn = nil

    local function setNoclip(value)
        if not value then
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
            return
        end
        if noclipConn then return end
        noclipConn = RunService.Stepped:Connect(function()
            local char = player.Character
            if not char then return end
            -- วนทุกเฟรมเพราะเกม/สคริปต์อื่นจะเขียน CanCollide กลับเป็น true เอง
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end)
    end

    local speedSection = tab:Section({Title = "ความเร็ว", Opened = true})
    if speedSection then
        speedSection:Slider({
            Title = "ความเร็วเดิน",
            Value = {Min = 16, Max = 300, Default = 16},
            Step = 1,
            Callback = setWalk,
        })
        speedSection:Slider({
            Title = "กระโดดสูง",
            Value = {Min = 50, Max = 250, Default = 50},
            Step = 1,
            Callback = setJump,
        })
        speedSection:Toggle({
            Title = "บิน",
            Desc = "W/S หน้า-หลัง, A/D ซ้าย-ขวา, Space ขึ้น, C ลง",
            Value = false,
            Callback = setFly,
        })
        speedSection:Toggle({
            Title = "ทะลุกำแพง (Noclip)",
            Desc = "ตัวทะลุผ่านสิ่งของได้",
            Value = false,
            Callback = setNoclip,
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
