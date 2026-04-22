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

local matchers = {
    exact    = matchExact,
    pattern  = matchPattern,
    wildcard = matchWildcard,
    group    = matchGroup,
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
    -- 1. check spam tracking
    local key = groupKey(data)
    local now = os.clock()
    local s = inst.spamStats[key]
    if not s then
        s = { count=0, windowStart=now, lastSeen=now, sample=data.remotePath }
        inst.spamStats[key] = s
    end
    if now - s.windowStart > inst.config.windowSeconds then
        -- reinicia janela
        s.count = 0
        s.windowStart = now
    end
    s.count = s.count + 1
    s.lastSeen = now
    local rate = s.count / math.max(0.1, now - s.windowStart)
    if rate > inst.config.autoBlockThreshold and not inst.suggestedBlocks[key] then
        inst.suggestedBlocks[key] = {
            sample = data.remotePath,
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
            groupKey = key,
            sample = sug.sample,
            rate = sug.rate,
        }
    end
    table.sort(list, function(a,b) return a.rate > b.rate end)
    return list
end

function M.acceptSuggestion(inst, groupKeyValue, silent)
    M.addRule(inst, "group", groupKeyValue, { silent = silent ~= false })
    inst.suggestedBlocks[groupKeyValue] = nil
end

function M.dismissSuggestion(inst, groupKeyValue)
    inst.suggestedBlocks[groupKeyValue] = nil
end

-- helpers expostos
M.groupKey = groupKey
M.nameShape = nameShape
M.parentPath = parentPath
M.leafName = leafName

return M
