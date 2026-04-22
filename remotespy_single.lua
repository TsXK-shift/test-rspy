# Remote Spy Pro v4.0

Remote spy avançado para Roblox com serializer de args em código Lua executável.
Inspirado no SimpleSpy V3 mas reescrito com arquitetura modular mais enxuta e
sem dependência de `loadstring` externo.

## O que ele faz de diferente do v3.0 anterior

1. **Serializer real**: em vez de só mostrar `"(arg1, arg2)"` resumido, gera
   **código Lua executável** que reconstrói os argumentos. Suporta CFrame,
   Vector3, Color3, Instance com path correto, tabelas aninhadas, tabelas
   cíclicas, strings com escape, `getNil` pra nil instances, etc.

2. **Hook híbrido**: usa **`__namecall` via `hookmetamethod`** (pega todas as
   chamadas `remote:FireServer(...)` mesmo que o jogo faça cache) + 
   **`hookfunction` nos protótipos** (pega `remote.FireServer(remote, ...)` 
   cached calls). Combinados, cobrem 100% dos casos.

3. **Hook antes da UI**: o v3.0 esperava 300ms pra inicializar os hooks. 
   Nesse tempo todos os `FireServer` da inicialização do jogo já tinham 
   disparado. O v4 aplica os hooks ANTES de montar a interface.

4. **`cloneref` em tudo**: usa `cloneref` pra obter referências a Instance 
   que burlam detecção por `__index` do anti-cheat.

5. **`deepclone` dos args no momento da captura**: previne race condition 
   caso o jogo mute a tabela de argumentos depois.

6. **Renderização virtual** com pool de 20 itens: suporta milhares de logs 
   sem lag.

## Estrutura

```
RemoteSpyPro/
├── main.lua                  # loader (baixa módulos via HttpGet)
├── build_single.lua          # gera arquivo único offline
├── remotespy_single.lua      # ARQUIVO ÚNICO já pronto (use este)
├── modules/
│   ├── serializer.lua        # args → código Lua executável
│   ├── hooks.lua             # interceptação namecall + hookfunction
│   └── ui.lua                # interface virtual
└── README.md
```

## Como usar

### Opção A — arquivo único (recomendado, não precisa de internet no exec)

Envia `remotespy_single.lua` pro teu GitHub e executa:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USUARIO/REPO/main/remotespy_single.lua"))()
```

### Opção B — modular (mais fácil de dar updates)

1. Sobe a pasta `RemoteSpyPro/` inteira pro teu GitHub
2. Edita a linha `BASE_URL` em `main.lua` com o link do teu repo
3. Executa:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USUARIO/REPO/main/main.lua"))()
```

## API runtime

Depois de carregado, fica exposto em `getgenv().RSP_Pro`:

```lua
getgenv().RSP_Pro.state.logs      -- array de todos os logs
getgenv().RSP_Pro.state.blocked   -- dict {path=true} dos remotes bloqueados
getgenv().RSP_Pro.state.config    -- config runtime
getgenv().RSP_Pro.hooks.stats     -- contadores {ns, fs, is, ce}
getgenv().RSP_Pro.serializer      -- pra usar o serializer em outros scripts
```

### Debug rápido pra conferir se está interceptando

```lua
print(getgenv().RSP_Pro.hooks.stats)
-- saída esperada depois de jogar 1 min:
-- { ns = 15, fs = 8, is = 2, ce = 42 }
```
Se `fs + is + ns` ficar em 0 após interação real no jogo, algo está bloqueando 
(jogo usa UnreliableRemoteEvent de forma rara ou algum anti-tamper).

## Configs

Na aba Config da UI ou via `getgenv().RSP_Pro.state.config`:

- `enabled` — liga/desliga captura
- `logCheckCaller` — **default false** = não loga chamadas do próprio 
  executor. Ligue se quiser ver `FireServer` chamado pelos seus próprios scripts.
- `logClientEvents` — loga `OnClientEvent` (Server → Client)
- `autoScroll` — scroll automático pra novos logs

## Botões do painel de detalhes

- **📋 Copiar Script** — copia código Lua executável completo pro clipboard
- **📝 Copiar Path** — copia só o path do remote
- **🚫 Bloquear** — impede este remote (por path) de disparar pro servidor
- **▶ Executar** — dispara o remote de novo com os mesmos args (replay)

## Compatibilidade

Testado em: Xeno, Delta, Solara, Fluxus, KRNL, Synapse X, Wave.
Requer pelo menos `hookmetamethod` **ou** `hookfunction`. Os dois funcionando 
é o ideal.
