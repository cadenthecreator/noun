local stor = require("libs.storageLib")
local completion = require("cc.completion")
settings.define("interface.manipulator",
   {
      type = "string",
      description = "the manipulator for taking in and depositing items through chatbox or remote interface"
   }
)
settings.save()
local manipulator_name =settings.get("interface.manipulator")
os.pullEvent("storage_ready")
if not manipulator_name then
   sleep()
   local peripherals = peripheral.find("peripheral_hub").getNamesRemote()
   peripherals[#peripherals+1] = peripheral.find("peripheral_hub").getNameLocal()
   print("no interface manipulator specified")
   term.write("manipulator: ")
   settings.set("interface.manipulator", read(nil, nil, function(text) return completion.choice(text, peripherals) end))
   settings.save()
   os.reboot()
end

local manipulator = peripheral.wrap(manipulator_name)
local BOT_NAME = "&cNOUN"

if not chatbox.hasCapability("command") or not chatbox.hasCapability("tell") then
  error("Chatbox does not have the required permissions. Did you register the license?")
end


while true do
    local event, user, command, args, data = os.pullEvent("command")
    if data.ownerOnly then
        local m = manipulator.getMetaOwner()
        if command == "dep" or command == "deposit" or command == "d" then
            local succ, out = stor.put(manipulator_name,m.heldItemSlot+1,tonumber(args and args[1]))
            if succ then
                chatbox.tell(user, "deposited "..tostring(out).." items", BOT_NAME) 
            else
                chatbox.tell(user, out, BOT_NAME)
            end
        elseif command == "take" or command == "give" or command == "t" or command == "g" then
            local count = nil
            if args and tonumber(args[#args]) then
                count = tonumber(table.remove(args,#args))
            end
            local name = ""
            if args and #args > 0 then
                name = table.concat(args," ")
            end
            -- pass nil when there's no search string so stor.list sorts by count
            local results = stor.list((name ~= "" and name) or nil)
            local first = results and results[1]
            if not first then
                chatbox.tell(user, "no matching item found", BOT_NAME)
            else
                local succ, out = stor.take(first.id,manipulator_name,count)
                if succ then
                    chatbox.tell(user, "took "..tostring(out).." x "..first.name, BOT_NAME) 
                else
                    chatbox.tell(user, out, BOT_NAME)
                end
            end
        elseif command == "search" or command == "s" or command == "query" or command == "q" or command == "find" or command == "f" then
            local query = (args and #args > 0) and table.concat(args," ") or nil
            local output = stor.list(query)
            local strlist = {}
            for i = 1,math.min(#output,10) do
                local item = output[i]
                strlist[i] = item.name.." - "..tostring(item.count)
            end
            chatbox.tell(user, table.concat(strlist,"\n"), BOT_NAME)
        end
    end
    
end
