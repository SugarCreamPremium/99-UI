-- Version 12.13
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
