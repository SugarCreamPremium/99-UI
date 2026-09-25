-- Version 4.44
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

        local function nearFire(pos)
            if not pos then return false end
            -- วัดระยะแนวนอน (ไม่เอา Y: ปล่อยจากความสูง +10 เหนือไฟ ถ้าตกพื้นยังถือว่าอยู่ที่ไฟ)
            local flat = Vector3.new(pos.X - firePos.X, 0, pos.Z - firePos.Z)
            return flat.Magnitude <= 15
        end

        -- ลำดับตายตัว: วาร์ปมาที่กองไฟก่อน -> รอ 0.5 วิ -> ตรวจว่าอยู่ที่กองไฟจริงแล้ว -> ค่อยปล่อย
        -- ไม่อยู่ที่กองไฟ = ห้ามปล่อยเด็ดขาด (คืนทันที ไม่แตะ BagDrop เลย)
        local targetPos = firePos + Vector3.new(0, 10, 0)
        pcall(function() hrp.CFrame = CFrame.new(targetPos) end)
        task.wait(0.5)

        local atFire = false
        hrp = getHRP()
        if hrp and nearFire(hrp.Position) then
            atFire = true
        end
        if not atFire then return end

        if Client and Client.InventoryHandler then
            pcall(function() Client.InventoryHandler.RequestEquipItem(oldSack) end)
            task.wait(0.3)
        end

        local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local BagDrop = events and events:FindFirstChild("RequestBagDropItem")
        if not BagDrop then return end

        for name in pairs(collectedChildren) do
            -- เช็คซ้ำทุกตัวก่อนปล่อย: ต้องอยู่ที่กองไฟเท่านั้น หลุดจากไฟ = หยุดปล่อยทันที
            local hrp2 = getHRP()
            if not (hrp2 and nearFire(hrp2.Position)) then break end
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
            -- เก็บผล drag เหมือน Item.lua: สำเร็จเท่านั้นถึงนับว่าดึงเสร็จ
            local dragOk = false
            if StartDrag then
                dragOk = pcall(function() StartDrag:FireServer(item) end)
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

            -- 5) drag ไม่สำเร็จ -> ปลดล็อกให้รอบหน้าลองดึงใหม่ (เหมือน Item.lua: นับเฉพาะ dragOk)
            --    (ยังต้องอ้างสิทธิ์ warped[item] ไว้ก่อน drag เสมอ กัน 2 รอบติดกันยิง drag ซ้อนกันตอนบิน)
            if not dragOk then
                warped[item] = nil
            end
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

    -- เช็คว่าต้นนี้ตัดได้ไหม (เลียนแบบ ToolModule.GetModelFromPart ของเกมทุกกรณี):
    -- 1) ชื่ออยู่ในรายชื่อต้นไม้จากไฟล์ Farm Map
    -- 2) มี Attribute Resource (เช่น "Wood")
    -- 3) มี AllowTool_<ชื่อขวานที่ถือ> = ขวานประเภทนี้ตัดต้นนี้ได้
    -- 4) ToolTier: ต้นไม่มี ToolTier = ตัดได้เสมอ (ไม่สนใจเลเวลขวาน)
    --    ต้นมี ToolTier + ขวานมี AxeLevel = ต้อง AxeLevel >= 3 (ตรงกับเกม: 3 <= AxeLevel)
    --    ต้นมี ToolTier + ขวานไม่มี AxeLevel = ต้อง tier ขวาน >= tier ต้น (ตรงกับเกม: ToolTier <= ToolTier)
    local function canCutTree(tree, tool)
        if typeof(tree) ~= "Instance" or not tree.Parent then return false end
        -- เช็คชื่อก่อน (ถูกที่สุด) กรองพวก Part/ของอื่นออกก่อนอ่าน Attribute
        if not table.find(CHOPPABLE_TREE_NAMES, tree.Name) then return false end
        if tree:GetAttribute("Destroyed") then return false end
        if tree:GetAttribute("NotAttackable") then return false end
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

    local function getTreesSorted(firePos, tool)
        local found = {}
        for _, item in ipairs(workspace:GetDescendants()) do
            if item:GetAttribute("Health") and table.find(CHOPPABLE_TREE_NAMES, item.Name)
                and canCutTree(item, tool) then
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

            -- บินวนรัศมีขยายแบบละเอียด (ใช้ทั้งรอบค้นหาแรกและรอบไปช่วยเด็กใหม่)
            local function searchExtended()
                for radius2 = 20, 1500, 40 do
                    local steps = 60
                    local circumference = 2 * math.pi * radius2
                    local speed = 1000
                    local duration = circumference / speed

                    for i = 0, steps do
                        local angle = (i / steps) * math.pi * 2
                        local circlePos = firePos + Vector3.new(math.cos(angle) * radius2, airHeight, math.sin(angle) * radius2)
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

            -- 1. บินดึงเชื้อเพลิงรอบแคมป์ไฟ พร้อมช่วยเด็ก (เหมือนเดิม)
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

            -- 2. ถ้าเก็บเด็กยังไม่ครบ 4 คน ให้บินหาใหม่อีกรอบแบบละเอียดและกว้างขึ้น (เหมือนเดิม)
            if not allChildrenCollected(collectedChildren) then
                searchExtended()
            end

            -- 3. ปล่อยเด็กที่กองไฟเท่านั้น (วาร์ปไฟ -> รอ 0.5 -> เช็คว่าอยู่ที่ไฟ -> ปล่อย)
            --    ปล่อยเสร็จเช็คทุกครั้งว่าช่วยครบหรือยัง —
            --    ถ้ายังไม่ได้ช่วย หรือปล่อยผิดที่ (หลุดไปปล่อยกลางทาง) -> บินไปช่วยเด็กที่เหลือมาใหม่ แล้ววนกลับมาปล่อยจนครบ
            local childrenRounds = 0
            -- ต้องเข้าวนปล่อยอย่างน้อย 1 รอบเสมอ: อย่าไปเช็ค areAllChildrenRescued เป็นเงื่อนไขเข้า
            -- เพราะเด็กที่อยู่ในกระสอบ (ItemBag) จะไม่อยู่ใน Characters -> areAllChildrenRescued คืน true
            -- ทั้งที่ยังไม่ได้ปล่อย -> ถ้าใช้เป็นเงื่อนไขเข้า จะไม่ปล่อยเลย (เด็กค้างในกระสอบจนจบแล้ววาร์ปกลับ)
            while childrenRounds < 5 do
                dropAllLostChildren(firePos, collectedChildren)
                task.wait(0.5)

                -- เช็คหลังปล่อย: ตัวไหนปล่อยไปแล้วแต่ยังหลงทางอยู่ (กลับมา Characters ยัง Lost)
                -- -> ยกสถานะ "เก็บแล้ว" ออก ให้ไปช่วยอีกครั้ง
                for _, name in ipairs(LOST_CHILD_NAMES) do
                    if collectedChildren[name] then
                        local bag2 = player:FindFirstChild("ItemBag")
                        local bagChild = bag2 and bag2:FindFirstChild(name)
                        local chars2 = workspace:FindFirstChild("Characters")
                        local c2 = chars2 and chars2:FindFirstChild(name)
                        if not bagChild and c2 and not kidAlreadyRescued(c2) then
                            collectedChildren[name] = nil
                        end
                    end
                end

                if areAllChildrenRescued() then break end

                -- ยังช่วยไม่ครบ -> บินหาเด็กที่เหลือกลับมา แล้ววนกลับมาปล่อยใหม่
                searchExtended()
                childrenRounds = childrenRounds + 1
            end

            -- 3. บินตัดไม้ต่อถ้าเลเวลกองไฟยังไม่ถึง 7
            if getCurrentLevel() < maxLevel then
                local trees = getTreesSorted(firePos, bestAxe)
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

    local function findCuttableTreesInRange(center, range, tool)
        local found = {}
        for _, item in ipairs(workspace:GetDescendants()) do
            -- กรองเฉพาะ Model ก่อน (Part เล็กๆ นับพันไม่ต้องอ่าน Attribute)
            if item:IsA("Model") and canCutTree(item, tool) then
                local pos = resolveTreePos(item)
                if pos and (pos - center).Magnitude <= range then
                    table.insert(found, item)
                end
            end
        end
        return found
    end

    -- ของที่ผู้เล่นถืออยู่ตอนนี้ (ไม่บังคับถือขวานให้เอง)
    local function getEquippedTool()
        local char = player.Character
        local th = char and char:FindFirstChild("ToolHandle")
        local item = th and th:FindFirstChild("OriginalItem")
        return item and item.Value
    end

    chopAuraLoop = function()
        local damageEvent = ReplicatedStorage:FindFirstChild("RemoteEvents")
            and ReplicatedStorage.RemoteEvents:FindFirstChild("ToolDamageObject")
        local ownerId = tostring(player.UserId) .. "_" .. player.UserId
        local lastScan = 0
        local cachedTrees = {}
        while chopAuraEnabled do
            local hrp = getHRP()
            -- ใช้ของที่ผู้เล่นถือเองเท่านั้น (ผู้ใช้กดถือขวาน / เลื่อย เอง)
            local axe = getEquippedTool()
            if hrp and axe and axe:GetAttribute("WeaponResourceDamage") and damageEvent then
                -- สแกนหาต้นไม้ใหม่แค่ 1 ครั้ง/วิ: ที่แลคเพราะสแกน workspace ทั้งหมดทุก 0.2 วิ
                local now = os.clock()
                if now - lastScan >= 1 then
                    cachedTrees = findCuttableTreesInRange(hrp.Position, chopAuraRange, axe)
                    lastScan = now
                end
                -- ตัดพร้อมกันทุกต้นที่สแกนเจอ (ยิงล็อตเดียวทุก ~0.2 วิ)
                for _, tree in ipairs(cachedTrees) do
                    pcall(function()
                        damageEvent:InvokeServer(tree, axe, ownerId, hrp.CFrame, false)
                    end)
                end
                task.wait(0.2)
            else
                -- ไม่ได้ถือขวาน -> รอเฉยๆ (ไม่มีระบบถือให้แล้ว)
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

    -- ของที่รับลองปลูกได้: ชื่อ Sapling/Giant Sapling หรือมีแท็ก Plantable
    -- (ตรงกับ findRealSapling ของ Plant Sapling Loop.lua ที่ใช้ได้จริง —
    -- อย่าไปบังคับ Interaction Attribute เพราะของจริงในเกมอาจไม่มี)
    local function isSaplingLike(item)
        return item.Name == "Sapling" or item.Name == "Giant Sapling"
            or item:HasTag("Plantable")
    end

    -- หา Sapling ที่ปลูกได้ เฉพาะใน Items (แบบ Plant Sapling Loop.lua — หาของใน
    -- กระเป๋า/Inventory แล้วยิง remote เซิร์ฟเวอร์ reject วนไม่จบ ต้องเป็นของที่วางในโลกเท่านั้น)
    -- ยังไม่ได้เป็นของคนอื่น (Owner ว่างหรือเป็นเรา)
    local function findSapling()
        local items = workspace:FindFirstChild("Items")
        if not items then return nil end
        local fallback = nil
        for _, item in ipairs(items:GetChildren()) do
            local owner = item:GetAttribute("Owner")
            if not owner or owner == player.UserId then
                if isSaplingLike(item) then return item end
                if item:HasTag("Acorn") and not fallback then fallback = item end
            end
        end
        return fallback
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

    -- เช็คว่าจุดนี้ห่างกองไฟพอ (เกม/เซิร์ฟเวอร์ห้ามปลูกใกล้ไฟ <40) — แบบเดียวกับ Plant Sapling Loop.lua
    -- วัดจาก MainFire.PrimaryPart เหมือน reference (ไม่ใช้ "Fire" child ซึ่งตำแหน่งอาจต่าง)
    local function fireSafe(pos)
        local mainFire = getMainFire()
        local firePart = mainFire and (mainFire.PrimaryPart or mainFire:FindFirstChildWhichIsA("BasePart"))
        local firePos = firePart and firePart.Position
        if not firePos then return true end
        return (firePos - pos).Magnitude >= 40
    end

    -- ปลูก 1 ต้นที่ใต้เท้าเรา (เลียนแบบ Plant Sapling Loop.lua ที่ใช้ได้จริง):
    -- ไม่ต้องย้าย/drag ตัว Sapling เลย — เอาแค่ตำแหน่งใต้เท้าหา Grass แล้วย้าย Parent
    -- ไป TempStorage ก่อนยิง remote (ย้ายตัวของมันเองทำให้เซิร์ฟเวอร์ reject)
    local function plantSaplingAtFeet(sapling)
        local events = Client and Client.Events
        local temp = ReplicatedStorage:FindFirstChild("TempStorage")
        if not events or not temp then return false end

        -- ไม่ Alive (ตาย/กำลังรีสปอน) -> เซิร์ฟเวอร์ reject ทุกกรณี ข้ามไปแบบเงียบๆ
        -- (เช็คเดียวกันกับ Plant Sapling Loop.lua)
        if Client and Client.PlayerHandler and not Client.PlayerHandler.Alive then return false end

        local hrp = getHRP()
        if not hrp or not sapling then return false end

        local grass = findGrassAt(hrp.Position)
        if not grass then return false end
        if not fireSafe(grass) then return false end

        local parent = sapling.Parent
        sapling.Parent = temp

        if sapling:HasTag("Acorn") then
            -- Acorn: เกมต้องการระยะ 4-60 จาก tree root (ส่งตำแหน่งของตัวมันเอง)
            -- Client.Events.RequestPlantAcorn เป็น wrapper (UtilityModules/Events) ไม่ใช่ Instance
            -- ใช้ :InvokeServer ตรงๆ แบบเดียวกับเกม (TreeRootClient.lua:120)
            local pos = resolveTreePos(sapling) or hrp.Position
            local ok, res = pcall(function() return events.RequestPlantAcorn:InvokeServer(sapling, pos) end)
            if not (ok and res and res.Success) then
                sapling.Parent = parent
                return false
            end
            return true
        end

        -- Client.Events.RequestPlantItem เป็น wrapper (UtilityModules/Events) ไม่ใช่ Instance
        -- ใช้ :InvokeServer ตรงๆ แบบเดียวกับ reference และเกม (InteractionHandler.lua:1229)
        local ok, res = pcall(function() return events.RequestPlantItem:InvokeServer(sapling, grass) end)
        if not (ok and res and res.Success) then
            sapling.Parent = parent
            return false
        end
        return true
    end

    -- ดึง Sapling มาไว้ที่ตัวเราก่อนแล้วค่อยปลูก (แบบเดียวกับ Auto Plant Sapling Loop.lua)
    -- ต้องผ่าน drag remote ของเกม (RequestStartDraggingItem -> PivotTo -> StopDraggingItem)
    -- การย้ายตัวเองโดยไม่ผ่าน drag ทำให้เซิร์ฟเวอร์ไม่รับรู้/reset ตำแหน่ง
    local function pullItemToFeet(sapling)
        local hrp = getHRP()
        if not hrp or not sapling then return false end
        local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local startDrag = remoteEvents and remoteEvents:FindFirstChild("RequestStartDraggingItem")
        local stopDrag = remoteEvents and remoteEvents:FindFirstChild("StopDraggingItem")
        if not (startDrag and stopDrag) then return false end
        local ok = pcall(function() startDrag:FireServer(sapling) end)
        task.wait(0.02)
        if sapling:IsA("Model") then
            pcall(function() sapling:PivotTo(CFrame.new(hrp.Position)) end)
        elseif sapling:IsA("BasePart") then
            pcall(function() sapling.CFrame = CFrame.new(hrp.Position) end)
        end
        task.wait(0.02)
        pcall(function() stopDrag:FireServer(sapling) end)
        return ok
    end

    local function plantLoop()
        while plantEnabled do
            local sapling = findSapling()
            if sapling then
                local ok, plantedOrErr = pcall(function()
                    pullItemToFeet(sapling)
                    task.wait(0.05) -- รอ drag วางตัวก่อนยิง remote ปลูก
                    return plantSaplingAtFeet(sapling)
                end)
                if ok and plantedOrErr then
                    task.wait(0.1) -- เป้า: ต้นละ ~0.1s หลังยิงจบ
                else
                    task.wait(0.3) -- reject/error รอ 0.3 กันยิงรัวใส่ของเดิม
                end
            else
                task.wait(0.5)
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
            Desc = "ถือขวาน/เลื่อยด้วยตัวเอง แล้วจะตัดทุกต้นที่ตัดได้ในระยะพร้อมกัน",
            Value = false,
            Callback = setChopAura,
        })
        chopSection:Slider({
            Title = "ระยะตัด",
            Value = {Min = 5, Max = 80, Default = chopAuraRange},
            Step = 1,
            Callback = function(value) chopAuraRange = math.clamp(value, 5, 100) end,
        })
    end

    local plantSection = tab:Section({Title = "ปลูกต้นไม้", Opened = true})
    if plantSection then
        plantSection:Toggle({
            Title = "ปลูก Sapling อัตโนมัติ",
            Desc = "หา Sapling แล้วปลูกใต้เท้าทันที (ต้องห่างจากกองไฟ > 40)",
            Value = false,
            Callback = setPlantEnabled,
        })

        -- ============================================
        -- ปลูกต้นไม้เป็นวงกลมรอบกองไฟ
        -- ============================================
        -- กองไฟอยู่ที่ Center (PrimaryPart) — ต้องห่าง >= 40 ตามที่ fireSafe บังคับ
        local circleEnabled = false
        local circleRunning = false
        local circleRadius = 50
        local circleCount = 12
        local circleIndex = 1

        -- forward declaration: setCircleEnabled เรียก circleLoop ก่อนถึงจุดนิยาม
        -- (ไม่ declare ล่วงหน้า Lua จะ resolve เป็น global nil -> error ตอนกด toggle)
        local circleLoop

        local function setCircleEnabled(value)
            circleEnabled = value
            if circleEnabled and not circleRunning then
                circleRunning = true
                circleIndex = 1
                task.spawn(circleLoop)
            end
        end

        circleLoop = function()
            local mainFire = getMainFire()
            local firePart = mainFire and (mainFire.PrimaryPart or mainFire:FindFirstChildWhichIsA("BasePart"))
            local firePos = firePart and firePart.Position
            if not firePos then
                circleRunning = false
                return
            end

            local count = math.clamp(circleCount, 4, 36)
            local step = (2 * math.pi) / count

            while circleEnabled do
                local hrp = getHRP()
                local sapling = findSapling()
                if hrp and sapling then
                    -- จุดรอบวง: เริ่มที่ตำแหน่งเดิมก่อน แล้วไล่ทีละจุด
                    local angle = step * (circleIndex - 1)
                    local radius = math.max(circleRadius, 40)
                    local spot = findGrassAt(firePos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
                        or (firePos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
                    circleIndex = (circleIndex % count) + 1

                    if fireSafe(spot) then
                        hrp.CFrame = CFrame.new(spot + Vector3.new(0, 3, 0))
                        task.wait(0.1)
                        local ok, planted = pcall(function()
                            pullItemToFeet(sapling)
                            task.wait(0.05)
                            return plantSaplingAtFeet(sapling)
                        end)
                        task.wait(ok and planted and 0.15 or 0.4)
                    else
                        task.wait(0.1)
                    end
                else
                    task.wait(0.5)
                end
            end
            circleRunning = false
        end

        plantSection:Toggle({
            Title = "ปลูกรอบกองไฟเป็นวงกลม",
            Desc = "วาร์ปไปปลูก Sapling ทีละจุดรอบวงกลม (ต้องห่างจากกองไฟ >= 40)",
            Value = false,
            Callback = setCircleEnabled,
        })
        plantSection:Slider({
            Title = "รัศมีวง",
            Value = {Min = 40, Max = 150, Default = circleRadius},
            Step = 1,
            Callback = function(value) circleRadius = math.clamp(value, 40, 150) end,
        })
        plantSection:Slider({
            Title = "จำนวนจุดต่อรอบ",
            Value = {Min = 4, Max = 36, Default = circleCount},
            Step = 1,
            Callback = function(value) circleCount = math.clamp(value, 4, 36) end,
        })
    end
end

return Campfire
