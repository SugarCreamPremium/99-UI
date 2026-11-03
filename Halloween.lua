-- Halloween.lua : Sugar Hub UI module (Halloween tab)
-- Single feature: Auto-farm Candy (ported from the AutoCandy block in MainScript.lua)
--
-- How it farms candy:
--   Night : wear a full costume set (4 pieces, same set) -> knock on every HalloweenHouse
--           via RequestKnockOnDoor (no distance check, no cutscene warp) -> claim the promised candy
--           with RequestCollectCandy -> wait until the server consumes the worn set -> next house.
--   Day   : open CostumeBox1 boxes to get costume pieces, and keep collecting dropped pieces.
-- Knocking without a full costume gives a Trick (no candy), so it never knocks without one.

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")

local LOBBY_PLACE_ID = 79546208627805

local M = {}

function M.register(ctx)
    local player = ctx.Player
    local tab = ctx.Tab
    local Client = ctx.Client

    local SLOTS = { "Head", "Torso", "Foot", "Accessory" }
    local COOLDOWN = 3        -- seconds, server cooldown per house after a rejected knock
    local COOLDOWN_MAX = 60   -- rejected houses back off up to this many seconds
    local BOX_GAP = 0.15      -- seconds between opening boxes
    local COSTUME_WAIT = 20   -- server consumes the set ~13s after the knock, so wait longer than that

    local enabled = false
    local runId = 0           -- bumped on every toggle so an old loop stops by itself

    local function notify(text)
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Sugar Hub",
                Text = text,
                Duration = 4,
            })
        end)
    end

    local function farmLoop(myRun)
        local function alive()
            return enabled and runId == myRun
        end

        -- wait for the costume folders (they load later than the character)
        local Costume, Closet, Items
        while alive() and not (Costume and Closet and Items) do
            Costume = player:FindFirstChild("Costume")
            Closet = player:FindFirstChild("CostumeCloset")
            Items = workspace:FindFirstChild("Items")
            if not (Costume and Closet and Items) then task.wait(2) end
        end
        if not alive() then return end

        local Events = Client.Events
        local Wear = Events.RequestWearCostumePieces
        local Store = Events.RequestStoreWornCostumePiece
        local Equip = Events.RequestEquipCostume
        local Open = Events.RequestOpenItemChest
        local KNOCK = Events.RequestKnockOnDoor
        local Collect = Events.RequestCollectCandy

        ------------------------------------------------------------
        -- Costumes
        ------------------------------------------------------------
        -- every piece we own (worn + in the closet), grouped by CostumeId / slot
        local function ownedBySet()
            local owned = {}
            for _, folder in ipairs({ Costume, Closet }) do
                for _, p in ipairs(folder:GetChildren()) do
                    local id, slot = p:GetAttribute("CostumeId"), p:GetAttribute("CostumeSlot")
                    if id and slot then
                        owned[id] = owned[id] or {}
                        owned[id][slot] = owned[id][slot] or p
                    end
                end
            end
            return owned
        end

        -- CostumeId of the full set being worn (4 pieces, 4 slots, same set), or nil
        local function wornSetId()
            local id, n = nil, 0
            local slots = {}
            for _, p in ipairs(Costume:GetChildren()) do
                local pid, slot = p:GetAttribute("CostumeId"), p:GetAttribute("CostumeSlot")
                if pid and slot then
                    n = n + 1
                    slots[slot] = true
                    if id == nil then
                        id = pid
                    elseif id ~= pid then
                        return nil
                    end
                end
            end
            if n ~= 4 then return nil end
            for _, slot in ipairs(SLOTS) do
                if not slots[slot] then return nil end
            end
            return id
        end

        -- true when a full set is worn (wears one from the closet if needed)
        local function ensureCostume()
            if wornSetId() then return true end
            for setId, slots in pairs(ownedBySet()) do
                local set = {}
                for _, slot in ipairs(SLOTS) do
                    if slots[slot] then table.insert(set, slots[slot]) end
                end
                if #set == 4 then
                    -- put pieces of other sets back into the closet first
                    for _, p in ipairs(Costume:GetChildren()) do
                        if p:GetAttribute("CostumeId") ~= setId then
                            pcall(function() Store:InvokeServer(p) end)
                        end
                    end
                    task.wait(0.1)
                    local missing = {}
                    for _, p in ipairs(set) do
                        if p.Parent == Closet then table.insert(missing, p) end
                    end
                    if #missing > 0 then
                        pcall(function() Wear:InvokeServer(missing) end)
                        task.wait(0.6)
                    end
                    if wornSetId() == setId then return true end
                end
            end
            return false
        end

        ------------------------------------------------------------
        -- Costume boxes / dropped pieces
        ------------------------------------------------------------
        local function openBoxes()
            local boxes = {}
            for _, d in ipairs(Items:GetChildren()) do
                if d:GetAttribute("LootTable") == "CostumeBox1" then
                    table.insert(boxes, d)
                end
            end
            if #boxes == 0 then return 0 end
            for _, b in ipairs(boxes) do
                if not alive() then break end
                pcall(function() Open:FireServer(b) end)
                task.wait(BOX_GAP)
            end
            return #boxes
        end

        -- pick up dropped costume pieces (items that throw are skipped)
        local failedDrops = setmetatable({}, { __mode = "k" })
        local function collectDrops()
            for _, d in ipairs(Items:GetChildren()) do
                if not alive() then return end
                if d:GetAttribute("Interaction") == "Costume" and tick() >= (failedDrops[d] or 0) then
                    local ok, res = pcall(function() return Equip:InvokeServer(d) end)
                    if ok and type(res) == "table" and res.Success then
                        if d.Parent then d.Parent = Closet end
                    else
                        failedDrops[d] = tick() + 30
                    end
                    task.wait(0.05)
                end
            end
        end

        ------------------------------------------------------------
        -- Houses
        ------------------------------------------------------------
        local function isKnocker(node)
            if not node:IsA("Model") or not node.PrimaryPart then return false end
            local att = node.PrimaryPart:FindFirstChild("ProximityAttachment")
            if not (att and att:FindFirstChildOfClass("ProximityPrompt")) then return false end
            local blocker = node:FindFirstChild("Blocker")
            if not (blocker and blocker:FindFirstChild("Particle")) then return false end
            return node:FindFirstChild("Door") ~= nil
        end

        local function findKnocker(node, depth, seen)
            depth, seen = depth or 0, seen or {}
            if depth > 6 or seen[node] then return nil end
            seen[node] = true
            if isKnocker(node) then return node end
            for _, child in pairs(node:GetChildren()) do
                local f = findKnocker(child, depth + 1, seen)
                if f then return f end
            end
            return nil
        end

        local knockerCache = setmetatable({}, { __mode = "k" })
        local nextKnock = setmetatable({}, { __mode = "k" })
        local rejects = setmetatable({}, { __mode = "k" })
        local lastKnockSet, lastKnockAt = nil, 0
        local stripTime = 0   -- measured time the server takes to remove the set

        -- the server removes the worn set when the cutscene ends, not when it answers;
        -- wait until it is gone, otherwise the next tick would knock again with a dead set
        local function waitCostumeConsumed(setId)
            local t0 = tick()
            local limit = math.max(COSTUME_WAIT, stripTime * 2)
            while alive() and wornSetId() == setId and tick() - t0 < limit do
                task.wait(0.1)
            end
            if wornSetId() ~= setId then stripTime = tick() - t0 end
        end

        local function knockHouses()
            local setId = wornSetId()
            if not setId then return false end
            if lastKnockSet == setId then
                if tick() - lastKnockAt < COSTUME_WAIT then return false end
                lastKnockSet = nil -- stuck for too long: release so we do not stop forever
            end

            local now = tick()
            for _, house in ipairs(CollectionService:GetTagged("HalloweenHouse")) do
                if not alive() then return false end
                if now >= (nextKnock[house] or 0)
                    and not house:GetAttribute("Visited_" .. player.UserId) then
                    local kn = knockerCache[house]
                    if not (kn and kn.Parent) then
                        kn = findKnocker(house)
                        knockerCache[house] = kn
                    end
                    if kn then
                        local idNow = wornSetId()
                        if not idNow or idNow == lastKnockSet then return false end

                        local ok, res = pcall(function() return KNOCK:InvokeServer(kn) end)
                        if ok and type(res) == "table" and res.Success then
                            rejects[house] = nil
                            if (res.Candy or 0) > 0 then
                                -- the allowance is set when the knock answers, claim it right away
                                pcall(function() Collect:FireServer(999, "TrickOrTreating") end)
                            end
                            lastKnockSet, lastKnockAt = idNow, tick()
                            waitCostumeConsumed(idNow)
                            if wornSetId() ~= idNow then lastKnockSet = nil end
                            nextKnock[house] = tick() + 120 -- used, next round later
                        else
                            -- rejected: back off 3, 6, 12 ... up to 60 seconds per house
                            local n = (rejects[house] or 0) + 1
                            rejects[house] = n
                            nextKnock[house] = tick() + math.min(COOLDOWN * 2 ^ (n - 1), COOLDOWN_MAX)
                        end
                        return true
                    end
                end
            end
            return false
        end

        ------------------------------------------------------------
        -- Main loop
        ------------------------------------------------------------
        task.wait(1)
        while alive() do
            local ok = pcall(function()
                local night = workspace:GetAttribute("State") == "Night"

                collectDrops()

                if not night then
                    -- day: open boxes to get costume pieces
                    if openBoxes() == 0 then task.wait(3) end
                else
                    if ensureCostume() then
                        if not knockHouses() then task.wait(1) end
                    else
                        -- no full set: never knock (it would be a Trick), try boxes instead
                        if openBoxes() == 0 then task.wait(3) end
                    end
                end
            end)
            if not ok then task.wait(3) end
        end
    end

    local section = tab:Section({ Title = "ฮาโลวีน", Opened = true })
    section:Toggle({
        Title = "ฟาร์มแคนดี้อัตโนมัติ",
        Desc = "กลางวันเปิดกล่องชุด กลางคืนใส่ชุดครบเซ็ตแล้วเคาะประตูทุกบ้านเพื่อเก็บแคนดี้ (ใช้ได้เฉพาะในแมพฟาร์ม)",
        Value = false,
        Callback = function(state)
            runId = runId + 1
            enabled = state == true
            if not enabled then return end

            if game.PlaceId == LOBBY_PLACE_ID then
                notify("ฟาร์มแคนดี้ใช้ได้เฉพาะในแมพฟาร์ม")
                enabled = false
                return
            end

            local myRun = runId
            task.spawn(function()
                local ok, err = pcall(farmLoop, myRun)
                if not ok then
                    warn("Error : [Halloween] auto candy crashed: " .. tostring(err) .. " / toggle it off and on to restart")
                end
            end)
        end,
    })
end

return M
