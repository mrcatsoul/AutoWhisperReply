local ADDON_NAME = ...

local STRING_SCHOOL_UNKNOWN = STRING_SCHOOL_UNKNOWN

local LOCALE = GetLocale()
local ADDON_NAME_LOCALE_SHORT = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"TitleS-ruRU") or GetAddOnMetadata(ADDON_NAME,"TitleS") or ADDON_NAME
local ADDON_NAME_LOCALE = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Title-ruRU") or GetAddOnMetadata(ADDON_NAME,"Title") or ADDON_NAME
local ADDON_NOTES = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Notes-ruRU") or GetAddOnMetadata(ADDON_NAME,"Notes") or STRING_SCHOOL_UNKNOWN
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME,"Version") or STRING_SCHOOL_UNKNOWN

local slashCmd = "/awr"

local cfg, friendsNames, messageCD, recentlySendPMNames, guildMembersNames, notifiedMsgs = {}, {}, {}, {}, {}, {}
local playerName = UnitName("player")

local print = print
local wipe = table.wipe
local GetNumFriends = GetNumFriends
local SendChatMessage = SendChatMessage
local UnitIsDND = UnitIsDND
local GetGuildRosterInfo = GetGuildRosterInfo
local GetFriendInfo = GetFriendInfo
local GetNumGuildMembers = GetNumGuildMembers
local GetTime = GetTime
local ShowFriends = ShowFriends
local GetPlayerInfoByGUID = GetPlayerInfoByGUID

local function _print(msg,msg2,msg3,frame)
  if not cfg.enable_chat_print then return end
  if frame then
    frame:AddMessage("|cff3399ff["..ADDON_NAME_LOCALE_SHORT.."]|r: "..msg, msg2 and msg2 or "", msg3 and msg3 or "")
  else
    print("|cff3399ff["..ADDON_NAME_LOCALE_SHORT.."]|r: "..msg, msg2 and msg2 or "", msg3 and msg3 or "")
  end
end

local f = CreateFrame("frame")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)

function f:CHAT_MSG_WHISPER(...)
  local msg, name = ...
  if not cfg.enable_addon or not cfg.enable_auto_reply or not name or name == "" or name == STRING_SCHOOL_UNKNOWN or name == playerName then return end
  local noReply = (cfg.enable_accept_pm_from_friends_only and friendsNames[name]) 
                  or (cfg.enable_accept_pm_from_guild_members and guildMembersNames[name])
                  or (cfg.enable_accept_pm_we_recently_whisper_send and recentlySendPMNames[name])
                  or not (cfg.enable_accept_pm_from_friends_only or cfg.enable_accept_pm_from_guild_members or cfg.enable_accept_pm_we_recently_whisper_send)
  local shouldReply = not noReply
  --print("shouldReply",shouldReply)
  if shouldReply then
    local t = GetTime()
    if messageCD[name] and messageCD[name] < t then
      messageCD[name] = nil
    end
    if not messageCD[name] then
      messageCD[name] = t + cfg.auto_reply_cooldown
      --print(cfg.auto_reply_message,name)
      SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName),"WHISPER",nil,name)
    end
  end
end

function f:CHAT_MSG_WHISPER_INFORM(...)
  local msg, name = ...
  if not cfg.enable_addon or not name or name == "" or name == STRING_SCHOOL_UNKNOWN or msg == cfg.auto_reply_message:gsub("#playerName",playerName) then return end
  if cfg.enable_accept_pm_we_recently_whisper_send and not recentlySendPMNames[name] and not ( (cfg.enable_accept_pm_from_friends_only and friendsNames[name]) or (cfg.enable_accept_pm_from_guild_members and guildMembersNames[name]) ) then
    _print(name, "временно добавлен в белый список для общения")
    recentlySendPMNames[name] = true
  end
  if cfg.auto_disable_dnd_on_whisper_sent and UnitIsDND("player") then
    if not cfg.enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent then
      cfg.enable_auto_dnd = false
    end
    SendChatMessage("", "DND")
  end
end

function f:PLAYER_ENTERING_WORLD(...)
  f:onFirstLaunch()
  playerName = UnitName("player")
  ShowFriends()
  if not cfg.enable_addon then return end
  if cfg.enable_auto_dnd and not UnitIsDND("player") and (cfg.enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent or not cfg.auto_disable_dnd_on_whisper_sent) then
    SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
    _print("Режим авто-|cffff0000DND|r включен, автоответ для фанатов: "..cfg.auto_reply_message:gsub("#playerName",playerName).."")
  end
end

function f:GUILD_ROSTER_UPDATE()
  --print("GUILD_ROSTER_UPDATE")
  wipe(guildMembersNames)
  for i=1,GetNumGuildMembers() do
    local name = GetGuildRosterInfo(i)
    if name and name~="" and name~=STRING_SCHOOL_UNKNOWN then 
      guildMembersNames[name] = true
    end
  end
end

function f:FRIENDLIST_UPDATE()
  --print("FRIENDLIST_UPDATE")
  wipe(friendsNames)
  for i=1,GetNumFriends() do
    local name = GetFriendInfo(i)
    if name and name~="" and name~=STRING_SCHOOL_UNKNOWN then 
      friendsNames[name] = true
      --print(name)
    end
  end
end

local classColors = {
  ["DEATHKNIGHT"] = "C41F3B", -- 1
  ["DRUID"] = "FF7D0A",       -- 2
  ["HUNTER"] = "A9D271",      -- 3
  ["MAGE"] = "40C7EB",        -- 4
  ["PALADIN"] = "F58CBA",     -- 5
  ["PRIEST"] = "FFFFFF",      -- 6
  ["ROGUE"] = "FFF569",       -- 7
  ["SHAMAN"] = "0070DE",      -- 8
  ["WARLOCK"] = "8787ED",     -- 9
  ["WARRIOR"] = "C79C6E",     -- 10
  ["UNKNOWN"] = "999999",     -- 11
}

local function PlayerWhisperHyperLink(name,guid,class,addBrackets)
  local link
  
  if (not class) and guid then
    class = select(2,GetPlayerInfoByGUID(guid))
  end

  if name then
    local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "999999"
  
    if addBrackets then
      link = "|Hplayer:"..name..":WHISPER:"..string.upper(name).."|h[|c"..classColor..""..name.."|r]|h"
    else
      link = "|Hplayer:"..name..":WHISPER:"..string.upper(name).."|h|c"..classColor..""..name.."|r|h"
    end
  else
    link = addBrackets and "|cff999999[UNKNOWN]|r" or "|cff999999UNKNOWN|r"
  end
  
  return link
end

--local MARKED_DND = MARKED_DND

local function chatFilter(self, event, msg, name, ...)
  --print((cfg.enable_accept_pm_from_friends_only and friendsNames[name]))
  if not (msg and name) then return end
  local isGoodMsg = not cfg.enable_addon
  or (event=="CHAT_MSG_SYSTEM" --[[and cfg.enable_auto_dnd]] and not msg:find(cfg.auto_reply_message:gsub("#playerName",playerName)) --[[not msg:match(MARKED_DND:gsub("%%s", "(.+)"))]])
  or (event=="CHAT_MSG_WHISPER_INFORM" and msg~=cfg.auto_reply_message:gsub("#playerName",playerName))
  or (event=="CHAT_MSG_WHISPER" and ( (cfg.enable_accept_pm_we_recently_whisper_send and recentlySendPMNames[name]) or (cfg.enable_accept_pm_from_friends_only and friendsNames[name]) or (cfg.enable_accept_pm_from_guild_members and guildMembersNames[name]) ) )
  or (event=="CHAT_MSG_WHISPER" and not cfg.enable_accept_pm_we_recently_whisper_send and not cfg.enable_accept_pm_from_friends_only and not cfg.enable_accept_pm_from_guild_members)
  or ((event=="CHAT_MSG_WHISPER" or event=="CHAT_MSG_WHISPER_INFORM") and not cfg.enable_hide_blocked_messages)
  if not isGoodMsg then
    if event=="CHAT_MSG_WHISPER" and cfg.enable_blocked_msg_notification then
      local msgId, senderGuid = select(9,...)
      --print(GetPlayerInfoByGUID(senderGuid))
      if not notifiedMsgs[msgId] then
        notifiedMsgs[msgId] = true
        _print("Входящее сообщение от "..PlayerWhisperHyperLink(name,senderGuid,nil,true).." было заблокировано для показа")
      end
    end
    --if event=="CHAT_MSG_WHISPER" then
      --print("not isGoodMsg")
    --end
    return true
  end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", chatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", chatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", chatFilter)

-- чат линк
local function ChatLink(text,option,colorHex,chatTarget)
  text = text or "ТЫК"
  option = option or ""
  chatTarget = chatTarget or ""
  colorHex = colorHex or "71d5ff"
  return "|cff"..colorHex.."|Haddon:"..ADDON_NAME.."_link:"..option..":"..chatTarget..":|h["..text.."|r|cff"..colorHex.."]|h|r"
end

DEFAULT_CHAT_FRAME:HookScript("OnHyperlinkClick", function(self, link, str, button, ...)
  local linkType, arg1, option, chatTarget = strsplit(":", link)
  if linkType == "addon" and arg1 and option and arg1==""..ADDON_NAME.."_link" then
    if option == "Settings" then
      InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
      if not f.cfgFrame:IsShown() then
        --print("dsdfsf")
        InterfaceOptionsFrameAddOnsListScrollBarScrollDownButton:Click()
        InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
      end
    end
  end
end)

do
  local old = ItemRefTooltip.SetHyperlink 
  function ItemRefTooltip:SetHyperlink(link, ...)
    if link:find(ADDON_NAME.."_link") then return end
    return old(self, link, ...)
  end
end

-- опции
local options =
{
  {"enable_addon","Включить аддон",nil,true},
  {"enable_accept_pm_from_friends_only","Принимать входящие только пм от друзей",nil,false},
  {"enable_accept_pm_from_guild_members","Принимать входящие только пм от согильдейцев",nil,false},
  {"enable_accept_pm_we_recently_whisper_send","Принимать входящие только пм от тех, кому мы сами недавно писали в пм (разрешение работает до следующего релога)",nil,false},
  {"enable_auto_reply","Включить автоответ в пм тем, чьи входящие мы не принимаем (должен быть включен хотя бы один пункт выше)",nil,true},
  {"auto_reply_message","Сообщение автоответ. Ввод пустой строки выставит сообщение по умолчанию",nil,"#playerName не может сейчас ответить т.к афк. Попробуй написать позже."},
  {"auto_reply_cooldown","Отправлять автоответ не чаще чем раз в N сек",nil,10,1,100000},
  {"enable_hide_blocked_messages","Скрывать заблокированные сообщения",nil,true},
  {"enable_blocked_msg_notification","Отображать уведомления о заблокированных сообщениях",nil,false},
  {"enable_auto_dnd","Держать режим |cffff0000DND(не беспокоить)|r включенным всегда",nil,false},
  {"auto_disable_dnd_on_whisper_sent","Выключать режим |cffff0000DND|r если отправляем сообщение кому-то в пм (чтобы нам могли ответить)",nil,true},
  {"enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent","Снова включать |cffff0000DND|r при смене зоны если тот был |cffff0000ВЫКЛЮЧЕН|r при отправке сообщения кому-либо в пм(опцией выше), и до этого DND был |cff00ff00ВКЛЮЧЕН|r",nil,true},
  {"enable_chat_print","Инфо сообщения от аддона в чат (принты/лог работы)",nil,true},
}

--------------------------------------------------------------------------------
-- фрейм прокрутки для фрейма настроек. нужен чтобы прокручивать настройки вверх-вниз
--------------------------------------------------------------------------------
local CFG_SCROLL_FRAME_WIDTH, CFG_SCROLL_FRAME_HEIGHT = 800, 400

local cfgScrollFrame = CreateFrame("ScrollFrame", ADDON_NAME.."SettingsScrollFrame", InterfaceOptionsFramePanelContainer, "UIPanelScrollFrameTemplate")
f.cfgScrollFrame = cfgScrollFrame
cfgScrollFrame.name = ADDON_NAME_LOCALE  -- Название во вкладке интерфейса
cfgScrollFrame:SetSize(CFG_SCROLL_FRAME_WIDTH, CFG_SCROLL_FRAME_HEIGHT)
cfgScrollFrame:Hide()
cfgScrollFrame:SetVerticalScroll(10)
cfgScrollFrame:SetHorizontalScroll(10)
_G[ADDON_NAME.."SettingsScrollFrameScrollBar"]:SetPoint("topleft",cfgScrollFrame,"topright",-25,-25)
_G[ADDON_NAME.."SettingsScrollFrameScrollBar"]:SetFrameLevel(1000)
_G[ADDON_NAME.."SettingsScrollFrameScrollBarScrollDownButton"]:SetPoint("top",_G[ADDON_NAME.."SettingsScrollFrameScrollBar"],"bottom",0,7)

--------------------------------------------------------------------------------
-- фрейм настроек который должен быть помещен в фрейм прокрутки
--------------------------------------------------------------------------------
cfgFrame = CreateFrame("button", ADDON_NAME.."_cfgFrame", InterfaceOptionsFramePanelContainer)
f.cfgFrame = cfgFrame
cfgFrame:SetSize(CFG_SCROLL_FRAME_WIDTH, CFG_SCROLL_FRAME_HEIGHT) 
cfgFrame:SetAllPoints(InterfaceOptionsFramePanelContainer)
--cfgFrame:Hide()
cfgFrame:RegisterEvent("ADDON_LOADED")
cfgFrame:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)

function cfgFrame:ADDON_LOADED(addon)
  if addon==ADDON_NAME then
    cfgFrame:InitConfig()
    cfgFrame:UpdateVisual()
    cfgFrame:CreateOptions()
    _print("Аддон загружен. Настройки:|r "..ChatLink("Линк","Settings")..", либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r")
  end
end

--------------------------------------------------------------------------------
-- связываем скролл-фрейм с фреймом настроек в котором все опции
--------------------------------------------------------------------------------
cfgScrollFrame:SetScrollChild(cfgFrame)

--------------------------------------------------
-- регистрируем фрейм настроек в близ настройках интерфейса (интерфейс->модификации) этой самой функцией 
--------------------------------------------------
InterfaceOptions_AddCategory(cfgScrollFrame)

--------------------------------------------------------------------------------
-- при показе/скрытии скролл-фрейма - показывается/скрывается фрейм настроек
--------------------------------------------------------------------------------
cfgScrollFrame:SetScript("OnShow", function()
  --print("cfgFrame:Show")
  cfgFrame:Show()
end)

cfgScrollFrame:SetScript("OnHide", function()
  cfgFrame:Hide()
end)

--------------------------------------------------------------------------------
-- заголовок фрейма опций
--------------------------------------------------------------------------------
do
  local text = cfgFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetTextColor(1, 1, 1)
  text:SetFont(GameFontNormal:GetFont(), 18, "OUTLINE")
  text:SetText(ADDON_NAME_LOCALE.." v"..ADDON_VERSION.."")
  text:SetJustifyH("LEFT")
  text:SetJustifyV("BOTTOM")
  cfgFrame.TitleText = text
end

--------------------------------------------------------------------------------
-- тултип (подсказка) для заголовка фрейма опций
--------------------------------------------------------------------------------
do
  local tip = CreateFrame("button", nil, cfgFrame)
  tip:SetPoint("center",cfgFrame.TitleText,"center")
  --tip:SetSize(cfgFrame.TitleText:GetStringWidth()+11,cfgFrame.TitleText:GetStringHeight()+1) -- Измените размеры фрейма настроек ++ 4.3.24
  
  --------------------------------------------------------------------------------
  -- действия при наведении мышкой на тултип
  --------------------------------------------------------------------------------
  tip:SetScript("OnEnter", function(self) -- при наведении мышкой на фрейм чекбокса (маусовер) ...
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(""..ADDON_NAME_LOCALE.." v"..ADDON_VERSION.."", nil, nil, nil, nil, true)
    GameTooltip:AddLine("\n"..ADDON_NOTES, 1, 1, 1, true)
    GameTooltip:Show() -- ... появится подсказка
  end)

  tip:SetScript("OnLeave", function(self) -- при снятии фокуса мышки с фрейма чекбокса ... 
    GameTooltip:Hide() -- ... подсказка скроется
  end)
  
  tip:SetScript("OnShow", function(self)
    tip:SetSize(cfgFrame.TitleText:GetStringWidth(),cfgFrame.TitleText:GetStringHeight()) 
  end)
end

function cfgFrame:UpdateVisual()
  if not cfg.enable_addon or not cfg.enable_auto_dnd then
    if UnitIsDND("player") then
      SendChatMessage("", "DND")
    end
  elseif cfg.enable_auto_dnd then
    if not UnitIsDND("player") then
      SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
    end
  end
  cfgFrame:Hide()
  -- cfgScrollFrame:Hide()
  cfgFrame:Show()
  -- cfgScrollFrame:Show()
  wipe(messageCD)
end

function cfgFrame:InitConfig()
  cfg = mrcatsoul_AutoWhisperReply or {}

  -- [1] - settingName, [2] - checkboxText, [3] - tooltipText, [4] - значение по умолчанию, [5] - minValue, [6] - maxValue  
  for _,v in ipairs(options) do
    if cfg[v[1]]==nil then
      cfg[v[1]]=v[4]
      --_print(""..v[1]..": "..tostring(cfg[v[1]]).." (задан параметр по умолчанию)")
    end
  end

  if mrcatsoul_AutoWhisperReply == nil then
    mrcatsoul_AutoWhisperReply = cfg
    cfg = mrcatsoul_AutoWhisperReply
    _print("Инициализация конфига")
    cfgFrame.isFirstLaunch = true
  end
end

function cfgFrame:CreateOptions()
  if cfgFrame.options then return end
  cfgFrame.options=true
  cfgFrame.optNum=0
  
  -- [1] - settingName, [2] - checkboxText, [3] - tooltipText, [4] - значение по умолчанию, [5] - minValue, [6] - maxValue 
  for i,v in ipairs(options) do
    if v[4]~=nil then
      --print(type(v[4]))
      if type(v[4])=="boolean" then
        cfgFrame:createCheckbox(v[1], v[2], v[3], v[4], cfgFrame.optNum)
        if options[i+1] and (type(options[i+1][4])=="number" or type(options[i+1][4])=="string") then
          cfgFrame.optNum=cfgFrame.optNum+3
        else
          cfgFrame.optNum=cfgFrame.optNum+2
        end
      elseif type(v[4])=="number" or type(v[4])=="string" then
        cfgFrame:createEditBox(v[1], v[2], v[3], v[4], v[5], v[6], cfgFrame.optNum)
        if options[i+1] and type(options[i+1][4])=="boolean" then
          cfgFrame.optNum=cfgFrame.optNum+1.5
        else
          cfgFrame.optNum=cfgFrame.optNum+2
        end
      end
    end
  end
end

---------------------------------------------------------------
-- функция создания чекбоксов. так как их будет много - нужно будет спамить её по кд
---------------------------------------------------------------
function cfgFrame:createCheckbox(settingName,checkboxText,tooltipText,defValue,optNum) -- offsetY отступ от cfgFrame.TitleText
  local checkBox = CreateFrame("CheckButton",ADDON_NAME.."_"..settingName,cfgFrame,"UICheckButtonTemplate") -- фрейм чекбокса
  checkBox:SetPoint("TOPLEFT", cfgFrame.TitleText, "BOTTOMLEFT", 0, -10-(optNum*10))
  checkBox:SetSize(28,28)
  
  local textFrame = CreateFrame("Button",nil,checkBox) -- фрейм текст чекбокса, не совсем по гениальному, ну лан
  textFrame:SetPoint("LEFT", checkBox, "RIGHT", 0, 0)
  
  local text = textFrame:CreateFontString(nil, "ARTWORK") -- текст для чекбокса
  text:SetFont(GameFontNormal:GetFont(), 12)
  text:SetText(checkboxText)
  text:SetAllPoints(textFrame)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("BOTTOM")
  
  --textFrame:SetSize(text:GetStringWidth(), text:GetStringHeight()) -- ставим длинее чем длина текста а то чет он сокращается троеточием, тут надо бы разобраться кек 
  
  if not tooltipText then
    tooltipText = checkboxText
  end
  
  checkBox:SetScript("OnClick", function(self) -- по клику по фрейму проставляется настройка, чекбокс
    cfg[settingName] = self:GetChecked() and true or false
    cfgFrame:UpdateVisual()
    _print(""..settingName..":",tostring(cfg[settingName]))
  end)
  
  textFrame:SetScript("OnShow", function(self)
    self:SetSize(text:GetStringWidth(), text:GetStringHeight())
  end)
  
  textFrame:SetScript("OnClick", function() -- по клику по фрейму проставляется настройка, текст
    if checkBox:GetChecked() then
      checkBox:SetChecked(false)
    else
      checkBox:SetChecked(true)
    end
    cfg[settingName] = checkBox:GetChecked() and true or false
    cfgFrame:UpdateVisual()
    _print(""..settingName..":",tostring(cfg[settingName]))
  end)
  
  checkBox:SetScript("OnShow", function(self) 
    self:SetChecked(cfg[settingName])
  end)
  
  -- подсказка
  if tooltipText and tooltipText~="" then
    checkBox:SetScript("OnEnter", function(self) -- при наведении мышкой на фрейм чекбокса (маусовер) ...
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
      GameTooltip:AddLine("По умолчанию: "..tostring(defValue).."", 0, 1, 1)
      GameTooltip:Show() -- ... появится подсказка
    end)
    
    checkBox:SetScript("OnLeave", function(self) -- при снятии фокуса мышки с фрейма чекбокса ...
      GameTooltip:Hide() -- ... подсказка скроется
    end)
    
    textFrame:SetScript("OnEnter", function(self) -- при наведении мышкой на фрейм текста (маусовер) ...
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
      GameTooltip:AddLine("По умолчанию: "..tostring(defValue).."", 0, 1, 1)
      GameTooltip:Show() -- ... появится подсказка
    end)
    
    textFrame:SetScript("OnLeave", function(self) -- при снятии фокуса мышки с фрейма текста ...
      GameTooltip:Hide() -- ... подсказка скроется
    end)
  end
end

---------------------------------------------------------------
-- функция создания эдитбоксов. ими тоже будем спамить где надо
---------------------------------------------------------------
-- [1] - settingName, [2] - checkboxText, [3] - tooltipText, [4] - значение по умолчанию, [5] - minValue, [6] - maxValue 
function cfgFrame:createEditBox(settingName,checkboxText,tooltipText,defValue,minValue,maxValue,optNum) -- offsetY отступ от cfgFrame.TitleText
  local editBox = CreateFrame("EditBox",ADDON_NAME.."_"..settingName,cfgFrame,"InputBoxTemplate") -- фрейм чекбокса
  editBox:SetPoint("TOPLEFT", cfgFrame.TitleText, "BOTTOMLEFT", 8, -10-(optNum*10))
  editBox:SetAutoFocus(false)
  editBox:SetSize(22,12)
  editBox:SetFont(GameFontNormal:GetFont(), 12)
  --editBox:SetText(cfg[settingName])
  --editBox:SetTextColor(1,1,1)
  
  if minValue and maxValue or type(defValue)=="number" then
    editBox.isNumeric=true
  end
  
  if not tooltipText then
    tooltipText = checkboxText
  end
  
  local textFrame = CreateFrame("Button",nil,editBox) -- фрейм текст чекбокса, не совсем по гениальному, ну лан
  textFrame:SetPoint("LEFT", editBox, "RIGHT", 3, 0)
  
  local text = textFrame:CreateFontString(nil, "ARTWORK") -- текст для чекбокса
  text:SetFont(GameFontNormal:GetFont(), 12)
  text:SetText(checkboxText)
  text:SetAllPoints(textFrame)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("BOTTOM")
  
  editBox.textFrame = textFrame
  textFrame.text = text
  
  --textFrame:SetSize(text:GetStringWidth(), text:GetStringHeight()) -- ставим длинее чем длина текста а то чет он сокращается троеточием, тут надо бы разобраться кек 

  editBox:SetScript("OnEnterPressed", function(self) 
    if editBox.isNumeric then
      local num = tonumber(self:GetText())
      if num then
        if num < minValue then
          cfg[settingName] = minValue
        elseif num > maxValue then
          cfg[settingName] = maxValue
        else
          cfg[settingName] = num
        end
        self:SetText(cfg[settingName])
        _print(""..settingName..":", tostring(cfg[settingName]))
        cfgFrame:UpdateVisual()
      else
        self:SetText(cfg[settingName])
      end
    else
      local new = self:GetText()
      if new == "" then
        new = defValue
        self:SetText(defValue)
      end
      cfg[settingName] = new
      _print(""..settingName..":", tostring(cfg[settingName]))
    end
    self:ClearFocus()
  end)

  editBox:SetScript("OnEscapePressed", function(self) 
    self:SetText(cfg[settingName])
    self:ClearFocus() 
    cfgFrame:UpdateVisual()
  end)

  editBox:SetScript("OnShow", function(self) -- при появлении фрейма флаг выставится или снимется исходя из настроек
    if not self:HasFocus() then 
      self:SetText(cfg[settingName]) 
      self:SetWidth(self:GetNumLetters()*7+22)
    end 
  end)
  
  editBox:SetScript("OnUpdate", function(self)
    self:SetWidth(self:GetNumLetters()*7+22)
    --print(self:GetText(),self:GetNumLetters())
    self.textFrame:SetPoint("LEFT", self, "RIGHT", 3, 0)
  end)
  
  textFrame:SetScript("OnShow", function(self)
    self:SetSize(self.text:GetStringWidth()+1,self.text:GetStringHeight())
  end)
    
  -- подсказка
  if tooltipText and tooltipText~="" then
    editBox:SetScript("OnEnter", function(self) -- при наведении мышкой на фрейм чекбокса (маусовер) ...
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
      GameTooltip:AddLine("По умолчанию: "..tostring(defValue).."", 0, 1, 1)
      if minValue and maxValue then
        GameTooltip:AddLine("Мин: "..tostring(minValue)..", макс: "..tostring(maxValue).."", 0, 1, 1)
      end
      GameTooltip:Show() -- ... появится подсказка
    end)
    
    editBox:SetScript("OnLeave", function(self) -- при снятии фокуса мышки с фрейма чекбокса ...
      GameTooltip:Hide() -- ... подсказка скроется
    end)

    textFrame:SetScript("OnEnter", function(self) -- при наведении мышкой на фрейм текста (маусовер) ...
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
      GameTooltip:AddLine("По умолчанию: "..tostring(defValue).."", 0, 1, 1)
      if minValue and maxValue then
        GameTooltip:AddLine("Мин: "..tostring(minValue)..", макс: "..tostring(maxValue).."", 0, 1, 1)
      end
      GameTooltip:Show() -- ... появится подсказка
    end)
    
    textFrame:SetScript("OnLeave", function(self) -- при снятии фокуса мышки с фрейма текста ...
      GameTooltip:Hide() -- ... подсказка скроется
    end)
  end
end

function f:onFirstLaunch()
  if not cfgFrame.isFirstLaunch then return end
  cfgFrame.isFirstLaunch = nil
  local t = GetTime()+4
  CreateFrame("frame"):SetScript("OnUpdate", function(self)
    if t < GetTime() then
      RaidNotice_AddMessage(RaidWarningFrame, "|cff33ccff["..ADDON_NAME.."]:|r |cffffffff"..ADDON_NOTES.."\nНастройки: Главное меню>Интерфейс>Модификации, либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r", ChatTypeInfo["RAID_WARNING"])
      _print("|cff33ccff["..ADDON_NAME.."]:|r "..ADDON_NOTES.."\nНастройки: Главное меню>Интерфейс>Модификации, либо "..ChatLink("Тык","Settings")..", либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r")
      --if RaidWarningFrame:IsShown() then
      --  PlaySound("RaidWarning")
      --end
      PlaySoundFile("interface\\addons\\"..ADDON_NAME.."\\swagga.mp3")
      self:SetScript("OnUpdate", nil)
      self=nil
    end
  end)
end

SlashCmdList[ADDON_NAME] = function(msg)
  if msg and msg~="" and msg~=cfg.auto_reply_message then
    cfg.auto_reply_message = msg
    --_print("auto_reply_message:", cfg.auto_reply_message)
    SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
    _print("Режим авто-|cffff0000DND|r включен, автоответ для фанатов: "..cfg.auto_reply_message:gsub("#playerName",playerName).."")
  else
    InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
    if not f.cfgFrame:IsShown() then
      InterfaceOptionsFrameAddOnsListScrollBarScrollDownButton:Click()
      InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
    end
  end
end

_G["SLASH_"..ADDON_NAME.."1"] = slashCmd
