--[[
    RSP Serializer - converte args reais em código Lua executável
    Inspirado no DataToCode do SimpleSpy V3, porém simplificado e sem
    dependência de loadstring externo.

    Suporta: nil, boolean, number (inf/nan), string (multiline + escapes),
    Vector2/3, CFrame, UDim/UDim2, Color3, BrickColor, NumberRange, Ray,
    TweenInfo, Rect, EnumItem, Instance (com path correto), tables
    (com detecção de ciclos, duplicatas e chaves não-triviais), userdata
    genérico, funções (nome via debug.info).

    API:
      serializer.encode(args)  -> (string codigoLua, bool precisaGetNil)
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local MAX_TABLE = 1000
local MAX_STRING = 10000
local INDENT = 4

local M = {}

local function identIsValid(s)
    return type(s) == "string" and s:match("^[%a_][%w_]*$") == s
end

-- escape de strings (lida com \n, \t, \\, ", bytes não-imprimíveis)
local function escapeStr(s)
    if #s > MAX_STRING then s = s:sub(1, MAX_STRING) end
    local buf, n = {}, 0
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = string.byte(c)
        if c == "\\" then n=n+1; buf[n]="\\\\"
        elseif c == '"' then n=n+1; buf[n]='\\"'
        elseif c == "\n" then n=n+1; buf[n]="\\n"
        elseif c == "\r" then n=n+1; buf[n]="\\r"
        elseif c == "\t" then n=n+1; buf[n]="\\t"
        elseif b < 32 or b > 126 then n=n+1; buf[n]="\\"..b
        else n=n+1; buf[n]=c
        end
    end
    return '"'..table.concat(buf)..'"'
end

-- number especial (inf, nan)
local function encodeNum(v)
    if v ~= v then return "0/0" end
    if v == math.huge then return "math.huge" end
    if v == -math.huge then return "-math.huge" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return tostring(v)
end

-- Instance → path executável
local function instanceToPath(inst, state)
    if not inst then return "nil" end
    local okGame = pcall(function() return inst == game end)
    if okGame and inst == game then return "game" end
    if inst == workspace then return "workspace" end
    if inst == LocalPlayer then return 'game:GetService("Players").LocalPlayer' end

    -- character do LocalPlayer
    if LocalPlayer and LocalPlayer.Character and inst == LocalPlayer.Character then
        return 'game:GetService("Players").LocalPlayer.Character'
    end

    local parts = {}
    local cur = inst
    local depth = 0
    local rootedInGame = false
    local serviceRoot = nil

    while cur and depth < 50 do
        depth = depth + 1
        local ok, parent = pcall(function() return cur.Parent end)
        if not ok then break end
        if parent == game then
            serviceRoot = cur
            rootedInGame = true
            break
        end
        if parent == nil then
            -- instância nil (não parented ao DataModel)
            break
        end
        local name = cur.Name
        if identIsValid(name) then
            table.insert(parts, 1, "."..name)
        else
            table.insert(parts, 1, ':FindFirstChild('..escapeStr(name)..')')
        end
        cur = parent
    end

    if rootedInGame and serviceRoot then
        local cls = serviceRoot.ClassName
        local head
        if cls == "Workspace" then
            head = "workspace"
        else
            head = string.format('game:GetService("%s")', cls)
        end
        return head..table.concat(parts)
    end

    -- fallback: nil instance
    state.needGetNil = true
    local okName = pcall(function() return inst.Name end)
    local okCls  = pcall(function() return inst.ClassName end)
    if okName and okCls then
        return string.format('getNil(%s, "%s")%s',
            escapeStr(inst.Name), inst.ClassName, table.concat(parts))
    end
    return 'nil --[[instance sem path]]'
end

-- encoders por typeof
local typeEncoders = {
    ["nil"]     = function() return "nil" end,
    boolean     = function(v) return tostring(v) end,
    number      = encodeNum,
    string      = function(v) return escapeStr(v) end,
    Vector2     = function(v) return string.format("Vector2.new(%s, %s)", encodeNum(v.X), encodeNum(v.Y)) end,
    Vector3     = function(v) return string.format("Vector3.new(%s, %s, %s)", encodeNum(v.X), encodeNum(v.Y), encodeNum(v.Z)) end,
    CFrame      = function(v)
        local c = {v:GetComponents()}
        local parts = {}
        for i, n in ipairs(c) do parts[i] = encodeNum(n) end
        return "CFrame.new("..table.concat(parts, ", ")..")"
    end,
    UDim        = function(v) return string.format("UDim.new(%s, %d)", encodeNum(v.Scale), v.Offset) end,
    UDim2       = function(v) return string.format("UDim2.new(%s, %d, %s, %d)",
        encodeNum(v.X.Scale), v.X.Offset, encodeNum(v.Y.Scale), v.Y.Offset) end,
    Color3      = function(v) return string.format("Color3.fromRGB(%d, %d, %d)",
        math.floor(v.R*255+0.5), math.floor(v.G*255+0.5), math.floor(v.B*255+0.5)) end,
    BrickColor  = function(v) return string.format("BrickColor.new(%q)", v.Name) end,
    NumberRange = function(v) return string.format("NumberRange.new(%s, %s)", encodeNum(v.Min), encodeNum(v.Max)) end,
    Ray         = function(v) return string.format("Ray.new(Vector3.new(%s,%s,%s), Vector3.new(%s,%s,%s))",
        encodeNum(v.Origin.X), encodeNum(v.Origin.Y), encodeNum(v.Origin.Z),
        encodeNum(v.Direction.X), encodeNum(v.Direction.Y), encodeNum(v.Direction.Z)) end,
    Rect        = function(v) return string.format("Rect.new(%s, %s, %s, %s)",
        encodeNum(v.Min.X), encodeNum(v.Min.Y), encodeNum(v.Max.X), encodeNum(v.Max.Y)) end,
    TweenInfo   = function(v) return string.format(
        "TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %d, %s, %s)",
        encodeNum(v.Time), v.EasingStyle.Name, v.EasingDirection.Name,
        v.RepeatCount, tostring(v.Reverses), encodeNum(v.DelayTime)) end,
    EnumItem    = function(v) return tostring(v) end,
    Enum        = function(v) return "Enum."..tostring(v) end,
    Enums       = function() return "Enum" end,
    RBXScriptSignal     = function() return "nil --[[RBXScriptSignal não serializável]]" end,
    RBXScriptConnection = function() return "nil --[[RBXScriptConnection não serializável]]" end,
}

-- encoder de tabela com controle de ciclo/duplicata/profundidade
local encodeValue

local function encodeTable(t, state, level, path)
    -- duplicata: referência já vista → marca como duplicata (tratada depois)
    if state.seen[t] then
        return "{} --[[DUPLICATE]]"
    end
    state.seen[t] = path or "<root>"
    level = level + 1
    local indent = string.rep(" ", level * INDENT)
    local closeIndent = string.rep(" ", (level-1) * INDENT)

    local count = 0
    local parts = {}

    -- array-part primeiro (estetica)
    local isArrayLike = true
    local expect = 1
    for k, _ in pairs(t) do
        if k ~= expect then isArrayLike = false; break end
        expect = expect + 1
    end

    if isArrayLike then
        for i, v in ipairs(t) do
            count = count + 1
            if count > MAX_TABLE then
                parts[#parts+1] = indent.."-- MAX_TABLE excedido"
                break
            end
            local subPath = path.."["..i.."]"
            parts[#parts+1] = indent..encodeValue(v, state, level, subPath)..","
        end
    else
        for k, v in pairs(t) do
            count = count + 1
            if count > MAX_TABLE then
                parts[#parts+1] = indent.."-- MAX_TABLE excedido"
                break
            end
            local keyStr, subPath
            if identIsValid(k) then
                keyStr = k
                subPath = path.."."..k
            else
                local ek = encodeValue(k, state, level, path.."[?]")
                keyStr = "["..ek.."]"
                subPath = path.."["..ek.."]"
            end
            parts[#parts+1] = indent..keyStr.." = "..encodeValue(v, state, level, subPath)..","
        end
    end

    if count == 0 then return "{}" end
    return "{\n"..table.concat(parts, "\n").."\n"..closeIndent.."}"
end

encodeValue = function(v, state, level, path)
    level = level or 0
    path = path or "args"

    local tt = typeof(v)
    local enc = typeEncoders[tt]
    if enc then return enc(v) end

    if tt == "Instance" then
        return instanceToPath(v, state)
    end
    if tt == "table" then
        return encodeTable(v, state, level, path)
    end
    if tt == "function" then
        local ok, info = pcall(debug.info, v, "n")
        if ok and info and info ~= "" then
            return string.format('nil --[[function %s]]', tostring(info))
        end
        return "nil --[[function]]"
    end
    if tt == "userdata" then
        return "newproxy(true) --[[userdata genérico]]"
    end
    if tt == "buffer" then
        return "buffer.create(0) --[[buffer]]"
    end
    return string.format("nil --[[%s]]", tt)
end

-- API pública
function M.encode(args)
    local state = { seen = {}, needGetNil = false }
    local n = #args
    if n == 0 then
        return "local args = {}", false
    end

    local parts = {}
    for i = 1, n do
        parts[i] = string.rep(" ", INDENT)..encodeValue(args[i], state, 1, "args["..i.."]")..","
    end
    local code = "local args = {\n"..table.concat(parts, "\n").."\n}"
    return code, state.needGetNil
end

-- encode single value (pra preview de args individuais)
function M.encodeSingle(v)
    local state = { seen = {}, needGetNil = false }
    return encodeValue(v, state, 0, "v"), state.needGetNil
end

-- preview curto (pra lista de logs, não executável)
function M.preview(v, maxLen)
    maxLen = maxLen or 60
    local tt = typeof(v)
    if tt == "string" then
        local s = v:gsub("\n", "\\n"):gsub("\t", "\\t")
        if #s > maxLen then s = s:sub(1, maxLen-3).."..." end
        return '"'..s..'"'
    elseif tt == "number" or tt == "boolean" or tt == "nil" then
        return tostring(v)
    elseif tt == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    elseif tt == "Vector2" then
        return string.format("V2(%.1f,%.1f)", v.X, v.Y)
    elseif tt == "CFrame" then
        return string.format("CF(%.1f,%.1f,%.1f)", v.Position.X, v.Position.Y, v.Position.Z)
    elseif tt == "Color3" then
        return string.format("RGB(%d,%d,%d)", v.R*255, v.G*255, v.B*255)
    elseif tt == "Instance" then
        local ok, cls = pcall(function() return v.ClassName end)
        local ok2, nm  = pcall(function() return v.Name end)
        return string.format("<%s:%s>", ok and cls or "?", ok2 and nm or "?")
    elseif tt == "table" then
        local n = 0; for _ in pairs(v) do n = n + 1 end
        return string.format("{%d items}", n)
    elseif tt == "EnumItem" then
        return tostring(v)
    end
    return "<"..tt..">"
end

function M.previewArgs(args, maxArgs)
    maxArgs = maxArgs or 8
    if not args or #args == 0 then return "()" end
    local parts = {}
    for i = 1, math.min(#args, maxArgs) do
        parts[i] = M.preview(args[i])
    end
    if #args > maxArgs then
        parts[#parts+1] = string.format("+%d", #args - maxArgs)
    end
    return "("..table.concat(parts, ", ")..")"
end

return M
