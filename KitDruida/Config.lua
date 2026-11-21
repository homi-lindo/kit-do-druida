-- Kit do Druida: janela de ajustes e botão no minimapa.
-- Botão do minimapa: clique abre a janela; botão direito destrava (ou trava) todos os quadros;
-- arrastar leva o botão para outro ponto da borda do minimapa. /kit abre a janela.

local _, K = ...

---------------------------------------------------------------------------
-- Janela
---------------------------------------------------------------------------

local janela = CreateFrame("Frame", "KitDruidaJanela", UIParent)
janela:SetSize(430, 500)
janela:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
janela:SetFrameStrata("DIALOG")
janela:SetClampedToScreen(true)
janela:SetMovable(true)
janela:EnableMouse(true)
janela:RegisterForDrag("LeftButton")
janela:SetScript("OnDragStart", janela.StartMoving)
janela:SetScript("OnDragStop", janela.StopMovingOrSizing)
janela:Hide()
tinsert(UISpecialFrames, "KitDruidaJanela")   -- Esc fecha

local fundo = janela:CreateTexture(nil, "BACKGROUND")
fundo:SetAllPoints(janela)
fundo:SetColorTexture(0.04, 0.04, 0.06, 0.92)

local titulo = janela:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titulo:SetPoint("TOP", janela, "TOP", 0, -12)
titulo:SetText("Kit do Druida")

local okFechar, fechar = pcall(CreateFrame, "Button", nil, janela, "UIPanelCloseButton")
if okFechar and fechar then
    fechar:SetPoint("TOPRIGHT", janela, "TOPRIGHT", -2, -2)
else
    fechar = CreateFrame("Button", nil, janela, "UIPanelButtonTemplate")
    fechar:SetSize(24, 22)
    fechar:SetText("X")
    fechar:SetPoint("TOPRIGHT", janela, "TOPRIGHT", -6, -6)
    fechar:SetScript("OnClick", function()
        janela:Hide()
    end)
end

local botoes = {}
local y = -44

local function Secao(texto)
    local s = janela:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s:SetPoint("TOPLEFT", janela, "TOPLEFT", 16, y)
    s:SetText(texto)
    y = y - 22
end

-- Uma linha de botões; cada item = { largura, chave, função do clique }
local function Linha(itens)
    local x = 16
    for _, item in ipairs(itens) do
        local b = CreateFrame("Button", nil, janela, "UIPanelButtonTemplate")
        b:SetSize(item[1], 22)
        b:SetPoint("TOPLEFT", janela, "TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            item[3]()
            K.AtualizarJanela()
        end)
        botoes[item[2]] = b
        x = x + item[1] + 6
    end
    y = y - 28
end

local function SimNao(v)
    return v and "sim" or "não"
end

local function Porcento(nome)
    return math.floor(K.Escala(nome) * 100 + 0.5) .. "%"
end

local function AlternarBuff(chave)
    K.db.contador.buffs[chave] = not K.db.contador.buffs[chave]
    K.Contador.Desenhar()
end

local function Alternar(tabela, chave)
    tabela[chave] = not tabela[chave]
end

Linha({ { 398, "mover", function() K.ModoMover() end } })
y = y - 6

Secao("Contador de Buffs")
Linha({
    { 130, "contadorVer", function() K.AlternarVisivel("contador") end },
    { 128, "contadorMenos", function() K.MudarEscala("contador", -0.1) end },
    { 128, "contadorMais", function() K.MudarEscala("contador", 0.1) end },
})
Linha({
    { 196, "buff_motw", function() AlternarBuff("motw") end },
    { 196, "buff_thorns", function() AlternarBuff("thorns") end },
})
Linha({
    { 196, "buff_comida", function() AlternarBuff("comida") end },
    { 196, "buff_rested", function() AlternarBuff("rested") end },
})
Linha({
    { 196, "contadorSom", function() Alternar(K.db.contador, "som") end },
    { 196, "contadorTeste", function() K.Contador.Testar() end },
})
y = y - 6

Secao("Painel da Sessão")
Linha({
    { 130, "painelVer", function() K.AlternarVisivel("painel") end },
    { 128, "painelMenos", function() K.MudarEscala("painel", -0.1) end },
    { 128, "painelMais", function() K.MudarEscala("painel", 0.1) end },
})
Linha({ { 196, "painelNova", function() K.Painel.NovaSessao() end } })
y = y - 6

Secao("Aviso de Erva")
Linha({
    { 130, "ervaLigado", function() Alternar(K.db.erva, "ligado") end },
    { 128, "ervaMenos", function() K.MudarEscala("erva", -0.1) end },
    { 128, "ervaMais", function() K.MudarEscala("erva", 0.1) end },
})
Linha({
    { 196, "ervaSom", function() Alternar(K.db.erva, "som") end },
    { 196, "ervaTeste", function() K.Erva.Testar() end },
})
y = y - 6

Secao("Venda Certa")
Linha({ { 398, "vendaCinzas", function() Alternar(K.db.venda, "cinzas") end } })
y = y - 6

Secao("Preço no Ícone")
Linha({
    { 196, "precoLigado", function()
        Alternar(K.db.preco, "ligado")
        K.Preco.AtualizarTudo()
    end },
    { 196, "precoUnidade", function()
        Alternar(K.db.preco, "unidade")
        K.Preco.AtualizarTudo()
    end },
})
y = y - 6

Secao("Blocos de quests")
Linha({
    { 130, "blocosVer", function() K.AlternarVisivel("blocos") end },
    { 128, "blocosMenos", function() K.MudarEscala("blocos", -0.1) end },
    { 128, "blocosMais", function() K.MudarEscala("blocos", 0.1) end },
})
Linha({
    { 196, "blocosPinos", function()
        Alternar(K.db.blocos, "pinos")
        K.Blocos.AtualizarPinos()
    end },
    { 196, "blocosRecalcular", function() K.Blocos.Recalcular() end },
})
y = y - 6

Secao("Macros do Druida")
Linha({ { 398, "macrosCriar", function() K.Macros.Sincronizar() end } })
y = y - 6

Secao("Chat")
Linha({ { 398, "chatInterrogacao", function() Alternar(K.db.chat, "interrogacao") end } })

local dica = janela:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dica:SetPoint("TOPLEFT", janela, "TOPLEFT", 16, y - 4)
dica:SetWidth(398)
dica:SetJustifyH("LEFT")
dica:SetText("Botão direito no ícone do minimapa também destrava os quadros. "
    .. "A qualquer hora, Shift + arrastar move um quadro.")
janela:SetHeight(-y + 50)

function K.AtualizarJanela()
    if not K.db then
        return
    end
    botoes.mover:SetText(K.movendo and "Travar quadros" or "Destravar quadros para mover")
    botoes.contadorVer:SetText("Mostrar: " .. SimNao(K.QuadroVisivel("contador")))
    botoes.contadorMenos:SetText("Menor (" .. Porcento("contador") .. ")")
    botoes.contadorMais:SetText("Maior")
    for _, r in ipairs(K.BUFFS) do
        botoes["buff_" .. r.chave]:SetText(r.rotulo .. ": " .. SimNao(K.db.contador.buffs[r.chave]))
    end
    botoes.contadorSom:SetText("Som dos alertas: " .. SimNao(K.db.contador.som))
    botoes.contadorTeste:SetText("Testar alerta")
    botoes.painelVer:SetText("Mostrar: " .. SimNao(K.QuadroVisivel("painel")))
    botoes.painelMenos:SetText("Menor (" .. Porcento("painel") .. ")")
    botoes.painelMais:SetText("Maior")
    botoes.painelNova:SetText("Começar sessão nova")
    botoes.ervaLigado:SetText("Ligado: " .. SimNao(K.db.erva.ligado))
    botoes.ervaMenos:SetText("Menor (" .. Porcento("erva") .. ")")
    botoes.ervaMais:SetText("Maior")
    botoes.ervaSom:SetText("Som: " .. SimNao(K.db.erva.som))
    botoes.ervaTeste:SetText("Testar aviso")
    botoes.vendaCinzas:SetText("Vender os itens cinza: " .. SimNao(K.db.venda.cinzas))
    botoes.precoLigado:SetText("Preço na bolsa: " .. SimNao(K.db.preco.ligado))
    botoes.precoUnidade:SetText("Valor: " .. (K.db.preco.unidade and "de uma unidade" or "da pilha inteira"))
    botoes.blocosVer:SetText("Mostrar: " .. SimNao(K.QuadroVisivel("blocos")))
    botoes.blocosMenos:SetText("Menor (" .. Porcento("blocos") .. ")")
    botoes.blocosMais:SetText("Maior")
    botoes.blocosPinos:SetText("Marcadores no mapa: " .. SimNao(K.db.blocos.pinos))
    botoes.blocosRecalcular:SetText("Recalcular agora")
    local feitos, total = K.Macros.Contagem()
    botoes.macrosCriar:SetText(string.format("Criar ou atualizar os macros do guia (%d de %d no personagem)",
        feitos, total))
    botoes.chatInterrogacao:SetText("\"?\" com AltGr+W sem apagar a palavra: " .. SimNao(K.db.chat.interrogacao))
end
janela:SetScript("OnShow", K.AtualizarJanela)

function K.AlternarJanela()
    janela:SetShown(not janela:IsShown())
end

---------------------------------------------------------------------------
-- Botão no minimapa
---------------------------------------------------------------------------

local botaoMapa = CreateFrame("Button", "KitDruidaBotaoMinimapa", Minimap)
botaoMapa:SetSize(31, 31)
botaoMapa:SetFrameStrata("MEDIUM")
botaoMapa:SetFrameLevel(8)
botaoMapa:RegisterForClicks("LeftButtonUp", "RightButtonUp")
botaoMapa:RegisterForDrag("LeftButton")

local fundoMapa = botaoMapa:CreateTexture(nil, "BACKGROUND")
fundoMapa:SetSize(20, 20)
fundoMapa:SetPoint("TOPLEFT", botaoMapa, "TOPLEFT", 7, -5)
fundoMapa:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local iconeMapa = botaoMapa:CreateTexture(nil, "ARTWORK")
iconeMapa:SetSize(17, 17)
iconeMapa:SetPoint("TOPLEFT", botaoMapa, "TOPLEFT", 7, -6)
iconeMapa:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")
iconeMapa:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local bordaMapa = botaoMapa:CreateTexture(nil, "OVERLAY")
bordaMapa:SetSize(53, 53)
bordaMapa:SetPoint("TOPLEFT", botaoMapa, "TOPLEFT", 0, 0)
bordaMapa:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

botaoMapa:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function PosicionarBotao()
    local angulo = math.rad((K.db and K.db.minimapa.angulo) or 225)
    local raio = (Minimap:GetWidth() / 2) + 5
    botaoMapa:ClearAllPoints()
    botaoMapa:SetPoint("CENTER", Minimap, "CENTER", math.cos(angulo) * raio, math.sin(angulo) * raio)
end

local function SeguirCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then
        return
    end
    local cx, cy = GetCursorPosition()
    local escala = Minimap:GetEffectiveScale()
    cx, cy = cx / escala, cy / escala
    K.db.minimapa.angulo = math.deg(math.atan2(cy - my, cx - mx))
    PosicionarBotao()
end

botaoMapa:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", SeguirCursor)
end)
botaoMapa:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)
botaoMapa:SetScript("OnClick", function(_, botao)
    if botao == "RightButton" then
        K.ModoMover()
    else
        K.AlternarJanela()
    end
end)
botaoMapa:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Kit do Druida")
    GameTooltip:AddLine("Clique: ajustes", 1, 1, 1)
    GameTooltip:AddLine("Botão direito: destravar ou travar os quadros para mover", 1, 1, 1)
    GameTooltip:AddLine("Arraste: muda este botão de lugar", 1, 1, 1)
    GameTooltip:Show()
end)
botaoMapa:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

K.AoEntrar(PosicionarBotao)

SLASH_KITDRUIDA1 = "/kit"
SlashCmdList.KITDRUIDA = function(msg)
    msg = type(msg) == "string" and msg:lower() or ""
    if msg:find("mover", 1, true) then
        K.ModoMover()
    elseif msg:find("macro", 1, true) then
        K.Macros.Sincronizar()
    else
        K.AlternarJanela()
    end
end
