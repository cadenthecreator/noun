local stor = require("libs.storageLib")

if not fs.exists("pixelui.lua") then
    shell.run("wget run https://pinestore.cc/d/154")
    fs.move("pixelui.lua","libs/pixelui.lua")
end

local pixelui = require("libs.pixelui")