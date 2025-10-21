local expect = dofile("rom/modules/main/cc/expect.lua")
expect = expect.expect

if not fs.exists("libs/fzy.lua") then
    shell.run("wget https://github.com/swarn/fzy-lua/raw/refs/heads/main/src/fzy_lua.lua libs/fzy.lua")
end

local fzy = require("libs.fzy")

local peripherals = peripheral.getNames()
local storage_filters = {
    "sc%-goodies",
}

local storage = {}
local items = {}

for _,periph in ipairs(peripherals) do
    for _,filt in ipairs(storage_filters) do
        if periph:find(filt) then
            storage[periph] = peripheral.wrap(periph)
            break
        end
    end
end

local function saveitems()
    local file = fs.open(".items","w")
    file.write(textutils.serialiseJSON(items))
    file.close()
end

local function loaditems()
    local file = fs.open(".items","r")
    items = textutils.unserialiseJSON(file.readAll())
    file.close()
end

local function rescan()
    items = {}
    for n,i in pairs(storage) do
        for s,id in pairs(i.list()) do
            local item = i.getItemDetail(s)
            if not items[item.name] then
                items[item.name] = {
                    count = item.count,
                    id = item.name,
                    name = item.displayName,
                    maxCount = item.maxCount,
                    locations = {
                        {
                            id = n,
                            slot = s,
                            name = item.displayName,
                            count = item.count,
                            maxCount = item.maxCount
                        }
                    }
                }
            else
                items[item.name].count = items[item.name].count + item.count
                items[item.name].locations[#items[item.name].locations+1] = {
                    id = n,
                    slot = s,
                    name = item.displayName,
                    count = item.count,
                    maxCount = item.maxCount,
                }
            end
        end
    end
end

local function sum_lowest_to(locations,count)
    local cmds = {}
    local blacklist = {}
    local total = 0
    repeat
        local lowest = 99999
        local lowest_indx = 0
        for k,v in pairs(locations) do
            if not blacklist[k] then
                if v.count < lowest then
                    lowest = v.count
                    lowest_indx = k
                end
            end
        end
        if lowest_indx > 0 then
            blacklist[lowest_indx] = true
            local take_count = math.min(lowest,count)
            cmds[#cmds+1] = {
                location = lowest_indx,
                count = take_count,
            }
            count = count - take_count
            total = total + take_count
        end
    until count == 0 or #locations == #blacklist
    return cmds, total
end

local function fill_highest(locations,count,max)
    local cmds = {}
    local blacklist = {}
    local total = 0
    if #locations > 0 then
        repeat
            local highest = 0
            local highest_indx = 0
            for k,v in pairs(locations) do
                if not blacklist[k] then
                    if v.count > highest and v.count < max then
                        highest = v.count
                        highest_indx = k
                    elseif v.count >= max then
                        blacklist[k] = true
                    end
                end
            end
            if highest_indx > 0 then
                blacklist[highest_indx] = true
                cmds[#cmds+1] = {
                    location = highest_indx,
                    count = math.min(max - highest,count),
                }
                count = count - math.min(max - highest,count)
                total = total + math.min(max - highest,count)
            end
        until count == 0 or #locations <= #blacklist
    end
    if count > 0 then
        repeat
            cmds[#cmds+1] = {
                location = -1,
                count = math.min(max,count),
            }
            count = count - math.min(max,count)
            total = total + math.min(max,count)
        until count == 0
    end
    return cmds, total
end

local function take(name, to, count,toslot)
    expect(1,name,"string")
    expect(2,to,"string")
    local item = items[name]
    if not item then error("Item not found",2) end
    -- plan to take up to requested or up to one stack if unspecified
    count = math.min(count or item.locations[1].maxCount,item.count)
    toslot = toslot or 1
    expect(3,count,"number")
    expect(4,toslot,"number")
    local to = peripheral.wrap(to)
    if to.getInventory then
        to = to.getInventory()
    end
    local offset = 0
    local cmds, planned_total = sum_lowest_to(item.locations,count)
    local actual_total = 0

    for _,i in ipairs(cmds) do
        local location = item.locations[i.location]
        if not location then goto continue_end end
        local need = i.count
        local remaining = need
        -- attempt to fill destination slots starting at toslot+offset
        while remaining > 0 do
            local destSlot = toslot + offset
            -- avoid infinite loops: if destination doesn't have size, cap attempts
            local destSize = (to.size and to.size()) or 64
            if destSlot > destSize then
                -- no more destination slots; stop trying
                break
            end
            local quantity = to.pullItems(location.id,location.slot,math.min(remaining, location.maxCount), destSlot)
            remaining = remaining - (quantity or 0)
            actual_total = actual_total + (quantity or 0)

            -- check destination slot detail: if slot is full or contains different item, move to next slot
            local detail = to.getItemDetail(destSlot)
            if (quantity == 0) or (detail and (detail.maxCount == detail.count or detail.name ~= name)) then
                offset = offset + 1
            end

            -- if pullItems returned 0 and destination slot moved forward past destSize, stop
            if quantity == 0 and destSlot >= destSize then
                break
            end
        end

        local moved_from_location = need - remaining
        if moved_from_location <= 0 then
            -- nothing moved from this location
            goto continue_store
        end

        -- subtract moved amount from storage location
        if moved_from_location >= location.count then
            -- remove this location
            item.locations[i.location] = nil
        else
            location.count = location.count - moved_from_location
            item.locations[i.location] = location
        end

        ::continue_store::
        ::continue_end::
    end

    -- compact locations and update item count by actual moved
    if #item.locations > 0 then
        local new_locations = {}
        for _,i in pairs(item.locations) do
            if i then new_locations[#new_locations+1] = i end
        end
        item.locations = new_locations
        item.count = item.count - actual_total
        if item.count < 0 then item.count = 0 end
    else
        items[name] = nil
    end
    return true, actual_total
end

local function put(from,fromslot,count)
    if not from or type(from) ~= "string" then return false, "Invalid argument #1" end
    if not fromslot or type(fromslot) ~= "number" then return false, "Invalid argument #2" end
    if type(count) ~= "number" and count then return false, "Invalid argument #3" end
    count = count or 64
    from = peripheral.wrap(from)
    if from.getInventory then
        from = from.getInventory()
    end
    local detail = from.getItemDetail(fromslot)
    if detail then
        local item = items[detail.name]
        if not item then
            item = {
                    count = 0,
                    maxCount = detail.maxCount,
                    name = detail.displayName,
                    id = detail.name,
                    locations = {
                    }
                }
        end
        local to_move = math.min(detail.count, count)
        local cmds,total_planned = fill_highest(item.locations,to_move, detail.maxCount)
        local actual_total = 0

        for _,c in ipairs(cmds) do
            if c.location == -1 then
                local slot = -1
                local location = ""
                for k,v in pairs(storage) do
                    local items_list = v.list()
                    for s = 1,v.size() do
                        if not items_list[s] then
                            slot = s
                            location = k
                            break
                        end
                    end
                    if slot ~= -1 then
                        break
                    end
                end
                if slot == -1 then
                    -- no empty slot found, skip
                else
                    local moved = from.pushItems(location,fromslot,c.count,slot) or 0
                    if moved > 0 then
                        item.locations[#item.locations+1] =
                        {
                            id = location,
                            slot = slot,
                            count = moved,
                            name = detail.displayName,
                            maxCount = detail.maxCount,
                        }
                        actual_total = actual_total + moved
                    end
                end
            else
                local location = item.locations[c.location]
                if location then
                    local moved = from.pushItems(location.id,fromslot,c.count,location.slot) or 0
                    if moved > 0 then
                        location.count = location.count + moved
                        item.locations[c.location] = location
                        actual_total = actual_total + moved
                    end
                end
            end
        end

        item.count = item.count + actual_total
        if item.count > 0 then
            items[detail.name] = item
        else
            items[detail.name] = nil
        end
        return true, actual_total
    else
        return false, "No items found"
    end
end

local function sortItems(item1, item2) 
  return item1.count > item2.count
end


local function sortItems(item1, item2) 
  return item1.count > item2.count
end

local function split_terms(s)
    if not s or s == "" then return nil end
    local out = {}
    for tok in s:lower():gmatch("%S+") do out[#out+1] = tok end
    if #out == 0 then return nil end
    return out
end

local function list(search)
    local results = {}
    for name,v in pairs(items) do
        if v.count > 0 then
            results[#results+1] = {
                id = v.id,
                name = v.name,
                count = v.count,
                maxCount = v.maxCount
            }
        else
            items[name] = nil
        end
    end

    local terms = split_terms(search)
    if not terms then
        table.sort(results, sortItems)
        return results
    end

    -- score each item by summing per-token fzy scores; require all tokens to match (score > 0)
    local scored = {}
    for _,item in ipairs(results) do
        local name_l = item.name:lower()
        local total_score = 0
        local ok = true
        for _,tok in ipairs(terms) do
            local s = fzy.score(tok, name_l) or 0
            if s <= 0 then
                ok = false
                break
            end
            total_score = total_score + s
        end
        if ok then
            scored[#scored+1] = { item = item, score = total_score }
        end
    end

    table.sort(scored, function(a,b)
        if a.score == b.score then
            return a.item.count > b.item.count
        end
        return a.score > b.score
    end)

    local out = {}
    for _,v in ipairs(scored) do out[#out+1] = v.item end
    return out
end

if not fs.exists(".items") then
    rescan()
    saveitems()
end
print("loading from file...")
loaditems()
print("done!")
sleep(0)
os.queueEvent("storage_ready")
while true do
    local args = {os.pullEvent()}
    local id = args[2]
    if args[1] == "take" then
        os.queueEvent(tostring(id).."_take_done",take(args[3],args[4],args[5],args[6]))
        saveitems()
    elseif args[1] == "put" then
        os.queueEvent(tostring(id).."_put_done",put(args[3],args[4],args[5]))
        saveitems()
    elseif args[1] == "list" then
        os.queueEvent(tostring(id).."_list_done",list(args[3]))
    end
end