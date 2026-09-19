-- Version 12.06
local Campfire = {}

function Campfire.register(context)
    local tab = context.Tab
    local player = context.Player
    local Client = context.Client
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:Section({Title = "กองไฟ", Opened = true})
    if not section then return end

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
    -- หาขวานดีสุดจาก Inventory: มี WeaponResourceDamage = ตัดไม้ได้
        -- (ไม่จำกัดชื่อ GenericAxe แล้ว ใครมี attribute นี้ก็เป็นขวาน)
        local function getBestAxe()
        local inv = player:FindFirstChild("Inventory")
        if not inv then return nil end
        local best, bestDmg = nil, -1
        for _, tool in ipairs(inv:GetChildren()) do
            local dmg = tool:GetAttribute("WeaponResourceDamage")
            if dmg and dmg > 0 and dmg > bestDmg then
                bestDmg = dmg
                best = tool
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
        -- ของที่ถืออยู่คือขวานไหม = มี WeaponResourceDamage (เช็ค attribute ไม่ใช่ชื่อ)
        if not currentAxe or not currentAxe:GetAttribute("WeaponResourceDamage") then
            equipAxe(axe)
            task.wait(0.3)
            char = player.Character
            th = char and char:FindFirstChild("ToolHandle")
            currentAxe = th and th:FindFirstChild("OriginalItem") and th.OriginalItem.Value
        end
        if not currentAxe or not currentAxe:GetAttribute("WeaponResourceDamage") then
            return nil
        end
        return currentAxe
    end

    -- รวมชิ้นส่วนทั้งหมดของของชิ้นนี้ (Model -> ทุก BasePart ลูกหลาน, Part -> ตัวมันเอง)
    local function collectParts(item)
        local parts = {}
        if item:IsA("Model") then
            for _, part in ipairs(item:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(parts, part) end
            end
        elseif item:IsA("BasePart") then
            table.insert(parts, item)
        end
        return parts
    end

    -- ทำลายเฉพาะ Joints ที่เชื่อมกับชิ้นส่วนภายนอกโมเดล (ไม่แตะข้อต่อภายใน)
    local function breakExternalJoints(item, parts)
        for _, part in ipairs(parts) do
            pcall(function()
                for _, joint in ipairs(part:GetJoints()) do
                    local other = joint.Part0 == part and joint.Part1 or joint.Part0
                    if other and other:IsA("BasePart") and not other:IsDescendantOf(item) then
                        joint:Destroy()
                    end
                end
            end)
            pcall(function()
                for _, wc in ipairs(part:GetChildren()) do
                    if wc:IsA("WeldConstraint") then
                        local other = wc.Part0 == part and wc.Part1 or wc.Part0
                        if other and other:IsA("BasePart") and not other:IsDescendantOf(item) then
                            wc:Destroy()
                        end
                    end
                end
            end)
        end
    end

    -- ปลด Anchor ทุกชิ้นของของที่ดึงมา (ไม่ให้เหลือชิ้นไหนลอยค้าง)
    local function releaseAnchors(parts)
        for _, part in ipairs(parts) do
            pcall(function()
                if part.Parent then
                    part.Anchored = false
                end
            end)
        end
    end

    local function warpItemToFire(item, firePos, warped)
        if warped[item] then return end
        local parts = collectParts(item)
        if #parts == 0 then return end
        warped[item] = true

        -- ดึงแบบพร้อมกันทุกชิ้น (แยก task ต่อชิ้น) -> รวมเวลาแค่ ~0.1 วิ ไม่ว่าจะกี่ชิ้น
        task.spawn(function()
            -- 1) ปลดข้อต่อภายนอกเท่านั้น (ส่วนภายในโมเดลยังติดกันเหมือนเดิม)
            breakExternalJoints(item, parts)

            -- 2) Anchor ทุกชิ้นชั่วคราว (กันลูกกระจายระหว่างดึง)
            for _, part in ipairs(parts) do
                pcall(function() part.Anchored = true end)
            end
            task.wait(0.02)

            local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
            local StartDrag = events and events:FindFirstChild("RequestStartDraggingItem")
            local StopDrag = events and events:FindFirstChild("StopDraggingItem")
            if StartDrag then
                pcall(function() StartDrag:FireServer(item) end)
            end
            task.wait(0.02)

            -- กระจายจุดตกเล็กน้อยรอบกองไฟ กันของทุกชิ้นซ้อนทับจุดเดียวกันพอดี
            local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
            local targetPos = firePos + Vector3.new(0, 10, 0) + offset
            if item:IsA("Model") then
                pcall(function() item:PivotTo(CFrame.new(targetPos)) end)
            else
                pcall(function() item.CFrame = CFrame.new(targetPos) end)
            end
            task.wait(0.02)
            if StopDrag then
                pcall(function() StopDrag:FireServer(item) end)
            end
            task.wait(0.02)

            -- 3) ปลด Anchor ทุกชิ้นเสมอ ไม่ว่า drag จะ error หรือ part โดน destroy กลางคัน
            releaseAnchors(parts)

            -- 4) เช็คซ้ำอีกรอบหลัง server กลับสถานะ (กัน anchor ค้างจากฝั่งเกม)
            task.delay(0.4, function() releaseAnchors(parts) end)
        end)
    end

    -- รายชื่อต้นไม้ที่ตัดได้: ตรวจจากไฟล์ Farm Map (Small Tree, Snowy Small Tree, TreeBig1-3, "Tree", Bear Tree)
    -- + ชื่อที่เคยเห็นในเกมเพิ่มเติม (Fairy Small Tree, Birch Tree, Dead Tree1-3)
    -- ตัวกรองจริงยังเช็ค Attribute Resource + AllowTool_<ขวาน> + ToolTier อีกชั้น (ดู canCutTree)
    local CHOPPABLE_TREE_NAMES = {
        "Small Tree",
        "Fairy Small Tree",
        "Snowy Small Tree",
        "Birch Tree",
        "Dead Tree1",
        "Dead Tree2",
        "Dead Tree3",
        "TreeBig1",
        "TreeBig2",
        "TreeBig3",
        "Tree",
        "Bear Tree",
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

    -- หาตำแหน่งต้นไม้ให้ปลอดภัย (กัน nil หลุดไปบวกกับ Vector3)
    local function resolveTreePos(tree)
        if tree == nil then return nil end
        if tree:IsA("Model") then
            local ok, pivot = pcall(function() return tree:GetPivot() end)
            if ok and pivot then return pivot.Position end
            for _, part in ipairs(tree:GetDescendants()) do
                if part:IsA("BasePart") then return part.Position end
            end
            return nil
        end
        if tree:IsA("BasePart") then return tree.Position end
        return nil
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
                    if not (tree and tree.Parent) then
                        break
                    end

                    -- treePos ต้องอยู่นอก if-block (ใช้ต่อใน while ตอนฟัน) กัน nil หลุดไปบวก Vector3
                    local treePos = resolveTreePos(tree)
                    if not treePos then break end
                    local cutPos = treePos + Vector3.new(0, 30, 0)

                    local foliage = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Foliage")
                    if not foliage or tree:IsDescendantOf(foliage) then
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
                    end
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

    section:Paragraph({
        Title = "อัพเกรดกองไฟและช่วยเด็ก",
        Desc = "เริ่มกระบวนการอัปเกรดและช่วยเด็ก",
        Buttons = {{
            Title = "เริ่ม",
            Icon = "flame",
            Callback = startFireRoutine,
        }},
    })
    section:Paragraph({
        Title = "วาร์ปกลับแคมป์ไฟ",
        Desc = "กลับไปยังตำแหน่งกองไฟ",
        Buttons = {{
            Title = "วาร์ป",
            Icon = "map-pin",
            Callback = function()
                local hrp = getHRP()
                local firePart = getFirePart()
                if hrp and firePart then
                    hrp.CFrame = CFrame.new(firePart.Position + Vector3.new(5, 3, 0))
                end
            end,
        }},
    })

    -- ============================================
    -- ตัดต้นไม้รอบตัว (Kill Aura) + ปลูกต้นไม้
    -- ============================================
    local chopAuraEnabled = false
    local chopAuraRange = 25
    local chopAuraRunning = false

    -- forward declaration (ฟังก์ชันจริงอยู่ด้านล่าง): setChopAura เรียกก่อนฟังก์ชันประกาศ
    -- ถ้าไม่ declare ล่วงหน้า Lua จะ resolve เป็น global nil -> error ตอนกด toggle
    local chopAuraLoop

    local function setChopAura(value)
        chopAuraEnabled = value
        if chopAuraEnabled and not chopAuraRunning then
            chopAuraRunning = true
            task.spawn(chopAuraLoop)
        end
    end

    -- เช็คว่าต้นนี้ตัดได้ไหม (เลียนแบบ ToolModule.GetModelFromPart ของเกม):
    -- 1) ชื่ออยู่ในรายชื่อต้นไม้จากไฟล์ Farm Map
    -- 2) มี Attribute Resource (เช่น "Wood")
    -- 3) มี AllowTool_<ชื่อขวานที่ถือ> = ขวานประเภทนี้ตัดต้นนี้ได้
    -- 4) ToolTier: ต้นต้องการ tier เท่าไหร่ ขวานต้องพอดีหรือมากกว่า (หรือ AxeLevel >= 3)
    local function canCutTree(tree, tool)
        if typeof(tree) ~= "Instance" or not tree.Parent then return false end
        if tree:GetAttribute("Destroyed") then return false end
        if tree:GetAttribute("NotAttackable") then return false end
        if not table.find(CHOPPABLE_TREE_NAMES, tree.Name) then return false end
        if not tree:GetAttribute("Resource") then return false end
        local toolName = tool and tool:GetAttribute("ToolName")
        if not toolName or not tree:GetAttribute("AllowTool_" .. toolName) then return false end
        local reqTier = tree:GetAttribute("ToolTier")
        if reqTier then
            local axeLevel = tool:GetAttribute("AxeLevel")
            if axeLevel then
                if axeLevel < 3 then return false end
            elseif (tool:GetAttribute("ToolTier") or 1) < reqTier then
                return false
            end
        end
        return true
    end

    local function findCuttableTreesInRange(center, range, tool)
        local found = {}
        for _, item in ipairs(workspace:GetDescendants()) do
            if canCutTree(item, tool) then
                local pos = resolveTreePos(item)
                if pos and (pos - center).Magnitude <= range then
                    table.insert(found, item)
                end
            end
        end
        return found
    end

    chopAuraLoop = function()
        local damageEvent = ReplicatedStorage:FindFirstChild("RemoteEvents")
            and ReplicatedStorage.RemoteEvents:FindFirstChild("ToolDamageObject")
        local ownerId = tostring(player.UserId) .. "_" .. player.UserId
        while chopAuraEnabled do
            local hrp = getHRP()
            local bestAxe = getBestAxe()
            local axe = hrp and checkAndReequipAxe(bestAxe)
            if hrp and axe and damageEvent then
                -- ตัดพร้อมกันทุกต้นในระยะ (ยิงล็อตเดียวทุก ~0.2 วิ)
                for _, tree in ipairs(findCuttableTreesInRange(hrp.Position, chopAuraRange, axe)) do
                    local target = tree
                    pcall(function()
                        damageEvent:InvokeServer(target, axe, ownerId, hrp.CFrame, false)
                    end)
                end
                task.wait(0.2)
            else
                task.wait(0.5)
            end
        end
        chopAuraRunning = false
    end

    -- ============================================
    -- ปลูกต้นไม้ด้วย Sapling ที่เท้าของเรา
    -- ============================================
    local plantEnabled = false
    local plantRunning = false

    -- หา Sapling ที่ปลูกได้ (ใน Items หรือกระเป๋า, ยังไม่ได้เป็นของคนอื่น)
    local function findSapling()
        local candidates = {}
        local items = workspace:FindFirstChild("Items")
        if items then
            for _, item in ipairs(items:GetChildren()) do
                table.insert(candidates, item)
            end
        end
        local inv = player:FindFirstChild("Inventory")
        if inv then
            for _, item in ipairs(inv:GetChildren()) do
                table.insert(candidates, item)
            end
        end
        for _, item in ipairs(candidates) do
            if item.Name == "Sapling"
                and (item:HasTag("Plantable") or item:HasTag("Acorn")) then
                local owner = item:GetAttribute("Owner")
                if not owner or owner == player.UserId then
                    return item
                end
            end
        end
        return nil
    end

    -- หาพื้นดินใต้จุด (Raycast ลงล่าง เฉพาะชั้น Ground/Snow แบบเดียวกับเกม)
    local function findGrassAt(pos)
        local map = workspace:FindFirstChild("Map")
        local ground = map and map:FindFirstChild("Ground")
        if not ground then return nil end
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { ground, map:FindFirstChild("Snow") }
        params.FilterType = Enum.RaycastFilterType.Include
        params.IgnoreWater = true
        local hit = workspace:Raycast(pos, Vector3.new(0, -55, 0), params)
        return hit and hit.Position or nil
    end

    -- ปลูก 1 ต้นที่เท้าเรา (เลียนแบบ AttemptPlantItem ของเกม)
    local function plantSaplingAtFeet(sapling)
        local hrp = getHRP()
        if not hrp or not sapling then return end

        -- ย้าย Sapling มาที่เท้าก่อน (ใช้ตำแหน่งตัวเองหา Grass แบบเดียวกับเกม)
        pcall(function()
            if sapling:IsA("Model") then
                sapling:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, 0.5, 0)))
            elseif sapling:IsA("BasePart") then
                sapling.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 0.5, 0))
            end
        end)
        task.wait(0.05)

        local events = Client and Client.Events
        local temp = ReplicatedStorage:FindFirstChild("TempStorage")
        if not events or not temp then return end
        local parent = sapling.Parent

        if sapling:HasTag("Acorn") then
            -- Acorn: เกมต้องการระยะ 4-60 จาก tree root (ส่งตำแหน่งของมันเอง)
            local remote = events.RequestPlantAcorn
            if typeof(remote) ~= "Instance" then return end
            local pos = resolveTreePos(sapling) or hrp.Position
            sapling.Parent = temp
            local ok, res = pcall(function() return remote:InvokeServer(sapling, pos) end)
            if not (ok and res and res.Success) then sapling.Parent = parent end
        else
            local remote = events.RequestPlantItem
            if typeof(remote) ~= "Instance" then return end
            local at = resolveTreePos(sapling) or hrp.Position
            local grass = findGrassAt(at) or findGrassAt(hrp.Position)
            if not grass then return end
            sapling.Parent = temp
            local ok, res = pcall(function() return remote:InvokeServer(sapling, grass) end)
            if not (ok and res and res.Success) then sapling.Parent = parent end
        end
    end

    local function plantLoop()
        while plantEnabled do
            local sapling = findSapling()
            if sapling then
                pcall(plantSaplingAtFeet, sapling)
                task.wait(0.8)
            else
                task.wait(1)
            end
        end
        plantRunning = false
    end

    local function setPlantEnabled(value)
        plantEnabled = value
        if plantEnabled and not plantRunning then
            plantRunning = true
            task.spawn(plantLoop)
        end
    end

    local chopSection = tab:Section({Title = "ตัดต้นไม้รอบตัว", Opened = true})
    if chopSection then
        chopSection:Toggle({
            Title = "ตัดต้นไม้ Kill Aura",
            Desc = "ตัดทุกต้นที่ตัดได้ในระยะพร้อมกัน (ต้องถือขวาน) เริ่มจาก self-check ToolTier อัตโนมัติ",
            Value = false,
            Callback = setChopAura,
        })
        chopSection:Slider({
            Title = "ระยะตัด",
            Value = {Min = 5, Max = 100, Default = chopAuraRange},
            Step = 1,
            Callback = function(value) chopAuraRange = math.clamp(value, 5, 100) end,
        })
    end

    local plantSection = tab:Section({Title = "ปลูกต้นไม้", Opened = true})
    if plantSection then
        plantSection:Toggle({
            Title = "ปลูก Sapling อัตโนมัติ",
            Desc = "หา Sapling ใน Items/กระเป๋า แล้วปลูกที่เท้าของเราเรื่อยๆ",
            Value = false,
            Callback = setPlantEnabled,
        })
    end
end

return Campfire
