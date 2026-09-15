-- Version 8.42
local Campfire = {}

function Campfire.register(context)
    local tab = context.Tab
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:CreateSection("อัพเกรดกองไฟอัตโนมัติ")

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getMainFire()
        local map = workspace:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
        return camp and camp:FindFirstChild("MainFire")
    end

    local function getFirePart()
        local mainFire = getMainFire()
        return mainFire and (mainFire:FindFirstChild("Fire") or mainFire.PrimaryPart or mainFire:FindFirstChildWhichIsA("BasePart"))
    end

    local function getFireFrame()
        local mainFire = getMainFire()
        local center = mainFire and mainFire:FindFirstChild("Center")
        local gui = center and center:FindFirstChild("BillboardGui")
        return gui and gui:FindFirstChild("Frame")
    end

    local maxLevel = 7

    local function getCurrentLevel()
        local frame = getFireFrame()
        local textLabel = frame and frame:FindFirstChild("TextLabel")
        if not textLabel then return 1 end

        local fireText = textLabel.Text
        if fireText:find("FIRE FULLY UPGRADED") or fireText:find("MAP FULLY REVEALED") then
            return maxLevel
        end
        if fireText == "" or fireText:match("^%s*$") then
            return maxLevel
        end
        local levelMatch = string.match(fireText, "level (%d+)")
        return tonumber(levelMatch) or 1
    end

    local function getBestAxe()
        local inv = player:FindFirstChild("Inventory")
        if not inv then return nil end
        local best, bestDmg = nil, -1
        for _, tool in ipairs(inv:GetChildren()) do
            if tool:GetAttribute("ToolName") == "GenericAxe" then
                local dmg = tool:GetAttribute("WeaponResourceDamage") or 0
                if dmg > bestDmg then
                    bestDmg = dmg
                    best = tool
                end
            end
        end
        return best
    end

    local function equipAxe(axe)
        if not axe or not Client or not Client.InventoryHandler then return end
        pcall(function()
            Client.InventoryHandler.RequestEquipItem(axe)
        end)
    end

    local function checkAndReequipAxe(axe)
        local char = player.Character
        local th = char and char:FindFirstChild("ToolHandle")
        local currentAxe = th and th:FindFirstChild("OriginalItem") and th.OriginalItem.Value
        if not currentAxe then
            equipAxe(axe)
            task.wait(0.3)
            char = player.Character
            th = char and char:FindFirstChild("ToolHandle")
            currentAxe = th and th:FindFirstChild("OriginalItem") and th.OriginalItem.Value
        end
        return currentAxe
    end

    local function warpItemToFire(item, firePos, warped)
        if warped[item] then return end
        task.spawn(function()
            pcall(function()
                local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
                if not events then return end
                local StartDrag = events:FindFirstChild("RequestStartDraggingItem")
                local StopDrag = events:FindFirstChild("StopDraggingItem")
                if not (StartDrag and StopDrag) then return end

                StartDrag:FireServer(item)
                task.wait(0.1)

                local targetPos = firePos + Vector3.new(0, 10, 0)
                if item:IsA("Model") then
                    item:PivotTo(CFrame.new(targetPos))
                else
                    item.CFrame = CFrame.new(targetPos)
                end

                task.wait(0.1)
                StopDrag:FireServer(item)
            end)
        end)
        warped[item] = true
    end

    local CHOPPABLE_TREE_NAMES = {
        "Small Tree",
        "Fairy Small Tree",
        "Snowy Small Tree",
        "Birch Tree",
        "Dead Tree1",
        "Dead Tree2",
        "Dead Tree3",
    }

    local function getTreesSorted(firePos)
        local found = {}
        for _, item in ipairs(workspace:GetDescendants()) do
            if item:GetAttribute("Health") and table.find(CHOPPABLE_TREE_NAMES, item.Name) then
                table.insert(found, item)
            end
        end
        table.sort(found, function(a, b)
            local posA = a:IsA("Model") and a:GetPivot().Position or a.Position
            local posB = b:IsA("Model") and b:GetPivot().Position or b.Position
            local distA = (posA - firePos).Magnitude
            local distB = (posB - firePos).Magnitude
            return distA < distB
        end)
        return found
    end

    local isWorking = false

    local function startFireRoutine()
        if isWorking then return end
        local hrp = getHRP()
        local firePart = getFirePart()
        if not hrp or not firePart then return end

        local firePos = firePart.Position

        -- 1. เช็คก่อนเริ่ม: ถ้าเลเวล 7 หรือ Max แล้ว วาร์ปกลับกองไฟทันที
        if getCurrentLevel() >= maxLevel then
            hrp.CFrame = CFrame.new(firePos + Vector3.new(5, 3, 0))
            return
        end

        isWorking = true

        task.spawn(function()
            -- หาขวานและถือทันทีก่อนเริ่ม
            local bestAxe = getBestAxe()
            if bestAxe then
                equipAxe(bestAxe)
                task.wait(0.3)
            end

            local platform = Instance.new("Part")
            platform.Size = Vector3.new(10, 1, 10)
            platform.Anchored = true
            platform.CanCollide = true
            platform.Transparency = 1
            platform.Parent = workspace

            local warpedItems = setmetatable({}, {__mode = "k"})
            local FIRE_FUEL_ITEMS = {
                ["Fuel Canister"] = true,
                ["Oil Barrel"] = true,
                ["Coal"] = true,
                ["Log"] = true,
            }

            local airHeight = 20

            -- 2. บินดึงเชื้อเพลิงรอบๆ กองไฟ
            for radius = 20, 1000, 40 do
                if getCurrentLevel() >= maxLevel then break end

                local steps = 50 + math.floor(radius / 40) * 5
                local circumference = 2 * math.pi * radius
                local speed = 1000
                local duration = circumference / speed

                for i = 0, steps do
                    if getCurrentLevel() >= maxLevel then break end

                    local currentHRP = getHRP()
                    if not currentHRP then break end

                    local alpha = i / steps
                    local angle = alpha * math.pi * 2
                    local offsetX = math.cos(angle) * radius
                    local offsetZ = math.sin(angle) * radius
                    local circlePos = firePos + Vector3.new(offsetX, airHeight, offsetZ)

                    currentHRP.CFrame = CFrame.new(circlePos)
                    platform.Position = circlePos - Vector3.new(0, 3, 0)

                    local itemsFolder = workspace:FindFirstChild("Items")
                    if itemsFolder then
                        for _, item in ipairs(itemsFolder:GetChildren()) do
                            if not warpedItems[item] and FIRE_FUEL_ITEMS[item.Name] then
                                warpItemToFire(item, firePos, warpedItems)
                            end
                        end
                    end

                    task.wait(duration / steps)
                end
            end

            -- 3. ถ้าดึงเชื้อเพลิงแล้วยังไม่ถึง Level 7 ให้บินตัดไม้ต่อ
            if getCurrentLevel() < maxLevel then
                local trees = getTreesSorted(firePos)
                local damageEvent = ReplicatedStorage:FindFirstChild("RemoteEvents")
                    and ReplicatedStorage.RemoteEvents:FindFirstChild("ToolDamageObject")
                local ownerId = tostring(player.UserId) .. "_" .. player.UserId

                for _, tree in ipairs(trees) do
                    if getCurrentLevel() >= maxLevel then break end
                    if not (tree and tree.Parent) then continue end

                    local foliage = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Foliage")
                    if foliage and not tree:IsDescendantOf(foliage) then
                        continue
                    end

                    local treePos = tree:IsA("Model") and tree:GetPivot().Position or tree.Position
                    local cutPos = treePos + Vector3.new(0, 30, 0)

                    local curHRP = getHRP()
                    if not curHRP then break end

                    curHRP.CFrame = CFrame.new(cutPos)
                    platform.Position = cutPos - Vector3.new(0, 33, 0)
                    task.wait(0.1)

                    local treeParent = tree.Parent
                    local hitCount = 0
                    local failStreak = 0

                    while tree.Parent == treeParent and getCurrentLevel() < maxLevel do
                        -- ตรวจสอบและถือขวานซ้ำหากหลุดมือ
                        local currentAxe = checkAndReequipAxe(bestAxe)
                        if not currentAxe then break end

                        curHRP = getHRP()
                        if not curHRP then break end

                        -- เคลื่อนที่เล็กน้อยขณะตัด
                        local dir = math.random(1, 4)
                        local offset = (dir == 1 and Vector3.new(-3, 0, 0))
                            or (dir == 2 and Vector3.new(0, 0, -3))
                            or (dir == 3 and Vector3.new(3, 0, 0))
                            or Vector3.new(0, 0, 3)

                        local walkPos = treePos + Vector3.new(0, 30, 0) + offset
                        curHRP.CFrame = CFrame.new(walkPos)

                        if damageEvent then
                            local success = pcall(function()
                                damageEvent:InvokeServer(tree, currentAxe, ownerId, curHRP.CFrame, false)
                            end)
                            if success then
                                failStreak = 0
                            else
                                failStreak = failStreak + 1
                                if failStreak >= 5 then break end
                            end
                        end

                        task.wait(0.1)
                        hitCount = hitCount + 1
                        if hitCount >= 500 then break end
                    end

                    -- ดึง Log ที่หล่นจากการตัดเข้ากองไฟทันที
                    local itemsFolder = workspace:FindFirstChild("Items")
                    if itemsFolder then
                        for _, item in ipairs(itemsFolder:GetChildren()) do
                            if not warpedItems[item] and FIRE_FUEL_ITEMS[item.Name] then
                                warpItemToFire(item, firePos, warpedItems)
                            end
                        end
                    end
                end
            end

            -- ลบ platform รองรับ
            platform:Destroy()

            -- 4. วาร์ปกลับแคมป์ไฟเสมอเมื่อเสร็จสิ้น
            local endHRP = getHRP()
            if endHRP then
                endHRP.CFrame = CFrame.new(firePos + Vector3.new(5, 3, 0))
            end

            isWorking = false
        end)
    end

    local createButton = rawget(section, "CreateButton") or (tab and tab.CreateButton)
    if createButton then
        createButton(section, "อัพเกรดกองไฟอัตโนมัติ (ดึงเชื้อเพลิง + ตัดไม้)", startFireRoutine)
        createButton(section, "วาร์ปกลับแคมป์ไฟ", function()
            local hrp = getHRP()
            local firePart = getFirePart()
            if hrp and firePart then
                hrp.CFrame = CFrame.new(firePart.Position + Vector3.new(5, 3, 0))
            end
        end)
    end
end

return Campfire
