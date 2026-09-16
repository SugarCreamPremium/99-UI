-- Version 6.15
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

    local function isValidItem(item)
        local items = workspace:FindFirstChild("Items")
        if not item or item.Parent ~= items then return false end
        if not (item:IsA("Model") or item:IsA("BasePart")) then return false end
        if not getItemPosition(item) then return false end
        local interaction = item:GetAttribute("Interaction")
        if interaction ~= "Item" and interaction ~= "Tool" then return false end
        local owner = item:GetAttribute("Owner")
        return not owner or owner == player.UserId
    end

    local function pullSingleItem(item, targetPosition)
        if warpedItems[item] or not isValidItem(item) then return false end
        local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
        local startDrag = events and events:FindFirstChild("RequestStartDraggingItem")
        local stopDrag = events and events:FindFirstChild("StopDraggingItem")
        if not (startDrag and stopDrag) then return false end

        local success = pcall(function()
            startDrag:FireServer(item)
            task.wait(0.1)
            if item:IsA("Model") then
                item:PivotTo(CFrame.new(targetPosition))
            else
                item.CFrame = CFrame.new(targetPosition)
            end
            task.wait(0.1)
            stopDrag:FireServer(item)
        end)
        if success then warpedItems[item] = true end
        return success
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
                    task.wait(0.08)
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
                task.wait(0.08)
                if count >= maxAmount then break end
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
    action("รีเฟรชรายชื่อสิ่งของ", "อัปเดตรายการ Item ที่ดึงได้", "รีเฟรช", "refresh-cw", refreshItems)
    action("ดึงสิ่งของที่เลือก", "ดึง Item ตามรายการที่เลือก", "ดึง", "download", function()
        if selectedItemName ~= "(ยังไม่มีไอเทม)" then pullSpecificItem(selectedItemName) end
    end)
    action("ดึงทุกอย่างที่ดึงได้", "ดึง Item ที่ผ่านการตรวจสอบทั้งหมด", "ดึงทั้งหมด", "download", pullAllItems)
end

return Item

return Item
