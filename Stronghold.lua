-- Version 10.14
local Stronghold = {}

function Stronghold.register(context)
    local tab = context.Tab
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local CollectionService = game:GetService("CollectionService")

    local section = tab:Section({Title = "ระบบลง Stronghold อัตโนมัติ", Opened = true})
    if not section then return end

    section:Paragraph({
        Title = "ข้อกำหนดการใช้งาน",
        Desc = "⚠️ ต้องอัปเกรดกองไฟจนเปิดแมพก่อน เพื่อให้เกมโหลดสตรองโฮลด์และแสดงตัวนับเวลาได้ถูกต้อง",
    })

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getWeapon()
        local char = player.Character
        local handle = char and char:FindFirstChild("ToolHandle")
        local item = handle and handle:FindFirstChild("OriginalItem")
        return item and item.Value
    end

    local function getBestCombatWeapon()
        local inv = player:FindFirstChild("Inventory")
        if not inv then return nil end
        local best, bestDmg = nil, -1
        for _, tool in ipairs(inv:GetChildren()) do
            if tool:GetAttribute("ToolName") == "GenericAxe" or tool:GetAttribute("ToolName") == "MeleeWeapon" then
                local dmg = tool:GetAttribute("WeaponDamage") or 0
                if dmg > bestDmg then
                    bestDmg = dmg
                    best = tool
                end
            end
        end
        return best
    end

    local function equipWeapon(tool)
        if not tool or not Client or not Client.InventoryHandler then return end
        pcall(function()
            Client.InventoryHandler.RequestEquipItem(tool)
        end)
    end

    -- ตรวจสอบและถืออาวุธใหม่เสมอหากหลุดมือ
    local function checkAndReequipWeapon(bestTool)
        local current = getWeapon()
        if not current and bestTool then
            equipWeapon(bestTool)
            task.wait(0.15)
            current = getWeapon()
        end
        return current
    end

    local function getStrongholdTimeRemaining()
        for _, sh in ipairs(CollectionService:GetTagged("Stronghold")) do
            if sh.Name ~= "AlienMothership" then
                local f = sh:FindFirstChild("Functional")
                if f and f:GetAttribute("OpenTime") then
                    return f:GetAttribute("OpenTime") - workspace:GetServerTimeNow()
                end
            end
        end
        return nil
    end

    local function getStrongholdRoot()
        local map = workspace:FindFirstChild("Map")
        local landmarks = map and map:FindFirstChild("Landmarks")
        return landmarks and landmarks:FindFirstChild("Stronghold")
    end

    local function getTriggerZone()
        local sh = getStrongholdRoot()
        local functional = sh and sh:FindFirstChild("Functional")
        local tz = functional
            and functional:FindFirstChild("EnemyWaves12")
            and functional.EnemyWaves12:FindFirstChild("Wave1")
            and functional.EnemyWaves12.Wave1:FindFirstChild("TriggerZone")
        if tz and tz:IsA("BasePart") then return tz end
        return nil
    end

    local function isStrongholdEnemy(model)
        if typeof(model) ~= "Instance" or not model.Parent then return false end
        if model:GetAttribute("StrongholdEnemy") ~= true then return false end
        if model:GetAttribute("NotAttackable") == true then return false end
        if game:GetService("Players"):GetPlayerFromCharacter(model) then return false end
        return true
    end

    local function findCultists()
        local list = {}
        local chars = workspace:FindFirstChild("Characters")
        if not chars then return list end
        for _, c in ipairs(chars:GetChildren()) do
            if c.Name ~= "Deer" and isStrongholdEnemy(c) then
                local root = c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart")
                local hum = c:FindFirstChildOfClass("Humanoid") or c:FindFirstChildWhichIsA("Humanoid", true)
                if root and hum then
                    table.insert(list, c)
                end
            end
        end
        return list
    end

    local function isStrongholdCleared()
        local sh = getStrongholdRoot()
        local func = sh and sh:FindFirstChild("Functional")
        local gate = func and func:FindFirstChild("FinalGate")
        if not gate then return false end
        local part = gate:IsA("BasePart") and gate or gate:FindFirstChildWhichIsA("BasePart", true)
        return part and part.CanCollide == false
    end

    -- ปรับเลือดเป็น 0 (ทั้ง Humanoid และ Attribute) ตาม MainScript
    local function zeroEnemyHealth(model)
        if not model or not model.Parent then return end
        pcall(function()
            local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
            if hum then hum.Health = 0 end
            model:SetAttribute("Health", 0)
        end)
    end

    -- เก็บเพชร
    local function collectDiamonds()
        local TakeDiamondsEvent = ReplicatedStorage.RemoteEvents.RequestTakeDiamonds
        local COLLECT_EMPTY_STOP = 3
        local emptyStreak = 0

        while emptyStreak < COLLECT_EMPTY_STOP do
            local found = {}
            local items = workspace:FindFirstChild("Items")
            if items then
                for _, item in ipairs(items:GetChildren()) do
                    if item.Name == "Diamond" then
                        local owner = item:GetAttribute("Owner")
                        if owner == nil or owner == player.UserId then
                            local part = item:IsA("BasePart") and item or (item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)))
                            if part then
                                table.insert(found, {model = item, part = part})
                            end
                        end
                    end
                end
            end

            if #found == 0 then
                emptyStreak = emptyStreak + 1
            else
                emptyStreak = 0
                for _, d in ipairs(found) do
                    if d.model and d.model.Parent then
                        local tries = 0
                        local startDiamonds = player:GetAttribute("Diamonds")
                        local gotIt = false
                        while not gotIt and tries < 20 and d.model.Parent do
                            tries = tries + 1
                            local hrp = getHRP()
                            if hrp and d.part and d.part.Parent then
                                hrp.CFrame = CFrame.new(d.part.Position + Vector3.new(0, 2, 0))
                            end
                            pcall(function() TakeDiamondsEvent:FireServer(d.model) end)
                            task.wait(0.2)
                            if player:GetAttribute("Diamonds") ~= startDiamonds then
                                gotIt = true
                            end
                        end
                        task.wait(0.1)
                    end
                end
            end
            task.wait(0.3)
        end
    end

    -- เปิดหีบเพชร
    local function openDiamondChest()
        local chest = nil
        for _ = 1, 10 do
            local items = workspace:FindFirstChild("Items")
            chest = (items and items:FindFirstChild("Stronghold Diamond Chest"))
                or workspace:FindFirstChild("Stronghold Diamond Chest", true)
            if chest then break end
            task.wait(0.5)
        end
        if not chest then return end

        local chestPos = chest:IsA("Model") and chest:GetPivot().Position
            or (chest:IsA("BasePart") and chest.Position)
            or (chest:FindFirstChildWhichIsA("BasePart", true) and chest:FindFirstChildWhichIsA("BasePart", true).Position)

        local hrp = getHRP()
        if hrp and chestPos then
            hrp.CFrame = CFrame.new(chestPos + Vector3.new(0, 3, 0))
        end
        task.wait(0.5)

        local prompt = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            for _ = 1, 5 do
                if not prompt.Parent or not prompt.Enabled then break end
                if typeof(fireproximityprompt) == "function" then
                    fireproximityprompt(prompt, 0, true)
                else
                    pcall(function() prompt.HoldDuration = 0 end)
                    prompt:InputHoldBegin()
                    task.wait(0.1)
                    prompt:InputHoldEnd()
                end
                task.wait(0.3)
            end
        end
    end

    -- สถานะ UI
    local statusParagraph = section:Paragraph({
        Title = "สถานะ Stronghold",
        Desc = "กำลังตรวจสอบเวลา...",
    })

    local autoEnabled = false
    local autoRunning = false

    -- นับเวลาถอยหลังตลอดเวลา
    task.spawn(function()
        while true do
            local remaining = getStrongholdTimeRemaining()
            if not remaining then
                if statusParagraph and statusParagraph.SetDesc then
                    statusParagraph:SetDesc("ไม่พบข้อมูลเวลา (อาจต้องอัปเกรดกองไฟเปิดแมพก่อน)")
                end
            elseif remaining <= 0 then
                if statusParagraph and statusParagraph.SetDesc then
                    statusParagraph:SetDesc("✅ สตรองโฮลด์เปิดแล้ว! (พร้อมลงทันที)")
                end
            else
                local minutes = math.floor(remaining / 60)
                local seconds = math.floor(remaining % 60)
                if statusParagraph and statusParagraph.SetDesc then
                    statusParagraph:SetDesc(string.format("⏳ เหลือเวลา: %02d:%02d", minutes, seconds))
                end
            end
            task.wait(1)
        end
    end)

    -- ลูป Auto Stronghold (เล่นวนซ้ำเรื่อยๆ ตราบใดที่ยังเปิด toggle อยู่)
    local function strongholdLoop()
        local HOVER_HEIGHT = 10
        local ownerId = tostring(player.UserId) .. "_" .. player.UserId
        local damageEvent = ReplicatedStorage.RemoteEvents.ToolDamageObject

        while autoEnabled do
            local remaining = getStrongholdTimeRemaining()
            if not remaining or remaining > 0 then
                task.wait(1)
            else
                -- สตรองโฮลด์เปิดแล้ว: ถืออาวุธ
                local bestTool = getBestCombatWeapon()
                if bestTool then
                    equipWeapon(bestTool)
                    task.wait(0.3)
                end

                -- วาร์ปไป TriggerZone เพื่อเริ่มเวฟ
                local tz = getTriggerZone()
                local hrp = getHRP()
                if tz and hrp then
                    hrp.CFrame = CFrame.new(tz.Position + Vector3.new(0, 2, 0))
                    task.wait(1)
                end

                -- ต่อสู้จนกว่าสตรองโฮลด์จะเคลียร์
                while autoEnabled and not isStrongholdCleared() do
                    local cultists = findCultists()
                    if #cultists > 0 then
                        -- ตรวจสอบและ re-equip อาวุธก่อนตีทุกรอบหากหลุดมือ
                        local weapon = checkAndReequipWeapon(bestTool)
                        local curHrp = getHRP()

                        if curHrp and weapon then
                            -- คำนวณจุดศูนย์กลาง (Centroid) ของ Cultist ทุกตัว เพื่อวาร์ปจุดเดียวแล้วตีพร้อมกันแบบ Batch
                            local validCultists = {}
                            local centroid = Vector3.zero
                            local maxY = -math.huge

                            for _, cultist in ipairs(cultists) do
                                if cultist and cultist.Parent then
                                    local root = cultist:FindFirstChild("HumanoidRootPart") or cultist.PrimaryPart
                                    if root then
                                        table.insert(validCultists, cultist)
                                        centroid = centroid + root.Position
                                        if root.Position.Y > maxY then maxY = root.Position.Y end
                                    end
                                end
                            end

                            if #validCultists > 0 then
                                centroid = centroid / #validCultists
                                -- วาร์ปไปเหนือ Centroid 10 studs และก้มหน้าลง
                                local warpPos = Vector3.new(centroid.X, maxY + HOVER_HEIGHT, centroid.Z)
                                curHrp.CFrame = CFrame.new(warpPos) * CFrame.Angles(math.rad(-90), 0, 0)

                                -- 1) รอ 0.2 วิ ให้เซิร์ฟเวอร์รับรู้ตำแหน่ง CFrame ใหม่
                                task.wait(0.2)

                                -- 2) ลดเลือดทุกตัวพร้อมกันเป็น 0
                                for _, cultist in ipairs(validCultists) do
                                    zeroEnemyHealth(cultist)
                                end

                                -- 3) รอ 1 วินาที ให้เซิร์ฟเวอร์รับการลดเลือด (Health = 0 Replicate)
                                task.wait(1)

                                -- ตรวจสอบอาวุธอีกครั้งก่อนตี
                                weapon = checkAndReequipWeapon(bestTool)

                                -- 4) ตีทุกตัวพร้อมกันจากจุดเดียว (Multi-target Hit)
                                for _, cultist in ipairs(validCultists) do
                                    if cultist and cultist.Parent and weapon and curHrp then
                                        pcall(function()
                                            damageEvent:InvokeServer(cultist, weapon, ownerId, curHrp.CFrame, false)
                                        end)
                                    end
                                end
                            end
                        end
                        task.wait(0.1)
                    else
                        -- รอมอนเวฟถัดไป
                        local curTz = getTriggerZone()
                        local curHrp = getHRP()
                        if curTz and curHrp then
                            curHrp.CFrame = CFrame.new(curTz.Position + Vector3.new(0, 2, 0))
                        end
                        task.wait(0.5)
                    end
                end

                -- เคลียร์เสร็จ เปิดหีบและเก็บเพชร
                if autoEnabled then
                    task.wait(1)
                    openDiamondChest()
                    task.wait(1)
                    collectDiamonds()
                end

                -- เมื่อจบรอบ จะวนกลับไปเช็คเวลารอบถัดไปต่อเรื่อยๆ
                task.wait(2)
            end
        end
        autoRunning = false
    end

    local function setAuto(value)
        autoEnabled = value
        if autoEnabled and not autoRunning then
            autoRunning = true
            task.spawn(strongholdLoop)
        end
    end

    section:Toggle({
        Title = "ออโต้ลง Stronghold อัตโนมัติ",
        Desc = "รอเวลา -> วาร์ปไปตี (Centroid AOE) -> เลือด 0 -> รอ 1s -> ตีพร้อมกัน -> เปิดหีบเก็บเพชร -> วนซ้ำเรื่อยๆ",
        Value = false,
        Callback = setAuto,
    })

    section:Button({
        Title = "วาร์ปไปหน้า Stronghold (Sign)",
        Desc = "วาร์ปไปยังป้ายหน้าประตูทางเข้า Stronghold",
        Callback = function()
            local hrp = getHRP()
            local sh = getStrongholdRoot()
            local building = sh and sh:FindFirstChild("Building")
            local sign = building and building:FindFirstChild("Sign")
            if hrp and sign then
                local signPos = sign:IsA("BasePart") and sign.Position
                    or (sign:IsA("Model") and sign:GetPivot().Position)
                    or (sign:FindFirstChildWhichIsA("BasePart", true) and sign:FindFirstChildWhichIsA("BasePart", true).Position)
                if signPos then
                    hrp.CFrame = CFrame.new(signPos + Vector3.new(0, 3, 5))
                end
            end
        end,
    })
end

return Stronghold
