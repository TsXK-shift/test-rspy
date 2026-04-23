--[[
    RSP Scanner - descobre TUDO que existe, mesmo sem ser disparado

    Diferente dos hooks (que só pegam o que é ativo), o scanner:
      - lista todos RemoteEvent/RemoteFunction/BindableEvent/BindableFunction no game
      - enumera globals (_G, getgenv())
      - inspeciona connections ativas via getconnections (se disponível)
      - lista scripts (LocalScript) ativos

    Isso é descoberta passiva - não intercepta, só lê o que está lá.
]]

local M = {}

local function safePath(inst)
    local ok, r = pcall(function()
        local parts, cur, d = {}, inst, 0
        while cur and cur ~= game and d < 30 do
            table.insert(parts, 1, cur.Name)
            cur = cur.Parent
            d = d + 1
        end
        return table.concat(parts, ".")
    end)
    return ok and r or tostring(inst)
end

-- 1. Scanner de Remotes/Bindables
-- retorna lista completa classificada
function M.scanInstances()
    local result = {
        RemoteEvent = {},
        RemoteFunction = {},
        UnreliableRemoteEvent = {},
        BindableEvent = {},
        BindableFunction = {},
    }
    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            local ok, cls = pcall(function() return obj.ClassName end)
            if ok and result[cls] then
                table.insert(result[cls], {
                    name = obj.Name,
                    path = safePath(obj),
                    instance = obj,
                })
            end
        end
    end)
    -- ordena por path
    for _, list in pairs(result) do
        table.sort(list, function(a, b) return a.path < b.path end)
    end
    return result
end

-- 2. Scanner de globals (getgenv + _G)
-- útil pra ver o que scripts do jogo expõem
function M.scanGlobals()
    local result = {}
    local function add(k, v, source)
        local t = type(v)
        local info = {
            key = tostring(k),
            type = t,
            source = source,
        }
        if t == "function" then
            local okDbg, dbg = pcall(debug.info, v, "s")
            info.location = okDbg and dbg or nil
        elseif t == "table" then
            local n = 0
            for _ in pairs(v) do
                n = n + 1
                if n > 50 then break end
            end
            info.size = n
        elseif t == "string" or t == "number" or t == "boolean" then
            info.value = tostring(v):sub(1, 100)
        end
        table.insert(result, info)
    end

    pcall(function()
        -- _G (globals legacy)
        for k, v in pairs(_G or {}) do
            if k ~= "_G" and k ~= "_ENV" then
                add(k, v, "_G")
            end
        end
    end)
    if getgenv then
        pcall(function()
            for k, v in pairs(getgenv()) do
                -- pula builtins comuns pra não poluir
                if type(k) == "string" and not k:match("^[A-Za-z][A-Za-z0-9_]*$") then
                    add(k, v, "getgenv")
                elseif type(k) == "string" and #k > 0
                    and k ~= "_G" and k ~= "_ENV"
                    and k ~= "script" and k ~= "game" and k ~= "workspace"
                    and k ~= "task" and k ~= "Enum" and k ~= "Instance"
                    and k ~= "shared" and k ~= "getgenv" and k ~= "getrenv"
                then
                    add(k, v, "getgenv")
                end
            end
        end)
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

-- 3. Scanner de connections (se getconnections disponível)
-- mostra quantos listeners cada remote tem + de onde vêm
function M.scanConnections(remoteEventInstance)
    if not getconnections then return nil, "getconnections não disponível neste executor" end
    local ok, conns = pcall(getconnections, remoteEventInstance.OnClientEvent)
    if not ok then return nil, tostring(conns) end
    local result = {}
    for i, c in ipairs(conns) do
        local info = { index = i }
        pcall(function() info.state = c.State end)
        pcall(function() info.func = c.Function end)
        pcall(function()
            if info.func then
                local dbg = debug.info(info.func, "s")
                info.location = dbg
            end
        end)
        result[i] = info
    end
    return result
end

-- 4. Scanner de LocalScripts ativos
function M.scanScripts()
    local result = {}
    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            local ok, isLs = pcall(function() return obj:IsA("LocalScript") or obj:IsA("ModuleScript") end)
            if ok and isLs then
                local enabled = true
                pcall(function() enabled = obj.Enabled ~= false end)
                table.insert(result, {
                    name = obj.Name,
                    path = safePath(obj),
                    instance = obj,
                    class = obj.ClassName,
                    enabled = enabled,
                })
            end
        end
    end)
    table.sort(result, function(a, b) return a.path < b.path end)
    return result
end

-- tenta descompilar um script (se decompile disponível)
function M.tryDecompile(scriptInstance)
    if not decompile then return nil, "decompile não disponível" end
    local ok, src = pcall(decompile, scriptInstance)
    if not ok then return nil, tostring(src) end
    return src
end

return M
