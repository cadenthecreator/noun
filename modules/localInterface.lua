local stor = require("libs.storageLib")
local completion = require("cc.completion")
settings.define("interface.inventory",
   {
      type = "string",
      description = "the inventory for taking in and depositing items"
   }
)
settings.save()
local out_name =settings.get("interface.inventory")
if not out_name then
   sleep()
   local peripherals = peripheral.find("peripheral_hub").getNamesRemote()
   peripherals[#peripherals+1] = peripheral.find("peripheral_hub").getNameLocal()
   print("no interface inventory specified")
   term.write("inventory: ")
   settings.set("interface.inventory", read(nil, nil, function(text) return completion.choice(text, peripherals) end))
   settings.save()
   os.reboot()
end
local out = peripheral.wrap(out_name)
local lightcolor = colors.white
local mediumcolor = colors.lightGray
local darkcolor = colors.black
local sx,sy = term.getSize()
os.pullEvent("storage_ready")
local items = stor.list()
local function listify(l)
   local out = {}
   for _,i in ipairs(l) do
        out[#out+1] = i.name..string.rep(" ",sx-i.name:len()-tostring(i.count):len())..tostring(i.count)
   end
   return out
end

local tabs = {}
local current_tab = "storage"
local take = nil
tabs.storage = {
   scroll = 0,
   selected = 0,
   search = "",
   update = function (self)
      local event = {os.pullEvent()}
      if event[1] == "char" then
         self.search = self.search..event[2]
         items = stor.list(self.search)
         self.scroll = 0
         self.selected = 1
      elseif event[1] == "key" then
         if event[2] == keys.backspace then
            self.search = self.search:sub(1,self.search:len()-1)
            items = stor.list(self.search)
            self.scroll = 0
            self.selected = 1
         elseif event[2] == keys.enter then
            take = items[self.selected]
            current_tab = "extract" 
         elseif event[2] == keys.up then
            self.selected = self.selected - 1
            if self.selected-self.scroll < 1 then
               self.scroll = self.selected-1
            elseif self.selected-self.scroll > sy-1 then
               self.scroll = (self.selected - sy)+1
            end
         elseif event[2] == keys.down then
            self.selected = self.selected + 1
            if self.selected-self.scroll < 0 then
               self.scroll = self.selected-1
            elseif self.selected-self.scroll > sy-2 then
               self.scroll = (self.selected - sy)+1
            end
         end
      elseif event[1] == "mouse_scroll" then
         self.scroll = self.scroll + event[2]
      elseif event[1] == "mouse_click" or event[1] == "mouse_drag" then
         if event[4] ~= sy then
            if items[event[4]+self.scroll] then
               self.selected = event[4]+self.scroll
            end
         end
      end
      self.scroll = math.max(math.min(self.scroll,math.max(#items-(sy-1),0)),0)
      self.selected = math.max(math.min(self.selected,#items),1)
   end,
   render = function (self)
      local list = listify(items)
      term.setBackgroundColor(lightcolor)
      term.setTextColor(darkcolor)
      term.setCursorPos(1,sy)
      term.clearLine()
      if self.search ~= "" then
         term.write(self.search)
      else
         term.setTextColor(mediumcolor)
         term.write("search...")
      end
      for y = 1,sy-1 do
         term.setBackgroundColor(darkcolor)
         term.setTextColor(lightcolor)
         term.setCursorPos(1,y)
         if y+self.scroll == self.selected then
            term.setBackgroundColor(lightcolor)
            term.setTextColor(darkcolor)
         end
         term.clearLine()
         if list[y+self.scroll] then
            term.write(list[y+self.scroll])
         end
      end
      sleep()
   end
}

tabs.extract = {
   count = "",
   update = function (self)
      local event = {os.pullEvent()}
      if event[1] == "char" then
         self.count = self.count..event[2]:gsub("[^%d]", "")
      elseif event[1] == "key" then
         if event[2] == keys.backspace then
            self.count = self.count:sub(1,self.count:len()-1)
         elseif event[2] == keys.enter then
            if take then
               stor.take(take.name,out_name,tonumber(self.count),2)
               items = stor.list(tabs.storage.search)
            end
            self.count = ""
            current_tab = "storage"
            sleep()
         elseif event[2] == keys.x then
            self.count = ""
            current_tab = "storage"
            sleep()
         end
      end
   end,
   render = function (self)
      term.setBackgroundColor(darkcolor)
      term.clear()
      term.setBackgroundColor(lightcolor)
      term.setTextColor(darkcolor)
      term.setCursorPos(1,sy)
      term.clearLine()
      if self.count ~= "" then
         term.write(self.count)
      else
         if take then
            term.setTextColor(mediumcolor)
            term.write(tostring(take.maxCount))
         end
      end
      term.setBackgroundColor(darkcolor)
      term.setTextColor(lightcolor)
      term.setCursorPos(1,sy-1)
      term.write("amount: ")
      sleep()
   end
}


local function update()
   while true do
      tabs[current_tab]:update()
   end
end

local function render()
   while true do
      tabs[current_tab]:render()
   end
end

local function pull()
   while true do
      if out.getItemDetail(1) then
         stor.put(out_name,1)
         items = stor.list(tabs.storage.search)
      end
   end
end

parallel.waitForAny(render,update,pull)