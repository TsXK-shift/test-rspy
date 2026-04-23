--[[
    build_single.lua - gera um único arquivo Lua contendo todos os módulos
    inline. Rode este script localmente (fora do Roblox) com Lua 5.1+ pra
    gerar remotespy_single.lua.

    Uso: lua build_single.lua

    O arquivo de saída NÃO depende de HttpGet, pode rodar offline.
]]

local modules = {"serializer", "blocker", "scanner", "hooks", "ui"}

local function readFile(path)
    local f = io.open(path, "r")
    if not f then error("não consegui abrir "..path) end
    local s = f:read("*a")
    f:close()
    return s
end

local out = {}
table.insert(out, "-- Remote Spy Pro v4.0 (arquivo único)")
table.insert(out, "-- Gerado automaticamente - não editar manualmente")
table.insert(out, "")
table.insert(out, "getgenv().__RSP_MODULES = getgenv().__RSP_MODULES or {}")
table.insert(out, "")

for _, name in ipairs(modules) do
    local src = readFile("modules/"..name..".lua")
    table.insert(out, "-- ═══════════════════════════════════════")
    table.insert(out, "-- módulo: "..name)
    table.insert(out, "-- ═══════════════════════════════════════")
    table.insert(out, "getgenv().__RSP_MODULES."..name.." = (function()")
    table.insert(out, src)
    table.insert(out, "end)()")
    table.insert(out, "")
end

-- main (sem a parte de loadModule remoto, pega direto de __RSP_MODULES)
local mainSrc = readFile("main.lua")
table.insert(out, "-- ═══════════════════════════════════════")
table.insert(out, "-- main")
table.insert(out, "-- ═══════════════════════════════════════")
table.insert(out, mainSrc)

local outFile = io.open("remotespy_single.lua", "w")
outFile:write(table.concat(out, "\n"))
outFile:close()
print("[build] gerado: remotespy_single.lua ("..#table.concat(out,"\n").." bytes)")
