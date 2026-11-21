-- Kit do Druida: Venda Certa.
-- Na janela do vendedor, um botão vende de uma vez os itens cinza e os que rendem menos no
-- leilão do que no vendedor. O preço do leilão vem do Auctionator (é preciso ter feito um Full
-- Scan); dele se desconta a taxa de 5% da casa de leilão. Ficam na bolsa: item sem preço
-- conhecido no leilão, item vinculado (soulbound) e item sem valor no vendedor.
-- Antes de vender, a lista sai no chat e uma janela pede confirmação com o total.

local NOME, K = ...

local TAXA_LEILAO = 0.05
local POR_VEZ = 8          -- itens vendidos por rodada
local INTERVALO = 0.3      -- segundos entre rodadas

local vendendo = false

local function TemAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink
end

local function PrecoLeilao(link)
    if not TemAuctionator() then
        return nil
    end
    local ok, preco = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, NOME, link)
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

-- Itens a vender: { bolsa, slot, link, qtd, valor, motivo }, e o total em cobre
local function Listar()
    local lista, total = {}, 0
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return lista, total
    end
    local cinzas = not K.db or K.db.venda.cinzas ~= false
    for bolsa = 0, (NUM_BAG_SLOTS or 4) do
        local vagas = C_Container.GetContainerNumSlots(bolsa) or 0
        for slot = 1, vagas do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bolsa, slot)
            if ok and type(info) == "table" and type(info.hyperlink) == "string"
                and not info.isLocked and not info.hasNoValue then
                local link = info.hyperlink
                local qtd = info.stackCount or 1
                local vendedor = PrecoVendedor(link)
                if vendedor then
                    local motivo
                    if info.quality == 0 then
                        if cinzas then
                            motivo = "cinza"
                        end
                    elseif not info.isBound then
                        local leilao = PrecoLeilao(link)
                        if leilao and leilao * (1 - TAXA_LEILAO) < vendedor then
                            motivo = "leilão " .. K.MoedaIcone(leilao) .. ", vendedor " .. K.MoedaIcone(vendedor)
                        end
                    end
                    if motivo then
                        lista[#lista + 1] = { bolsa = bolsa, slot = slot, link = link, qtd = qtd,
                            valor = vendedor * qtd, motivo = motivo }
                        total = total + vendedor * qtd
                    end
                end
            end
        end
    end
    return lista, total
end

local function Mostrar(lista, total)
    for _, item in ipairs(lista) do
        local quantos = item.qtd > 1 and (" x" .. item.qtd) or ""
        print(K.PREFIXO .. item.link .. quantos .. ": " .. K.MoedaIcone(item.valor) .. " (" .. item.motivo .. ")")
    end
    print(K.PREFIXO .. #lista .. " item(ns), " .. K.MoedaIcone(total) .. " no total.")
    if not TemAuctionator() then
        print(K.PREFIXO .. "sem o Auctionator, só os cinzas entram.")
    end
end

local function Vender(lista)
    if vendendo or type(lista) ~= "table" then
        return
    end
    vendendo = true
    local i = 1
    local function Rodada()
        if not (MerchantFrame and MerchantFrame:IsShown()) or InCombatLockdown() then
            vendendo = false
            print(K.PREFIXO .. "parei: a janela do vendedor fechou ou você entrou em combate.")
            return
        end
        local ultimo = math.min(i + POR_VEZ - 1, #lista)
        for k = i, ultimo do
            local item = lista[k]
            local ok, info = pcall(C_Container.GetContainerItemInfo, item.bolsa, item.slot)
            if ok and type(info) == "table" and info.hyperlink == item.link and not info.isLocked then
                C_Container.UseContainerItem(item.bolsa, item.slot)
            end
        end
        i = ultimo + 1
        if i <= #lista then
            C_Timer.After(INTERVALO, Rodada)
        else
            vendendo = false
        end
    end
    Rodada()
end

StaticPopupDialogs["KITDRUIDA_VENDA"] = {
    text = "Vender %s item(ns) por %s?",
    button1 = YES or "Sim",
    button2 = NO or "Não",
    OnAccept = function(_, lista)
        Vender(lista)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Perguntar()
    if InCombatLockdown() then
        print(K.PREFIXO .. "em combate não dá; tente depois.")
        return
    end
    local lista, total = Listar()
    if #lista == 0 then
        print(K.PREFIXO .. "nada para vender.")
        return
    end
    Mostrar(lista, total)
    StaticPopup_Show("KITDRUIDA_VENDA", #lista, K.MoedaIcone(total), lista)
end

local botao
local function CriarBotao()
    if botao or not MerchantFrame then
        return
    end
    botao = CreateFrame("Button", "KitDruidaVendaBotao", MerchantFrame, "UIPanelButtonTemplate")
    botao:SetSize(130, 24)
    botao:SetPoint("BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", 0, 4)
    botao:SetText("Venda certa")
    botao:SetScript("OnClick", Perguntar)
    botao:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Venda Certa")
        GameTooltip:AddLine("Vende os cinzas e o que rende menos no leilão do que no vendedor. "
            .. "Mostra a lista e pede confirmação antes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    botao:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local eventos = CreateFrame("Frame")
eventos:RegisterEvent("MERCHANT_SHOW")
eventos:SetScript("OnEvent", CriarBotao)

SLASH_KITVENDA1 = "/venda"
SlashCmdList.KITVENDA = function()
    local lista, total = Listar()
    if #lista == 0 then
        print(K.PREFIXO .. "nada para vender agora.")
    else
        Mostrar(lista, total)
        print(K.PREFIXO .. "isto é só a lista; a venda é pelo botão na janela do vendedor.")
    end
end
