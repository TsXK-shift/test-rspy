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
    stats = { ns = 0, fs = 0, is = 0, ufs = 0, ce = 0 },
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

        callback({
            type       = method,
            remoteType = cls,
            remote     = self,
            remoteName = self.Name,
            remotePath = safePath(self),
            args       = args,
            argCount   = #args,
            callerScript = src,
            callerLine = ln,
            metamethod = metamethod,
            blocked    = env.isBlocked and env.isBlocked(self) or false,
        })
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
                            local blocked = env.isBlocked and env.isBlocked(self)
                            emit(method, self, args, "__namecall")
                            if blocked then
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
                        local blocked = env.isBlocked and env.isBlocked(self)
                        emit(methodName, self, args, "hookfunction")
                        if blocked then
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
        -- UnreliableRemoteEvent só existe em versões recentes, falha silenciosa ok
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
                callback({
                    type       = "OnClientEvent",
                    remoteType = "RemoteEvent",
                    remote     = obj,
                    remoteName = obj.Name,
                    remotePath = safePath(obj),
                    args       = deepclone(args),
                    argCount   = #args,
                    metamethod = "passive",
                    blocked    = false,
                })
            end)
        end)
    end
    task.spawn(function()
        pcall(function()
            for _, obj in ipairs(game:GetDescendants()) do watchRE(obj) end
        end)
        game.DescendantAdded:Connect(function(obj) task.defer(watchRE, obj) end)
    end)

    return true
end

function M.shutdown()
    -- Nota: desfazer hookfunction/hookmetamethod requer re-aplicar os originais
    -- como hook, o que nem todo executor suporta. Default: apenas desabilita via flag.
    M._installed = false
end

return M
