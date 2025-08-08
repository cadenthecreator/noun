local lib = {}

function lib.put(from,fromslot,count)
    local id = math.random(0,999999)
    os.queueEvent("put",id,from, fromslot, count)
    local _,succ,msg = os.pullEvent(tostring(id).."_put_done")
    return succ,msg
end

function lib.take(name, to, count, toslot)
    local id = math.random(0,999999)
    os.queueEvent("take",id,name, to, count, toslot)
    local _,succ,msg = os.pullEvent(tostring(id).."_take_done")
    return succ,msg
end

function lib.list(search)
    local id = math.random(0,999999)
    os.queueEvent("list",id,search)
    local _,out = os.pullEvent(tostring(id).."_list_done")
    return out
end

return lib