-- Scroll Transmog for AzerothCore 3.3.5a / mod-ale.
-- Based on the portable transmog technique: server-side DB + PLAYER_VISIBLE_ITEM.
-- No custom Item update field and no client patch are required.

local C = {
    -- Set to true to print debug lines to the server console and send
    -- debug broadcasts to players. GMs can also toggle it in game with
    -- the chat command: transmog debug
    DEBUG = false,
    -- Warmane/client-known entries. These entries already have client icons.
    DECEPTION = 23885,
    ILLUSION = 35517,
    PURIFICATION = 24315,
    ESSENCE = 38567,
    LEGENDARY_ESSENCE = 38567,
    -- Offset added to the source item entry to derive a unique named
    -- essence entry (e.g. 200000 + 49623 = 249623 → "Essence of Shadowmourne").
    -- Must match the formula in sql/05_world_essence_names.sql.
    ESSENCE_ENTRY_OFFSET = 200000,
    LEGENDARY = 5,
    SESSION_TIMEOUT = 120,
    -- WotLK PLAYER_VISIBLE_ITEM_1_ENTRYID and two uint32 fields per slot.
    VISIBLE_ITEM_1_ENTRY = 283,
    VISIBLE_ITEM_STRIDE = 2,
    BAG_0 = 255,
    EQUIPMENT_END = 19,
    BAG_START = 19,
    BAG_END = 23,
    ITEM_START = 23,
    ITEM_END = 39,

    -- How scrolls are rewarded from raid bosses:
    --   "loot"   scrolls appear in the boss loot window for the whole raid.
    --            Handled by creature_loot_template; run sql/03_world_boss_loot.sql
    --            and adjust its chance variables. The onKill hook stays inactive.
    --   "onkill" this script gives the scroll directly (and only) to the player
    --            who lands the killing blow, using the chances below.
    --   "off"    no boss rewards at all (hand out scrolls via vendor/quest/etc).
    DROP_MODE = "loot",
    -- Chances used only in "onkill" mode (0.08 = 8%, 0.01 = 1%).
    NORMAL_CHANCE = 0.08,
    LEGENDARY_CHANCE = 0.01,
    -- Raid maps and boss entries used only in "onkill" mode.
    -- If BOSS_ENTRIES is empty (default), it will be auto-populated from
    -- the world DB at startup: all rank-3 creatures in RAID_MAPS plus
    -- their difficulty_entry_1/2/3 variants (10H/25N/25H).
    RAID_MAPS = { [249] = true, [533] = true, [615] = true, [616] = true, [603] = true, [649] = true, [631] = true, [724] = true },
    BOSS_ENTRIES = {
        -- Leave empty for auto-population, or manually add entries:
        -- [28860] = true, -- Sartharion 10N
        -- [30449] = true, -- Vesperon
    },
}

local sessions, fakeByPlayer, ownerByItem = {}, {}, {}

local function isEssence(entry)
    return entry == C.ESSENCE or entry == C.LEGENDARY_ESSENCE
end

local function debugLog(text)
    if not C.DEBUG then return end
    print("[ScrollTransmog DEBUG] " .. tostring(text))
end

local function debugSay(player, text)
    if not C.DEBUG then return end
    player:SendBroadcastMessage("[Transmog DEBUG] " .. text)
end

local function pid(player) return player:GetGUIDLow() end
local function iid(item) return item and item:GetGUIDLow() or 0 end
local function itemEntry(item) return item and item:GetEntry() or 0 end
local function visibleField(slot) return C.VISIBLE_ITEM_1_ENTRY + slot * C.VISIBLE_ITEM_STRIDE end
local function say(player, text) player:SendBroadcastMessage("[Transmog] " .. text) end
local function close(player) player:GossipComplete() end

local function blocked(player)
    return not player or player:IsDead() or player:IsInCombat() or (player.IsInTrade and player:IsInTrade())
end

local function owned(player, item)
    return item and item:GetOwnerGUID() == player:GetGUID() and not item:IsInTrade()
end

local function eligible(player, item)
    if not item then
        debugLog("eligible=false reason=item_nil")
        return false
    end
    local isOwned = owned(player, item)
    local soulbound = item:IsSoulBound()
    local canUse = player:CanUseItem(item)
    debugLog(string.format("eligible item=%d owner=%s soulbound=%s canUse=%s", iid(item), tostring(isOwned), tostring(soulbound), tostring(canUse)))
    return isOwned and soulbound and canUse
end

local function category(item)
    local class, sub, inv = item:GetClass(), item:GetSubClass(), item:GetInventoryType()
    if class == 4 then
        if inv >= 1 and inv <= 12 then return "armor:" .. inv end
        if inv == 16 or inv == 18 or inv == 20 then return "armor:" .. inv end
        return nil
    end
    if class ~= 2 then return nil end
    if sub == 0 or sub == 4 or sub == 7 then return inv == 17 and "2h" or "1h" end
    if sub == 1 or sub == 5 or sub == 8 then return "2h" end
    if sub == 2 or sub == 3 or sub == 18 then return "ranged" end
    if sub == 6 or sub == 10 then return "staff" end
    if sub == 20 then return "polearm" end
    if sub == 13 then return "fist" end
    if sub == 15 then return "dagger" end
    if sub == 19 then return "wand" end
    if sub == 14 and inv == 14 then return "shield" end
    return nil
end

local function categoryValues(class, sub, inv)
    if class == 4 then
        if inv >= 1 and inv <= 12 or inv == 16 or inv == 18 or inv == 20 then return "armor:" .. inv end
        return nil
    end
    if class ~= 2 then return nil end
    if sub == 0 or sub == 4 or sub == 7 then return inv == 17 and "2h" or "1h" end
    if sub == 1 or sub == 5 or sub == 8 then return "2h" end
    if sub == 2 or sub == 3 or sub == 18 then return "ranged" end
    if sub == 6 or sub == 10 then return "staff" end
    if sub == 20 then return "polearm" end
    if sub == 13 then return "fist" end
    if sub == 15 then return "dagger" end
    if sub == 19 then return "wand" end
    if sub == 14 and inv == 14 then return "shield" end
    return nil
end

local function compatible(source, target)
    local a, b = category(source), category(target)
    if not a or not b then return false end
    if a:sub(1, 6) == "armor:" or b:sub(1, 6) == "armor:" then return a == b end
    if a == b then return true end
    return (a == "ranged" and b == "ranged") or (a == "staff" and b == "polearm") or (a == "polearm" and b == "staff")
end

local function compatibleCategory(sourceCategory, target)
    local b = category(target)
    if not sourceCategory or not b then return false end
    if sourceCategory:sub(1, 6) == "armor:" or b:sub(1, 6) == "armor:" then return sourceCategory == b end
    if sourceCategory == b then return true end
    return (sourceCategory == "ranged" and b == "ranged") or (sourceCategory == "staff" and b == "polearm") or (sourceCategory == "polearm" and b == "staff")
end

local function equipped(player)
    local result = {}
    for slot = 0, C.EQUIPMENT_END - 1 do
        local item = player:GetItemByPos(C.BAG_0, slot)
        if item then result[#result + 1] = item end
    end
    return result
end

local function inventory(player)
    local result = {}
    for slot = C.ITEM_START, C.ITEM_END - 1 do
        local item = player:GetItemByPos(C.BAG_0, slot)
        if item then result[#result + 1] = item end
    end
    for bag = C.BAG_START, C.BAG_END - 1 do
        local bagItem = player:GetItemByPos(C.BAG_0, bag)
        if bagItem then
            for slot = 0, bagItem:GetBagSize() - 1 do
                local item = player:GetItemByPos(bag, slot)
                if item then result[#result + 1] = item end
            end
        end
    end
    return result
end

local function allItems(player)
    local result = equipped(player)
    for _, item in ipairs(inventory(player)) do result[#result + 1] = item end
    return result
end

local function findItem(player, wanted)
    for _, item in ipairs(allItems(player)) do
        if iid(item) == wanted then return item end
    end
end

local function findEntry(player, wanted)
    for _, item in ipairs(allItems(player)) do
        if itemEntry(item) == wanted then return item end
    end
end

local function add(player, text, sender, action)
    player:GossipMenuAddItem(0, text, sender, action)
end

local function menu(player, title)
    player:GossipClearMenu()
    add(player, title, 0, 0)
end

local function fakeEntry(item)
    local p = ownerByItem[iid(item)]
    return p and fakeByPlayer[p] and fakeByPlayer[p][iid(item)] or nil
end

local function setFake(item, appearance)
    local player = item:GetOwner()
    if not player then return false end
    local p, i = pid(player), iid(item)
    fakeByPlayer[p] = fakeByPlayer[p] or {}
    fakeByPlayer[p][i], ownerByItem[i] = appearance, p
    player:UpdateUInt32Value(visibleField(item:GetSlot()), appearance)
    CharDBExecute(string.format("REPLACE INTO custom_transmogrification (GUID, FakeEntry, Owner) VALUES (%d, %d, %d)", i, appearance, p))
    return true
end

local function clearFake(item)
    local player = item:GetOwner()
    local p, i = pid(player), iid(item)
    if fakeByPlayer[p] then fakeByPlayer[p][i] = nil end
    ownerByItem[i] = nil
    player:UpdateUInt32Value(visibleField(item:GetSlot()), itemEntry(item))
    CharDBExecute("DELETE FROM custom_transmogrification WHERE GUID=" .. i)
end

local function loadPlayer(player)
    local p = pid(player)
    fakeByPlayer[p] = {}
    local rows = CharDBQuery("SELECT GUID,FakeEntry FROM custom_transmogrification WHERE Owner=" .. p)
    if not rows then return end
    repeat
        local itemGuid, appearance = rows:GetUInt32(0), rows:GetUInt32(1)
        fakeByPlayer[p][itemGuid], ownerByItem[itemGuid] = appearance, p
    until not rows:NextRow()
    for _, item in ipairs(equipped(player)) do
        local appearance = fakeByPlayer[p][iid(item)]
        if appearance then player:UpdateUInt32Value(visibleField(item:GetSlot()), appearance) end
    end
end

local function showRoot(player, scroll)
    local s = { scroll = scroll, step = "root", time = os.time() }
    sessions[pid(player)] = s
    menu(player, "Scroll Transmog")
    if scroll == C.PURIFICATION then
        s.step = "purify"
        for _, item in ipairs(equipped(player)) do
            if fakeEntry(item) then add(player, "Remove appearance from " .. item:GetName(), 3, iid(item)) end
        end
    else
        add(player, "Extract appearance into Essence", 1, 0)
        add(player, "Apply Essence to equipped item", 2, 0)
    end
    add(player, "Cancel", 9, 0)
    player:GossipSendMenu(1, player, 0)
end

local function consume(player, item)
    player:RemoveItem(item, 1)
end

local function extract(player, scroll, target)
    debugLog(string.format("extract player=%d scroll=%d target=%s", pid(player), scroll, target and tostring(itemEntry(target)) or "nil"))
    if not target or not eligible(player, target) or not category(target) then
        say(player, "Target must be an equipped or inventory Soulbound armor or weapon.")
        return false
    end
    local quality = target:GetQuality()
    if scroll == C.ILLUSION and quality ~= C.LEGENDARY then
        say(player, "Scroll of Illusion requires a Legendary item.")
        return false
    end
    if scroll == C.DECEPTION and quality == C.LEGENDARY then
        say(player, "Use Scroll of Illusion for Legendary items.")
        return false
    end
    local essenceEntry = C.ESSENCE
    local essence = player:AddItem(essenceEntry, 1)
    if not essence then
        debugLog("extract failed reason=AddItem returned nil entry=" .. essenceEntry)
        say(player, "Essence item cannot be stored. Check MaxCount and inventory space.")
        return false
    end
    CharDBExecute(string.format("REPLACE INTO essence_tracking (essence_item_id, original_item_name, owner_guid, appearance_entry, source_class, source_subclass, source_inventory_type) VALUES (%d,'%s',%d,%d,%d,%d,%d)", iid(essence), target:GetName():gsub("'", "''"), pid(player), itemEntry(target), target:GetClass(), target:GetSubClass(), target:GetInventoryType()))
    consume(player, scroll)
    debugLog(string.format("extract success source=%d essence=%d essenceGuid=%d", itemEntry(target), essenceEntry, iid(essence)))
    say(player, "Appearance of |cff1eff00" .. target:GetName() .. "|r extracted into an Essence. Use the Essence on a compatible item to apply it.")
    return true
end

local function applyEssence(player, essence, target)
    debugLog(string.format("apply player=%d essence=%s target=%s", pid(player), essence and tostring(itemEntry(essence)) or "nil", target and tostring(itemEntry(target)) or "nil"))
    local metadata = CharDBQuery("SELECT appearance_entry,source_class,source_subclass,source_inventory_type FROM essence_tracking WHERE essence_item_id=" .. iid(essence) .. " AND owner_guid=" .. pid(player) .. " ORDER BY id DESC LIMIT 1")
    local appearance = metadata and metadata:GetUInt32(0) or 0
    local sourceCategory = metadata and categoryValues(metadata:GetUInt32(1), metadata:GetUInt32(2), metadata:GetUInt32(3)) or nil
    if target and appearance ~= 0 and itemEntry(target) == appearance then
        say(player, "Choose a different target item.")
        return false
    end
    if not essence then
        say(player, "Essence item not found.")
        return false
    end
    if not target or not eligible(player, target) or not compatibleCategory(sourceCategory, target) then
        say(player, "The target item is not compatible.")
        return false
    end
    if appearance == 0 or not setFake(target, appearance) then say(player, "This Essence has no valid appearance."); return false end
    CharDBExecute("DELETE FROM essence_tracking WHERE essence_item_id=" .. iid(essence))
    consume(player, essence)
    say(player, "Appearance applied successfully.")
    return true
end

local function purify(player, scroll, target)
    debugLog(string.format("purify player=%d scroll=%s target=%s", pid(player), scroll and tostring(itemEntry(scroll)) or "nil", target and tostring(itemEntry(target)) or "nil"))
    if not target or not fakeEntry(target) then say(player, "That item has no active transmogrification."); return false end
    clearFake(target)
    consume(player, scroll)
    say(player, "Appearance removed successfully.")
    return true
end

-- Returns the name of the item whose appearance is stored in this Essence.
local function essenceInfo(player, essence)
    local rows = CharDBQuery("SELECT original_item_name FROM essence_tracking WHERE essence_item_id=" .. iid(essence) .. " AND owner_guid=" .. pid(player) .. " ORDER BY id DESC LIMIT 1")
    return rows and rows:GetString(0) or nil
end

-- Stock mod-ale exposes item use as RegisterItemEvent(entry, ITEM_EVENT_ON_USE, fn).
-- The fourth argument is the item selected as the use target.
local function itemUse(event, player, item, target)
    debugLog(string.format("OnUse event=%s player=%s item=%s itemGuid=%s target=%s targetGuid=%s", tostring(event), player and tostring(pid(player)) or "nil", item and tostring(itemEntry(item)) or "nil", item and tostring(iid(item)) or "nil", target and tostring(itemEntry(target)) or "nil", target and tostring(iid(target)) or "nil"))
    debugSay(player, string.format("ItemUse item=%s target=%s", item and tostring(itemEntry(item)) or "nil", target and tostring(itemEntry(target)) or "nil"))
    if blocked(player) then say(player, "You cannot use this while dead, in combat, or trading."); return false end
    local e = itemEntry(item)
    if e == C.DECEPTION or e == C.ILLUSION then
        if target then
            debugLog("deception/illusion received target immediately")
            extract(player, e, target)
        else
            sessions[pid(player)] = { mode = "extract", scroll = e, scrollGuid = iid(item), time = os.time() }
            debugLog("deception/illusion target=nil; session armed, waiting for a second item-use event")
            say(player, "Select an equipped or inventory item to extract its appearance.")
        end
        return false
    end
    if e == C.PURIFICATION then
        if target then
            debugLog("purification received target immediately")
            purify(player, item, target)
        else
            sessions[pid(player)] = { mode = "purify", scrollGuid = iid(item), time = os.time() }
            debugLog("purification target=nil; session armed, waiting for a second item-use event")
            say(player, "Select an equipped item to purify.")
        end
        return false
    end
    if isEssence(e) then
        local sourceName = essenceInfo(player, item)
        if sourceName then say(player, "This Essence holds the appearance of: |cff1eff00" .. sourceName .. "|r.") end
        if target then
            debugLog("essence received target immediately")
            applyEssence(player, item, target)
        else
            sessions[pid(player)] = { mode = "apply", essenceGuid = iid(item), time = os.time() }
            debugLog("essence target=nil; session armed, waiting for a second item-use event")
            if sourceName then
                say(player, "Select a compatible equipped item to apply the appearance of |cff1eff00" .. sourceName .. "|r.")
            else
                say(player, "Select a compatible equipped item to receive this appearance.")
            end
        end
        return false
    end
    return true
end

local function hello(event, player, item)
    if blocked(player) then say(player, "You cannot use this while dead, in combat, or trading."); return false end
    showRoot(player, itemEntry(item))
    return false
end

local function extractMenu(player, s)
    s.step = "extract"
    menu(player, "Extract from equipped BoP item")
    for _, item in ipairs(equipped(player)) do
        local q = item:GetQuality()
        if eligible(player, item) and category(item) and ((s.scroll == C.ILLUSION and q == C.LEGENDARY) or (s.scroll == C.DECEPTION and q ~= C.LEGENDARY)) then
            add(player, item:GetItemLink(player:GetDbcLocale()), 4, iid(item))
        end
    end
    add(player, "Back", 8, 0); player:GossipSendMenu(1, player, 0)
end

local function essenceMenu(player, s)
    s.step = "essence"
    menu(player, "Choose Essence")
    for _, item in ipairs(inventory(player)) do
        if isEssence(itemEntry(item)) then
            local sourceName = essenceInfo(player, item)
            if sourceName then
                add(player, "Essence [" .. sourceName .. "]", 5, iid(item))
            else
                add(player, item:GetItemLink(player:GetDbcLocale()), 5, iid(item))
            end
        end
    end
    add(player, "Back", 8, 0); player:GossipSendMenu(1, player, 0)
end

local function targetMenu(player, s)
    s.step = "target"
    local essence = findItem(player, s.essenceGuid)
    if not essence then close(player); return end
    -- Look up the source item's category from essence_tracking (the essence
    -- itself is a Trade Good so category(essence) would return nil).
    local row = CharDBQuery("SELECT appearance_entry,source_class,source_subclass,source_inventory_type FROM essence_tracking WHERE essence_item_id=" .. iid(essence) .. " AND owner_guid=" .. pid(player) .. " ORDER BY id DESC LIMIT 1")
    local sourceCategory = row and categoryValues(row:GetUInt32(1), row:GetUInt32(2), row:GetUInt32(3)) or nil
    local appearance = row and row:GetUInt32(0) or 0
    menu(player, "Apply appearance to equipped item")
    for _, item in ipairs(equipped(player)) do
        if item ~= essence and eligible(player, item) and compatibleCategory(sourceCategory, item) and itemEntry(item) ~= appearance then
            add(player, item:GetItemLink(player:GetDbcLocale()), 6, iid(item))
        end
    end
    add(player, "Back", 8, 0); player:GossipSendMenu(1, player, 0)
end

local function select(event, player, item, sender, action)
    local s = sessions[pid(player)]
    if not s or blocked(player) or os.time() - s.time > C.SESSION_TIMEOUT then sessions[pid(player)] = nil; close(player); return true end
    if sender == 9 then sessions[pid(player)] = nil; close(player); return true end
    if sender == 8 then showRoot(player, s.scroll); return true end
    if sender == 1 then extractMenu(player, s); return true end
    if sender == 2 then essenceMenu(player, s); return true end
    if sender == 3 then
        local target = findItem(player, action)
        if target and fakeEntry(target) then clearFake(target); player:RemoveItem(item, 1); say(player, "Appearance removed.") end
        sessions[pid(player)] = nil; close(player); return true
    end
    if sender == 4 then
        local source = findItem(player, action)
        if not source or not eligible(player, source) then close(player); return true end
        local out = C.ESSENCE
        local essence = player:AddItem(out, 1)
        if not essence then say(player, "Inventory is full."); close(player); return true end
        CharDBExecute(string.format("REPLACE INTO essence_tracking (essence_item_id, original_item_name, owner_guid, appearance_entry) VALUES (%d,'%s',%d,%d)", iid(essence), source:GetName():gsub("'", "''"), pid(player), itemEntry(source)))
        player:RemoveItem(item, 1); say(player, "Appearance extracted into an Essence.")
        sessions[pid(player)] = nil; close(player); return true
    end
    if sender == 5 then
        local essence = findItem(player, action)
        if essence and isEssence(itemEntry(essence)) then s.essenceGuid = action; targetMenu(player, s) end
        return true
    end
    if sender == 6 then
        local target, essence = findItem(player, action), findItem(player, s.essenceGuid)
        if not target or not essence or not eligible(player, target) then close(player); return true end
        local row = CharDBQuery("SELECT appearance_entry,source_class,source_subclass,source_inventory_type FROM essence_tracking WHERE essence_item_id=" .. iid(essence) .. " AND owner_guid=" .. pid(player) .. " ORDER BY id DESC LIMIT 1")
        local appearance = row and row:GetUInt32(0) or 0
        local sourceCategory = row and categoryValues(row:GetUInt32(1), row:GetUInt32(2), row:GetUInt32(3)) or nil
        if appearance == 0 or not compatibleCategory(sourceCategory, target) or not setFake(target, appearance) then close(player); return true end
        CharDBExecute("DELETE FROM essence_tracking WHERE essence_item_id=" .. iid(essence))
        player:RemoveItem(essence, 1); player:RemoveItem(item, 1); say(player, "Appearance applied.")
        sessions[pid(player)] = nil; close(player); return true
    end
    return true
end

local function onLogin(event, player)
    loadPlayer(player)
    debugSay(player, "scroll_transmog.lua loaded and login hook active")
end
local function onLogout(event, player) sessions[pid(player)] = nil; fakeByPlayer[pid(player)] = nil end
local function onEquip(event, player, item, bag, slot)
    debugLog(string.format("OnEquip player=%d item=%s itemGuid=%s bag=%s slot=%s", pid(player), tostring(itemEntry(item)), tostring(iid(item)), tostring(bag), tostring(slot)))
    local appearance = fakeEntry(item)
    if appearance then player:UpdateUInt32Value(visibleField(slot), appearance) end
end

-- Direct-reward mode: only the player who lands the killing blow receives
-- a scroll. Active only when C.DROP_MODE = "onkill"; in "loot" mode the
-- creature_loot_template rows from sql/03_world_boss_loot.sql are used instead.
local function onKill(event, killer, killed)
    if not killed or not C.RAID_MAPS[killed:GetMapId()] or not C.BOSS_ENTRIES[killed:GetEntry()] then return end
    if math.random() <= C.LEGENDARY_CHANCE then killer:AddItem(C.ILLUSION, 1)
    elseif math.random() <= C.NORMAL_CHANCE then killer:AddItem(C.DECEPTION, 1) end
end

-- GM chat command: "transmog debug" toggles debug output at runtime.
local function onChat(event, player, msg)
    if msg ~= "transmog debug" then return end
    if player:GetGMRank() < 3 then return end
    C.DEBUG = not C.DEBUG
    say(player, "Debug output " .. (C.DEBUG and "enabled" or "disabled") .. ".")
    return false
end

CharDBQuery([[CREATE TABLE IF NOT EXISTS custom_transmogrification (GUID INT UNSIGNED NOT NULL, FakeEntry INT UNSIGNED NOT NULL, Owner INT UNSIGNED NOT NULL, PRIMARY KEY (GUID)) ENGINE=InnoDB]])
CharDBQuery([[CREATE TABLE IF NOT EXISTS essence_tracking (id INT AUTO_INCREMENT PRIMARY KEY, essence_item_id INT UNSIGNED NOT NULL, original_item_name VARCHAR(255) NOT NULL, owner_guid INT UNSIGNED NOT NULL, appearance_entry INT UNSIGNED NOT NULL, KEY(owner_guid), KEY(essence_item_id)) ENGINE=InnoDB]])

-- Auto-populate BOSS_ENTRIES from world DB if empty (onkill mode only)
if C.DROP_MODE == "onkill" then
    local count = 0
    for _ in pairs(C.BOSS_ENTRIES) do count = count + 1 end
    if count == 0 then
        local mapList = ""
        for m in pairs(C.RAID_MAPS) do mapList = mapList .. m .. "," end
        mapList = mapList:sub(1, -2)
        local query = string.format([[
            SELECT DISTINCT e FROM (
                SELECT ct.entry AS e FROM creature_template ct
                JOIN creature c ON c.id1 = ct.entry
                WHERE FIND_IN_SET(c.map, '%s') AND ct.rank = 3
              UNION
                SELECT dt.entry FROM creature_template ct
                JOIN creature c ON c.id1 = ct.entry
                JOIN creature_template dt ON dt.entry = ct.difficulty_entry_1
                WHERE FIND_IN_SET(c.map, '%s') AND ct.rank = 3
              UNION
                SELECT dt.entry FROM creature_template ct
                JOIN creature c ON c.id1 = ct.entry
                JOIN creature_template dt ON dt.entry = ct.difficulty_entry_2
                WHERE FIND_IN_SET(c.map, '%s') AND ct.rank = 3
              UNION
                SELECT dt.entry FROM creature_template ct
                JOIN creature c ON c.id1 = ct.entry
                JOIN creature_template dt ON dt.entry = ct.difficulty_entry_3
                WHERE FIND_IN_SET(c.map, '%s') AND ct.rank = 3
            ) x
        ]], mapList, mapList, mapList, mapList)
        local rows = WorldDBQuery(query)
        if rows then
            repeat
                C.BOSS_ENTRIES[rows:GetUInt32(0)] = true
            until not rows:NextRow()
        end
        local bossCount = 0
        for _ in pairs(C.BOSS_ENTRIES) do bossCount = bossCount + 1 end
        debugLog("onkill mode: auto-populated " .. bossCount .. " boss entries (all difficulties)")
    else
        debugLog("onkill mode: using manual BOSS_ENTRIES (" .. count .. " entries)")
    end
end

for _, itemEntryId in ipairs({ C.DECEPTION, C.ILLUSION, C.PURIFICATION }) do
    debugLog("register item event entry=" .. itemEntryId)
    RegisterItemEvent(itemEntryId, 2, itemUse)
end
RegisterItemEvent(C.ESSENCE, 2, itemUse)
if C.LEGENDARY_ESSENCE ~= C.ESSENCE then
    RegisterItemEvent(C.LEGENDARY_ESSENCE, 2, itemUse)
end
RegisterPlayerEvent(3, onLogin)
RegisterPlayerEvent(4, onLogout)
if C.DROP_MODE == "onkill" then
    RegisterPlayerEvent(7, onKill)
    debugLog("drop mode: onkill (killing player is rewarded directly)")
else
    debugLog("drop mode: " .. tostring(C.DROP_MODE) .. " (onKill hook inactive)")
end
RegisterPlayerEvent(29, onEquip)
RegisterPlayerEvent(18, onChat)

local online = GetPlayersInWorld()
if online then
    for _, player in ipairs(online) do
        loadPlayer(player)
        debugSay(player, "scroll_transmog.lua loaded successfully")
    end
end
debugLog("scroll transmog script loaded")
