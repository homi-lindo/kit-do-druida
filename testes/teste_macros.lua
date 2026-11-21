-- Banco de testes do Macros.lua fora do jogo (LuaJIT): API de macros simulada.
-- Uso: luajit teste_macros.lua <caminho do Macros.lua>

local caminho = assert(arg[1], "passe o caminho do Macros.lua")
local timers, quadros, falas = {}, {}, {}
local emCombate, sabeDireBear = false, false

-- macros do jogo: lista de { nome, icone, corpo, doPersonagem }; um macro seu "Dash" já existe
local macros = { { nome = "Dash", icone = 1, corpo = "/cast Dash", personagem = false } }
local function Achar(nome)
    for i, m in ipairs(macros) do
        if m.nome == nome then return i end
    end
    return 0
end
function GetMacroIndexByName(nome) return Achar(nome) end
function GetMacroInfo(i)
    local m = macros[i]
    if m then return m.nome, m.icone, m.corpo end
end
function CreateMacro(nome, icone, corpo, personagem)
    if emCombate then error("CreateMacro bloqueado em combate") end
    assert(#nome <= 16, "nome comprido: " .. nome)
    assert(#corpo <= 255, "corpo comprido: " .. nome)
    macros[#macros + 1] = { nome = nome, icone = icone, corpo = corpo, personagem = personagem }
    return #macros
end
function EditMacro(i, nome, icone, corpo)
    if emCombate then error("EditMacro bloqueado em combate") end
    local m = macros[type(i) == "number" and i or Achar(i)]
    m.nome, m.icone, m.corpo = nome, icone, corpo
    return i
end
function InCombatLockdown() return emCombate end
function IsPlayerSpell(id) return id == 9634 and sabeDireBear end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
function CreateFrame()
    local f = { scripts = {} }
    function f:RegisterEvent() end
    function f:SetScript(nome, fn) self.scripts[nome] = fn end
    quadros[#quadros + 1] = f
    return f
end
local printOriginal = print
function print(t) falas[#falas + 1] = t end

local carregar = {}
local K = { PREFIXO = "Kit: ", db = {} }
function K.AoCarregar(fn) carregar[#carregar + 1] = fn end
function K.GuardarErro(t) printOriginal("!! ERRO GUARDADO: " .. t) end

local function Evento(nome)
    for _, f in ipairs(quadros) do
        if f.scripts.OnEvent then f.scripts.OnEvent(f, nome) end
    end
end
local function Timers()
    local lista = timers
    timers = {}
    for _, fn in ipairs(lista) do fn() end
end
local function Passo(titulo, fn)
    falas = {}
    fn()
    printOriginal("== " .. titulo)
    for _, t in ipairs(falas) do printOriginal("   " .. t) end
end

assert(loadfile(caminho))("KitDruida", K)
for _, fn in ipairs(carregar) do fn() end

printOriginal(string.format("contagem antes: %d de %d", K.Macros.Contagem()))
Passo("1. botão, pela primeira vez", function() K.Macros.Sincronizar() end)
printOriginal(string.format("contagem depois: %d de %d", K.Macros.Contagem()))
Passo("2. botão de novo", function() K.Macros.Sincronizar() end)
Passo("3. aprende Dire Bear Form (SPELLS_CHANGED)", function()
    sabeDireBear = true
    Evento("SPELLS_CHANGED")
    Timers()
end)
printOriginal("   corpo do Urso: " .. macros[Achar("Urso")].corpo:gsub("\n", " | "))
Passo("4. você apaga o Gato; feitiço novo não o recria", function()
    table.remove(macros, Achar("Gato"))
    Evento("SPELLS_CHANGED")
    Timers()
end)
Passo("5. botão em combate, depois o combate acaba", function()
    emCombate = true
    K.Macros.Sincronizar()
    emCombate = false
    Evento("PLAYER_REGEN_ENABLED")
    Timers()
end)
printOriginal("== macros no fim:")
for _, m in ipairs(macros) do
    printOriginal(string.format("   %-14s personagem=%-5s %s", m.nome, tostring(m.personagem), m.corpo:gsub("\n", " | ")))
end
