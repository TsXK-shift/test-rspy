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
