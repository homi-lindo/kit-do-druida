-- Kit do Druida: Preço no Ícone.
-- Escreve em cada item da bolsa o preço do leilão (em cima, em azul) e o do vendedor (embaixo,
-- em dourado). O que rende mais, já descontada a taxa de 5% do leilão, fica aceso; o outro, cinza.
-- O preço do leilão vem do Auctionator e precisa de um Full Scan. Item vinculado (soulbound) não
-- vai a leilão: mostra só o vendedor. Item sem valor no vendedor mostra só o leilão.
-- Na janela do Kit: mostrar ou não, e valor da pilha inteira ou de uma unidade.
--
-- Os ganchos na bolsa são os do Pawn para o Forever (PawnBags.lua): o UpdateItems de cada
-- ContainerFrame e do ContainerFrameCombinedBags, com EnumerateValidItems.

local _, K = ...
local P = {}
K.Preco = P

local TAXA_LEILAO = 0.05
local COR_VENDEDOR = { 1, 0.82, 0 }
local COR_LEILAO = { 0.35, 0.8, 1 }
local COR_APAGADA = { 0.55, 0.55, 0.55 }
local MODERNO = ContainerFrameMixin ~= nil
local QUADROS = NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES or 13

K.AoCarregar(function()
    if type(K.db.preco) ~= "table" then
        K.db.preco = {}
    end
    if K.db.preco.ligado == nil then
        K.db.preco.ligado = true
    end
    if K.db.preco.unidade == nil then
        K.db.preco.unidade = false
    end
end)

local function Opcoes()
    return (K.db and K.db.preco) or { ligado = true, unidade = false }
end

-- Preço curto, que cabe no ícone: 125g, 15g, 1,2g, 35s, 8c
local function Curto(cobre)
    cobre = math.floor(cobre + 0.5)
    if cobre >= 100000 then
        return math.floor(cobre / 10000) .. "g"
    elseif cobre >= 10000 then
        local decimal = string.format("%.1f", math.floor(cobre / 1000) / 10)
        return (decimal:gsub("%.0$", ""):gsub("%.", ",")) .. "g"
    elseif cobre >= 100 then
        return math.floor(cobre / 100) .. "s"
    end
    return cobre .. "c"
end

local function PrecoLeilao(link)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink) then
        return nil
    end
    local ok, preco = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, K.NOME, link)
    if ok and type(preco) == "number" and preco > 0 then
        return preco
    end
    return nil
end

local function PrecoVendedor(link)
    local buscar = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not buscar then
        return nil
    end
    local resultado = { pcall(buscar, link) }
    local preco = resultado[1] and resultado[12] or nil   -- 11º valor de GetItemInfo, depois do ok do pcall
    if type(preco) == "number" and preco > 0 then
        return preco
    end
    return nil
end

local function Textos(botao)
    if not botao.KitLeilao then
        botao.KitLeilao = botao:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        botao.KitLeilao:SetPoint("TOPLEFT", botao, "TOPLEFT", 2, -2)
        botao.KitVendedor = botao:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        botao.KitVendedor:SetPoint("BOTTOMLEFT", botao, "BOTTOMLEFT", 2, 2)
    end
    return botao.KitLeilao, botao.KitVendedor
end

local function Bolsa(botao)
    if botao.GetBagID then
        return botao:GetBagID()
    end
    local pai = botao:GetParent()
    return pai and pai:GetID()
end

local function AtualizarBotao(botao)
    if not botao or botao.isExtended or not botao.CreateFontString then
        return
    end
    local leilaoTexto, vendedorTexto = Textos(botao)
    leilaoTexto:SetText("")
    vendedorTexto:SetText("")
    local opcoes = Opcoes()
    if not opcoes.ligado then
        return
    end
    local okBolsa, bolsa = pcall(Bolsa, botao)
    local slot = botao:GetID()
    if not okBolsa or type(bolsa) ~= "number" or type(slot) ~= "number" then
        return
    end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bolsa, slot)
    if not ok or type(info) ~= "table" or type(info.hyperlink) ~= "string" then
        return
    end
    local qtd = opcoes.unidade and 1 or (info.stackCount or 1)
    local vendedor = (not info.hasNoValue) and PrecoVendedor(info.hyperlink) or nil
    local leilao = (not info.isBound) and PrecoLeilao(info.hyperlink) or nil
    local leilaoRendeMais = leilao and (not vendedor or leilao * (1 - TAXA_LEILAO) > vendedor)
    if leilao then
        local cor = leilaoRendeMais and COR_LEILAO or COR_APAGADA
        leilaoTexto:SetText(Curto(leilao * qtd))
        leilaoTexto:SetTextColor(cor[1], cor[2], cor[3])
    end
    if vendedor then
        local cor = leilaoRendeMais and COR_APAGADA or COR_VENDEDOR
        vendedorTexto:SetText(Curto(vendedor * qtd))
        vendedorTexto:SetTextColor(cor[1], cor[2], cor[3])
    end
end

local function AtualizarQuadro(quadro)
    if not quadro then
        return
    end
    if MODERNO and quadro.EnumerateValidItems then
        for _, botao in quadro:EnumerateValidItems() do
            AtualizarBotao(botao)
        end
    elseif quadro.GetName and quadro:GetName() then
        local prefixo = quadro:GetName() .. "Item"
        for i = 1, (quadro.size or 0) do
            AtualizarBotao(_G[prefixo .. i])
        end
    end
end

function P.AtualizarTudo()
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        AtualizarQuadro(ContainerFrameCombinedBags)
    end
    for i = 1, QUADROS do
        local quadro = _G["ContainerFrame" .. i]
        if quadro and quadro:IsShown() then
            AtualizarQuadro(quadro)
        end
    end
end

local function Ganchos()
    if MODERNO then
        if type(ContainerFrameMixin.UpdateItems) == "function" then
            hooksecurefunc(ContainerFrameMixin, "UpdateItems", AtualizarQuadro)
        end
        -- O gancho no mixin não alcança as bolsas já criadas: cada uma ganha o seu
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
            hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", AtualizarQuadro)
        end
        for i = 1, QUADROS do
            local quadro = _G["ContainerFrame" .. i]
            if quadro and quadro.UpdateItems then
                hooksecurefunc(quadro, "UpdateItems", AtualizarQuadro)
            end
        end
    elseif ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", AtualizarQuadro)
    end
end

K.AoEntrar(function()
    Ganchos()
    P.AtualizarTudo()
end)

local eventos = CreateFrame("Frame")
eventos:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(eventos.RegisterEvent, eventos, "AUCTION_HOUSE_CLOSED")
eventos:SetScript("OnEvent", function()
    if K.db then
        P.AtualizarTudo()
    end
end)
