-- Remote Spy Pro v4.0 (arquivo único)
-- Gerado automaticamente - não editar manualmente

getgenv().__RSP_MODULES = getgenv().__RSP_MODULES or {}

-- ═══════════════════════════════════════
-- módulo: serializer
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.serializer = (function()
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

end)()

-- ═══════════════════════════════════════
-- módulo: blocker
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.blocker = (function()
--[[
    RSP Blocker - sistema avançado de bloqueio anti-spam

    Suporta 4 modos de match:
      exact   - path idêntico (ex: "ReplicatedStorage.Events.Move")
      pattern - pattern Lua (ex: "Events%.Move%d+")
      wildcard- glob com * (ex: "Events.Move*")
      group   - grupo fuzzy: mesmo prefixo/parent + mesma estrutura

    Cada rule tem:
      { type="exact|pattern|wildcard|group", value=str,
        silent=bool,  -- true = não loga E não dispara (default: true)
        hits=int,     -- contador de hits
        created=time }

    Detecção automática de spam:
      rastreia frequência de cada remoteKey nos últimos 5s;
      se > autoBlockThreshold msgs/s, sugere bloqueio do GROUPING
      (não do path exato - assim pega mutações de nome).
]]

local M = {}

-- rules: lista de regras ativas
-- spamStats: { [key] = {count, windowStart, lastSeen, sample} }
local function new()
    return {
        rules = {},
        spamStats = {},
        suggestedBlocks = {},  -- { [groupKey] = {sample, rate, suggestedAt} }
        config = {
            autoBlockThreshold = 10,  -- msgs/s pra considerar spam
            windowSeconds = 5,
            silentByDefault = true,    -- bloqueados somem da lista por padrão
        },
    }
end

-- ── MATCHERS ──

local function matchExact(value, data)
    return data.remotePath == value
end

local function matchPattern(value, data)
    local ok, r = pcall(string.find, data.remotePath, value)
    return ok and r ~= nil
end

-- wildcard: * vira .-, . vira %.
local function wildcardToPattern(w)
    local escaped = w:gsub("([%(%)%[%]%+%-%^%$%?])", "%%%1"):gsub("%.", "%%."):gsub("%*", ".-")
    return "^"..escaped.."$"
end

local function matchWildcard(value, data)
    local pat = wildcardToPattern(value)
    local ok, r = pcall(string.find, data.remotePath, pat)
    return ok and r ~= nil
end

-- group: value é uma "assinatura" tipo "ReplicatedStorage.Events.*"
-- onde * substitui só o último segmento do path, e o nome do remote
-- é considerado igual se for: mesmo comprimento E mesmo charset pattern.
-- Ex: "Move1", "Move2", "MoveX" → todos match.
-- Ex: "AbC123" e "XyZ456" → match (mesma estrutura: 3 letras + 3 dígitos)
local function nameShape(name)
    if name == "" or name == "<empty>" then return "<empty>" end
    -- remove prefixo <hidden:...> pra comparar nomes visíveis
    if name:sub(1, 8) == "<hidden:" then return "<hidden>" end
    local shape = {}
    for i = 1, #name do
        local c = name:sub(i, i)
        local b = c:byte()
        if b >= 48 and b <= 57 then shape[i] = "D"       -- digito
        elseif b >= 65 and b <= 90 then shape[i] = "U"   -- upper
        elseif b >= 97 and b <= 122 then shape[i] = "l"  -- lower
        else shape[i] = "_"
        end
    end
    return table.concat(shape)
end

local function parentPath(path)
    local lastDot = path:match(".*()%.")
    if not lastDot then return "" end
    return path:sub(1, lastDot - 1)
end

local function leafName(path)
    local lastDot = path:match(".*()%.")
    if not lastDot then return path end
    return path:sub(lastDot + 1)
end

-- groupKey: identifica o "grupo" de um remote = parentPath + shape do nome
local function groupKey(data)
    local parent = parentPath(data.remotePath)
    local shape = nameShape(data.remoteName or "")
    return parent.."|"..shape
end

local function matchGroup(value, data)
    return groupKey(data) == value
end

-- signature: identifica remotes "funcionalmente iguais" por ESTRUTURA
-- Objetivo: capturar o PADRÃO semântico, não os valores específicos.
--
-- Estratégia:
--   - Números e strings longas viram placeholder "#" / "$"
--   - Strings curtas (até 24 chars) SÃO incluídas — elas são "tipos/chaves"
--   - Tabelas: inclui só as chaves (pras tabelas-como-caminho tipo {"Items","InUse"})
--     usa os VALORES string, porque eles são o identificador do update
--
-- Exemplo prático:
--   args = (1395, {"TimePlayed"}, 1970)   → sig: "#|[TimePlayed]|#"
--   args = (1400, {"TimePlayed"}, 9999)   → sig: "#|[TimePlayed]|#"  ← MESMA!
--   args = (1395, {"Items","InUse"}, {...}) → sig: "#|[Items,InUse]|{}"

local SHORT_STR_LIMIT = 24

local function argSignature(v, depth)
    depth = depth or 0
    if depth > 2 then return "~" end
    local t = typeof(v)
    if t == "nil" then return "n"
    elseif t == "boolean" then return "b"   -- só tipo, não valor
    elseif t == "number" then return "#"    -- qualquer número = placeholder
    elseif t == "string" then
        -- strings curtas são "keys/tipos" → incluir valor
        -- strings longas são "dados" → placeholder
        if #v <= SHORT_STR_LIMIT then return '"'..v..'"' end
        return "$"
    elseif t == "Instance" then
        local ok, cls = pcall(function() return v.ClassName end)
        return "I:"..(ok and cls or "?")
    elseif t == "table" then
        -- caso especial: "path array" tipo {"Items","InUse","GrowingSeeds"}
        -- se for array de strings curtas, inclui todas como identidade
        local isStringArray = true
        local strVals = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if type(k) ~= "number" or type(val) ~= "string" or #val > SHORT_STR_LIMIT then
                isStringArray = false
                break
            end
            strVals[k] = val
        end
        if isStringArray and n > 0 and n <= 8 then
            local parts = {}
            for i = 1, n do parts[i] = strVals[i] end
            return "["..table.concat(parts, ",").."]"
        end
        -- senão: só sinaliza que é tabela
        return "{}"
    elseif t == "Vector3" or t == "Vector2" or t == "CFrame" then
        return t
    elseif t == "Color3" then return "C"
    elseif t == "EnumItem" then return "E"
    end
    return "?"
end

local function signatureKey(data)
    local parts = { data.remotePath or "?", data.type or "?" }
    local args = data.args or {}
    for i = 1, math.min(#args, 5) do
        parts[#parts+1] = argSignature(args[i], 0)
    end
    return table.concat(parts, "|")
end

local function matchSignature(value, data)
    return signatureKey(data) == value
end

local matchers = {
    exact     = matchExact,
    pattern   = matchPattern,
    wildcard  = matchWildcard,
    group     = matchGroup,
    signature = matchSignature,
}

-- ── API ──

function M.new()
    return new()
end

function M.addRule(inst, ruleType, value, opts)
    opts = opts or {}
    if not matchers[ruleType] then return nil, "tipo inválido" end
    -- evita duplicata
    for _, r in ipairs(inst.rules) do
        if r.type == ruleType and r.value == value then return r end
    end
    local rule = {
        type = ruleType,
        value = value,
        silent = opts.silent ~= false,  -- default true
        hits = 0,
        created = os.time(),
    }
    table.insert(inst.rules, rule)
    return rule
end

function M.removeRule(inst, ruleType, value)
    for i, r in ipairs(inst.rules) do
        if r.type == ruleType and r.value == value then
            table.remove(inst.rules, i)
            return true
        end
    end
    return false
end

function M.clearRules(inst)
    inst.rules = {}
end

-- função chamada a cada remote interceptado
-- retorna { blocked=bool, silent=bool, reason=str } ou nil
function M.check(inst, data)
    -- 1. check spam tracking por SIGNATURE (mais específico que group)
    -- isso detecta "mesmo remote com mesmos primeiros args" — perfeito pra
    -- pegar updates periódicos de replica/timer que compartilham estrutura
    local key = signatureKey(data)
    local now = os.clock()
    local s = inst.spamStats[key]
    if not s then
        s = { count=0, windowStart=now, lastSeen=now,
              sample=data.remotePath, sampleData=data }
        inst.spamStats[key] = s
    end
    if now - s.windowStart > inst.config.windowSeconds then
        s.count = 0
        s.windowStart = now
    end
    s.count = s.count + 1
    s.lastSeen = now
    s.sampleData = data  -- sempre guarda mais recente pra preview
    local rate = s.count / math.max(0.1, now - s.windowStart)
    if rate > inst.config.autoBlockThreshold and not inst.suggestedBlocks[key] then
        inst.suggestedBlocks[key] = {
            sample = data.remotePath,
            sampleData = data,
            rate = rate,
            suggestedAt = now,
        }
    end

    -- 2. check rules
    for _, rule in ipairs(inst.rules) do
        local m = matchers[rule.type]
        if m and m(rule.value, data) then
            rule.hits = rule.hits + 1
            return {
                blocked = true,
                silent = rule.silent,
                reason = rule.type..":"..rule.value,
            }
        end
    end

    return nil
end

-- lista sugestões pendentes (pra UI mostrar)
function M.getSuggestions(inst)
    local list = {}
    for key, sug in pairs(inst.suggestedBlocks) do
        list[#list+1] = {
            signatureKey = key,
            sample = sug.sample,
            sampleData = sug.sampleData,
            rate = sug.rate,
        }
    end
    table.sort(list, function(a,b) return a.rate > b.rate end)
    return list
end

function M.acceptSuggestion(inst, signatureKeyValue, silent)
    M.addRule(inst, "signature", signatureKeyValue, { silent = silent ~= false })
    inst.suggestedBlocks[signatureKeyValue] = nil
end

function M.dismissSuggestion(inst, signatureKeyValue)
    inst.suggestedBlocks[signatureKeyValue] = nil
end

-- helpers expostos
M.groupKey = groupKey
M.signatureKey = signatureKey
M.nameShape = nameShape
M.parentPath = parentPath
M.leafName = leafName

return M

end)()

-- ═══════════════════════════════════════
-- módulo: scanner
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.scanner = (function()
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

end)()

-- ═══════════════════════════════════════
-- módulo: hooks
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.hooks = (function()
--[[
    RSP Hooks - camada de interceptação

    Estratégia: híbrida, seguindo o padrão SimpleSpy V3
      1) hookmetamethod(game, "__namecall") -> pega TODAS as chamadas
         method-call (remote:FireServer(...)) independente de cache.
      2) hookfunction nos protótipos de RemoteEvent/RemoteFunction/
         UnreliableRemoteEvent -> pega chamadas tipo remote.FireServer(remote, ...)
         que não passam por __namecall.

    Assim cobrimos TANTO method-call quanto cached-call.

    API:
      hooks.init(env, callback)
        env: tabela com funções do executor
        callback: função(data) chamada a cada chamada interceptada
      hooks.shutdown()  desfaz os hooks
      hooks.stats       tabela com contadores
]]

local M = {
    stats = { ns = 0, fs = 0, is = 0, ufs = 0, ce = 0, bind = 0, http = 0 },
    _installed = false,
    _originals = {},
}

-- deepclone preservando ref de Instance (evita race condition)
local function deepclone(v, seen)
    seen = seen or {}
    if type(v) ~= "table" then return v end
    if seen[v] then return seen[v] end
    local copy = {}
    seen[v] = copy
    for k, val in pairs(v) do
        copy[deepclone(k, seen)] = deepclone(val, seen)
    end
    return copy
end

-- detector de tabela cíclica (trava serializer)
local function isCyclic(t, seen)
    seen = seen or {}
    if type(t) ~= "table" then return false end
    if seen[t] then return true end
    seen[t] = true
    for _, v in pairs(t) do
        if type(v) == "table" and isCyclic(v, seen) then return true end
    end
    seen[t] = nil
    return false
end

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

-- detecta se o nome tem caracteres invisíveis (zero-width, controle, etc)
-- se tiver, retorna nome "amigável" em hex + flag
local function processName(name)
    if type(name) ~= "string" or name == "" then
        return "<empty>", true, ""
    end
    local isHidden = false
    local hex = {}
    for i = 1, #name do
        local b = string.byte(name, i)
        hex[i] = string.format("%02X", b)
        if b < 32 or b == 127 then isHidden = true end
    end
    -- heurística: zero-width chars em unicode (E2 80 8B..8F, etc)
    if name:find("[\194-\244]") then
        for i = 1, #name-1 do
            local a, b = string.byte(name, i), string.byte(name, i+1)
            if a == 0xE2 and b == 0x80 then isHidden = true; break end
            if a == 0xEF and b == 0xBB then isHidden = true; break end
        end
    end
    if isHidden then
        return string.format("<hidden:%s>", table.concat(hex)), true, table.concat(hex)
    end
    return name, false, table.concat(hex)
end

-- gera chave estável do remote (prefere DebugId se disponível)
local function stableKey(inst)
    local ok, dbgId = pcall(function() return game:GetDebugId(inst) end)
    if ok and dbgId then return dbgId end
    return safePath(inst)
end

function M.init(env, callback)
    if M._installed then return false, "já instalado" end
    M._installed = true

    local hookfunction     = env.hookfunction
    local hookmetamethod   = env.hookmetamethod
    local getnamecallmethod= env.getnamecallmethod
    local newcclosure      = env.newcclosure or function(f) return f end
    local checkcaller      = env.checkcaller or function() return false end
    local cloneref         = env.cloneref or function(x) return x end
    local getcallingscript = env.getcallingscript

    local IsA = game.IsA

    -- wrapper comum de log
    local function emit(method, self, args, metamethod)
        local cfg = env.config
        if not cfg or not cfg.enabled then return end
        if not cfg.logCheckCaller and checkcaller() then return end

        if isCyclic(args) then return end
        args = deepclone(args)

        local clsOk, cls = pcall(function() return self.ClassName end)
        if not clsOk then return end

        local remoteType
        if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
            remoteType = "RemoteEvent"
        elseif cls == "RemoteFunction" then
            remoteType = "RemoteFunction"
        else
            return
        end

        local src = nil
        if getcallingscript then
            local ok, s = pcall(getcallingscript)
            if ok and s then src = cloneref(s) end
        end

        local ln
        pcall(function()
            local info = debug.info(3, "l")
            ln = info
        end)

        if method == "FireServer" then M.stats.fs = M.stats.fs + 1
        elseif method == "InvokeServer" then M.stats.is = M.stats.is + 1 end
        if metamethod == "__namecall" then M.stats.ns = M.stats.ns + 1 end

        local rawName = self.Name
        local displayName, hiddenFlag, nameHex = processName(rawName)
        local key = stableKey(self)
        local path = safePath(self)

        local data = {
            type       = method,
            remoteType = cls,
            remote     = self,
            remoteName = displayName,
            remoteNameRaw = rawName,
            remoteNameHidden = hiddenFlag,
            remoteNameHex = nameHex,
            remoteKey  = key,
            remotePath = path,
            args       = args,
            argCount   = #args,
            callerScript = src,
            callerLine = ln,
            metamethod = metamethod,
        }

        -- isBlocked recebe data completa e retorna {blocked=bool, reason=str, silent=bool}
        local blockRes = nil
        if env.checkBlock then
            blockRes = env.checkBlock(data)
        end
        data.blocked = blockRes and blockRes.blocked or false
        data.blockReason = blockRes and blockRes.reason

        -- se é pra silenciar (não loga nem dispara), pula totalmente
        if blockRes and blockRes.silent then
            -- não loga, não dispara
            return "SILENT_BLOCK"
        end

        callback(data)
        return data.blocked and "BLOCK" or nil
    end

    -- ── MÉTODO 1: __namecall via hookmetamethod ──
    local namecallOk = false
    if hookmetamethod and getnamecallmethod then
        local oldNC
        local ok, err = pcall(function()
            oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    if typeof(self) == "Instance" then
                        local isRemote = false
                        pcall(function()
                            isRemote = IsA(self, "RemoteEvent")
                                or IsA(self, "RemoteFunction")
                                or IsA(self, "UnreliableRemoteEvent")
                        end)
                        if isRemote then
                            local args = {...}
                            local result = emit(method, self, args, "__namecall")
                            if result == "BLOCK" or result == "SILENT_BLOCK" then
                                if method == "InvokeServer" then return nil end
                                return
                            end
                        end
                    end
                end
                return oldNC(self, ...)
            end))
        end)
        if ok then
            M._originals.__namecall = oldNC
            namecallOk = true
        else
            warn("[RSP] __namecall hook falhou: "..tostring(err))
        end
    end

    -- ── MÉTODO 2: hookfunction nos protótipos ──
    -- (captura remote.FireServer(remote, ...) cached-call)
    if hookfunction then
        local function hookProto(className, methodName, key)
            local okCreate, temp = pcall(Instance.new, className)
            if not okCreate then return false end
            local orig = temp[methodName]
            temp:Destroy()
            local ok, err = pcall(function()
                M._originals[key] = hookfunction(orig, newcclosure(function(self, ...)
                    if typeof(self) == "Instance" then
                        local args = {...}
                        local result = emit(methodName, self, args, "hookfunction")
                        if result == "BLOCK" or result == "SILENT_BLOCK" then
                            if methodName == "InvokeServer" then return nil end
                            return
                        end
                    end
                    return M._originals[key](self, ...)
                end))
            end)
            if not ok then
                warn("[RSP] hookProto("..className..","..methodName..") falhou: "..tostring(err))
            end
            return ok
        end

        hookProto("RemoteEvent", "FireServer", "FireServer")
        hookProto("RemoteFunction", "InvokeServer", "InvokeServer")
        pcall(function()
            hookProto("UnreliableRemoteEvent", "FireServer", "UnreliableFireServer")
        end)
    end

    -- ── BÔNUS: OnClientEvent passivo (capta Server→Client) ──
    local patched = {}
    local function watchRE(obj)
        if typeof(obj) ~= "Instance" then return end
        local ok, isRE = pcall(function() return obj:IsA("RemoteEvent") end)
        if not ok or not isRE then return end
        if patched[obj] then return end
        patched[obj] = true
        pcall(function()
            obj.OnClientEvent:Connect(function(...)
                local cfg = env.config
                if not cfg or not cfg.enabled then return end
                if not cfg.logClientEvents then return end
                M.stats.ce = M.stats.ce + 1
                local args = {...}
                if isCyclic(args) then return end

                local rawName = obj.Name
                local displayName, hiddenFlag, nameHex = processName(rawName)
                local key = stableKey(obj)
                local path = safePath(obj)

                local data = {
                    type       = "OnClientEvent",
                    remoteType = "RemoteEvent",
                    remote     = obj,
                    remoteName = displayName,
                    remoteNameRaw = rawName,
                    remoteNameHidden = hiddenFlag,
                    remoteNameHex = nameHex,
                    remoteKey  = key,
                    remotePath = path,
                    args       = deepclone(args),
                    argCount   = #args,
                    metamethod = "passive",
                }
                local blockRes = env.checkBlock and env.checkBlock(data)
                if blockRes and blockRes.silent then return end
                data.blocked = blockRes and blockRes.blocked or false
                data.blockReason = blockRes and blockRes.reason
                callback(data)
            end)
        end)
    end
    task.spawn(function()
        pcall(function()
            for _, obj in ipairs(game:GetDescendants()) do watchRE(obj) end
        end)
        game.DescendantAdded:Connect(function(obj) task.defer(watchRE, obj) end)
    end)

    -- ── BINDABLE EVENT/FUNCTION ──
    -- captura comunicação interna do client (UI, hotkeys, sistemas internos)
    if hookfunction then
        local function hookBindable(className, methodName, resultType)
            local okCreate, temp = pcall(Instance.new, className)
            if not okCreate then return end
            local orig = temp[methodName]
            temp:Destroy()
            pcall(function()
                M._originals[className..methodName] = hookfunction(orig, newcclosure(function(self, ...)
                    local cfg = env.config
                    if typeof(self) ~= "Instance" or not cfg or not cfg.enabled then
                        return M._originals[className..methodName](self, ...)
                    end
                    if not cfg.logBindables then
                        return M._originals[className..methodName](self, ...)
                    end
                    local args = {...}
                    if not isCyclic(args) then
                        local rawName = self.Name
                        local displayName, hiddenFlag, nameHex = processName(rawName)
                        local data = {
                            type       = resultType,
                            remoteType = className,
                            remote     = self,
                            remoteName = displayName,
                            remoteNameRaw = rawName,
                            remoteNameHidden = hiddenFlag,
                            remoteNameHex = nameHex,
                            remoteKey  = stableKey(self),
                            remotePath = safePath(self),
                            args       = deepclone(args),
                            argCount   = #args,
                            metamethod = "hookfunction",
                        }
                        local blockRes = env.checkBlock and env.checkBlock(data)
                        if blockRes and blockRes.silent then
                            if methodName == "Invoke" then return nil end
                            return
                        end
                        data.blocked = blockRes and blockRes.blocked or false
                        M.stats.bind = (M.stats.bind or 0) + 1
                        callback(data)
                        if blockRes and blockRes.blocked then
                            if methodName == "Invoke" then return nil end
                            return
                        end
                    end
                    return M._originals[className..methodName](self, ...)
                end))
            end)
        end
        hookBindable("BindableEvent", "Fire", "BindableFire")
        hookBindable("BindableFunction", "Invoke", "BindableInvoke")
    end

    -- ── HTTP SPY ──
    -- captura requests externos (HttpService:GetAsync/PostAsync/RequestAsync)
    -- útil pra ver endpoints que o jogo chama (analytics, apis externas, etc)
    if hookfunction then
        local HttpService = game:GetService("HttpService")
        local function hookHttp(methodName)
            local orig = HttpService[methodName]
            if type(orig) ~= "function" then return end
            pcall(function()
                M._originals["http_"..methodName] = hookfunction(orig, newcclosure(function(self, ...)
                    local cfg = env.config
                    if typeof(self) ~= "Instance" or not cfg or not cfg.enabled or not cfg.logHttp then
                        return M._originals["http_"..methodName](self, ...)
                    end
                    local args = {...}
                    if not isCyclic(args) then
                        local url = "?"
                        if methodName == "RequestAsync" and type(args[1]) == "table" then
                            url = tostring(args[1].Url or "?")
                        elseif type(args[1]) == "string" then
                            url = args[1]
                        end
                        local data = {
                            type       = "Http_"..methodName,
                            remoteType = "HttpService",
                            remote     = self,
                            remoteName = methodName,
                            remoteNameRaw = methodName,
                            remoteNameHidden = false,
                            remoteKey  = "http_"..methodName,
                            remotePath = "HttpService."..methodName.." → "..(#url > 80 and url:sub(1,77).."..." or url),
                            args       = deepclone(args),
                            argCount   = #args,
                            metamethod = "hookfunction",
                        }
                        local blockRes = env.checkBlock and env.checkBlock(data)
                        if blockRes and blockRes.silent then return end
                        data.blocked = blockRes and blockRes.blocked or false
                        M.stats.http = (M.stats.http or 0) + 1
                        callback(data)
                    end
                    return M._originals["http_"..methodName](self, ...)
                end))
            end)
        end
        hookHttp("GetAsync")
        hookHttp("PostAsync")
        hookHttp("RequestAsync")
    end

    return true
end

function M.shutdown()
    -- Nota: desfazer hookfunction/hookmetamethod requer re-aplicar os originais
    -- como hook, o que nem todo executor suporta. Default: apenas desabilita via flag.
    M._installed = false
end

return M

end)()

-- ═══════════════════════════════════════
-- módulo: ui
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.ui = (function()
--[[
    RSP UI - interface com pool virtual (renderiza só ~20 itens),
    painel de detalhes com script Lua executável gerado pelo serializer,
    filtro, stats, blacklist, config.
]]

local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local M = {}

local GETNIL_HELPER = "local function getNil(name, class)\n    for _, v in next, getnilinstances() do\n        if v.ClassName == class and v.Name == name then return v end\n    end\nend\n\n"

local C = {
    BG       = Color3.fromRGB(13,13,18),
    Surface  = Color3.fromRGB(20,20,28),
    Panel    = Color3.fromRGB(26,26,36),
    PanelH   = Color3.fromRGB(32,32,44),
    Border   = Color3.fromRGB(42,42,58),
    Accent   = Color3.fromRGB(90,170,255),
    AccentD  = Color3.fromRGB(55,110,200),
    Success  = Color3.fromRGB(72,210,110),
    Warning  = Color3.fromRGB(255,185,55),
    Error    = Color3.fromRGB(255,72,72),
    Text     = Color3.fromRGB(220,220,235),
    TextD    = Color3.fromRGB(140,140,165),
    TextM    = Color3.fromRGB(80,80,100),

    FireServer         = Color3.fromRGB(90,170,255),
    InvokeServer       = Color3.fromRGB(175,115,255),
    OnClientEvent      = Color3.fromRGB(72,210,130),
}

local function typeColor(t) return C[t] or C.Accent end

-- construtores mínimos
local function N(cls, props, kids)
    local o = Instance.new(cls)
    if props then for k,v in pairs(props) do o[k]=v end end
    if kids then for _,k in ipairs(kids) do k.Parent = o end end
    return o
end
local function Rnd(r) return N("UICorner",{CornerRadius=UDim.new(0,r)}) end
local function Pad(y,x) return N("UIPadding",{
    PaddingTop=UDim.new(0,y), PaddingBottom=UDim.new(0,y),
    PaddingLeft=UDim.new(0,x), PaddingRight=UDim.new(0,x)}) end
local function Lbl(t,s,c,f,p)
    local l=N("TextLabel",{Text=t,TextSize=s,TextColor3=c,Font=f or Enum.Font.Gotham,
        BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center})
    if p then for k,v in pairs(p) do l[k]=v end end
    return l
end
local function Btn(t,s,p,extra)
    local b=N("TextButton",{Text=t,TextSize=s,TextColor3=C.Text,Font=Enum.Font.GothamMedium,
        BackgroundColor3=C.Panel, BorderSizePixel=0, AutoButtonColor=true})
    if p then for k,v in pairs(p) do b[k]=v end end
    if extra then for _,e in ipairs(extra) do e.Parent=b end end
    return b
end

local ITEM_H = 42
local ITEM_S = 45
local POOL_N = 20

function M.build(state)
    -- state: { config, logs, blocked, stats, serializer, env, hookStats, onBlock, onUnblock, onClear }

    -- destruir anterior
    local parent = (gethui and gethui()) or CoreGui
    pcall(function()
        local old = parent:FindFirstChild("RSP_ProV4")
        if old then old:Destroy() end
    end)

    local Gui = N("ScreenGui",{Name="RSP_ProV4", ResetOnSpawn=false, IgnoreGuiInset=true,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=parent})

    local WIN_W, WIN_H = 880, 560

    local Win = N("Frame",{Size=UDim2.new(0,WIN_W,0,WIN_H),
        Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2),
        BackgroundColor3=C.BG, BorderSizePixel=0, Parent=Gui},{
        Rnd(8),
        N("UIStroke",{Color=C.Border,Thickness=1}),
    })

    -- ── HEADER ──
    local HDR = N("Frame",{Size=UDim2.new(1,0,0,42),BackgroundColor3=C.Surface,
        BorderSizePixel=0, Parent=Win},{Rnd(8), Pad(0,14)})
    N("Frame",{Size=UDim2.new(1,0,0,10),Position=UDim2.new(0,0,1,-10),
        BackgroundColor3=C.Surface, BorderSizePixel=0, Parent=HDR})

    Lbl("🔍 Remote Spy Pro", 15, C.Text, Enum.Font.GothamBold, {
        Size=UDim2.new(0,200,1,0), Parent=HDR})
    local StatusLbl = Lbl("● ativo", 11, C.Success, Enum.Font.GothamMedium, {
        Size=UDim2.new(0,80,1,0), Position=UDim2.new(0,200,0,0), Parent=HDR})

    local execTag = Lbl(state.env.Name.." | "..(state.env.hookMode or "?"),
        10, C.TextD, Enum.Font.Gotham, {
        Size=UDim2.new(0,260,1,0), Position=UDim2.new(0,290,0,0),
        TextXAlignment=Enum.TextXAlignment.Right, Parent=HDR})

    local CloseBtn = Btn("✕", 14, {Size=UDim2.new(0,28,0,28),
        Position=UDim2.new(1,-34,0.5,-14), BackgroundColor3=C.Panel,
        TextColor3=C.Error, Parent=HDR}, {Rnd(6)})

    -- ── TABS ──
    local TABS = N("Frame",{Size=UDim2.new(1,-24,0,32),Position=UDim2.new(0,12,0,50),
        BackgroundTransparency=1, Parent=Win},{
        N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
            Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder})})

    local tabs, tabContents, currentTab = {}, {}, nil
    local function mkTab(name, order)
        local b = Btn(name, 12, {Size=UDim2.new(0,98,1,0),BackgroundColor3=C.Surface,
            TextColor3=C.TextD, LayoutOrder=order, Parent=TABS}, {Rnd(6)})
        tabs[name] = b
        tabContents[name] = N("Frame",{Size=UDim2.new(1,-24,1,-94),
            Position=UDim2.new(0,12,0,86), BackgroundColor3=C.Surface,
            BorderSizePixel=0, Visible=false, Parent=Win},{Rnd(8)})
        b.MouseButton1Click:Connect(function()
            if currentTab then
                tabs[currentTab].BackgroundColor3 = C.Surface
                tabs[currentTab].TextColor3 = C.TextD
                tabContents[currentTab].Visible = false
            end
            b.BackgroundColor3 = C.Accent
            b.TextColor3 = C.BG
            tabContents[name].Visible = true
            currentTab = name
        end)
    end
    mkTab("Logs", 1)
    mkTab("Blocked", 2)
    mkTab("Scanner", 3)
    mkTab("Config", 4)

    -- ╔══════════════════════════════════════╗
    -- ║           ABA LOGS                   ║
    -- ╚══════════════════════════════════════╝
    local LogTab = tabContents["Logs"]

    local TopBar = N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,
        Parent=LogTab}, {Pad(0,12)})
    local SearchBox = N("TextBox",{Size=UDim2.new(0,250,0,26),
        Position=UDim2.new(0,0,0.5,-13), BackgroundColor3=C.Panel,
        BorderSizePixel=0, PlaceholderText="🔍 filtrar por nome ou path",
        Text="", TextColor3=C.Text, PlaceholderColor3=C.TextD,
        TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left,
        ClearTextOnFocus=false, Parent=TopBar}, {Rnd(5), Pad(0,8)})

    local CountLbl = Lbl("0 logs", 11, C.TextD, Enum.Font.Gotham, {
        Size=UDim2.new(0,120,0,26), Position=UDim2.new(0,260,0.5,-13), Parent=TopBar})

    local ExportBtn = Btn("📤 Exportar", 11, {Size=UDim2.new(0,94,0,26),
        Position=UDim2.new(1,-188,0.5,-13),
        BackgroundColor3=C.AccentD, Parent=TopBar}, {Rnd(5)})

    local ClearBtn = Btn("🗑 Limpar", 11, {Size=UDim2.new(0,80,0,26),
        Position=UDim2.new(1,-88,0.5,-13),
        BackgroundColor3=Color3.fromRGB(50,18,18), TextColor3=C.Error,
        Parent=TopBar}, {Rnd(5)})

    -- split: lista | detalhes
    local Split = N("Frame",{Size=UDim2.new(1,-24,1,-48),Position=UDim2.new(0,12,0,40),
        BackgroundTransparency=1, Parent=LogTab})

    local LIST_W = 340
    local ListPanel = N("Frame",{Size=UDim2.new(0,LIST_W,1,0),
        BackgroundTransparency=1, Parent=Split})
    local LogScroll = N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=C.Border, CanvasSize=UDim2.new(0,0,0,0),
        Parent=ListPanel})
    local LogInner = N("Frame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, Parent=LogScroll})

    -- pool virtual
    local pool = {}
    for i=1,POOL_N do
        local item = N("Frame",{Size=UDim2.new(1,-6,0,ITEM_H),
            BackgroundColor3=C.Panel, BorderSizePixel=0, Visible=false,
            Parent=LogInner},{Rnd(5)})
        local bar = N("Frame",{Size=UDim2.new(0,3,1,-8),
            Position=UDim2.new(0,0,0,4), BackgroundColor3=C.Accent,
            BorderSizePixel=0, Parent=item},{Rnd(2)})
        local tagBg = N("Frame",{Size=UDim2.new(0,74,0,16),
            Position=UDim2.new(0,8,0,6), BackgroundColor3=C.BG,
            BorderSizePixel=0, Parent=item},{Rnd(4)})
        local tagLbl = Lbl("",9,C.Accent,Enum.Font.GothamBold,{
            Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center,
            Parent=tagBg})
        local nameLbl = Lbl("",12,C.Text,Enum.Font.GothamMedium,{
            Size=UDim2.new(1,-150,0,16),Position=UDim2.new(0,90,0,4),
            TextTruncate=Enum.TextTruncate.AtEnd, Parent=item})
        local argsLbl = Lbl("",10,C.TextD,Enum.Font.Code,{
            Size=UDim2.new(1,-100,0,14),Position=UDim2.new(0,90,0,22),
            TextTruncate=Enum.TextTruncate.AtEnd, Parent=item})
        local timeLbl = Lbl("",9,C.TextM,Enum.Font.Gotham,{
            Size=UDim2.new(0,54,0,14),Position=UDim2.new(1,-58,0,6),
            TextXAlignment=Enum.TextXAlignment.Right, Parent=item})
        local click = N("TextButton",{Text="",Size=UDim2.new(1,0,1,0),
            BackgroundTransparency=1, Parent=item})
        pool[i] = {item=item,bar=bar,tagBg=tagBg,tagLbl=tagLbl,
            nameLbl=nameLbl,argsLbl=argsLbl,timeLbl=timeLbl,click=click,log=nil}
    end

    local filtered = {}
    local selected = nil
    local showDetail -- forward

    -- ── SCROLL INTELIGENTE ──
    -- userScrolled: usuário subiu manualmente, pausa auto-scroll
    -- pendingNew: quantos logs novos chegaram enquanto estava pausado
    local userScrolled = false
    local pendingNew = 0
    local SCROLL_THRESHOLD = 30  -- px do fundo pra considerar "no fundo"

    -- botão flutuante "⬇ Ir pro final (N novos)"
    local JumpBtn = N("TextButton",{
        Text = "⬇ Ir pro final", TextSize = 11, TextColor3 = C.BG,
        Font = Enum.Font.GothamBold, BackgroundColor3 = C.Accent,
        BorderSizePixel = 0, Size = UDim2.new(0,150,0,28),
        Position = UDim2.new(1,-164,1,-38),  -- canto inferior direito do ListPanel
        Visible = false, AutoButtonColor = true, ZIndex = 5,
        Parent = ListPanel},{Rnd(14)})
    JumpBtn.MouseButton1Click:Connect(function()
        userScrolled = false
        pendingNew = 0
        JumpBtn.Visible = false
        local h = math.max(0, #filtered * ITEM_S)
        LogScroll.CanvasSize = UDim2.new(0,0,0,h)
        local vis = LogScroll.AbsoluteSize.Y
        LogScroll.CanvasPosition = Vector2.new(0, math.max(0, h-vis))
    end)

    -- detectar se usuário saiu do fundo
    local function isAtBottom()
        local h = LogScroll.CanvasSize.Y.Offset
        local vis = LogScroll.AbsoluteSize.Y
        local y = LogScroll.CanvasPosition.Y
        if h <= vis then return true end  -- ainda cabe tudo na tela
        return (h - vis - y) <= SCROLL_THRESHOLD
    end

    local function logMatchesBlockRule(log)
        for _, r in ipairs(state.blocker.rules) do
            if r.type == "exact" and r.value == log.remotePath then return true end
            if r.type == "group" and state.blockerLib.groupKey(log) == r.value then return true end
            if r.type == "signature" and state.blockerLib.signatureKey(log) == r.value then return true end
            if r.type == "wildcard" then
                local pat = r.value:gsub("([%(%)%[%]%+%-%^%$%?%.])", "%%%1"):gsub("%%%*", ".-")
                if log.remotePath:match("^"..pat.."$") then return true end
            end
            if r.type == "pattern" then
                local ok, res = pcall(string.find, log.remotePath, r.value)
                if ok and res then return true end
            end
        end
        return false
    end

    local function rebuildFiltered()
        filtered = {}
        local f = state.config.filter or ""
        local hide = state.config.hideBlocked
        for _, log in ipairs(state.logs) do
            if hide and logMatchesBlockRule(log) then
                -- pula: bloqueado e usuário quer esconder
            elseif f == "" or
               (log.remoteName or ""):lower():find(f,1,true) or
               (log.remotePath or ""):lower():find(f,1,true) or
               (log.type or ""):lower():find(f,1,true) or
               (log.remoteNameRaw or ""):lower():find(f,1,true) then
                filtered[#filtered+1] = log
            end
        end
    end

    local function renderList()
        local total = #filtered
        local canvasH = math.max(0, total * ITEM_S)
        if LogScroll.CanvasSize.Y.Offset ~= canvasH then
            LogScroll.CanvasSize = UDim2.new(0,0,0,canvasH)
        end
        local firstIdx = math.max(1, math.floor(LogScroll.CanvasPosition.Y / ITEM_S))
        for slot=1, POOL_N do
            local idx = firstIdx + slot - 1
            local pi = pool[slot]
            if idx > total then
                pi.item.Visible = false; pi.log = nil
            else
                local log = filtered[idx]
                local clr = typeColor(log.type)
                pi.log = log
                pi.item.Visible = true
                pi.item.Position = UDim2.new(0,3,0,(idx-1)*ITEM_S)
                local isBlocked = log.blocked or logMatchesBlockRule(log)
                pi.bar.BackgroundColor3 = isBlocked and C.Error or clr
                pi.tagLbl.TextColor3 = clr
                pi.tagLbl.Text = log.type or ""
                -- se nome escondido (hex), mostra em amarelo pra destacar
                if log.remoteNameHidden then
                    pi.nameLbl.Text = "⚠ "..(log.remoteName or "?")
                    pi.nameLbl.TextColor3 = isBlocked and C.Error or C.Warning
                else
                    pi.nameLbl.Text = log.remoteName or "?"
                    pi.nameLbl.TextColor3 = isBlocked and C.Error or C.Text
                end
                pi.argsLbl.Text = log.argsPreview or ""
                pi.timeLbl.Text = log.timestamp or ""
                pi.item.BackgroundColor3 = (selected == log) and C.PanelH or C.Panel
            end
        end
    end

    LogScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        renderList()
        -- atualizar estado de scroll: se voltou pro fundo, retoma auto-scroll
        if isAtBottom() then
            if userScrolled then
                userScrolled = false
                pendingNew = 0
                JumpBtn.Visible = false
            end
        else
            userScrolled = true
        end
    end)

    for _, pi in ipairs(pool) do
        pi.click.MouseButton1Click:Connect(function()
            if pi.log then
                selected = pi.log
                renderList()
                showDetail(pi.log)
            end
        end)
        pi.item.MouseEnter:Connect(function()
            if pi.log and selected ~= pi.log then
                pi.item.BackgroundColor3 = C.PanelH
            end
        end)
        pi.item.MouseLeave:Connect(function()
            if pi.log and selected ~= pi.log then
                pi.item.BackgroundColor3 = C.Panel
            end
        end)
    end

    -- painel de detalhes
    local DetailPanel = N("Frame",{Size=UDim2.new(1,-LIST_W-8,1,0),
        Position=UDim2.new(0,LIST_W+8,0,0), BackgroundColor3=C.Panel,
        BorderSizePixel=0, Parent=Split}, {Rnd(6)})

    local DTopBar = N("Frame",{Size=UDim2.new(1,-16,0,32),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, Parent=DetailPanel})

    local DTypeLbl = Lbl("", 13, C.Accent, Enum.Font.GothamBold, {
        Size=UDim2.new(0.5,0,1,0), Parent=DTopBar})
    local DMetaLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0),
        TextXAlignment=Enum.TextXAlignment.Right, Parent=DTopBar})

    local DInfoFrame = N("Frame",{Size=UDim2.new(1,-16,0,66),
        Position=UDim2.new(0,8,0,42), BackgroundColor3=C.BG,
        BorderSizePixel=0, Parent=DetailPanel}, {Rnd(5), Pad(4,8)})
    local DPathLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(1,0,0,14), Parent=DInfoFrame})
    local DScriptLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,16), Parent=DInfoFrame})
    local DTimeLbl = Lbl("", 10, C.TextM, Enum.Font.Gotham, {
        Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,32), Parent=DInfoFrame})
    -- preview da signature (mostra exatamente o que o botão "Padrão" vai bloquear)
    local DSigLbl = Lbl("", 9, Color3.fromRGB(255,130,220), Enum.Font.Code, {
        Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,48),
        TextTruncate=Enum.TextTruncate.AtEnd, Parent=DInfoFrame})

    -- code box: altura considera info frame (66+42=108) e 2 rows de botões (70+16)
    local CodeContainer = N("Frame",{Size=UDim2.new(1,-16,1,-210),
        Position=UDim2.new(0,8,0,116), BackgroundColor3=C.BG,
        BorderSizePixel=0, Parent=DetailPanel}, {Rnd(5)})
    local CodeScroll = N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=C.Border, CanvasSize=UDim2.new(0,0,0,0),
        Parent=CodeContainer})
    local CodeBox = N("TextLabel",{Text="-- Selecione um log para ver o script gerado",
        TextSize=11, Font=Enum.Font.Code, TextColor3=C.Text,
        BackgroundTransparency=1, Size=UDim2.new(1,-16,0,400),
        Position=UDim2.new(0,8,0,6), TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top, TextWrapped=false,
        Parent=CodeScroll})

    -- ações: 2 linhas com UIListLayout (não usa position fixa = sem sobreposição)
    local ActBar = N("Frame",{Size=UDim2.new(1,-16,0,70),
        Position=UDim2.new(0,8,1,-78), BackgroundTransparency=1, Parent=DetailPanel})

    local Row1 = N("Frame",{Size=UDim2.new(1,0,0,30),
        Position=UDim2.new(0,0,0,0), BackgroundTransparency=1, Parent=ActBar},{
        N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
            Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder})})
    local Row2 = N("Frame",{Size=UDim2.new(1,0,0,30),
        Position=UDim2.new(0,0,0,36), BackgroundTransparency=1, Parent=ActBar},{
        N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
            Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder})})

    -- LINHA 1: cópia + executar (sempre à direita do lado)
    local CopyScriptBtn = Btn("📋 Copiar Script", 11, {Size=UDim2.new(0,130,1,0),
        BackgroundColor3=C.AccentD, LayoutOrder=1, Parent=Row1}, {Rnd(5)})
    local CopyPathBtn = Btn("📝 Path", 11, {Size=UDim2.new(0,70,1,0),
        BackgroundColor3=C.Panel, LayoutOrder=2, Parent=Row1}, {Rnd(5)})
    local CopyArgsBtn = Btn("📦 Args", 11, {Size=UDim2.new(0,70,1,0),
        BackgroundColor3=C.Panel, LayoutOrder=3, Parent=Row1}, {Rnd(5)})
    local RunBtn = Btn("▶ Executar", 11, {Size=UDim2.new(0,100,1,0),
        BackgroundColor3=Color3.fromRGB(25,70,35), TextColor3=C.Success,
        LayoutOrder=4, Parent=Row1}, {Rnd(5)})

    -- LINHA 2: bloqueios (4 tipos, ordem de especificidade)
    local BlockExactBtn = Btn("🚫 Path", 10, {Size=UDim2.new(0,70,1,0),
        BackgroundColor3=Color3.fromRGB(50,18,18), TextColor3=C.Error,
        LayoutOrder=1, Parent=Row2}, {Rnd(5)})
    local BlockSigBtn = Btn("🚫 Padrão (spam)", 10, {Size=UDim2.new(0,130,1,0),
        BackgroundColor3=Color3.fromRGB(60,18,45), TextColor3=Color3.fromRGB(255,130,220),
        LayoutOrder=2, Parent=Row2}, {Rnd(5)})
    local BlockGroupBtn = Btn("🚫 Grupo", 10, {Size=UDim2.new(0,76,1,0),
        BackgroundColor3=Color3.fromRGB(60,30,18), TextColor3=Color3.fromRGB(255,180,120),
        LayoutOrder=3, Parent=Row2}, {Rnd(5)})
    local BlockWildBtn = Btn("🚫 Pasta", 10, {Size=UDim2.new(0,76,1,0),
        BackgroundColor3=Color3.fromRGB(55,30,55), TextColor3=Color3.fromRGB(230,150,230),
        LayoutOrder=4, Parent=Row2}, {Rnd(5)})
    local RunBtn = Btn("▶ Executar", 11, {Size=UDim2.new(0,94,1,0),
        Position=UDim2.new(1,-96,0,0), BackgroundColor3=Color3.fromRGB(25,70,35),
        TextColor3=C.Success, Parent=ActBar}, {Rnd(5)})

    local currentLog = nil
    local currentScript = ""

    showDetail = function(log)
        if not log then return end
        currentLog = log
        local clr = typeColor(log.type)
        DTypeLbl.Text = log.type or "?"
        DTypeLbl.TextColor3 = clr
        DMetaLbl.Text = log.metamethod or ""
        DPathLbl.Text = "📁 "..(log.remotePath or "?")
        local srcTxt = "📜 "
        if log.callerScript then
            local ok, p = pcall(function() return log.callerScript:GetFullName() end)
            srcTxt = srcTxt..(ok and p or tostring(log.callerScript))
            if log.callerLine then srcTxt = srcTxt..":"..log.callerLine end
        else
            srcTxt = srcTxt.."(script não disponível)"
        end
        DScriptLbl.Text = srcTxt
        local timeTxt = "⏰ "..(log.timestamp or "?").."  |  args: "..(log.argCount or 0)
        if log.remoteNameHidden then
            timeTxt = timeTxt.."  |  ⚠ nome hex: "..(log.remoteNameHex or "")
            DTimeLbl.TextColor3 = C.Warning
        else
            DTimeLbl.TextColor3 = C.TextM
        end
        DTimeLbl.Text = timeTxt

        -- mostra o padrão (signature) que o botão "🚫 Padrão" bloqueia
        local sigPreview = state.blockerLib.signatureKey(log)
        DSigLbl.Text = "🔖 padrão: "..sigPreview

        -- gerar script
        CodeBox.Text = "-- gerando..."
        task.spawn(function()
            local okGen, code, needNil = pcall(state.serializer.encode, log.args or {})
            if not okGen then
                currentScript = "-- erro ao gerar script:\n-- "..tostring(code)
            else
                local header = string.format("-- [RSP] %s  [%s via %s]\n-- Path: %s\n\n",
                    log.timestamp or "?", log.type or "?", log.metamethod or "?",
                    log.remotePath or "?")
                if needNil then header = header..GETNIL_HELPER end

                local pathCode = string.format('game:GetService("%s")',
                    log.remote and log.remote:FindFirstAncestorOfClass("Workspace") and "Workspace"
                    or "ReplicatedStorage")
                local okP, pathExact = pcall(state.serializer.encodeSingle, log.remote)
                if okP and pathExact then pathCode = pathExact end

                local call
                if log.type == "FireServer" then
                    call = pathCode..":FireServer(unpack(args))"
                elseif log.type == "InvokeServer" then
                    call = "local returned = "..pathCode..":InvokeServer(unpack(args))"
                elseif log.type == "OnClientEvent" then
                    -- gera firesignal pra simular recepção no cliente (útil pra testar UI)
                    call = "-- replay no cliente (requer executor com firesignal):\n"
                        .."-- firesignal("..pathCode..".OnClientEvent, unpack(args))\n"
                        .."-- ou conectar listener:\n"
                        .."-- "..pathCode..".OnClientEvent:Connect(function(...) print(...) end)"
                elseif log.type == "BindableFire" then
                    call = "-- simula Fire do BindableEvent (comunicação interna):\n"
                        ..pathCode..":Fire(unpack(args))"
                elseif log.type == "BindableInvoke" then
                    call = "-- simula Invoke do BindableFunction:\n"
                        .."local returned = "..pathCode..":Invoke(unpack(args))"
                elseif log.type and log.type:find("^Http_") then
                    local method = log.type:sub(6)
                    call = string.format(
                        "-- chamada HTTP interceptada:\n"..
                        "local result = game:GetService(\"HttpService\"):%s(unpack(args))",
                        method)
                else
                    call = "-- (tipo desconhecido)"
                end
                currentScript = header..code.."\n\n"..call
            end
            CodeBox.Text = currentScript
            local lines = 1
            for _ in currentScript:gmatch("\n") do lines = lines + 1 end
            local h = math.max(400, lines * 14)
            CodeBox.Size = UDim2.new(1,-16,0,h)
            CodeScroll.CanvasSize = UDim2.new(0,0,0,h+12)
            CodeScroll.CanvasPosition = Vector2.new(0,0)
        end)

        -- atualizar estado dos botões de bloqueio
        if logMatchesBlockRule(log) then
            DTypeLbl.Text = (log.type or "?").." [BLOCKED]"
            DTypeLbl.TextColor3 = C.Error
        end
    end

    CopyScriptBtn.MouseButton1Click:Connect(function()
        if not currentLog or currentScript == "" then return end
        if state.env.setclipboard then
            state.env.setclipboard(currentScript)
            CopyScriptBtn.Text = "✅!"
            task.delay(1.2, function() CopyScriptBtn.Text = "📋 Copiar" end)
        end
    end)

    CopyPathBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        if state.env.setclipboard then
            local p = currentLog.remotePath or ""
            if currentLog.remoteNameHidden then
                p = p.."\n-- nome hex: "..(currentLog.remoteNameHex or "")
            end
            state.env.setclipboard(p)
            CopyPathBtn.Text = "✅!"
            task.delay(1.2, function() CopyPathBtn.Text = "📝 Path" end)
        end
    end)

    -- copiar só os args serializados
    CopyArgsBtn.MouseButton1Click:Connect(function()
        if not currentLog or not state.env.setclipboard then return end
        local ok, code = pcall(state.serializer.encode, currentLog.args or {})
        if ok then
            state.env.setclipboard(code)
            CopyArgsBtn.Text = "✅!"
            task.delay(1.2, function() CopyArgsBtn.Text = "📦 Args" end)
        end
    end)

    -- Bloqueio exato (path literal)
    BlockExactBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        local path = currentLog.remotePath
        local removed = state.blockerLib.removeRule(state.blocker, "exact", path)
        if not removed then
            state.blockerLib.addRule(state.blocker, "exact", path, {silent = state.config.hideBlocked})
            BlockExactBtn.Text = "✅ Path"
        else
            BlockExactBtn.Text = "🚫 Path"
        end
        if uiApi then pcall(uiApi.rebuild) end
        task.delay(1.5, function() BlockExactBtn.Text = "🚫 Path" end)
    end)

    -- Bloqueio por SIGNATURE (mesmos args primitivos) — o mais poderoso
    -- Exemplo: bloqueia todos os FireServer(970, {"Items","InUse"}, ...) de uma vez
    BlockSigBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        local sk = state.blockerLib.signatureKey(currentLog)
        local removed = state.blockerLib.removeRule(state.blocker, "signature", sk)
        if not removed then
            state.blockerLib.addRule(state.blocker, "signature", sk, {silent = state.config.hideBlocked})
            BlockSigBtn.Text = "✅ Padrão bloqueado"
        else
            BlockSigBtn.Text = "🚫 Padrão (spam)"
        end
        if uiApi then pcall(uiApi.rebuild) end
        task.delay(1.5, function() BlockSigBtn.Text = "🚫 Padrão (spam)" end)
    end)

    -- Bloqueio por grupo (mesmo parent + shape do nome — pega mutações de nome)
    BlockGroupBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        local gk = state.blockerLib.groupKey(currentLog)
        local removed = state.blockerLib.removeRule(state.blocker, "group", gk)
        if not removed then
            state.blockerLib.addRule(state.blocker, "group", gk, {silent = state.config.hideBlocked})
            BlockGroupBtn.Text = "✅ Grupo"
        else
            BlockGroupBtn.Text = "🚫 Grupo"
        end
        if uiApi then pcall(uiApi.rebuild) end
        task.delay(1.5, function() BlockGroupBtn.Text = "🚫 Grupo" end)
    end)

    -- Bloqueio por pasta (wildcard pai.*)
    BlockWildBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        local parent = state.blockerLib.parentPath(currentLog.remotePath)
        local wild = parent..".*"
        local removed = state.blockerLib.removeRule(state.blocker, "wildcard", wild)
        if not removed then
            state.blockerLib.addRule(state.blocker, "wildcard", wild, {silent = state.config.hideBlocked})
            BlockWildBtn.Text = "✅ Pasta"
        else
            BlockWildBtn.Text = "🚫 Pasta"
        end
        if uiApi then pcall(uiApi.rebuild) end
        task.delay(1.5, function() BlockWildBtn.Text = "🚫 Pasta" end)
    end)

    RunBtn.MouseButton1Click:Connect(function()
        if not currentLog or not currentLog.remote then return end
        RunBtn.Text = "..."
        task.spawn(function()
            local ok, err = pcall(function()
                if currentLog.type == "FireServer" then
                    currentLog.remote:FireServer(unpack(currentLog.args))
                elseif currentLog.type == "InvokeServer" then
                    currentLog.remote:InvokeServer(unpack(currentLog.args))
                end
            end)
            RunBtn.Text = ok and "✓ OK" or "✗ Erro"
            task.delay(1.5, function() RunBtn.Text = "▶ Executar" end)
        end)
    end)

    ClearBtn.MouseButton1Click:Connect(function()
        table.clear(state.logs)
        selected = nil
        currentLog = nil
        filtered = {}
        userScrolled = false
        pendingNew = 0
        JumpBtn.Visible = false
        LogScroll.CanvasSize = UDim2.new(0,0,0,0)
        LogScroll.CanvasPosition = Vector2.new(0,0)
        for _, p in ipairs(pool) do p.item.Visible = false; p.log = nil end
        CountLbl.Text = "0 logs"
        CodeBox.Text = "-- logs limpos"
    end)

    -- Export: gera script Lua completo com TODOS os logs visíveis
    -- (respeita filtro atual, mas inclui bloqueados se hideBlocked=false)
    ExportBtn.MouseButton1Click:Connect(function()
        if not state.env.setclipboard then
            ExportBtn.Text = "❌ sem clipboard"
            task.delay(2, function() ExportBtn.Text = "📤 Exportar" end)
            return
        end
        ExportBtn.Text = "⏳ gerando..."
        task.spawn(function()
            local parts = {}
            parts[#parts+1] = "-- Remote Spy Pro - Export"
            parts[#parts+1] = "-- Total: "..#filtered.." logs"
            parts[#parts+1] = "-- Gerado em: "..os.date("%Y-%m-%d %H:%M:%S")
            parts[#parts+1] = ""
            local needGetNilGlobal = false
            local chunks = {}
            for _, log in ipairs(filtered) do
                local okGen, code, needNil = pcall(state.serializer.encode, log.args or {})
                if okGen then
                    if needNil then needGetNilGlobal = true end
                    local header = string.format(
                        "\n-- [%d] %s  %s  [%s]\n-- path: %s",
                        #chunks+1, log.timestamp or "?", log.type or "?",
                        log.metamethod or "?", log.remotePath or "?")
                    if log.remoteNameHidden then
                        header = header.."\n-- ⚠ nome hex: "..(log.remoteNameHex or "")
                    end
                    chunks[#chunks+1] = header.."\n"..code
                end
            end
            if needGetNilGlobal then
                parts[#parts+1] = "local function getNil(name, class)"
                parts[#parts+1] = "    for _, v in next, getnilinstances() do"
                parts[#parts+1] = "        if v.ClassName == class and v.Name == name then return v end"
                parts[#parts+1] = "    end"
                parts[#parts+1] = "end"
                parts[#parts+1] = ""
            end
            for _, c in ipairs(chunks) do parts[#parts+1] = c end
            local out = table.concat(parts, "\n")

            -- tenta salvar em arquivo se executor suporta
            local savedToFile = false
            if writefile then
                local fname = "RemoteSpy_Export_"..os.time()..".lua"
                local ok = pcall(writefile, fname, out)
                if ok then savedToFile = fname end
            end

            state.env.setclipboard(out)
            if savedToFile then
                ExportBtn.Text = "✅ "..savedToFile
            else
                ExportBtn.Text = "✅ no clipboard"
            end
            task.delay(3, function() ExportBtn.Text = "📤 Exportar" end)
        end)
    end)

    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        state.config.filter = SearchBox.Text:lower()
        rebuildFiltered()
        CountLbl.Text = #filtered.." logs"
        LogScroll.CanvasPosition = Vector2.new(0,0)
        renderList()
    end)

    -- ╔══════════════════════════════════════╗
    -- ║          ABA BLOCKED                 ║
    -- ╚══════════════════════════════════════╝
    local BlkTab = tabContents["Blocked"]
    local BlkScroll = N("ScrollingFrame",{Size=UDim2.new(1,-16,1,-16),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=4, ScrollBarImageColor3=C.Border,
        CanvasSize=UDim2.new(0,0,0,0), Parent=BlkTab})
    local BlkList = N("Frame",{Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1, Parent=BlkScroll},{
        N("UIListLayout",{Padding=UDim.new(0,4), SortOrder=Enum.SortOrder.LayoutOrder}),
        Pad(4,4)})
    local blkLayout = BlkList:FindFirstChildOfClass("UIListLayout")
    blkLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        BlkScroll.CanvasSize = UDim2.new(0,0,0,blkLayout.AbsoluteContentSize.Y+16)
    end)

    local typeColors = {
        exact     = Color3.fromRGB(255,72,72),
        signature = Color3.fromRGB(255,130,220),
        group     = Color3.fromRGB(255,180,80),
        wildcard  = Color3.fromRGB(220,120,255),
        pattern   = Color3.fromRGB(120,220,255),
    }

    local refreshBlocked
    refreshBlocked = function()
        for _, c in ipairs(BlkList:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end

        -- ── REGRAS ATIVAS ──
        local ord = 0
        ord = ord + 1
        Lbl("── REGRAS ATIVAS ("..#state.blocker.rules..") ──",
            10, C.TextD, Enum.Font.GothamBold,{
            Size=UDim2.new(1,0,0,18), LayoutOrder=ord, Parent=BlkList})

        if #state.blocker.rules == 0 then
            ord = ord + 1
            Lbl("Nenhuma regra ativa. Use os botões 🚫 no painel de logs.",
                10, C.TextM, Enum.Font.Gotham,{
                Size=UDim2.new(1,0,0,30),
                TextXAlignment=Enum.TextXAlignment.Center,
                LayoutOrder=ord, Parent=BlkList})
        end

        for i, rule in ipairs(state.blocker.rules) do
            ord = ord + 1
            local clr = typeColors[rule.type] or C.Error
            local row = N("Frame",{Size=UDim2.new(1,-4,0,38),
                BackgroundColor3=Color3.fromRGB(30,20,20),BorderSizePixel=0,
                LayoutOrder=ord, Parent=BlkList},{Rnd(5),
                N("UIStroke",{Color=clr, Transparency=0.5, Thickness=1})})
            Lbl(rule.type:upper(),10,clr,Enum.Font.GothamBold,{
                Size=UDim2.new(0,60,0,18), Position=UDim2.new(0,10,0,4),Parent=row})
            Lbl("hits: "..rule.hits,9,C.TextD,Enum.Font.Code,{
                Size=UDim2.new(0,80,0,14),Position=UDim2.new(0,72,0,6),Parent=row})
            Lbl(rule.value, 10, C.Text, Enum.Font.Code,{
                Size=UDim2.new(1,-180,0,16),Position=UDim2.new(0,10,0,20),
                TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})
            local unb = Btn("Remover", 10, {Size=UDim2.new(0,78,0,22),
                Position=UDim2.new(1,-84,0.5,-11),
                BackgroundColor3=Color3.fromRGB(25,60,30),TextColor3=C.Success,
                Parent=row},{Rnd(4)})
            unb.MouseButton1Click:Connect(function()
                state.blockerLib.removeRule(state.blocker, rule.type, rule.value)
                refreshBlocked()
                if uiApi then pcall(uiApi.rebuild) end
            end)
        end

        -- ── SUGESTÕES DE SPAM (auto-detectadas) ──
        local suggestions = state.blockerLib.getSuggestions(state.blocker)
        ord = ord + 1
        Lbl("── SUGESTÕES DE SPAM ("..#suggestions..") ──",
            10, C.TextD, Enum.Font.GothamBold,{
            Size=UDim2.new(1,0,0,18), LayoutOrder=ord, Parent=BlkList})

        if #suggestions == 0 then
            ord = ord + 1
            Lbl("Nenhum remote com spam detectado ainda.",
                10, C.TextM, Enum.Font.Gotham,{
                Size=UDim2.new(1,0,0,24),
                TextXAlignment=Enum.TextXAlignment.Center,
                LayoutOrder=ord, Parent=BlkList})
        end

        for _, sug in ipairs(suggestions) do
            ord = ord + 1
            local row = N("Frame",{Size=UDim2.new(1,-4,0,52),
                BackgroundColor3=Color3.fromRGB(40,30,15),BorderSizePixel=0,
                LayoutOrder=ord, Parent=BlkList},{Rnd(5),
                N("UIStroke",{Color=C.Warning, Transparency=0.4, Thickness=1})})
            Lbl("⚠ SPAM", 10, C.Warning, Enum.Font.GothamBold,{
                Size=UDim2.new(0,54,0,16), Position=UDim2.new(0,10,0,4), Parent=row})
            Lbl(string.format("%.1f msg/s", sug.rate), 9, C.Warning, Enum.Font.Code,{
                Size=UDim2.new(0,80,0,14), Position=UDim2.new(0,66,0,6), Parent=row})
            Lbl("assinatura: "..sug.signatureKey, 9, C.TextD, Enum.Font.Code,{
                Size=UDim2.new(1,-20,0,14), Position=UDim2.new(0,10,0,20),
                TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})
            Lbl("exemplo: "..sug.sample, 9, C.TextM, Enum.Font.Code,{
                Size=UDim2.new(1,-190,0,14), Position=UDim2.new(0,10,0,34),
                TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})
            local accept = Btn("🚫 Bloquear", 10, {Size=UDim2.new(0,80,0,22),
                Position=UDim2.new(1,-168,0.5,-11),
                BackgroundColor3=Color3.fromRGB(60,25,25), TextColor3=C.Error,
                Parent=row},{Rnd(4)})
            local dismiss = Btn("Ignorar", 10, {Size=UDim2.new(0,68,0,22),
                Position=UDim2.new(1,-84,0.5,-11),
                BackgroundColor3=C.Panel, Parent=row},{Rnd(4)})
            accept.MouseButton1Click:Connect(function()
                state.blockerLib.acceptSuggestion(state.blocker, sug.signatureKey, state.config.hideBlocked)
                refreshBlocked()
                if uiApi then pcall(uiApi.rebuild) end
            end)
            dismiss.MouseButton1Click:Connect(function()
                state.blockerLib.dismissSuggestion(state.blocker, sug.signatureKey)
                refreshBlocked()
            end)
        end

        -- ── BOTÕES GLOBAIS ──
        ord = ord + 1
        local controls = N("Frame",{Size=UDim2.new(1,-4,0,32),
            BackgroundTransparency=1, LayoutOrder=ord, Parent=BlkList})
        Btn("🗑 Limpar regras",10,{Size=UDim2.new(0,130,1,0),
            Position=UDim2.new(0,0,0,0),BackgroundColor3=Color3.fromRGB(50,18,18),
            TextColor3=C.Error, Parent=controls},{Rnd(4)})
            .MouseButton1Click:Connect(function()
                state.blockerLib.clearRules(state.blocker)
                refreshBlocked()
                if uiApi then pcall(uiApi.rebuild) end
            end)
        Btn("🔄 Atualizar",10,{Size=UDim2.new(0,100,1,0),
            Position=UDim2.new(0,138,0,0),BackgroundColor3=C.Panel,
            Parent=controls},{Rnd(4)})
            .MouseButton1Click:Connect(refreshBlocked)
    end

    tabs["Blocked"].MouseButton1Click:Connect(refreshBlocked)
    -- auto-refresh suggestions em background
    task.spawn(function()
        while Gui.Parent do
            task.wait(2)
            if currentTab == "Blocked" then
                pcall(refreshBlocked)
            end
        end
    end)

    -- ╔══════════════════════════════════════╗
    -- ║          ABA SCANNER                 ║
    -- ╚══════════════════════════════════════╝
    local ScTab = tabContents["Scanner"]

    local ScTopBar = N("Frame",{Size=UDim2.new(1,-16,0,32),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, Parent=ScTab})
    local scanType = "remotes"
    local scanTabs = {}
    local function mkScanTab(name, label, order)
        local b = Btn(label, 11, {Size=UDim2.new(0,110,1,0),
            Position=UDim2.new(0,(order-1)*116,0,0),
            BackgroundColor3=C.Panel, TextColor3=C.TextD,
            Parent=ScTopBar},{Rnd(5)})
        scanTabs[name] = b
        return b
    end
    local scB1 = mkScanTab("remotes", "📡 Remotes", 1)
    local scB2 = mkScanTab("bindables", "🔗 Bindables", 2)
    local scB3 = mkScanTab("scripts", "📜 Scripts", 3)
    local scB4 = mkScanTab("globals", "🌐 Globals", 4)
    local scanBtn = Btn("🔄 Rescan", 11, {Size=UDim2.new(0,86,1,0),
        Position=UDim2.new(1,-90,0,0),
        BackgroundColor3=C.AccentD, Parent=ScTopBar},{Rnd(5)})

    local ScCount = Lbl("", 10, C.TextD, Enum.Font.Code,{
        Size=UDim2.new(1,-16,0,14),Position=UDim2.new(0,8,0,44),Parent=ScTab})

    local ScScroll = N("ScrollingFrame",{Size=UDim2.new(1,-16,1,-72),
        Position=UDim2.new(0,8,0,62), BackgroundColor3=C.BG,
        BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=C.Border, CanvasSize=UDim2.new(0,0,0,0),
        Parent=ScTab},{Rnd(5)})
    local ScList = N("Frame",{Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1, Parent=ScScroll},{
        N("UIListLayout",{Padding=UDim.new(0,2), SortOrder=Enum.SortOrder.LayoutOrder}),
        Pad(4,6)})
    local scLayout = ScList:FindFirstChildOfClass("UIListLayout")
    scLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ScScroll.CanvasSize = UDim2.new(0,0,0,scLayout.AbsoluteContentSize.Y+12)
    end)

    local function clearScanList()
        for _, c in ipairs(ScList:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
        end
    end

    local function scanRowClass(cls)
        local colors = {
            RemoteEvent = Color3.fromRGB(90,170,255),
            RemoteFunction = Color3.fromRGB(175,115,255),
            UnreliableRemoteEvent = Color3.fromRGB(130,130,255),
            BindableEvent = Color3.fromRGB(255,160,55),
            BindableFunction = Color3.fromRGB(255,115,75),
            LocalScript = Color3.fromRGB(90,230,130),
            ModuleScript = Color3.fromRGB(130,210,180),
        }
        return colors[cls] or C.Accent
    end

    local function runScan()
        clearScanList()
        ScCount.Text = "escaneando..."
        task.spawn(function()
            local ord = 0
            if scanType == "remotes" then
                local r = state.scanner.scanInstances()
                local total = #r.RemoteEvent + #r.RemoteFunction + #r.UnreliableRemoteEvent
                ScCount.Text = string.format(
                    "📡 %d Remotes  |  RE:%d  RF:%d  UnRE:%d",
                    total, #r.RemoteEvent, #r.RemoteFunction, #r.UnreliableRemoteEvent)
                for _, cls in ipairs({"RemoteEvent","RemoteFunction","UnreliableRemoteEvent"}) do
                    for _, item in ipairs(r[cls]) do
                        ord = ord + 1
                        local row = N("Frame",{Size=UDim2.new(1,-4,0,26),
                            BackgroundColor3=C.Panel,BorderSizePixel=0,
                            LayoutOrder=ord, Parent=ScList},{Rnd(4),Pad(0,8)})
                        local clr = scanRowClass(cls)
                        N("Frame",{Size=UDim2.new(0,3,1,-6),
                            Position=UDim2.new(0,-5,0,3),BackgroundColor3=clr,
                            BorderSizePixel=0,Parent=row},{Rnd(2)})
                        Lbl(cls,9,clr,Enum.Font.GothamBold,{
                            Size=UDim2.new(0,120,1,0),Parent=row})
                        Lbl(item.path,10,C.Text,Enum.Font.Code,{
                            Size=UDim2.new(1,-196,1,0),Position=UDim2.new(0,126,0,0),
                            TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
                        Btn("Copiar",9,{Size=UDim2.new(0,62,0,18),
                            Position=UDim2.new(1,-66,0.5,-9),
                            BackgroundColor3=C.AccentD,Parent=row},{Rnd(3)})
                            .MouseButton1Click:Connect(function()
                                if state.env.setclipboard then
                                    local ok, p = pcall(state.serializer.encodeSingle, item.instance)
                                    state.env.setclipboard(ok and p or item.path)
                                end
                            end)
                    end
                end
            elseif scanType == "bindables" then
                local r = state.scanner.scanInstances()
                local total = #r.BindableEvent + #r.BindableFunction
                ScCount.Text = string.format(
                    "🔗 %d Bindables  |  BE:%d  BF:%d",
                    total, #r.BindableEvent, #r.BindableFunction)
                for _, cls in ipairs({"BindableEvent","BindableFunction"}) do
                    for _, item in ipairs(r[cls]) do
                        ord = ord + 1
                        local row = N("Frame",{Size=UDim2.new(1,-4,0,26),
                            BackgroundColor3=C.Panel,BorderSizePixel=0,
                            LayoutOrder=ord, Parent=ScList},{Rnd(4),Pad(0,8)})
                        local clr = scanRowClass(cls)
                        Lbl(cls,9,clr,Enum.Font.GothamBold,{
                            Size=UDim2.new(0,120,1,0),Parent=row})
                        Lbl(item.path,10,C.Text,Enum.Font.Code,{
                            Size=UDim2.new(1,-196,1,0),Position=UDim2.new(0,126,0,0),
                            TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
                        Btn("Copiar",9,{Size=UDim2.new(0,62,0,18),
                            Position=UDim2.new(1,-66,0.5,-9),
                            BackgroundColor3=C.AccentD,Parent=row},{Rnd(3)})
                            .MouseButton1Click:Connect(function()
                                if state.env.setclipboard then
                                    local ok, p = pcall(state.serializer.encodeSingle, item.instance)
                                    state.env.setclipboard(ok and p or item.path)
                                end
                            end)
                    end
                end
            elseif scanType == "scripts" then
                local r = state.scanner.scanScripts()
                ScCount.Text = "📜 "..#r.." Scripts"
                for _, item in ipairs(r) do
                    ord = ord + 1
                    local row = N("Frame",{Size=UDim2.new(1,-4,0,26),
                        BackgroundColor3=C.Panel,BorderSizePixel=0,
                        LayoutOrder=ord, Parent=ScList},{Rnd(4),Pad(0,8)})
                    local clr = scanRowClass(item.class)
                    Lbl(item.class,9,clr,Enum.Font.GothamBold,{
                        Size=UDim2.new(0,100,1,0),Parent=row})
                    Lbl(item.enabled and "✓" or "✗", 11,
                        item.enabled and C.Success or C.Error,Enum.Font.GothamBold,{
                        Size=UDim2.new(0,14,1,0),Position=UDim2.new(0,104,0,0),Parent=row})
                    Lbl(item.path,10,C.Text,Enum.Font.Code,{
                        Size=UDim2.new(1,-196,1,0),Position=UDim2.new(0,124,0,0),
                        TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
                    if decompile then
                        Btn("Decompile",9,{Size=UDim2.new(0,72,0,18),
                            Position=UDim2.new(1,-76,0.5,-9),
                            BackgroundColor3=C.AccentD,Parent=row},{Rnd(3)})
                            .MouseButton1Click:Connect(function()
                                local src, err = state.scanner.tryDecompile(item.instance)
                                if src and state.env.setclipboard then
                                    state.env.setclipboard(src)
                                end
                            end)
                    end
                end
            elseif scanType == "globals" then
                local r = state.scanner.scanGlobals()
                ScCount.Text = "🌐 "..#r.." Globals  (getgenv + _G)"
                for _, item in ipairs(r) do
                    ord = ord + 1
                    local row = N("Frame",{Size=UDim2.new(1,-4,0,26),
                        BackgroundColor3=C.Panel,BorderSizePixel=0,
                        LayoutOrder=ord, Parent=ScList},{Rnd(4),Pad(0,8)})
                    local typeClr = item.type == "function" and C.Accent
                        or item.type == "table" and C.Warning
                        or C.Text
                    Lbl("["..item.source.."]",9,C.TextD,Enum.Font.Code,{
                        Size=UDim2.new(0,60,1,0),Parent=row})
                    Lbl(item.type,9,typeClr,Enum.Font.GothamBold,{
                        Size=UDim2.new(0,68,1,0),Position=UDim2.new(0,64,0,0),Parent=row})
                    local suffix = ""
                    if item.size then suffix = "  ("..item.size.." items)"
                    elseif item.value then suffix = "  = "..item.value
                    elseif item.location then suffix = "  @ "..item.location end
                    Lbl(item.key..suffix,10,C.Text,Enum.Font.Code,{
                        Size=UDim2.new(1,-140,1,0),Position=UDim2.new(0,136,0,0),
                        TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
                end
            end
            if ord == 0 then
                Lbl("Nada encontrado", 11, C.TextM, Enum.Font.Gotham,{
                    Size=UDim2.new(1,0,0,30),
                    TextXAlignment=Enum.TextXAlignment.Center,
                    LayoutOrder=1, Parent=ScList})
            end
        end)
    end

    local function setScanType(t)
        scanType = t
        for name, b in pairs(scanTabs) do
            if name == t then
                b.BackgroundColor3 = C.Accent
                b.TextColor3 = C.BG
            else
                b.BackgroundColor3 = C.Panel
                b.TextColor3 = C.TextD
            end
        end
        runScan()
    end
    scB1.MouseButton1Click:Connect(function() setScanType("remotes") end)
    scB2.MouseButton1Click:Connect(function() setScanType("bindables") end)
    scB3.MouseButton1Click:Connect(function() setScanType("scripts") end)
    scB4.MouseButton1Click:Connect(function() setScanType("globals") end)
    scanBtn.MouseButton1Click:Connect(runScan)
    -- auto-scan quando aba é aberta
    tabs["Scanner"].MouseButton1Click:Connect(function()
        if scanType == "remotes" then setScanType("remotes") end
    end)
    setScanType("remotes")  -- estado inicial

    -- ╔══════════════════════════════════════╗
    -- ║           ABA CONFIG                 ║
    -- ╚══════════════════════════════════════╝
    local CfgTab = tabContents["Config"]
    local CfgScroll = N("ScrollingFrame",{Size=UDim2.new(1,-16,1,-16),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=4, ScrollBarImageColor3=C.Border,
        CanvasSize=UDim2.new(0,0,0,0), Parent=CfgTab})
    local CfgList = N("Frame",{Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1, Parent=CfgScroll},{
        N("UIListLayout",{Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder}),
        Pad(4,4)})
    local cfgLayout = CfgList:FindFirstChildOfClass("UIListLayout")
    cfgLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        CfgScroll.CanvasSize = UDim2.new(0,0,0,cfgLayout.AbsoluteContentSize.Y+16)
    end)

    local ord = 0
    local function cfgSec(txt)
        ord = ord + 1
        Lbl(txt, 10, C.TextD, Enum.Font.GothamBold, {
            Size=UDim2.new(1,0,0,18), LayoutOrder=ord, Parent=CfgList})
    end
    local function cfgTog(label, key)
        ord = ord + 1
        local row = N("Frame",{Size=UDim2.new(1,-4,0,30),BackgroundColor3=C.Panel,
            BorderSizePixel=0,LayoutOrder=ord,Parent=CfgList},{Rnd(5), Pad(0,10)})
        Lbl(label,11,C.Text,Enum.Font.Gotham,{Size=UDim2.new(1,-50,1,0),Parent=row})
        local on = state.config[key]
        local bg = N("Frame",{Size=UDim2.new(0,34,0,16),
            Position=UDim2.new(1,-40,0.5,-8),
            BackgroundColor3=on and C.Accent or C.Border,BorderSizePixel=0,
            Parent=row},{Rnd(8)})
        local knob = N("Frame",{Size=UDim2.new(0,10,0,10),
            Position=UDim2.new(on and 1 or 0, on and -13 or 3, 0.5, -5),
            BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Parent=bg},{Rnd(5)})
        N("TextButton",{Text="",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
            Parent=bg}).MouseButton1Click:Connect(function()
            state.config[key] = not state.config[key]
            local v = state.config[key]
            TweenService:Create(bg,TweenInfo.new(0.14),{
                BackgroundColor3=v and C.Accent or C.Border}):Play()
            TweenService:Create(knob,TweenInfo.new(0.14),{
                Position=UDim2.new(v and 1 or 0, v and -13 or 3, 0.5, -5)}):Play()
        end)
    end

    cfgSec("── CAPTURA ──")
    cfgTog("Habilitar captura", "enabled")
    cfgTog("Logar chamadas do próprio executor (checkcaller)", "logCheckCaller")
    cfgTog("Logar OnClientEvent (Server → Client)", "logClientEvents")
    cfgTog("Logar BindableEvent/BindableFunction (interno do client)", "logBindables")
    cfgTog("Logar HttpService (GetAsync/PostAsync/RequestAsync)", "logHttp")

    cfgSec("── BLOQUEIO ──")
    cfgTog("Esconder bloqueados da lista", "hideBlocked")
    -- listener: quando toggle hideBlocked muda, rebuild da lista
    task.spawn(function()
        local last = state.config.hideBlocked
        while Gui.Parent do
            task.wait(0.3)
            if state.config.hideBlocked ~= last then
                last = state.config.hideBlocked
                rebuildFiltered()
                CountLbl.Text = #filtered.." logs"
                renderList()
            end
        end
    end)

    -- slider de threshold de spam
    ord = ord + 1
    local spamRow = N("Frame",{Size=UDim2.new(1,-4,0,32),BackgroundColor3=C.Panel,
        BorderSizePixel=0,LayoutOrder=ord,Parent=CfgList},{Rnd(5), Pad(0,10)})
    local spamLbl = Lbl("Threshold spam: "..state.blocker.config.autoBlockThreshold.." msg/s",
        11, C.Text, Enum.Font.Gotham,{Size=UDim2.new(0.7,0,1,0),Parent=spamRow})
    Btn("−",13,{Size=UDim2.new(0,24,0,18),Position=UDim2.new(1,-56,0.5,-9),
        BackgroundColor3=C.BG, Parent=spamRow},{Rnd(4)})
        .MouseButton1Click:Connect(function()
            state.blocker.config.autoBlockThreshold = math.max(2,
                state.blocker.config.autoBlockThreshold - 1)
            spamLbl.Text = "Threshold spam: "..state.blocker.config.autoBlockThreshold.." msg/s"
        end)
    Btn("+",13,{Size=UDim2.new(0,24,0,18),Position=UDim2.new(1,-28,0.5,-9),
        BackgroundColor3=C.AccentD, Parent=spamRow},{Rnd(4)})
        .MouseButton1Click:Connect(function()
            state.blocker.config.autoBlockThreshold = math.min(100,
                state.blocker.config.autoBlockThreshold + 1)
            spamLbl.Text = "Threshold spam: "..state.blocker.config.autoBlockThreshold.." msg/s"
        end)

    cfgSec("── INTERFACE ──")
    cfgTog("Auto-scroll", "autoScroll")

    cfgSec("── AMBIENTE ──")
    ord = ord + 1
    local envBox = N("Frame",{Size=UDim2.new(1,-4,0,90),
        BackgroundColor3=C.Panel,BorderSizePixel=0,LayoutOrder=ord,
        Parent=CfgList},{Rnd(5), Pad(6,10)})
    Lbl("Executor: "..state.env.Name, 11, C.Text, Enum.Font.GothamBold,{
        Size=UDim2.new(1,0,0,16),Parent=envBox})
    Lbl("Hook: "..(state.env.hookMode or "?"), 10, C.TextD, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,18),Parent=envBox})
    local hookStatsLbl = Lbl("", 10, C.TextD, Enum.Font.Code,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,34),Parent=envBox})
    Lbl("hookfunction: "..tostring(state.env.CanHookFunction)
        .."  |  hookmetamethod: "..tostring(state.env.CanHookMeta),
        9, C.TextM, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,50),Parent=envBox})
    Lbl("clipboard: "..(state.env.setclipboard and "✓" or "✗")
        .."  |  cloneref: "..(state.env.cloneref and "✓" or "✗"),
        9, C.TextM, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,66),Parent=envBox})

    -- export json
    ord = ord + 1
    local ExpBtn = Btn("📤 Exportar JSON", 11, {Size=UDim2.new(0,160,0,28),
        BackgroundColor3=C.AccentD, LayoutOrder=ord,Parent=CfgList}, {Rnd(5)})
    ExpBtn.MouseButton1Click:Connect(function()
        if not state.env.setclipboard then return end
        local export = {}
        for _, l in ipairs(state.logs) do
            export[#export+1] = {
                id=l.id,timestamp=l.timestamp,type=l.type,
                remoteName=l.remoteName, remotePath=l.remotePath,
                argCount=l.argCount, argsPreview=l.argsPreview,
                metamethod=l.metamethod, blocked=l.blocked,
            }
        end
        local ok, j = pcall(HttpService.JSONEncode, HttpService, export)
        if ok then
            state.env.setclipboard(j)
            ExpBtn.Text = "✓ Copiado!"
            task.delay(1.5, function() ExpBtn.Text = "📤 Exportar JSON" end)
        end
    end)

    -- DRAG
    do
        local drag,ds,sp = false
        HDR.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                drag=true; ds=i.Position; sp=Win.Position end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                local d=i.Position-ds
                Win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,
                    sp.Y.Scale,sp.Y.Offset+d.Y) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then drag=false end
        end)
    end

    CloseBtn.MouseButton1Click:Connect(function() Gui:Destroy() end)

    -- abrir aba inicial (não usar :Fire() - RBXScriptSignal não tem esse método)
    tabs["Logs"].BackgroundColor3 = C.Accent
    tabs["Logs"].TextColor3 = C.BG
    tabContents["Logs"].Visible = true
    currentTab = "Logs"

    -- animação de abertura
    Win.Size = UDim2.new(0,0,0,0)
    TweenService:Create(Win, TweenInfo.new(0.25, Enum.EasingStyle.Back,
        Enum.EasingDirection.Out), {Size=UDim2.new(0,WIN_W,0,WIN_H)}):Play()

    -- hookStats live update
    task.spawn(function()
        while Gui.Parent do
            local s = state.hookStats or {}
            hookStatsLbl.Text = string.format("stats: ns=%d fs=%d is=%d ce=%d",
                s.ns or 0, s.fs or 0, s.is or 0, s.ce or 0)
            task.wait(0.5)
        end
    end)

    -- API para atualizar UI externamente
    return {
        onNewLog = function(log)
            log.argsPreview = state.serializer.previewArgs(log.args or {}, 6)
            rebuildFiltered()
            CountLbl.Text = #filtered.." logs"

            if state.config.autoScroll and not userScrolled then
                -- usuário está no fundo: scrolla pro novo log normalmente
                task.defer(function()
                    local h = math.max(0, #filtered * ITEM_S)
                    LogScroll.CanvasSize = UDim2.new(0,0,0,h)
                    local vis = LogScroll.AbsoluteSize.Y
                    LogScroll.CanvasPosition = Vector2.new(0, math.max(0, h-vis))
                    renderList()
                end)
            else
                -- usuário subiu pra ler: não mexe no scroll, só atualiza canvas
                -- e mostra quantos logs novos chegaram
                pendingNew = pendingNew + 1
                JumpBtn.Text = "⬇ "..pendingNew.." novo"..(pendingNew>1 and "s" or "")
                JumpBtn.Visible = true
                task.defer(renderList)
            end
        end,
        rebuild = function()
            rebuildFiltered()
            CountLbl.Text = #filtered.." logs"
            renderList()
        end,
        gui = Gui,
    }
end

return M

end)()

-- ═══════════════════════════════════════
-- main
-- ═══════════════════════════════════════
--[[
    Remote Spy Pro v4.0  -  Main Loader

    Arquitetura:
      modules/serializer.lua  -  args → código Lua executável
      modules/hooks.lua       -  __namecall + hookfunction combinados
      modules/ui.lua          -  interface virtual

    Uso: edite BASE_URL abaixo pro seu repositório, depois:
      loadstring(game:HttpGet("https://SEU_REPO/main.lua"))()

    Ou execute tudo num arquivo único (use build_single.lua).
]]

--═══════════════════════════════════════════════════════
-- CONFIGURE AQUI: URL base do seu repositório (sem barra final)
--═══════════════════════════════════════════════════════
local BASE_URL = "https://raw.githubusercontent.com/TsXK-shift/test-rspy/refs/heads/main"
--═══════════════════════════════════════════════════════

-- Detectar se rodando do arquivo único (build_single.lua coloca os módulos em getgenv())
local function loadModule(name)
    if getgenv().__RSP_MODULES and getgenv().__RSP_MODULES[name] then
        return getgenv().__RSP_MODULES[name]
    end
    local url = BASE_URL.."/modules/"..name..".lua"
    local ok, src = pcall(game.HttpGet, game, url)
    if not ok then
        error("[RSP] Falha ao baixar "..name..": "..tostring(src))
    end
    local f, err = loadstring(src, name)
    if not f then error("[RSP] Erro ao compilar "..name..": "..tostring(err)) end
    return f()
end

-- ── DETECÇÃO DE AMBIENTE ──
local env = {
    hookfunction      = hookfunction or replaceclosure,
    hookmetamethod    = hookmetamethod,
    newcclosure       = newcclosure or function(f) return f end,
    getnamecallmethod = getnamecallmethod,
    checkcaller       = checkcaller or function() return false end,
    setclipboard      = setclipboard or toclipboard or (Clipboard and Clipboard.set),
    getrawmetatable   = getrawmetatable,
    cloneref          = cloneref or function(x) return x end,
    getcallingscript  = getcallingscript,
    Name = (identifyexecutor and identifyexecutor())
        or (getexecutorname and getexecutorname())
        or "Unknown",
}
env.CanHookFunction = env.hookfunction ~= nil
env.CanHookMeta     = env.hookmetamethod ~= nil and env.getnamecallmethod ~= nil

-- ── ESTADO GLOBAL ──
-- Cleanup anterior
if getgenv().RSP_Pro and getgenv().RSP_Pro.gui then
    pcall(function() getgenv().RSP_Pro.gui:Destroy() end)
end

local state = {
    version = "4.1",
    logs = {},
    stats = {},
    config = {
        enabled = true,
        logCheckCaller = false,
        logClientEvents = true,
        logBindables = false,  -- BindableEvent/BindableFunction (opt-in, pode gerar spam)
        logHttp = true,        -- HttpService calls
        autoScroll = true,
        filter = "",
        hideBlocked = true,
    },
    env = env,
}

-- ── CARREGAR MÓDULOS ──
print("[RSP] Executor:", env.Name)
print("[RSP] hookfunction:", tostring(env.CanHookFunction),
      "| hookmetamethod:", tostring(env.CanHookMeta))

local okS, serializer = pcall(loadModule, "serializer")
if not okS then
    warn("[RSP] FALHA serializer:", serializer); return
end
local okB, blocker = pcall(loadModule, "blocker")
if not okB then
    warn("[RSP] FALHA blocker:", blocker); return
end
local okH, hooks = pcall(loadModule, "hooks")
if not okH then
    warn("[RSP] FALHA hooks:", hooks); return
end
local okU, ui = pcall(loadModule, "ui")
if not okU then
    warn("[RSP] FALHA ui:", ui); return
end
local okSc, scanner = pcall(loadModule, "scanner")
if not okSc then
    warn("[RSP] FALHA scanner:", scanner); return
end

-- instância do blocker com estado
state.blocker = blocker.new()
state.blockerLib = blocker
state.serializer = serializer
state.scanner = scanner
state.hookStats = hooks.stats

-- CRÍTICO: setar env ANTES de hooks.init
env.config = state.config
env.checkBlock = function(data) return blocker.check(state.blocker, data) end

-- ╔══════════════════════════════════════╗
-- ║ hooks ANTES da UI                    ║
-- ╚══════════════════════════════════════╝

local uiApi
local addLogQueue = {}

local function logCallback(data)
    data.id = #state.logs + 1
    data.timestamp = os.date("%H:%M:%S")
    local okP, preview = pcall(serializer.previewArgs, data.args or {}, 6)
    data.argsPreview = okP and preview or "(?)"

    table.insert(state.logs, data)
    if #state.logs > 500 then table.remove(state.logs, 1) end

    local p = data.remotePath or "?"
    state.stats[p] = state.stats[p] or {calls=0, blocked=0}
    state.stats[p].calls = state.stats[p].calls + 1
    if data.blocked then state.stats[p].blocked = state.stats[p].blocked + 1 end

    if uiApi then
        pcall(uiApi.onNewLog, data)
    else
        table.insert(addLogQueue, data)
    end
end

-- determinar hookMode
local hookMode = "fallback"
if env.CanHookMeta then hookMode = "namecall+hookfunction"
elseif env.CanHookFunction then hookMode = "hookfunction" end
env.hookMode = hookMode

-- INICIALIZAR HOOKS
local okInit, errInit = pcall(hooks.init, env, logCallback)
if not okInit then
    warn("[RSP] ❌ Erro ao inicializar hooks: "..tostring(errInit))
else
    print("[RSP] ✓ Hooks ativos em modo:", hookMode)
end

-- ── UI ──
local okUi, uiResult = pcall(ui.build, state)
if not okUi then
    warn("[RSP] ❌ Erro ao montar UI: "..tostring(uiResult))
    return
end
uiApi = uiResult

-- drenar fila acumulada
if #addLogQueue > 0 then
    print("[RSP] drenando", #addLogQueue, "logs pré-UI")
    pcall(uiApi.rebuild)
end

-- Exportar pro escopo global pra poder inspecionar
getgenv().RSP_Pro = {
    state = state,
    hooks = hooks,
    serializer = serializer,
    gui = uiApi.gui,
    version = state.version,
}

-- log de inicialização
task.spawn(function()
    task.wait(0.1)
    logCallback({
        type = "FireServer",
        remoteType = "Sistema",
        remote = nil,
        remoteName = "RSP_Init",
        remotePath = "System.RSP_Init",
        args = {"executor="..env.Name, "mode="..hookMode},
        argCount = 2,
        metamethod = "system",
        blocked = false,
    })
end)

print("[RSP] v"..state.version.." carregado. Use getgenv().RSP_Pro pra inspecionar.")
