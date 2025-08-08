local stor = require("libs.storageLib")
local out_name = "minecraft:barrel_2"
if not fs.exists("libs/pixelui.lua") then
    shell.run("wget run https://pinestore.cc/d/154")
    fs.move("pixelui.lua","libs/pixelui.lua")
end
local sx,sy = term.getSize()
local PixelUI = require("libs.pixelui")
os.pullEvent("storage_ready")

PixelUI.init()

local items = stor.list()
local function listify(l)
   local out = {}
   for _,i in ipairs(l) do
        out[#out+1] = i.name..string.rep(" ",sx-i.name:len()-tostring(i.count):len())..tostring(i.count)
   end
   return out
end
local takename = ""
local function onSelect(_,_,indx)
    takename = items[indx].name
end
local list = PixelUI.listView({
    x=1,
    y=1,
    width=sx,
    height=sy-1,
    items = listify(items),
    onSelect = onSelect
})

local search = ""
local count = 64

local function take()
    if takename ~= "" then
        stor.take(takename,out_name,count)
        items = stor.list(search)
        list.items = listify(items)
    end
end

PixelUI.textBox({ 
    x = 1,
    y = sy,
    width = sx-6,
    placeholder = "Search here...",
    onChange = function(self, v)
        search = v
        items = stor.list(v)
        list.items = listify(items)
    end,
    onEnter = take
})
PixelUI.textBox({ 
    x = sx-5,
    y = sy,
    width = 6,
    text = "64",
    placeholder = "64",
    onChange = function(self, v)
        self.text = v:gsub("[^%d]", "")
        count = tonumber(self.text)
    end,
    onEnter = take
})
PixelUI.run()