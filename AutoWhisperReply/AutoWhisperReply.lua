local ADDON_NAME = ...

local UNKNOWN = UNKNOWN
local _G = _G
local print = print
local select = select
local wipe = table.wipe
local GetNumFriends = GetNumFriends
local SendChatMessage = SendChatMessage
local UnitIsDND = UnitIsDND
local UnitIsAFK = UnitIsAFK
local GetGuildRosterInfo = GetGuildRosterInfo
local GetFriendInfo = GetFriendInfo
local UnitName = UnitName
local GetNumGuildMembers = GetNumGuildMembers
local GetTime = GetTime
local ShowFriends = ShowFriends
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local MARKED_DND = MARKED_DND
local MARKED_AFK_MESSAGE = MARKED_AFK_MESSAGE
local CLEARED_DND = CLEARED_DND
local CLEARED_AFK = CLEARED_AFK

local LOCALE = GetLocale()
local ADDON_NAME_LOCALE_SHORT = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"TitleS-ruRU") or GetAddOnMetadata(ADDON_NAME,"TitleS") or ADDON_NAME
local ADDON_NAME_LOCALE = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Title-ruRU") or GetAddOnMetadata(ADDON_NAME,"Title") or ADDON_NAME
local ADDON_NOTES = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Notes-ruRU") or GetAddOnMetadata(ADDON_NAME,"Notes") or UNKNOWN
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME,"Version") or UNKNOWN

local playerName = UnitName("player")
local slashCmd = "/awr"
local cfg, friendsNames, messageCD, recentlySendPMNames, guildMembersNames, notifiedMsgs = {}, {}, {}, {}, {}, {}
local oldAutoReplyMsg = ""
local SendChatMessageTainted
local dndOrAfkRequestProcessed, dndChatFaked = true

local function _print(msg,msg2,msg3,frame,force)
  if not cfg.enable_chat_print and not force then return end
  if frame then
    frame:AddMessage("|cff3399ff["..ADDON_NAME_LOCALE_SHORT.."]|r: "..msg, msg2 and msg2 or "", msg3 and msg3 or "")
  else
    print("|cff3399ff["..ADDON_NAME_LOCALE_SHORT.."]|r: "..msg, msg2 and msg2 or "", msg3 and msg3 or "")
  end
end

local DelayedCall
do
  local DelayedCallFrame = CreateFrame("Frame")  -- Создаем один фрейм для всех отложенных вызовов
  DelayedCallFrame:Hide()  -- Изначально скрываем фрейм
  
  local calls = {}  -- Таблица для хранения отложенных вызовов
  
  local function OnUpdate(self, elapsed)
    for i, call in ipairs(calls) do
      call.time = call.time + elapsed
      if call.time >= call.delay then
        call.func()
        table.remove(calls, i)  -- Удаляем вызов из списка
      end
    end
  end
  
  DelayedCallFrame:SetScript("OnUpdate", OnUpdate)
  
  -- Основная функция для отложенных вызовов
  function DelayedCall(delay, func)
    table.insert(calls, { delay = delay, time = 0, func = func })
    if not DelayedCallFrame:IsShown() then
      DelayedCallFrame:Show()  -- Показываем фрейм, если еще не показан
    end
  end
end

local function TurnOnDNDIfNecessary(event)
  if cfg.enable_addon and dndOrAfkRequestProcessed and not UnitIsDND("player") then
    if cfg.enable_auto_dnd_force and not UnitIsAFK("player") then
      if not cfg.disable_dnd_before_sendchatmessage_and_turn_on_again then
        dndOrAfkRequestProcessed = nil
      end
      SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
      _print("force DND")
    elseif (event or dndChatFaked) and cfg.enable_auto_dnd and (cfg.enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent or not cfg.auto_disable_dnd_on_whisper_sent) then
      if not cfg.disable_dnd_before_sendchatmessage_and_turn_on_again then
        dndOrAfkRequestProcessed = nil
      end
      dndChatFaked = nil
      SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
      _print("Режим авто-|cffff0000DND|r включен, автоответ для фанатов: \""..cfg.auto_reply_message:gsub("#playerName",playerName).."\"",event,dndChatFaked)
    end
  end
end

local f = CreateFrame("frame")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)

f:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t and self.t + elapsed or 0
  if self.t < 0.1 then return end
  self.t = 0
  TurnOnDNDIfNecessary()
end)
  
function f:CHAT_MSG_SYSTEM(msg)
  if msg:match(MARKED_DND:gsub("%%s", "(.+)")) or msg==CLEARED_DND or msg==CLEARED_AFK or msg:match(MARKED_AFK_MESSAGE:gsub("%%s", "(.+)")) then
    --lagTime = GetTime() - msgLastSentTime
    --print("lagTime:",lagTime,msgLastSentTime)
    dndOrAfkRequestProcessed = true
  end
  if msg==CLEARED_AFK then
    --print("jghjghjghj")
    DelayedCall(0.5, function() TurnOnDNDIfNecessary(true) end)
  end
end

function f:CHAT_MSG_WHISPER(...)
  local msg, name = ...
  if not cfg.enable_addon or not cfg.enable_auto_reply or not name or name == "" or name == UNKNOWN or name == playerName then return end
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
  if not cfg.enable_addon or not name or name == "" or name == UNKNOWN or name == playerName or msg == cfg.auto_reply_message:gsub("#playerName",playerName) then return end
  if cfg.enable_accept_pm_we_recently_whisper_send and not recentlySendPMNames[name] and not ( (cfg.enable_accept_pm_from_friends_only and friendsNames[name]) or (cfg.enable_accept_pm_from_guild_members and guildMembersNames[name]) ) then
    _print(name, "временно добавлен в белый список для общения")
    recentlySendPMNames[name] = true
  end
  if not cfg.enable_auto_dnd_force and cfg.auto_disable_dnd_on_whisper_sent and UnitIsDND("player") then
    if not cfg.enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent then
      cfg.enable_auto_dnd = false
    end
    SendChatMessage("", "DND")
  end
end

function f:PLAYER_ENTERING_WORLD(...)
  f:OnFirstLaunch()
  playerName = UnitName("player")
  ShowFriends()
  TurnOnDNDIfNecessary(true)
end

function f:GUILD_ROSTER_UPDATE()
  --print("GUILD_ROSTER_UPDATE")
  wipe(guildMembersNames)
  for i=1,GetNumGuildMembers() do
    local name = GetGuildRosterInfo(i)
    if name and name~="" and name~=UNKNOWN then 
      guildMembersNames[name] = true
    end
  end
end

function f:FRIENDLIST_UPDATE()
  --print("FRIENDLIST_UPDATE")
  wipe(friendsNames)
  for i=1,GetNumFriends() do
    local name = GetFriendInfo(i)
    if name and name~="" and name~=UNKNOWN then 
      friendsNames[name] = true
      --print(name)
    end
  end
end

local function rgbToHex(r, g, b)
  return string.format("%02x%02x%02x", math.floor(255 * r), math.floor(255 * g), math.floor(255 * b))
end

local function PlayerWhisperHyperLink(name,guid,class,addBrackets)
  local link, colorStr 
  
  if (not class) and guid then
    class = select(2,GetPlayerInfoByGUID(guid))
  end

  if name then
    local colorStr = class and RAID_CLASS_COLORS[class] and rgbToHex(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b) or "999999"
    
    if addBrackets then
      link = "|Hplayer:"..name..":WHISPER:"..string.upper(name).."|h[|cff"..colorStr..""..name.."|r]|h"
    else
      link = "|Hplayer:"..name..":WHISPER:"..string.upper(name).."|h|cff"..colorStr..""..name.."|r|h"
    end
  else
    link = addBrackets and "|cff999999["..UNKNOWN:upper().."]|r" or "|cff999999"..UNKNOWN:upper().."|r"
  end
  
  return link
end

local function chatFilter(self, event, msg, name, ...)
  --print((cfg.enable_accept_pm_from_friends_only and friendsNames[name]))
  if not (msg and name) then return end
  -- if event=="CHAT_MSG_SYSTEM" and msg:find(cfg.auto_reply_message:gsub("#playerName",playerName)) then
    -- print("test +")
  -- end
  -- отобразить сообщение в чате если оно подходит по следующим критериям: ...
  local isGoodMsg = not cfg.enable_addon -- если аддон выключен;
  
  -- если это не системное (желтое) сообщение оповещающее нас о статусе включённого режима не беспокоить;
  or (event=="CHAT_MSG_SYSTEM" --[[and cfg.enable_auto_dnd]] and not msg:find(cfg.auto_reply_message:gsub("#playerName",playerName)) --[[not msg:match(MARKED_DND:gsub("%%s", "(.+)"))]] and not (msg==CLEARED_DND and cfg.disable_dnd_before_sendchatmessage_and_turn_on_again)) 
  
  -- если это исходящее пм сообщение, идентичное введенному в опции-строке "сообщение автоответ" + опция "скрывать автоответ" включена, либо это обычное исходящее сообщение
  or (event=="CHAT_MSG_WHISPER_INFORM" and ((msg ~= ((cfg.auto_reply_message):gsub("#playerName",playerName)) and cfg.enable_hide_auto_reply) or not cfg.enable_hide_auto_reply))
  
  -- если это входящее пм + хотя бы одна из опций друзья/гильдия/временно разрешенные включена + автор сообщения в списке друзей/гильдии/временно разрешенных соответственно
  or (event=="CHAT_MSG_WHISPER" and ( (cfg.enable_accept_pm_we_recently_whisper_send and recentlySendPMNames[name]) or (cfg.enable_accept_pm_from_friends_only and friendsNames[name]) or (cfg.enable_accept_pm_from_guild_members and guildMembersNames[name]) ) )
  
  -- если это входящее пм + все опции друзья/гильдия/временно разрешенные выключены
  or (event=="CHAT_MSG_WHISPER" and not cfg.enable_accept_pm_we_recently_whisper_send and not cfg.enable_accept_pm_from_friends_only and not cfg.enable_accept_pm_from_guild_members)
  
  -- если это входящее пм + опция "Скрывать из чата заблокированные входящие пм" выключена
  or (event=="CHAT_MSG_WHISPER" and not cfg.enable_hide_blocked_messages)
  
  -- если все критерии не удовлетворительные - сообщение фильтруется и не показывается в чате
  if not isGoodMsg then
    if event=="CHAT_MSG_WHISPER" and cfg.enable_blocked_msg_notification then -- уведомление если это входящее пм и включена опция "Отображать уведомления"
      local msgId, senderGuid = select(9,...)
      --print(GetPlayerInfoByGUID(senderGuid))
      if not notifiedMsgs[msgId] then
        notifiedMsgs[msgId] = true
        _print("Сообщение в пм от "..PlayerWhisperHyperLink(name,senderGuid,nil,true).." было |cffff0000заблокировано|r. |r"..f:ChatLink("Настройки","Settings").."",nil,nil,nil,true)
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
function f:ChatLink(text,option,colorHex,chatTarget)
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
  {"enable_accept_pm_from_friends_only","Принимать входящие пм только от друзей",nil,false},
  {"enable_accept_pm_from_guild_members","Принимать входящие пм только от согильдейцев",nil,false},
  {"enable_accept_pm_we_recently_whisper_send","Принимать входящие пм только от тех, кому мы сами недавно писали в пм (разрешение работает до следующего релога)",nil,false},
  {"enable_auto_reply","Включить автоответ в пм тем, чьи входящие мы не принимаем (должен быть включен хотя бы один пункт выше)",nil,true},
  {"auto_reply_message","Сообщение автоответ. Ввод пустой строки выставит сообщение по умолчанию. |cff00ff00#playerName|r автоматически заменится на имя нашего персонажа",nil,"#playerName не может сейчас ответить т.к афк. Попробуй написать позже."},
  {"auto_reply_cooldown","Отправлять автоответ не чаще чем раз в N сек",nil,10,1,100000},
  {"enable_hide_auto_reply","Скрывать из чата наш автоответ в пм другим",nil,true},
  {"enable_hide_blocked_messages","Скрывать из чата заблокированные входящие пм",nil,true},
  {"enable_blocked_msg_notification","Отображать уведомления о заблокированных пм",nil,true},
  {"enable_auto_dnd","Держать режим |cffff0000DND (не беспокоить)|r включенным всегда",nil,false},
  {"auto_disable_dnd_on_whisper_sent","Выключать |cffff0000DND|r если отправляем сообщение кому-то в пм (чтобы нам могли ответить)",nil,true},
  {"enable_turn_on_auto_dnd_on_zone_change_after_whisper_sent","Снова включать |cffff0000DND|r при смене зоны если тот был |cffff0000ВЫКЛЮЧЕН|r при отправке сообщения кому-либо в пм(опцией выше), и до этого DND был |cff00ff00ВКЛЮЧЕН|r",nil,true},
  {"enable_auto_dnd_force","|cffff0000Никогда не снимать DND|r (опция игнорирует все опции выше и вам никто не сможет написать в пм)",nil,false},
  {"disable_dnd_before_sendchatmessage_and_turn_on_again","|cffff8811Тест: при включенном DND фейкать его в чате. При отправке сообщения на долю секунды снимать режим |cffff0000DND|r для того чтобы "..CHAT_FLAG_DND.." не отображалось в чате, и после этого моментально включать обратно|r",nil,false},
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
    _print("Аддон загружен. Настройки:|r "..f:ChatLink("Линк","Settings")..", либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r")
    cfgFrame:UpdateVisual()
    cfgFrame:CreateOptions()
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
    if UnitIsDND("player") and not cfg.enable_auto_dnd_force then
      SendChatMessage("", "DND")
    end
  elseif ((cfg.enable_auto_dnd or cfg.enable_auto_dnd_force) and not UnitIsDND("player")) or oldAutoReplyMsg ~= cfg.auto_reply_message then
    oldAutoReplyMsg = cfg.auto_reply_message
    SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
  end

  if not SendChatMessageTainted and cfg.disable_dnd_before_sendchatmessage_and_turn_on_again then
    SendChatMessageTainted = true
    _G["SendChatMessage"] = function(msg,chatType,language,channel)
      if dndOrAfkRequestProcessed and cfg.disable_dnd_before_sendchatmessage_and_turn_on_again and UnitIsDND("player") and not (chatType=="DND" or chatType=="AFK") then
        dndOrAfkRequestProcessed = nil
        dndChatFaked = true
        _print("попыткаснятьднд")
        SendChatMessage("","DND")
      end
      SendChatMessage(msg,chatType,language,channel)
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

function f:OnFirstLaunch()
  if not cfgFrame.isFirstLaunch then return end
  cfgFrame.isFirstLaunch = nil
  DelayedCall(4, function() 
    RaidNotice_AddMessage(RaidWarningFrame, "|cff33ccff["..ADDON_NAME.."]:|r |cffffffff"..ADDON_NOTES.."\nНастройки: Главное меню>Интерфейс>Модификации, либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r", ChatTypeInfo["RAID_WARNING"])
    _print("|cff33ccff["..ADDON_NAME.."]:|r "..ADDON_NOTES.."\nНастройки: Главное меню>Интерфейс>Модификации, либо "..f:ChatLink("Тык","Settings")..", либо |cff3377ff"..slashCmd.."|r в чат, изменить автоответ: |cff3377ff"..slashCmd.." сообщение|r")
    --if RaidWarningFrame:IsShown() then
    --  PlaySound("RaidWarning")
    --end
    PlaySoundFile("interface\\addons\\"..ADDON_NAME.."\\swagga.mp3")
  end)
end

SlashCmdList[ADDON_NAME] = function(msg)
  if msg and msg~="" and msg~=cfg.auto_reply_message then
    cfg.auto_reply_message = msg
    --_print("auto_reply_message:", cfg.auto_reply_message)
    _print("Автоответ обновлён: \""..cfg.auto_reply_message:gsub("#playerName",playerName).."\"",nil,nil,nil,true)
    if UnitIsDND("player") then
      SendChatMessage(cfg.auto_reply_message:gsub("#playerName",playerName), "DND")
    end
  else
    InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
    if not f.cfgFrame:IsShown() then
      InterfaceOptionsFrameAddOnsListScrollBarScrollDownButton:Click()
      InterfaceOptionsFrame_OpenToCategory(f.cfgScrollFrame)
    end
  end
end

_G["SLASH_"..ADDON_NAME.."1"] = slashCmd
