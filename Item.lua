-- Version 9.27
local Item = {}

function Item.register(context)
    local tab = context.Tab
    local player = context.Player
    local ReplicatedStorage = context.ReplicatedStorage
    if not tab then return end

    local section = tab:CreateSection("ดึงสิ่งของ (Item Teleport)")

    local maxAmount = 10
    local selectedItemName = nil
    local isPulling = false

    local function getHead()
        local char = player.Character
        return char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    end

    local function pullSingleItem(item, targetPos)
        if not item or not item.Parent then return false end
        return pcall(function()
            local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
            if not events then return end
            local StartDrag = events:FindFirstChild("RequestStartDraggingItem")
            local StopDrag = events:FindFirstChild("StopDraggingItem")
            if not (StartDrag and StopDrag) then return end

            StartDrag:FireServer(item)
            task.wait(0.05)

            if item:IsA("Model") then
                item:PivotTo(CFrame.new(targetPos))
            else
                item.CFrame = CFrame.new(targetPos)
            end

            task.wait(0.05)
            StopDrag:FireServer(item)
        end)
    end

    local function getAvailableItemNames()
        local itemsFolder = workspace:FindFirstChild("Items")
        if not itemsFolder then return {} end

        local set = {}
        for _, item in ipairs(itemsFolder:GetChildren()) do
            local name = item.Name
            if name and name ~= "" and not set[name] then
                set[name] = true
            end
        end

        local list = {}
        for name in pairs(set) do
            table.insert(list, name)
        end
        table.sort(list)
        return list
    end

    local dropdownFrame = nil
    local itemContainer = nil
    local dropdownTitle = nil

    local function updateDropdownOptions(names)
        if not itemContainer then return end

        for _, child in ipairs(itemContainer:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        for _, itemName in ipairs(names) do
            local itemBtn = Instance.new("TextButton")
            itemBtn.Name = itemName
            itemBtn.Size = UDim2.new(1, 0, 0, 32)
            itemBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            itemBtn.Font = Enum.Font.Gotham
            itemBtn.Text = itemName
            itemBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
            itemBtn.TextSize = 13
            itemBtn.AutoButtonColor = true
            itemBtn.Parent = itemContainer

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = itemBtn

            itemBtn.MouseButton1Click:Connect(function()
                selectedItemName = itemName
                if dropdownTitle then
                    dropdownTitle.Text = "เลือกสิ่งของ : " .. itemName
                end
                if dropdownFrame then
                    local header = dropdownFrame:FindFirstChild("DropdownHeader") or dropdownFrame:FindFirstChildWhichIsA("TextButton")
                    local arrow = header and header:FindFirstChild("ArrowIcon")
                    if arrow then arrow.Rotation = 0 end
                    dropdownFrame:TweenSize(UDim2.new(1, 0, 0, 42), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.25, true)
                end
            end)
        end
    end

    local function pullSpecificItem(nameToPull)
        if isPulling or not nameToPull then return end
        local head = getHead()
        local itemsFolder = workspace:FindFirstChild("Items")
        if not head or not itemsFolder then return end

        isPulling = true
        task.spawn(function()
            local count = 0
            local targetPos = head.Position + Vector3.new(0, 3, 0)
            for _, item in ipairs(itemsFolder:GetChildren()) do
                if item.Name == nameToPull then
                    pullSingleItem(item, targetPos)
                    count = count + 1
                    task.wait(0.08)
                    if count >= maxAmount then
                        break
                    end
                end
            end
            isPulling = false
        end)
    end

    local function pullAllItems()
        if isPulling then return end
        local head = getHead()
        local itemsFolder = workspace:FindFirstChild("Items")
        if not head or not itemsFolder then return end

        isPulling = true
        task.spawn(function()
            local count = 0
            local targetPos = head.Position + Vector3.new(0, 3, 0)
            for _, item in ipairs(itemsFolder:GetChildren()) do
                pullSingleItem(item, targetPos)
                count = count + 1
                task.wait(0.08)
                if count >= maxAmount then
                    break
                end
            end
            isPulling = false
        end)
    end

    local initialList = getAvailableItemNames()
    if #initialList == 0 then
        initialList = {"(ยังไม่มีไอเทม)"}
    end

    tab:CreateDropdown("เลือกสิ่งของ", initialList, function(val)
        selectedItemName = val
    end)

    local pageContainer = rawget(section, "PageContainer") or (tab and rawget(tab, "PageContainer"))
    if pageContainer then
        for _, child in ipairs(pageContainer:GetChildren()) do
            local container = child:FindFirstChild("ItemContainer")
            if container then
                dropdownFrame = child
                itemContainer = container
                local header = child:FindFirstChild("DropdownHeader") or child:FindFirstChildWhichIsA("TextButton")
                dropdownTitle = header and (header:FindFirstChild("Title") or header:FindFirstChildWhichIsA("TextLabel"))
            end
        end
    end

    tab:CreateSlider("จำนวนชิ้นสูงสุด (1 - 100)", 1, 100, 10, function(value)
        maxAmount = math.clamp(value, 1, 100)
    end)

    local sectionFrame = rawget(section, "PageContainer")
    local slider = sectionFrame and sectionFrame.Parent:FindFirstChild("Slider")
    if slider then
        slider.Parent = sectionFrame
    end

    tab:CreateButton("รีเฟรชรายชื่อสิ่งของ", function()
        local currentList = getAvailableItemNames()
        updateDropdownOptions(currentList)
    end)

    tab:CreateButton("ดึงสิ่งของที่เลือก", function()
        if selectedItemName and selectedItemName ~= "(ยังไม่มีไอเทม)" then
            pullSpecificItem(selectedItemName)
        end
    end)

    tab:CreateButton("ดึงทุกอย่างที่ดึงได้", function()
        pullAllItems()
    end)
end

return Item
