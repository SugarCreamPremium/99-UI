-- Version 1.00
local Item = {}

function Item.register(context)
    local tab = context.Tab
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:Section({Title = "ดึงสิ่งของ", Opened = true})
    if not section then return end

    local maxAmount = 10
    local selectedItems = {}
    local isPulling = false
    local warpedItems = setmetatable({}, {__mode = "k"})

    local function getHead()
        local character = player.Character
        return character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
    end

    local function getItemPosition(item)
        if item:IsA("Model") then
            local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position
        elseif item:IsA("BasePart") then
            return item.Position
        end
    end

    local function getInteractionRoot(item)
        local current = item
        while current and current.Parent and current.Parent ~= workspace.Items do
            current = current.Parent
        end
        return current
    end

    local function isValidItem(item)
        local items = workspace:FindFirstChild("Items")
        if not item or not items or not item:IsDescendantOf(items) then return false end
        if not (item:IsA("Model") or item:IsA("BasePart")) then return false end
        if not getItemPosition(item) then return false end
        local root = getInteractionRoot(item)
        if root ~= item then return false end
        local name = item.Name
        if name == "Part" or name == "Cabin" or name == "Model" or name == "woodplanks"
            or name == "Berry Bush" or string.find(string.lower(name), "bush", 1, true) then
            return false
        end
        local map = workspace:FindFirstChild("Map")
        if map and item:IsDescendantOf(map) then return false end
        local interaction = item:GetAttribute("Interaction")
        if interaction ~= "Item" and interaction ~= "Tool" then return false end
        local owner = item:GetAttribute("Owner")
        return not owner or owner == player.UserId
    end

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

    local function pullSingleItem(item, targetPosition)
        if warpedItems[item] or not isValidItem(item) then return false end
        local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local startDrag = events and events:FindFirstChild("RequestStartDraggingItem")
        local stopDrag = events and events:FindFirstChild("StopDraggingItem")
        if not (startDrag and stopDrag) then return false end

        local parts = collectParts(item)
        if #parts == 0 then return false end

        -- 1) ปลดข้อต่อภายนอกเท่านั้น (ส่วนภายในโมเดลยังติดกันเหมือนเดิม)
        breakExternalJoints(item, parts)

        -- 2) Anchor ทุกชิ้นชั่วคราว (กันลูกกระจายระหว่างลาก)
        for _, part in ipairs(parts) do
            pcall(function() part.Anchored = true end)
        end
        task.wait(0.02)

        local dragOk = pcall(function() startDrag:FireServer(item) end)
        task.wait(0.02)
        if item:IsA("Model") then
            pcall(function() item:PivotTo(CFrame.new(targetPosition)) end)
        else
            pcall(function() item.CFrame = CFrame.new(targetPosition) end)
        end
        task.wait(0.02)
        pcall(function() stopDrag:FireServer(item) end)
        task.wait(0.02)

        -- 3) ปลด Anchor ทุกชิ้นเสมอ ไม่ว่า drag จะ error หรือ part โดน destroy กลางคัน
        releaseAnchors(parts)

        -- 4) เช็คซ้ำอีกรอบหลัง server กลับสถานะ (กัน anchor ค้างจากฝั่งเกม)
        task.delay(0.4, function() releaseAnchors(parts) end)

        if dragOk and item.Parent then warpedItems[item] = true end
        return dragOk
    end

    local function getAvailableItemNames()
        local items = workspace:FindFirstChild("Items")
        if not items then return {} end
        local names = {}
        for _, item in ipairs(items:GetChildren()) do
            if isValidItem(item) then names[item.Name] = true end
        end
        local result = {}
        for name in pairs(names) do table.insert(result, name) end
        table.sort(result)
        return result
    end

    local function pullSelectedItems()
        if isPulling or not next(selectedItems) then return end
        local items = workspace:FindFirstChild("Items")
        if not items then return end
        local target = getPullTargetPosition()
        if not target then return end
        isPulling = true
        task.spawn(function()
            -- pcall กัน error กลางลูป แล้ว isPulling ค้างเป็น true (กดดึงไม่ได้ไปตลอด)
            local ok, err = pcall(function()
                for _, name in ipairs(getAvailableItemNames()) do
                    if selectedItems[name] then
                        local count = 0
                        for _, item in ipairs(items:GetChildren()) do
                            if item.Name == name and pullSingleItem(item, target) then
                                count = count + 1
                                task.wait(0.02)
                                if count >= maxAmount then break end
                            end
                        end
                    end
                end
            end)
            if not ok then warn("Pull error: " .. tostring(err)) end
            isPulling = false
        end)
    end

    local function pullAllItems()
        if isPulling then return end
        local items = workspace:FindFirstChild("Items")
        if not items then return end
        local target = getPullTargetPosition()
        if not target then return end
        isPulling = true
        task.spawn(function()
            local ok, err = pcall(function()
                for _, item in ipairs(items:GetChildren()) do
                    pullSingleItem(item, target)
                    task.wait(0.02)
                end
            end)
            if not ok then warn("Pull error: " .. tostring(err)) end
            isPulling = false
        end)
    end

    -- ===== เปิดหีบ =====
    local openingChests = false

    local function getHRP()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getChests()
        local items = workspace:FindFirstChild("Items")
        if not items then return {} end
        local result = {}
        for _, obj in ipairs(items:GetChildren()) do
            if obj:IsA("Model") and obj.Name:match("Chest") then
                table.insert(result, obj)
            end
        end
        return result
    end

    local function getChestPrompt(chest)
        local main = chest:FindFirstChild("Main")
        local attachment = main and main:FindFirstChild("ProximityAttachment")
        local prompt = attachment and attachment:FindFirstChildWhichIsA("ProximityPrompt")
        if not prompt then
            prompt = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        return prompt
    end

    local function firePrompt(prompt)
        if not prompt or not prompt.Enabled then return false end
        if typeof(fireproximityprompt) == "function" then
            return pcall(fireproximityprompt, prompt, 0, true)
        end
        pcall(function() prompt.HoldDuration = 0 end)
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
        return true
    end

    local function getChestPos(chest)
        if chest:IsA("Model") then
            local part = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
            return chest:GetPivot().Position
        end
        return chest.Position
    end

    local function getFirePos()
        local map = workspace:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
        local mainFire = camp and camp:FindFirstChild("MainFire")
        local fire = mainFire and mainFire:FindFirstChild("Fire")
        -- "Fire" อาจไม่ใช่ BasePart -> ต้องเช็คชนิดก่อนอ่าน Position
        local part = fire and fire:IsA("BasePart") and fire
            or (mainFire and (mainFire.PrimaryPart or mainFire:FindFirstChildWhichIsA("BasePart")))
        return part and part.Position
    end

    local function openAllChests()
        if openingChests then return end

        -- เช็คก่อนเริ่ม: ถ้าทุกกล่องเปิดหมดแล้ว (ไม่เหลือ Proximity) -> ไม่ต้องทำอะไร
        local hasOpenable = false
        for _, chest in ipairs(getChests()) do
            local prompt = getChestPrompt(chest)
            if prompt and prompt.Parent and prompt.Enabled then
                hasOpenable = true
                break
            end
        end
        if not hasOpenable then return end

        openingChests = true
        task.spawn(function()
            local firstHRP = getHRP()
            if not firstHRP then
                openingChests = false
                return
            end
            local wasAnchored = firstHRP.Anchored
            pcall(function() firstHRP.Anchored = true end) -- ล็อคตัว

            -- วนเปิดหีบ จนกว่าเช็คใหม่แล้วจะไม่เหลือ Proximity ไหนเปิดได้
            local attempts = {}
            for pass = 1, 10 do
                local pending = {}
                for _, chest in ipairs(getChests()) do
                    local prompt = getChestPrompt(chest)
                    if prompt and prompt.Parent and prompt.Enabled
                        and (attempts[chest] or 0) < 6 then
                        table.insert(pending, {chest, prompt})
                    end
                end
                if #pending == 0 then break end

                for _, entry in ipairs(pending) do
                    local hrp = getHRP()
                    if not hrp then break end
                    local chest, prompt = entry[1], entry[2]
                    attempts[chest] = (attempts[chest] or 0) + 1

                    local pos = getChestPos(chest)
                    if pos then
                        pcall(function() hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end)
                        task.wait(0.1)
                    end
                    if firePrompt(prompt) then task.wait(0.25) end
                end
            end

            -- ปลดล็อค + วาร์ปกลับกองไฟ
            local endHRP = getHRP()
            if endHRP then
                pcall(function() endHRP.Anchored = wasAnchored end)
                local firePos = getFirePos()
                if firePos then
                    pcall(function() endHRP.CFrame = CFrame.new(firePos + Vector3.new(5, 3, 0)) end)
                end
            end
            openingChests = false
        end)
    end

    local itemDropdown
    local function selectionToList(value)
        if type(value) == "table" then
            local out = {}
            for _, name in ipairs(value) do
                if type(name) == "string" then table.insert(out, name) end
            end
            return out
        end
        if type(value) == "string" then return {value} end
        return {}
    end

    local function refreshItems()
        local names = getAvailableItemNames()
        if #names == 0 then names = {"(ยังไม่มีไอเทม)"} end
        if itemDropdown then
            itemDropdown:Refresh(names)
            for name in pairs(selectedItems) do
                if table.find(names, name) then
                    itemDropdown:Select(name)
                end
            end
        end
    end

    local initialNames = getAvailableItemNames()
    if #initialNames == 0 then initialNames = {"(ยังไม่มีไอเทม)"} end
    selectedItems[initialNames[1]] = true
    itemDropdown = section:Dropdown({
        Title = "เลือกสิ่งของ",
        Values = initialNames,
        Value = {initialNames[1]},
        Multi = true,
        SearchBarEnabled = true,
        AllowNone = false,
        Callback = function(value)
            local list = selectionToList(value)
            if type(value) == "string" and #list == 1 then
                -- กรณี WindUI ส่งค่ามาทีละตัว -> toggle เอาเอง
                local name = list[1]
                if selectedItems[name] then
                    selectedItems[name] = nil
                else
                    selectedItems[name] = true
                end
            else
                selectedItems = {}
                for _, name in ipairs(list) do selectedItems[name] = true end
            end
        end,
    })
    section:Slider({
        Title = "จำนวนชิ้น",
        Value = {Min = 1, Max = 100, Default = maxAmount},
        Step = 1,
        Callback = function(value) maxAmount = math.clamp(value, 1, 100) end,
    })

    local PULL_TARGETS = {
        { Key = "head",  Label = "บนหัวเรา" },
        { Key = "fire",  Label = "บนกองไฟ" },
        { Key = "craft", Label = "โต๊ะคราฟต์" },
    }
    local pullTarget = "head"

    local function getPullTargetPosition()
        if pullTarget == "fire" then
            local firePos = getFirePos()
            if firePos then return firePos + Vector3.new(0, 10, 0) end
        elseif pullTarget == "craft" then
            local map = workspace:FindFirstChild("Map")
            local camp = map and map:FindFirstChild("Campground")
            local craft = camp and camp:FindFirstChild("CraftingBench")
            local zone = craft and craft:FindFirstChild("TouchZone")
            if zone and zone:IsA("BasePart") then return zone.Position end
        end
        local head = getHead()
        return head and head.Position + Vector3.new(0, 3, 0)
    end

    local targetLabels = {}
    for _, t in ipairs(PULL_TARGETS) do table.insert(targetLabels, t.Label) end
    section:Dropdown({
        Title = "จุดดึงของ",
        Values = targetLabels,
        Value = targetLabels[1],
        AllowNone = false,
        Callback = function(value)
            for _, t in ipairs(PULL_TARGETS) do
                if t.Label == value then pullTarget = t.Key end
            end
        end,
    })

    local function action(title, desc, buttonTitle, icon, callback)
        section:Paragraph({Title = title, Desc = desc, Buttons = {{Title = buttonTitle, Icon = icon, Callback = callback}}})
    end
    action("รีเฟรชรายชื่อสิ่งของ", "อัปเดตรายการ Item ที่ดึงได้ (แนะนำเปิดแมพก่อน จะดึงของได้มากขึ้น)", "รีเฟรช", "refresh-cw", refreshItems)
    action("ดึงสิ่งของที่เลือก", "ดึง Item ตามที่เลือก", "ดึง", "download", function()
        if next(selectedItems) then pullSelectedItems() end
    end)
    action("ดึงทุกอย่างที่ดึงได้", "ดึง Item ทั้งหมด (ระวังเครื่องค้าง)", "ดึงทั้งหมด", "download", pullAllItems)

    local chestSection = tab:Section({Title = "เปิดหีบ", Opened = true})
    if chestSection then
        chestSection:Paragraph({
            Title = "เปิดหีบทั้งหมด",
            Desc = "วาร์ปเปิดหีบทุกกล่อง แล้วกลับกองไฟ (ถ้าเปิดหมดแล้ว กดแล้วไม่ทำอะไร)",
            Buttons = {{
                Title = "เปิดหีบทั้งหมด",
                Icon = "lock-open",
                Callback = openAllChests,
            }},
        })
    end
end

return Item
