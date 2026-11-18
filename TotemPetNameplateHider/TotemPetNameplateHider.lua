-- TPNH 1.4.2. Legacy WoW 1.12 / OctoWoW 1.17; Lua 5.0-compatible.
local addon=CreateFrame('Frame')
local totemNames={'Searing Totem','Magma Totem','Fire Nova Totem','Stoneclaw Totem','Stoneskin Totem','Earthbind Totem','Strength of Earth Totem','Tremor Totem','Healing Stream Totem','Mana Spring Totem','Mana Tide Totem','Poison Cleansing Totem','Disease Cleansing Totem','Fire Resistance Totem','Frost Resistance Totem','Nature Resistance Totem','Grounding Totem','Windfury Totem','Grace of Air Totem','Windwall Totem','Sentry Totem','Flametongue Totem','Tranquil Air Totem'}
local knownTotems,learned,hidden={},{},{}
local debugMode=false
local npcNames, playerNames, nonpvpNames = {}, {}, {}
local settingsWindow
local lastStats={plates=0,matches=0,hidden=0}
local function norm(s)
 if type(s)~='string' then return nil end
 return string.lower(string.gsub(s,'^%s*(.-)%s*$','%1'))
end
for _,v in ipairs(totemNames) do knownTotems[norm(v)]=true end
local function msg(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffTPNH|r '..s) end end
local function isTotem(n)
 if not n then return false end
 if knownTotems[n] or string.find(n,'totem',1,true) then return true end
 return false
end
local function safeExists(u)
 local ok, exists=pcall(UnitExists,u)
 return ok and exists
end
local function classifyUnit(u)
 if not safeExists(u) then return end
 local n=norm(UnitName(u))
 if not n then return end
 if UnitIsPlayer(u) then
  playerNames[n]=true; npcNames[n]=nil
  if UnitIsPVP and UnitIsEnemy and UnitIsEnemy('player',u) and not UnitIsPVP(u) then nonpvpNames[n]=true else nonpvpNames[n]=nil end
 elseif not (UnitPlayerControlled and UnitPlayerControlled(u)) and not isTotem(n) then
  npcNames[n]=true
 end
end
local function learnUnit(u)
 if not safeExists(u) or UnitIsPlayer(u) then return end
 local n=norm(UnitName(u))
 if n and n~='' and not isTotem(n) then learned[n]=true end
end
local function scanUnits()
 for _,u in ipairs({'target','mouseover','targettarget','pettarget'}) do classifyUnit(u) end
 for i=1,4 do classifyUnit('party'..i) end
 for i=1,40 do classifyUnit('raid'..i) end
 learnUnit('pet')
 for i=1,4 do learnUnit('partypet'..i) end
 for i=1,40 do learnUnit('raidpet'..i) end
 for _,u in ipairs({'target','mouseover','targettarget','pettarget'}) do
  if safeExists(u) and UnitPlayerControlled and UnitPlayerControlled(u) and not UnitIsPlayer(u) then learnUnit(u) end
 end
end
local function shouldHide(n)
 n=norm(n)
 if not n then return false end
 if TPNH_DB and TPNH_DB.exclude and TPNH_DB.exclude[n] then return false end
 local db=TPNH_DB or {}
 if db.totems~=false and isTotem(n) then return true end
 if db.pets~=false and (learned[n] or (db.include and db.include[n])) then return true end
 if db.nonpvp and nonpvpNames[n] then return true end
 if db.npcs and npcNames[n] and not playerNames[n] then return true end
 return false
end
local function collectText(f,depth,out)
 if depth>4 then return end
 if f.GetRegions then
  local r={f:GetRegions()}
  for _,v in ipairs(r) do
   if v.GetObjectType and v:GetObjectType()=='FontString' and v.GetText then
    local s=v:GetText()
    if s and s~='' then table.insert(out,s) end
   end
  end
 end
 if f.GetChildren then
  local c={f:GetChildren()}
  for _,v in ipairs(c) do collectText(v,depth+1,out) end
 end
end
local function hasBar(f,depth)
 if depth>4 then return false end
 if f.GetObjectType and f:GetObjectType()=='StatusBar' then return true end
 if f.GetChildren then
  local c={f:GetChildren()}
  for _,v in ipairs(c) do if hasBar(v,depth+1) then return true end end
 end
 return false
end
local function plateSize(f)
 if not f.GetWidth or not f.GetHeight then return false end
 local w,h=f:GetWidth() or 0,f:GetHeight() or 0
 return w>=35 and w<=450 and h>=5 and h<=180
end
local function restoreHidden()
 for f,alpha in pairs(hidden) do
  if f and f.SetAlpha then f:SetAlpha(alpha) end
  hidden[f]=nil
 end
 lastStats={plates=0,matches=0,hidden=0}
end
local function scan()
 if TPNH_DB and TPNH_DB.enabled==false then
  restoreHidden()
  return
 end
 scanUnits()
 local seen={}
 local stats={plates=0,matches=0,hidden=0}
 -- WorldFrame children are the normal native nameplates; inspect a second wrapper level.
 local function inspect(f,depth)
  if not f or seen[f] then return end
  seen[f]=true
  if plateSize(f) and hasBar(f,0) then
   local strings={}
   collectText(f,0,strings)
   if table.getn(strings)>0 then
    stats.plates=stats.plates+1
    local match=false
    for _,s in ipairs(strings) do if shouldHide(s) then match=true; break end end
    if match then
     stats.matches=stats.matches+1
     if hidden[f]==nil then hidden[f]=f:GetAlpha() end
     f:SetAlpha(0)
    end
   end
  end
  if depth<2 and f.GetChildren then
   local c={f:GetChildren()}
   for _,v in ipairs(c) do inspect(v,depth+1) end
  end
 end
 if WorldFrame and WorldFrame.GetChildren then
  local c={WorldFrame:GetChildren()}
  for _,v in ipairs(c) do inspect(v,0) end
 end
 -- UIParent fallback, restricted to one level to avoid touching unrelated panels.
 if UIParent and UIParent.GetChildren then
  local c={UIParent:GetChildren()}
  for _,v in ipairs(c) do inspect(v,0) end
 end
 -- Restore frames that have been reused or no longer match.
 for f,alpha in pairs(hidden) do
  local strings={}
  collectText(f,0,strings)
  local match=false
  for _,s in ipairs(strings) do if shouldHide(s) then match=true; break end end
  if not match then f:SetAlpha(alpha); hidden[f]=nil end
 end
 for _ in pairs(hidden) do stats.hidden=stats.hidden+1 end
 lastStats=stats
end
local elapsed=0
addon:SetScript('OnUpdate',function()
 elapsed=elapsed+(arg1 or 0)
 if elapsed<0.15 then return end
 elapsed=0
 scan()
end)
addon:RegisterEvent('PLAYER_ENTERING_WORLD')
addon:RegisterEvent('UNIT_PET')
addon:RegisterEvent('RAID_ROSTER_UPDATE')
addon:RegisterEvent('PARTY_MEMBERS_CHANGED')
addon:SetScript('OnEvent',function()
 if event=='PLAYER_ENTERING_WORLD' then
  TPNH_DB=TPNH_DB or {}
  TPNH_DB.include=TPNH_DB.include or {}
  TPNH_DB.exclude=TPNH_DB.exclude or {}
  if TPNH_DB.iconAngle==nil then TPNH_DB.iconAngle=225 end
 end
 scanUnits()
end)
SLASH_TPNH1='/tpnh'
SlashCmdList['TPNH']=function(input)
 local cmd,rest=string.match(input or '','^(%S+)%s*(.-)%s*$')
 cmd=norm(cmd or '')
 TPNH_DB=TPNH_DB or {}
 TPNH_DB.include=TPNH_DB.include or {}
 TPNH_DB.exclude=TPNH_DB.exclude or {}
 if cmd=='add' or cmd=='remove' or cmd=='exclude' then
  local name=rest~='' and rest or (safeExists('target') and UnitName('target'))
  local n=norm(name)
  if not n or n=='' then msg('Select a target or enter a name.'); return end
  if cmd=='add' then TPNH_DB.include[n]=true; TPNH_DB.exclude[n]=nil
  elseif cmd=='exclude' then TPNH_DB.exclude[n]=true; TPNH_DB.include[n]=nil
  else TPNH_DB.include[n]=nil; TPNH_DB.exclude[n]=nil; learned[n]=nil end
  msg(cmd..': '..name)
 elseif cmd=='learn' then
  if safeExists('target') and not UnitIsPlayer('target') then
   local n=norm(UnitName('target'))
   if n then TPNH_DB.include[n]=true; TPNH_DB.exclude[n]=nil; msg('Learned: '..UnitName('target')) end
  else msg('Target a pet or totem first.') end
 elseif cmd=='enable' or cmd=='disable' then
  TPNH_DB.enabled=(cmd=='enable')
  if not TPNH_DB.enabled then restoreHidden() end
  msg('Filtering '..(TPNH_DB.enabled and 'ON' or 'OFF'))
 elseif cmd=='debug' then
  debugMode=not debugMode
  msg('Debug '..(debugMode and 'ON' or 'OFF')..'. Use /tpnh inspect while nameplates are visible.')
 elseif cmd=='inspect' then
  msg('Candidates with text: '..lastStats.plates..' | matches: '..lastStats.matches..' | hidden: '..lastStats.hidden)
  if debugMode then msg('If candidates are 0 with visible nameplates, the client uses a different frame structure. Send this output for a targeted fix.') end
 elseif cmd=='status' then
  local count=0 for _ in pairs(learned) do count=count+1 end
  msg('v1.4.2 | enabled: '..((TPNH_DB.enabled==false) and 'OFF' or 'ON')..' | candidates: '..lastStats.plates..' | matches: '..lastStats.matches..' | hidden: '..lastStats.hidden..' | pet names: '..count)
 elseif cmd=='config' or cmd=='settings' or cmd=='' then
  if settingsWindow then if settingsWindow:IsShown() then settingsWindow:Hide() else settingsWindow:Show() end end
 elseif cmd=='npcs' or cmd=='nonpvp' or cmd=='totems' or cmd=='pets' then
  local val=norm(rest)
  if val=='on' then TPNH_DB[cmd]=true elseif val=='off' then TPNH_DB[cmd]=false else msg('Usage: /tpnh '..cmd..' on/off'); return end
  msg(cmd..' '..val)
 else
  msg('/tpnh config | enable | disable | status | debug | inspect | learn | add [name] | remove [name] | exclude [name]')
 end
end

-- Settings panel (legacy 1.12-compatible widgets, no modern Settings API).
local panel=CreateFrame('Frame','TPNHSettingsWindow',UIParent)
settingsWindow=panel
panel:SetWidth(355); panel:SetHeight(315)
panel:SetPoint('CENTER',UIParent,'CENTER',0,0)
panel:SetFrameStrata('DIALOG')
panel:SetMovable(true); panel:EnableMouse(true)
panel:RegisterForDrag('LeftButton')
panel:SetScript('OnDragStart',function() this:StartMoving() end)
panel:SetScript('OnDragStop',function() this:StopMovingOrSizing() end)
panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=32,insets={left=10,right=10,top=10,bottom=10}})
local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
title:SetPoint('TOP',panel,'TOP',0,-22); title:SetText('Nameplate Hider')
local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton')
close:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-5,-5)
local function checkbox(key,label,y)
 local b=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate')
 b:SetPoint('TOPLEFT',panel,'TOPLEFT',20,y)
 local t=panel:CreateFontString(nil,'OVERLAY','GameFontNormal')
 t:SetPoint('LEFT',b,'RIGHT',3,0); t:SetText(label)
 b:SetScript('OnClick',function() TPNH_DB[key]=this:GetChecked() and true or false end)
 b:SetScript('OnShow',function() TPNH_DB=TPNH_DB or {}; this:SetChecked(TPNH_DB[key]==true or (TPNH_DB[key]==nil and (key=='totems' or key=='pets'))) end)
 return b
end
checkbox('totems','Hide Shaman Totems',-55)
checkbox('pets','Hide Hunter / Warlock Pets',-92)
checkbox('nonpvp','Hide enemy non-PvP players (known only)',-129)
checkbox('npcs','Hide ordinary NPCs (known only)',-166)
local note=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
note:SetWidth(310); note:SetJustifyH('LEFT')
note:SetPoint('TOPLEFT',panel,'TOPLEFT',24,-214)
note:SetText('Legacy API limitation: NPC and PvP filters work only for identified names. Unknown nameplates stay visible to protect player nameplates.')
local help=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate')
help:SetWidth(135); help:SetHeight(24)
help:SetPoint('BOTTOM',panel,'BOTTOM',0,20); help:SetText('Inspect Nameplates')
help:SetScript('OnClick',function() msg('Candidates: '..lastStats.plates..' | matches: '..lastStats.matches..' | hidden: '..lastStats.hidden) end)
panel:Hide()


-- Movable minimap launcher; compatible with classic 1.12 Lua/UI API.
local launcher=CreateFrame('Button','TPNHMinimapButton',Minimap)
launcher:SetWidth(32); launcher:SetHeight(32)
launcher:SetFrameStrata('MEDIUM')
launcher:SetFrameLevel(8)
launcher:RegisterForClicks('LeftButtonUp','RightButtonUp')
launcher:RegisterForDrag('LeftButton')
launcher:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
local icon=launcher:CreateTexture(nil,'ARTWORK')
icon:SetWidth(20); icon:SetHeight(20)
icon:SetPoint('CENTER',launcher,'CENTER',0,0)
icon:SetTexture('Interface\\Icons\\Ability_Hunter_BeastCall')
local border=launcher:CreateTexture(nil,'OVERLAY')
border:SetWidth(53); border:SetHeight(53)
border:SetPoint('TOPLEFT',launcher,'TOPLEFT',0,0)
border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
local function placeLauncher()
 TPNH_DB=TPNH_DB or {}
 local a=TPNH_DB.iconAngle or 225
 local radians=a*math.pi/180
 launcher:ClearAllPoints()
 launcher:SetPoint('CENTER',Minimap,'CENTER',math.cos(radians)*80,math.sin(radians)*80)
end
local function updateLauncherTooltip()
 if not GameTooltip then return end
 GameTooltip:SetOwner(launcher,'ANCHOR_LEFT')
 GameTooltip:AddLine('Totem & Pet Nameplate Hider',1,0.82,0)
 GameTooltip:AddLine('Left-click: Settings',1,1,1)
 GameTooltip:AddLine('Right-click: Filtering ON/OFF',1,1,1)
 GameTooltip:AddLine('Drag: Move icon',1,1,1)
 GameTooltip:AddLine('Filtering: '..((TPNH_DB and TPNH_DB.enabled==false) and 'OFF' or 'ON'),0.5,0.85,1)
 GameTooltip:Show()
end
launcher:SetScript('OnEnter',function() updateLauncherTooltip() end)
launcher:SetScript('OnLeave',function() GameTooltip:Hide() end)
launcher:SetScript('OnClick',function()
 TPNH_DB=TPNH_DB or {}
 if arg1=='RightButton' then
  TPNH_DB.enabled=not (TPNH_DB.enabled~=false)
  if not TPNH_DB.enabled then restoreHidden() end
  msg('Filtering '..(TPNH_DB.enabled and 'ON' or 'OFF'))
  if GameTooltip and GameTooltip:IsShown() then updateLauncherTooltip() end
 else
  if settingsWindow:IsShown() then settingsWindow:Hide() else settingsWindow:Show() end
 end
end)
local dragging=false
launcher:SetScript('OnDragStart',function() dragging=true end)
launcher:SetScript('OnDragStop',function() dragging=false end)
launcher:SetScript('OnUpdate',function()
 if not dragging then return end
 local x,y=GetCursorPosition()
 local scale=UIParent:GetEffectiveScale()
 if scale and scale>0 then x=x/scale; y=y/scale end
 local mx,my=Minimap:GetCenter()
 if not mx or not my then return end
 local dx,dy=x-mx,y-my
 local a=math.atan2 and math.atan2(dy,dx) or math.atan(dy/(dx==0 and 0.00001 or dx))
 if not math.atan2 and dx<0 then a=a+math.pi end
 if not a then return end
 TPNH_DB=TPNH_DB or {}
 TPNH_DB.iconAngle=a*180/math.pi
 placeLauncher()
end)
placeLauncher()
