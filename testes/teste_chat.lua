-- Banco de testes do Chat.lua fora do jogo (LuaJIT): caixa de texto do WoW simulada, com o Ctrl+W
-- de apagar palavra, nas ordens em que o jogo pode agir.
-- Uso: luajit teste_chat.lua <caminho do Chat.lua>

local caminho = assert(arg[1], "passe o caminho do Chat.lua")
local ctrl, alt, tempo, fila = false, false, 1, {}
local falhas = 0

function IsControlKeyDown() return ctrl end
function IsAltKeyDown() return alt end
function GetTime() return tempo end
C_Timer = { After = function(_, fn) fila[#fila + 1] = fn end }
NUM_CHAT_WINDOWS = 1

local Caixa = {}
Caixa.__index = Caixa
local function NovaCaixa() return setmetatable({ texto = "", cursor = 0, hooks = {} }, Caixa) end
function Caixa:HookScript(nome, fn)
    self.hooks[nome] = self.hooks[nome] or {}
    table.insert(self.hooks[nome], fn)
end
function Caixa:Disparar(nome, ...)
    for _, fn in ipairs(self.hooks[nome] or {}) do fn(self, ...) end
end
function Caixa:GetText() return self.texto end
function Caixa:GetCursorPosition() return self.cursor end
function Caixa:SetText(t)
    self.texto, self.cursor = t, #t
    self:Disparar("OnCursorChanged")
    self:Disparar("OnTextChanged", false)
end
function Caixa:SetCursorPosition(p)
    self.cursor = p
    self:Disparar("OnCursorChanged")
end

ChatFrame1EditBox = NovaCaixa()
local caixa = ChatFrame1EditBox

local carregar, entrar = {}, {}
local K = { db = {} }
function K.AoCarregar(fn) carregar[#carregar + 1] = fn end
function K.AoEntrar(fn) entrar[#entrar + 1] = fn end
function K.GuardarErro(t) print("!! ERRO GUARDADO: " .. t); falhas = falhas + 1 end

assert(loadfile(caminho))("KitDruida", K)
for _, fn in ipairs(carregar) do fn() end
for _, fn in ipairs(entrar) do fn() end

-- o que o motor do jogo faz; cursorPrimeiro escolhe a ordem dos eventos
local cursorPrimeiro = true
local function Eventos()
    if cursorPrimeiro then
        caixa:Disparar("OnCursorChanged")
        caixa:Disparar("OnTextChanged", true)
    else
        caixa:Disparar("OnTextChanged", true)
        caixa:Disparar("OnCursorChanged")
    end
end
local function Inserir(s)
    caixa.texto = caixa.texto:sub(1, caixa.cursor) .. s .. caixa.texto:sub(caixa.cursor + 1)
    caixa.cursor = caixa.cursor + #s
    Eventos()
end
local function ApagarPalavra()
    local antes = caixa.texto:sub(1, caixa.cursor)
    local novo = antes:gsub("[^%s]*%s*$", "", 1)
    if novo == antes then return end -- nada a apagar: o jogo não muda nada
    caixa.texto = novo .. caixa.texto:sub(caixa.cursor + 1)
    caixa.cursor = #novo
    Eventos()
end
-- fim do quadro: roda o que ficou para o quadro seguinte e avança o relógio
local function Quadro()
    local lista = fila
    fila = {}
    for _, fn in ipairs(lista) do fn() end
    tempo = tempo + 1
end
local function Tecla(fn)
    fn()
    ctrl, alt = false, false
    Quadro()
end
local function Digitar(s)
    for i = 1, #s do Tecla(function() Inserir(s:sub(i, i)) end) end
end
local MODOS = {
    a = function() ApagarPalavra() end,                    -- só apaga
    b = function() ApagarPalavra(); Inserir("?") end,      -- apaga e põe o "?"
    c = function() Inserir("?"); ApagarPalavra() end,      -- põe o "?" e apaga
    d = function() Inserir("?") end,                       -- comporta-se bem
}
local function AltGrW(modo)
    Tecla(function()
        ctrl, alt = true, true
        MODOS[modo]()
    end)
end
local function AltGrQ()
    Tecla(function()
        ctrl, alt = true, true
        Inserir("/")
    end)
end
local function Comecar(texto, cursor)
    caixa.texto, caixa.cursor = texto, cursor or #texto
    caixa:Disparar("OnEditFocusGained")
    Quadro()
end
local function Conferir(nome, esperado, cursorEsperado)
    local ok = caixa.texto == esperado and (cursorEsperado == nil or caixa.cursor == cursorEsperado)
    if not ok then falhas = falhas + 1 end
    print(string.format("%-4s %-52s -> %-24q cursor %d", ok and "ok" or "FALHA", nome, caixa.texto, caixa.cursor))
end

for _, ordem in ipairs({ true, false }) do
    cursorPrimeiro = ordem
    print("### eventos: " .. (ordem and "cursor antes do texto" or "texto antes do cursor"))
    for _, modo in ipairs({ "a", "b", "c", "d" }) do
        Comecar("")
        Digitar("ola mundo")
        AltGrW(modo)
        Conferir("AltGr+W no fim, jogo no modo " .. modo, "ola mundo?", 10)
    end
    Comecar("você vem amanhã", 9)
    AltGrW("b")
    Conferir("AltGr+W no meio de texto com acento", "você vem? amanhã", 10)
    Comecar("")
    Digitar("e agora")
    AltGrQ()
    AltGrW("b")
    Conferir("AltGr+Q (/) e depois AltGr+W", "e agora/?", 9)
    Comecar("")
    Digitar("serio")
    AltGrW("b")
    AltGrW("b")
    Conferir("duas interrogações seguidas", "serio??", 7)
    Comecar("")
    Digitar("tudo bem ")
    AltGrW("b")
    Conferir("AltGr+W depois de espaço", "tudo bem ?", 10)
    Comecar("")
    AltGrW("a")
    Conferir("caixa vazia, jogo só apaga (limite conhecido)", "", 0)
    K.db.chat.interrogacao = false
    Comecar("")
    Digitar("desligado")
    AltGrW("a")
    Conferir("correção desligada: a palavra some", "", 0)
    K.db.chat.interrogacao = true
end
print("falhas: " .. falhas)
