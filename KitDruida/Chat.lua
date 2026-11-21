-- Kit do Druida: "?" no chat com AltGr+W (Ctrl+Alt+W).
-- No teclado ABNT2 sem a tecla / ?, o "?" sai com AltGr+W, que o Windows manda como Ctrl+Alt+W.
-- A caixa do chat do WoW lê o Ctrl e faz o Ctrl+W dela: apaga a palavra anterior. Aqui o Kit
-- guarda o texto de cada caixa de chat antes de cada tecla e, quando o chat apaga texto com Ctrl e
-- Alt apertados, devolve no quadro seguinte o texto como estava, com o "?" no lugar do cursor.
-- Funciona nas três ordens em que o jogo pode agir: só apagar, apagar e depois pôr o "?", ou pôr
-- o "?" e depois apagar. Limite: com a caixa vazia (ou o cursor no começo) não há o que apagar, e
-- se o jogo não puser o "?" sozinho, o Kit não percebe a tecla.
-- Só mexe nas caixas de chat. Nada é escrito nos quadros da Blizzard: o estado de cada caixa fica
-- em tabelas do Kit. A posição do cursor do WoW conta bytes, então acento (é, ç, ã) não quebra.

local _, K = ...
local C = {}
K.Chat = C

local fraca = { __mode = "k" }
local atual = setmetatable({}, fraca)      -- caixa -> { texto, cursor, quando }
local anterior = setmetatable({}, fraca)   -- a foto de antes da última
local corrigindo = setmetatable({}, fraca) -- caixa -> "agendado" (até o quadro seguinte) ou true
local ligadas = setmetatable({}, fraca)

K.AoCarregar(function()
    if type(K.db.chat) ~= "table" then
        K.db.chat = {}
    end
    if K.db.chat.interrogacao == nil then
        K.db.chat.interrogacao = true
    end
end)

local function Ligado()
    return K.db and K.db.chat and K.db.chat.interrogacao
end

local function AltGr()
    return IsControlKeyDown() and IsAltKeyDown()
end

local function Foto(caixa)
    return { texto = caixa:GetText() or "", cursor = caixa:GetCursorPosition() or 0, quando = GetTime() }
end

local function Guardar(caixa)
    anterior[caixa] = atual[caixa]
    atual[caixa] = Foto(caixa)
end

local function ComInterrogacao(foto)
    return foto.texto:sub(1, foto.cursor) .. "?" .. foto.texto:sub(foto.cursor + 1)
end

local function Corrigir(caixa, base)
    corrigindo[caixa] = true
    local desejado = ComInterrogacao(base)
    if caixa:GetText() ~= desejado then
        caixa:SetText(desejado)
    end
    caixa:SetCursorPosition(base.cursor + 1)
    corrigindo[caixa] = nil
    anterior[caixa] = nil
    atual[caixa] = Foto(caixa)
end

local function AoMudarTexto(caixa, doUsuario)
    if corrigindo[caixa] then
        return
    end
    local antes = atual[caixa]
    if doUsuario and antes and Ligado() and AltGr() then
        local agora = caixa:GetText() or ""
        if #agora < #antes.texto then
            -- o Ctrl+W do chat apagou texto; se o "?" já tinha entrado nesta mesma tecla, a base é
            -- o texto de antes dele
            local base, velho = antes, anterior[caixa]
            if velho and antes.quando == GetTime() and antes.texto == ComInterrogacao(velho) then
                base = velho
            end
            corrigindo[caixa] = "agendado"
            C_Timer.After(0, function()
                corrigindo[caixa] = nil
                local ok, erro = pcall(Corrigir, caixa, base)
                if not ok then
                    corrigindo[caixa] = nil
                    if K.GuardarErro then
                        K.GuardarErro("[Chat] " .. tostring(erro))
                    end
                end
            end)
            return
        end
    end
    Guardar(caixa)
end

-- Cursor que andou sem o texto mudar (setas, clique): atualiza a foto
local function AoMoverCursor(caixa)
    if corrigindo[caixa] or AltGr() then
        return
    end
    local foto = atual[caixa]
    local texto = caixa:GetText() or ""
    if foto and foto.texto == texto then
        foto.cursor = caixa:GetCursorPosition() or foto.cursor
    elseif not foto then
        atual[caixa] = Foto(caixa)
    end
end

local function Ligar(caixa)
    if not caixa or ligadas[caixa] or type(caixa.HookScript) ~= "function" then
        return
    end
    ligadas[caixa] = true
    caixa:HookScript("OnTextChanged", function(self, doUsuario)
        local ok, erro = pcall(AoMudarTexto, self, doUsuario)
        if not ok and K.GuardarErro then
            K.GuardarErro("[Chat] " .. tostring(erro))
        end
    end)
    caixa:HookScript("OnCursorChanged", function(self)
        pcall(AoMoverCursor, self)
    end)
    caixa:HookScript("OnEditFocusGained", function(self)
        anterior[self] = nil
        local ok, foto = pcall(Foto, self)
        atual[self] = ok and foto or nil
    end)
end

-- As caixas das janelas de chat, e as das janelas de sussurro que abrirem depois
local function LigarTodas()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        Ligar(_G["ChatFrame" .. i .. "EditBox"])
    end
    for _, nome in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do
        Ligar(_G[nome .. "EditBox"])
    end
end

K.AoEntrar(function()
    LigarTodas()
    if type(FCF_OpenTemporaryWindow) == "function" and hooksecurefunc then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            pcall(LigarTodas)
        end)
    end
end)
