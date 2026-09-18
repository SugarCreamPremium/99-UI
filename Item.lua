-- Version 9.49
local Item = {}

function Item.register(context)
    local tab = context.Tab
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:Section({Title = "ดึงสิ่งของ", Opened = true})
    if not section then return end

    local maxAmount = 10
    local selectedItemName
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

    local function pullSpecificItem(nameToPull)
        if isPulling or not nameToPull then return end
        local head = getHead()
        local items = workspace:FindFirstChild("Items")
        if not head or not items then return end
        isPulling = true
        task.spawn(function()
            local count = 0
            local targetPosition = head.Position + Vector3.new(0, 3, 0)
            for _, item in ipairs(items:GetChildren()) do
                if item.Name == nameToPull and pullSingleItem(item, targetPosition) then
                    count = count + 1
                    task.wait(0.02)
                    if count >= maxAmount then break end
                end
            end
            isPulling = false
        end)
    end

    local function pullAllItems()
        if isPulling then return end
        local head = getHead()
        local items = workspace:FindFirstChild("Items")
        if not head or not items then return end
        isPulling = true
        task.spawn(function()
            local count = 0
            local targetPosition = head.Position + Vector3.new(0, 3, 0)
            for _, item in ipairs(items:GetChildren()) do
                if pullSingleItem(item, targetPosition) then count = count + 1 end
                task.wait(0.02)
            end
            isPulling = false
        end)
    end

    local itemDropdown
    local function refreshItems()
        local names = getAvailableItemNames()
        if #names == 0 then names = {"(ยังไม่มีไอเทม)"} end
        selectedItemName = names[1]
        if itemDropdown then
            itemDropdown:Refresh(names)
            itemDropdown:Select(selectedItemName)
        end
    end

    local initialNames = getAvailableItemNames()
    if #initialNames == 0 then initialNames = {"(ยังไม่มีไอเทม)"} end
    selectedItemName = initialNames[1]
    itemDropdown = section:Dropdown({
        Title = "เลือกสิ่งของ",
        Values = initialNames,
        Value = selectedItemName,
        SearchBarEnabled = true,
        AllowNone = false,
        Callback = function(value) selectedItemName = value end,
    })
    section:Slider({
        Title = "จำนวนชิ้น",
        Value = {Min = 1, Max = 100, Default = maxAmount},
        Step = 1,
        Callback = function(value) maxAmount = math.clamp(value, 1, 100) end,
    })
    local function action(title, desc, buttonTitle, icon, callback)
        section:Paragraph({Title = title, Desc = desc, Buttons = {{Title = buttonTitle, Icon = icon, Callback = callback}}})
    end
    action("รีเฟรชรายชื่อสิ่งของ", "อัปเดตรายการ Item ที่ดึงได้ (แนะนำเปิดแมพก่อน จะดึงของได้มากขึ้น)", "รีเฟรช", "refresh-cw", refreshItems)
    action("ดึงสิ่งของที่เลือก", "ดึง Item ตามรายการที่เลือก", "ดึง", "download", function()
        if selectedItemName ~= "(ยังไม่มีไอเทม)" then pullSpecificItem(selectedItemName) end
    end)
    action("ดึงทุกอย่างที่ดึงได้", "ดึง Item ทั้งหมด (ระวังเครื่องค้าง)", "ดึงทั้งหมด", "download", pullAllItems)
end

return Item
