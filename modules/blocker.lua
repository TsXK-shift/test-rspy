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
