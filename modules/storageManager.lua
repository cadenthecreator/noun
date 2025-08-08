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
            if not items[item.displayName] then
                items[item.displayName] = {
                    count = item.count,
                    id = id.name,
                    locations = {
                        {
                            id = n,
                            slot = s,
                            count = item.count,
                            maxCount = item.maxCount
                        }
                    }
                }
            else
                items[item.displayName].count = items[item.displayName].count + item.count
                items[item.displayName].locations[#items[item.displayName].locations+1] = {
                    id = n,
                    slot = s,
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
            cmds[#cmds+1] = {
                location = lowest_indx,
                count = math.min(lowest,count),
            }
            count = count - math.min(lowest,count)
            total = total + math.min(lowest,count)
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
        until count == 0
    end
    return cmds, total
end

local function take(name, to, count,toslot)
    if not name or type(name) ~= "string" then return false, "Invalid argument #1" end
    if not to or type(to) ~= "string" then return false, "Invalid argument #2" end
    local item = items[name]
    count = math.min(count or 64,item.count)
    toslot = toslot or 1
    if type(count) ~= "number" then return false, "Invalid argument #3" end
    if type(toslot) ~= "number" then return false, "Invalid argument #4" end
    local to = peripheral.wrap(to)
    local offset = 0
    if not item then return false, "Item not found" end
    local cmds, total = sum_lowest_to(item.locations,count)
    for _,i in ipairs(cmds) do
        local location = item.locations[i.location]
        local count = i.count + 0
        repeat
            local quantity = to.pullItems(location.id,location.slot,math.min(count,location.maxCount),toslot+offset)
            count = count - quantity
            local detail = to.getItemDetail(toslot+offset)
            if detail and (detail.maxCount == detail.count or detail.displayName ~= name) then
                offset = offset + 1
            end
        until count == 0
        if i.count == location.count then
            location = nil
        else
            location.count = location.count - i.count
        end
        item.locations[i.location] = location
    end
    local new_locations = {}
    for _,i in pairs(item.locations) do
        new_locations[#new_locations+1] = i
    end
    item.locations = new_locations
    item.count = item.count - count
    return true, total
end

local function put(from,fromslot,count)
    if not from or type(from) ~= "string" then return false, "Invalid argument #1" end
    if not fromslot or type(fromslot) ~= "number" then return false, "Invalid argument #2" end
    if type(count) ~= "number" and count then return false, "Invalid argument #3" end
    from = peripheral.wrap(from)
    local detail = from.getItemDetail(fromslot)
    if detail then
        count = math.min(detail.count, count or detail.count)
        local item = items[detail.displayName]
        if not item then
            item = {
                    count = detail.count,
                    id = detail.name,
                    locations = {
                    }
                }
        end
        local cmds,total = fill_highest(item.locations,math.min(item.count,count), detail.maxCount)
        for _,c in ipairs(cmds) do
            if c.location == -1 then
                local slot = -1
                local location = ""
                for k,v in pairs(storage) do
                    local items = v.list()
                    for s = 1,v.size()+1 do
                        if not items[s] then
                            slot = s
                            location = k
                            break
                        end
                        if slot ~= -1 then
                            break
                        end
                    end
                    if slot ~= -1 then
                        break
                    end
                end
                from.pushItems(location,fromslot,c.count,slot)
                item.locations[#item.locations+1] =
                {
                    id = location,
                    slot = slot,
                    count = c.count,
                    maxCount = detail.maxCount,
                }
                item.count = item.count+count
            else
                local location = item.locations[c.location]
                from.pushItems(location.id,fromslot,c.count,location.slot)
                location.count = location.count + c.count
                item.count = item.count+count
                item.locations[c.location] = location
            end
        end
    else
        return false, "No items found"
    end
end

local function sortItems(item1, item2) 
  return item1.count > item2.count
end


local function list(search)
    local results = {}
    for name,v in pairs(items) do
        results[#results+1] = {
            name = name,
            count = v.count
        }
    end
    if not search or search == "" then
        table.sort(results,sortItems)
    else
        table.sort(results, function(a, b)
            return fzy.score(search, a.name) > fzy.score(search, b.name)
        end)
    end
    return results
end
if not fs.exists(".items") then
    rescan()
    saveitems()
end
print("loading from file...")
loaditems()
print("done!")
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