local moduledir = fs.list("modules")

local modules = {}

for _,i in ipairs(moduledir) do
    modules[#modules+1] = loadfile("modules/"..i,"t",_ENV)
end

parallel.waitForAll(table.unpack(modules))