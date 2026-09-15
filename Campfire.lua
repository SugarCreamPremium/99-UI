-- Version 9.15
local Campfire = {}

function Campfire.register(context)
    local tab = context.Tab
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:CreateSection("กองไฟ")

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

    -- ============================================
    -- LOST CHILDREN HELPERS
    -- ============================================
    local LOST_CHILD_NAMES = {
        "Lost Child",
        "Lost Child2",
        "Lost Child3",
        "Lost Child4",
    }
    local LOST_CHILD_TOTAL = #LOST_CHILD_NAMES

    local function kidAlreadyRescued(c)
        if c:GetAttribute("Lost") == false then return true end
        local interaction = c:GetAttribute("Interaction")
        if type(interaction) == "string" and string.sub(interaction, 1, 8) == "Befriend" then return true end
        return c:GetAttribute("Rescued") == true or c:GetAttribute("Friending") == true
    end

    local function kidStillLost(c)
        return c:GetAttribute("Lost") == true and c:GetAttribute("Interaction") == "CanBeBagged"
    end

    local function areAllChildrenRescued()
        local chars = workspace:FindFirstChild("Characters")
        if not chars then return true end
        for _, name in ipairs(LOST_CHILD_NAMES) do
            local c = chars:FindFirstChild(name)
            if c and not kidAlreadyRescued(c) then
                return false
            end
        end
        return true
    end

    local function allChildrenCollected(collectedChildren)
        for _, name in ipairs(LOST_CHILD_NAMES) do
            if not collectedChildren[name] then return false end
        end
        return true
    end

    local function collectLostChildren(collectedChildren)
        local chars = workspace:FindFirstChild("Characters")
        if not chars then return end

        for _, name in ipairs(LOST_CHILD_NAMES) do
            if not collectedChildren[name] then
                local c = chars:FindFirstChild(name)
                if c then
                    if kidAlreadyRescued(c) then
                        collectedChildren[name] = true
                    elseif kidStillLost(c) then
                        local head = c:FindFirstChild("Head")
                        local attachment = head and head:FindFirstChild("ProximityAttachment")
                        local prompt = attachment and attachment:FindFirstChild("ProximityInteraction")
                        if prompt then
                            local attempts = 0
                            while chars:FindFirstChild(name) and kidStillLost(c) and attempts < 10 do
                                local hrp = getHRP()
                                local root2 = c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
                                if hrp and root2 then
                                    hrp.CFrame = CFrame.new(root2.Position + Vector3.new(0, 2, 0))
                                    task.wait(0.1)
                                    if prompt.Enabled then
                                        pcall(function()
                                            if typeof(fireproximityprompt) == "function" then
                                                fireproximityprompt(prompt, 0, true)
                                            else
                                                prompt.HoldDuration = 0
                                                prompt:InputHoldBegin()
                                                task.wait(0.05)
                                                prompt:InputHoldEnd()
                                            end
                                        end)
                                    end
                                end
                                attempts = attempts + 1
                                task.wait(0.2)
                            end
                            if not chars:FindFirstChild(name) then
                                collectedChildren[name] = true
                            end
                        end
                    end
                end
            end
        end
    end

    local function dropAllLostChildren(firePos, collectedChildren)
        local inv = player:FindFirstChild("Inventory")
        local oldSack = inv and inv:FindFirstChild("Old Sack")
        if not oldSack then return end

        local hrp = getHRP()
        if not hrp then return end

        local targetPos = firePos + Vector3.new(0, 10, 0)
        pcall(function() hrp.CFrame = CFrame.new(targetPos) end)
        task.wait(0.5)

        if Client and Client.InventoryHandler then
            pcall(function() Client.InventoryHandler.RequestEquipItem(oldSack) end)
            task.wait(0.3)
        end

        local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local BagDrop = events and events:FindFirstChild("RequestBagDropItem")
        if not BagDrop then return end

        for name in pairs(collectedChildren) do
            local bag = player:FindFirstChild("ItemBag")
            local bagChild = bag and bag:FindFirstChild(name)
            if bagChild then
                pcall(function()
                    BagDrop:FireServer(oldSack, bagChild, false)
                end)
                task.wait(0.2)
            end
        end
    end

    -- ============================================
    -- FLOATING (AlignPosition + AlignOrientation)
    -- ============================================
    local floatAP = nil
    local floatAO = nil
    local followThread = nil

    local function ensureFloating(targetPos)
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (char and hrp) then return end

        if not hrp:FindFirstChild("FloatAttachment") then
            local att = Instance.new("Attachment")
            att.Name = "FloatAttachment"
            att.Parent = hrp
        end

        if not hrp:FindFirstChild("FloatAlignPosition") then
            floatAP = Instance.new("AlignPosition")
            floatAP.Name = "FloatAlignPosition"
            floatAP.Mode = Enum.PositionAlignmentMode.OneAttachment
            floatAP.Attachment0 = hrp.FloatAttachment
            floatAP.MaxForce = 5000
            floatAP.Responsiveness = 50
            floatAP.Position = targetPos or hrp.Position
            floatAP.Parent = hrp
        elseif targetPos then
            floatAP.Position = targetPos
        end

        if not hrp:FindFirstChild("FloatAlignOrientation") then
            floatAO = Instance.new("AlignOrientation")
            floatAO.Name = "FloatAlignOrientation"
            floatAO.Mode = Enum.OrientationAlignmentMode.OneAttachment
            floatAO.Attachment0 = hrp.FloatAttachment
            floatAO.MaxTorque = 5000
            floatAO.Responsiveness = 50
            floatAO.CFrame = hrp.CFrame
            floatAO.Parent = hrp
        end

        if not followThread then
            followThread = task.spawn(function()
                while floatAP and floatAP.Parent do
                    local c = player.Character
                    local h = c and c:FindFirstChild("HumanoidRootPart")
                    local hum = c and c:FindFirstChildOfClass("Humanoid")
                    if not h or not hum or hum.Health <= 0 then
                        break
                    end
                    floatAP.Position = h.Position
                    task.wait(0.1)
                end
                followThread = nil
            end)
        end
    end

    local function disableFloating()
        if followThread then
            pcall(function() task.cancel(followThread) end)
            followThread = nil
        end
        pcall(function() if floatAP then floatAP:Destroy() end end)
        pcall(function() if floatAO then floatAO:Destroy() end end)
        floatAP = nil
        floatAO = nil
    end

    -- ============================================
    -- AXE & TREE HANDLING
    -- ============================================
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

        -- ตรวจสอบก่อนเริ่ม: ถ้าเลเวลถึง 7 แล้ว และ ช่วยเด็กครบทั้ง 4 คนแล้ว -> ไม่ต้องทำอะไร
        if getCurrentLevel() >= maxLevel and areAllChildrenRescued() then
            hrp.CFrame = CFrame.new(firePos + Vector3.new(5, 3, 0))
            return
        end

        isWorking = true

        task.spawn(function()
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
            local collectedChildren = {}
            local FIRE_FUEL_ITEMS = {
                ["Fuel Canister"] = true,
                ["Oil Barrel"] = true,
                ["Coal"] = true,
                ["Log"] = true,
            }

            local airHeight = 20

            -- 1. บินดึงเชื้อเพลิงรอบแคมป์ไฟ พร้อมช่วยเด็ก
            for radius = 20, 1000, 40 do
                if getCurrentLevel() >= maxLevel and allChildrenCollected(collectedChildren) then break end

                local steps = 50 + math.floor(radius / 40) * 5
                local circumference = 2 * math.pi * radius
                local speed = 1000
                local duration = circumference / speed

                for i = 0, steps do
                    if getCurrentLevel() >= maxLevel and allChildrenCollected(collectedChildren) then break end

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

                    collectLostChildren(collectedChildren)

                    task.wait(duration / steps)
                end
            end

            -- 2. ถ้าเก็บเด็กยังไม่ครบ 4 คน ให้บินหาใหม่อีกรอบแบบละเอียดและกว้างขึ้น (Extended Range ตามแบบ MainScript)
            if not allChildrenCollected(collectedChildren) then
                for radius = 20, 1500, 40 do
                    local steps = 60
                    local circumference = 2 * math.pi * radius
                    local speed = 1000
                    local duration = circumference / speed

                    for i = 0, steps do
                        local angle = (i / steps) * math.pi * 2
                        local circlePos = firePos + Vector3.new(math.cos(angle) * radius, airHeight, math.sin(angle) * radius)
                        local curHRP = getHRP()
                        if curHRP then
                            curHRP.CFrame = CFrame.new(circlePos)
                        end
                        platform.Position = circlePos - Vector3.new(0, 3, 0)

                        collectLostChildren(collectedChildren)
                        task.wait(duration / steps)
                    end

                    -- เช็คหลังครบรอบเท่านั้น
                    if allChildrenCollected(collectedChildren) then break end
                end
            end

            -- ปล่อยเด็กทั้งหมดที่เก็บได้กลับกองไฟ
            dropAllLostChildren(firePos, collectedChildren)
            task.wait(0.5)

            -- 3. บินตัดไม้ต่อถ้าเลเวลกองไฟยังไม่ถึง 7
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

                    -- ระบบ Floating ตาม MainScript ด้วย AlignPosition + AlignOrientation
                    if not floatAP or not floatAP.Parent then
                        curHRP.CFrame = CFrame.new(cutPos)
                        task.wait(0.2)
                        ensureFloating(cutPos)
                    else
                        floatAP.Position = cutPos
                        curHRP.CFrame = CFrame.new(cutPos)
                    end
                    platform.Position = cutPos - Vector3.new(0, 33, 0)
                    task.wait(0.1)

                    local treeParent = tree.Parent
                    local hitCount = 0
                    local failStreak = 0

                    while tree.Parent == treeParent and getCurrentLevel() < maxLevel do
                        local currentAxe = checkAndReequipAxe(bestAxe)
                        if not currentAxe then break end

                        curHRP = getHRP()
                        if not curHRP then break end

                        local dir = math.random(1, 4)
                        local offset = (dir == 1 and Vector3.new(-3, 0, 0))
                            or (dir == 2 and Vector3.new(0, 0, -3))
                            or (dir == 3 and Vector3.new(3, 0, 0))
                            or Vector3.new(0, 0, 3)

                        local walkPos = treePos + Vector3.new(0, 30, 0) + offset
                        if floatAP and floatAP.Parent then
                            floatAP.Position = walkPos
                        end
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

                    -- ดึง Log เข้ากองไฟ
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

            -- ปิดระบบ floating และลบ platform
            disableFloating()
            if platform and platform.Parent then
                platform:Destroy()
            end

            -- นำขวานกลับมาถืออีกครั้งหากมี
            if bestAxe then
                equipAxe(bestAxe)
            end

            -- วาร์ปกลับแคมป์ไฟเสมอ
            local endHRP = getHRP()
            if endHRP then
                endHRP.CFrame = CFrame.new(firePos + Vector3.new(5, 3, 0))
            end

            isWorking = false
        end)
    end

    local createButton = rawget(section, "CreateButton") or (tab and tab.CreateButton)
    if createButton then
        createButton(section, "อัพเกรดกองไฟและช่วยเด็ก", startFireRoutine)
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
