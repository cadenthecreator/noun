local lib = {}

function lib.put(from,fromslot,count)
    local succ,msg = false,"Failed to get a response"
    local id = math.random(0,999999)
    os.queueEvent("put",id,from, fromslot, count)
    parallel.waitForAny(
    function ()
        _,succ,msg = os.pullEvent(tostring(id).."_put_done")
    end,
    function ()
        sleep(1)
    end
    )
    return succ,msg
end

function lib.take(name, to, count, toslot)
    local succ,msg = false,"Failed to get a response"
    local id = math.random(0,999999)
    os.queueEvent("take",id,name, to, count, toslot)
    parallel.waitForAny(
    function ()
        _,succ,msg = os.pullEvent(tostring(id).."_take_done")
    end,
    function ()
        sleep(1)
    end
    )
    return succ,msg
end

function lib.list(search)
    local out = {}
    local id = math.random(0,999999)
    os.queueEvent("list",id,search)
    parallel.waitForAny(
    function ()
        _,out = os.pullEvent(tostring(id).."_list_done")
    end,
    function ()
        sleep(1)
    end
    )
    return out
end

return lib