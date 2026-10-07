-- Guard: if this file gets loaded twice (e.g. listed twice in the .toc) every
-- hook would be installed twice and every ping would be sent twice.
if PingPongLoaded then return end
PingPongLoaded = true

-- Needs "## SavedVariables: PingPongDB" in PingPong.toc to persist overrides.
PingPongDB = PingPongDB or {}
PingPongDB.chars = PingPongDB.chars or {}

-- Reading what a button holds ------------------------------------------------
-- GetActionInfo's number for a spell is not trustworthy on this client (it made
-- Chain Lightning ping as Heroic Strike). The tooltip is: IdTip reads the spell
-- ID with GetSpell(), so PingPong does the same through a hidden tooltip.
local scan = CreateFrame("GameTooltip", "PingPongScanTooltip", nil, "GameTooltipTemplate")
scan:SetOwner(UIParent, "ANCHOR_NONE")

local function ReadTooltip(tip)
    local _, _, spellId = tip:GetSpell()
    if spellId then return "spell", spellId end
    local _, link = tip:GetItem()
    local itemId = link and tonumber(link:match("item:(%d+)"))
    if itemId then return "item", itemId end
    return nil
end

-- Returns "spell" or "item", and its real ID, for an action slot (nil if unknown)
local function TooltipTarget(slot)
    if type(slot) ~= "number" then return nil end
    scan:ClearLines()
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:SetAction(slot)
    return ReadTooltip(scan)
end

-- What a button holds, independent of where it sits on your bars:
-- "item:<id>", "spell:<id>", "macro:<name>" ...
local function ActionKey(slot)
    if type(slot) == "table" then return "item:" .. slot.id end -- bag item
    local t, id = GetActionInfo(slot)
    if t == "spell" or t == "item" then
        local k, real = TooltipTarget(slot)
        if k then return k .. ":" .. real end
        if id then return t .. ":" .. id end
    end
    local text = GetActionText(slot)
    if t == "macro" and text then
        return "macro:" .. text
    end
    if t and id then
        return t .. ":" .. tostring(id)
    end
    return nil
end

-- Overrides are stored per character (Realm-Name), so every hero has its own,
-- and are keyed by the spell/item/macro itself, so they follow it to any button.
local function GetOverrides()
    local key = (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
    local c = PingPongDB.chars[key]
    if not c then
        c = { override = {} }
        PingPongDB.chars[key] = c
    end
    return c.override
end

-- Keybinds -------------------------------------------------------------------
-- Saved account-wide in PingPongDB.keys, changed in the options window (/pp, Keybinds tab).
-- A keybind is one of:
--   { type = "double", key = "SHIFT" }                             double-tap a modifier
--   { type = "mods",   mods = { "CTRL", "SHIFT" } }                 modifiers held together
--   { type = "key",    mods = { "CTRL", "SHIFT" }, key = "M" }      modifiers + a key
--   { type = "click",  mods = { "SHIFT" }, button = "LeftButton" }  auras only (left click only)
-- mods keep the order they were pressed in; the first one is the "first key".
-- Actions: "aura" pings a buff/debuff, "spell" pings a spell/item's cooldown (it
-- also pings a hovered buff/debuff, next to the aura keybind), "whisper" does the
-- same but whispers your friendly target, "edit" opens the override window.
-- All of them are independent: none of them switches another one off.

local DEFAULT_KEYS = {
    aura  = { type = "click",  mods = { "SHIFT" }, button = "LeftButton" },
    spell = { type = "double", key = "SHIFT" },
    whisper = { type = "double", key = "CTRL" },
    edit  = { type = "mods",   mods = { "CTRL", "SHIFT" } },
}
local ACTIONS  = { "aura", "spell", "whisper", "edit" }
local MOD_LIST = { "ALT", "CTRL", "SHIFT" } -- the order WoW binding strings use
local MOD_DOWN = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }
local MOD_NAME = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }
local MOD_OF   = { LALT = "ALT", RALT = "ALT", LCTRL = "CTRL", RCTRL = "CTRL",
                   LSHIFT = "SHIFT", RSHIFT = "SHIFT" }
local CLICK_NAME = { LeftButton = "Left Click", RightButton = "Right Click",
                     MiddleButton = "Middle Click" }

local function Has(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

local function CopyBind(b)
    local c = {}
    for k, v in pairs(b) do
        if type(v) == "table" then
            local t = {}
            for i, x in ipairs(v) do t[i] = x end
            v = t
        end
        c[k] = v
    end
    return c
end

local function Keys()
    local k = PingPongDB.keys
    if type(k) ~= "table" then
        k = {}
        PingPongDB.keys = k
    end
    for act, def in pairs(DEFAULT_KEYS) do
        if type(k[act]) ~= "table" then k[act] = CopyBind(def) end
    end
    -- Right/middle click would cancel buffs, aura clicks are left click only
    if k.aura.type == "click" and k.aura.button ~= "LeftButton" then
        k.aura = CopyBind(DEFAULT_KEYS.aura)
    end
    return k
end

-- The keybind an action uses
local function Effective(act)
    return Keys()[act]
end

local function HeldMods()
    local down = {}
    for _, m in ipairs(MOD_LIST) do down[m] = MOD_DOWN[m]() and true or nil end
    return down
end

-- Are exactly these modifiers held (no more, no less)?
local function ModsMatch(mods, down)
    for _, m in ipairs(MOD_LIST) do
        if (down[m] and true or false) ~= Has(mods, m) then return false end
    end
    return true
end

local function KeyName(key)
    local t = GetBindingText and GetBindingText(key, "KEY_")
    return (t and t ~= "") and t or key
end

local function BindText(b)
    if not b then return "None" end
    if b.type == "double" then return "Double-tap " .. (MOD_NAME[b.key] or b.key) end
    local parts = {}
    for i, m in ipairs(b.mods or {}) do parts[i] = MOD_NAME[m] or m end
    if b.type == "key" then parts[#parts + 1] = KeyName(b.key) end
    if b.type == "click" then parts[#parts + 1] = CLICK_NAME[b.button] or b.button end
    return table.concat(parts, " + ")
end

-- Same keys pressed = same signature, whatever order the modifiers were set in
local function BindSig(b)
    local mods = {}
    for _, m in ipairs(MOD_LIST) do
        if Has(b.mods, m) then mods[#mods + 1] = m end
    end
    return b.type .. ":" .. table.concat(mods, "-") .. ":" .. tostring(b.key or b.button)
end

-- "CTRL-SHIFT-M", for SetOverrideBindingClick
local function BindString(b)
    local s = ""
    for _, m in ipairs(MOD_LIST) do
        if Has(b.mods, m) then s = s .. m .. "-" end
    end
    return s .. b.key
end

-- The first key of a keybind: Ctrl for Ctrl + Shift, Shift for Double-tap Shift
local function FirstKey(b)
    if b.type == "double" then return b.key end
    if b.mods and b.mods[1] then return b.mods[1] end
    return b.key
end

local function KeyLabel(token)
    return MOD_NAME[token] or KeyName(token)
end

local hooked, info = {}, {}

local function FormatTime(sec)
    local total = math.ceil(sec)
    if total < 0 then total = 0 end

    if total >= 3600 then
        -- 5:63h style = hours:minutes
        local h = math.floor(total / 3600)
        local m = math.floor((total % 3600) / 60)
        return string.format("%d:%02dh", h, m)
    elseif total >= 60 then
        -- 2:21m style = minutes:seconds
        local m = math.floor(total / 60)
        local sc = total % 60
        return string.format("%d:%02dm", m, sc)
    end
    return total .. "s"
end

-- Where pings go -------------------------------------------------------------
-- Chosen in the options window (General tab), saved account-wide.
local CHANNELS = {
    { "YELL",  "Yell",  "Everyone nearby sees it." },
    { "SAY",   "Say",   "Only players close to you see it." },
    { "PARTY", "Party", "Your party." },
    { "RAID",  "Raid",  "Your raid." },
    { "GUILD", "Guild", "Your guild." },
    { "GROUP", "Group", "Raid chat if you're in a raid, otherwise Party chat." },
}
local CHANNEL_NAME = {}
for _, c in ipairs(CHANNELS) do CHANNEL_NAME[c[1]] = c[2] end

local function GetChannel()
    local ch = PingPongDB.channel
    return CHANNEL_NAME[ch] and ch or "YELL"
end

-- Turns the chosen channel into a real chat type (nil + reason if you can't use it now)
local function ResolveChannel(ch)
    if ch == "GROUP" then
        if GetNumRaidMembers() > 0 then return "RAID" end
        if GetNumPartyMembers() > 0 then return "PARTY" end
        return nil, "you're not in a group"
    elseif ch == "RAID" then
        if GetNumRaidMembers() > 0 then return "RAID" end
        return nil, "you're not in a raid"
    elseif ch == "PARTY" then
        if GetNumPartyMembers() > 0 then return "PARTY" end
        return nil, "you're not in a party"
    elseif ch == "GUILD" then
        if IsInGuild() then return "GUILD" end
        return nil, "you're not in a guild"
    end
    return ch
end

local function WhisperTarget()
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
        and UnitIsFriend("player", "target") then
        return UnitName("target")
    end
    return nil
end

-- Every ping goes through here. whisper = true sends it to your friendly target.
local function Send(msg, whisper)
    if whisper then
        local name = WhisperTarget()
        if not name then
            print("|cff00ff00PingPong|r target a friendly player (not yourself) to whisper.")
            return false
        end
        SendChatMessage(msg, "WHISPER", nil, name)
        return true
    end
    local ch = GetChannel()
    local real, why = ResolveChannel(ch)
    if not real then
        print("|cff00ff00PingPong|r can't ping to " .. CHANNEL_NAME[ch] .. ": " .. why .. ".")
        return false
    end
    SendChatMessage(msg, real)
    return true
end

-- Show the icon on pings you receive (chat + bubbles). Saved account-wide,
-- changed with the "Show spell icons on pings" box in /pp (General tab).
local function IconsEnabled()
    return PingPongDB.icons ~= false
end

-- Why a spell/item can't be used --------------------------------------------
-- { word under the bubble icon (1 word, red), phrase shown in the ping text }
local BLOCKS = {
    dead          = { "Dead",          "you are dead" },
    stunned       = { "Stunned",       "you are stunned" },
    silenced      = { "Silenced",      "you are silenced" },
    pacified      = { "Pacified",      "you are pacified" },
    feared        = { "Feared",        "you are feared" },
    asleep        = { "Asleep",        "you are asleep" },
    disoriented   = { "Disoriented",   "you are disoriented" },
    incapacitated = { "Incapacitated", "you are incapacitated" },
    controlled    = { "Controlled",    "you are mind controlled" },
    banished      = { "Banished",      "you are banished" },
    frozen        = { "Frozen",        "you are frozen in ice" },
    mana          = { "Mana",          "not enough mana" },
    rage          = { "Rage",          "not enough rage" },
    energy        = { "Energy",        "not enough energy" },
    focus         = { "Focus",         "not enough focus" },
    runes         = { "Runes",         "not enough runes" },
    runic         = { "Runic",         "not enough runic power" },
    unusable      = { "Unusable",      "can't be used right now" },
}
local BLOCK_WORD = {} -- phrase in the ping text -> 1-word label for the bubble
for _, v in pairs(BLOCKS) do BLOCK_WORD[v[2]] = v[1] end

-- Icons on received pings ----------------------------------------------------
-- A ping starts with a spell/item link. When one arrives, the icon of that
-- spell/item is put in front of it, locally, for anyone who has this addon.

local function IconFromMessage(msg)
    if type(msg) ~= "string" then return nil end
    local kind, id, rest = msg:match("^|c%x%x%x%x%x%x%x%x|H(%a+):(%d+)[^|]*|h%[.-%]|h|r(.*)$")
    id = tonumber(id)
    if not id then return nil end
    -- Only PingPong's own wording gets an icon (spell/item pings and aura pings)
    if not (rest:find("^ Is ready to use!!!")
        or rest:find("^ Is on Cooldown %[")
        or rest:find("^ Is not ready %(none left%)")
        or rest:find("^ Is not ready to use %[")
        or rest:find("^ %(x%d+%) On ")
        or rest:find("^ On ")) then
        return nil
    end
    if kind == "spell" then
        return (select(3, GetSpellInfo(id)))
    elseif kind == "item" then
        return GetItemIcon(id)
    end
    return nil
end

-- Sizes, changed with the number boxes in /pp (General tab). Saved account-wide.
--   bubbleIcon: icon next to a chat bubble, in pixels
--   bubbleText: the Ready / cooldown / aura timer text under that icon
--   bubbleBorder: font border around that text: 0 none, 1 thin, 2 thick
--   bubbleLine: thickness of the dispel-colored line behind a debuff icon (0 = off)
--   chatIcon:   icons in the chat window, as a multiple of the chat font height
local Sizes = {
    default = { bubbleIcon = 32, bubbleText = 14, bubbleBorder = 1, bubbleLine = 2, chatIcon = 2 },
    limits  = { bubbleIcon = { 8, 128 }, bubbleText = { 6, 40 }, bubbleBorder = { 0, 2 }, bubbleLine = { 0, 10 }, chatIcon = { 0.5, 8 } },
}
function Sizes.get(key)
    local v = PingPongDB.sizes and tonumber(PingPongDB.sizes[key])
    if not v then return Sizes.default[key] end
    local lim = Sizes.limits[key]
    return math.max(lim[1], math.min(lim[2], v))
end

-- Font border for the bubble text: 0 none, 1 thin outline, 2 thick outline
local function BubbleFontFlags()
    local b = Sizes.get("bubbleBorder")
    if b >= 2 then return "THICKOUTLINE" end
    if b >= 1 then return "OUTLINE" end
    return ""
end

local function ChatIconSize()
    local _, h = ChatFrame1:GetFont()
    return math.floor((h or 14) * Sizes.get("chatIcon") + 0.5)
end

local function ChatIconFilter(self, event, msg, ...)
    if not IconsEnabled() then return false end
    local icon = IconFromMessage(msg)
    if icon then
        return false, "|T" .. icon .. ":" .. ChatIconSize() .. "|t " .. msg, ...
    end
    return false
end

local RECEIVE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
}
for _, ev in ipairs(RECEIVE_EVENTS) do
    ChatFrame_AddMessageEventFilter(ev, ChatIconFilter)
end

-- Chat bubbles: bubble text can't show icons, so a real texture is attached to
-- the bubble instead, just left of it. Bubbles only exist for say / yell (and
-- party). They are reused by the game, so the icon is hidden when it's gone.

local function PlainText(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
    msg = msg:gsub("|H.-|h(.-)|h", "%1")
    return msg
end

local bubbleJobs, bubbleMarks = {}, {}

local function BubbleText(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            return r:GetText()
        end
    end
end

-- Loose text for matching bubbles: no colors, link codes or punctuation
local function Loose(s)
    s = (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return (s:gsub("[^%w]", ""))
end

-- Status text under the bubble icon: green "Ready", or a red cooldown timer
local function ParseSeconds(t)
    local h, m = t:match("^(%d+):(%d+)h$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 end
    local mm, ss = t:match("^(%d+):(%d+)m$")
    if mm then return tonumber(mm) * 60 + tonumber(ss) end
    local sec = t:match("^(%d+)s$")
    return sec and tonumber(sec) or nil
end

-- Returns "ready", "none", or "cd" (+ seconds left); nil for aura pings
-- What Say() knows about an aura it just sent: buff or debuff, and the dispel
-- type. The bubble can't work that out from the text, so it's remembered here.
local auraMeta = {}

local function BubbleStatus(msg)
    if msg:find(" Is ready to use!!!", 1, true) then return "ready" end
    if msg:find(" Is not ready (none left)", 1, true) then return "none" end
    local why = msg:match(" Is not ready to use %[(.-)%]")
    if why then return "blocked", nil, BLOCK_WORD[why] or "Unusable" end
    local t = msg:match(" Is on Cooldown %[(.-)%]")
    if t then
        local sec = ParseSeconds(t)
        if sec then return "cd", sec end
    end
    return nil
end

local function SetBubbleLabel(m)
    local l = m.label
    if not l then return end
    if m.status == "ready" then
        l:SetText("Ready")
        l:SetTextColor(0, 1, 0)
        l:Show()
    elseif m.status == "none" then
        l:SetText("None left")
        l:SetTextColor(1, 0, 0)
        l:Show()
    elseif m.status == "blocked" then
        l:SetText(m.word or "Unusable")
        l:SetTextColor(1, 0, 0) -- same red as the cooldown text
        l:Show()
    elseif m.status == "cd" and m.expires then
        local left = m.expires - GetTime()
        if left <= 0 then
            l:SetText("Ready")
            l:SetTextColor(0, 1, 0)
        else
            l:SetText(FormatTime(left))
            l:SetTextColor(1, 0, 0)
        end
        l:Show()
    elseif (m.status == "buff" or m.status == "debuff") and m.expires then
        local left = m.expires - GetTime()
        if left <= 0 then
            l:Hide()
        else
            l:SetText(FormatTime(left))
            if m.status == "debuff" then
                l:SetTextColor(0.75, 0.05, 0.05) -- dark red
            else
                l:SetTextColor(1, 1, 1)          -- white
            end
            l:Show()
        end
    else
        l:Hide()
    end
end

local function TryBubble(job)
    for _, f in ipairs({ WorldFrame:GetChildren() }) do
        if not f:GetName() and f.GetRegions and f:IsShown() then
            local text = BubbleText(f)
            -- Bubble text may still hold the link codes, so compare plain text
            local norm = text and Loose(text)
            if norm and norm ~= "" and (norm == job.loose or norm:sub(1, 25) == job.loose:sub(1, 25)) then
                local m = bubbleMarks[f]
                if not m then
                    m = { tex = f:CreateTexture(nil, "OVERLAY") }
                    bubbleMarks[f] = m
                end
                m.tex:SetWidth(Sizes.get("bubbleIcon"))
                m.tex:SetHeight(Sizes.get("bubbleIcon"))
                m.tex:ClearAllPoints()
                m.tex:SetPoint("RIGHT", f, "LEFT", -2, 0)
                m.tex:SetTexture(job.icon)
                m.tex:Show()
                m.text = text
                m.dtype = job.dtype
                -- Colored line behind the icon: only for dispellable debuffs
                if not m.line then
                    m.line = f:CreateTexture(nil, "ARTWORK")
                    m.line:SetTexture("Interface\\Buttons\\WHITE8X8")
                end
                local lt = Sizes.get("bubbleLine")
                local lc = m.dtype and DebuffTypeColor and DebuffTypeColor[m.dtype]
                if lc and lt > 0 then
                    m.line:ClearAllPoints()
                    m.line:SetPoint("TOPLEFT", m.tex, "TOPLEFT", -lt, lt)
                    m.line:SetPoint("BOTTOMRIGHT", m.tex, "BOTTOMRIGHT", lt, -lt)
                    m.line:SetVertexColor(lc.r, lc.g, lc.b, 1)
                    m.line:Show()
                else
                    m.line:Hide()
                end
                if not m.label then
                    m.label = f:CreateFontString(nil, "OVERLAY")
                end
                m.label:SetFont(STANDARD_TEXT_FONT, Sizes.get("bubbleText"), BubbleFontFlags())
                m.label:ClearAllPoints()
                m.label:SetPoint("TOP", m.tex, "BOTTOM", 0, -2)
                m.status, m.expires, m.word = job.status, job.expires, job.word
                SetBubbleLabel(m)
                return true
            end
        end
    end
    return false
end

local bubbleFrame = CreateFrame("Frame")
bubbleFrame.t = 0
bubbleFrame:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.05 then return end
    self.t = 0
    for i = #bubbleJobs, 1, -1 do
        local job = bubbleJobs[i]
        job.tries = job.tries + 1
        if TryBubble(job) or job.tries > 20 then table.remove(bubbleJobs, i) end
    end
    -- Hide the icon once its bubble is gone or reused for another message
    for f, m in pairs(bubbleMarks) do
        if m.tex:IsShown() then
            if not f:IsShown() or BubbleText(f) ~= m.text then
                m.tex:Hide()
                if m.line then m.line:Hide() end
                if m.label then m.label:Hide() end
            elseif m.status == "cd" or m.status == "buff" or m.status == "debuff" then
                SetBubbleLabel(m) -- live countdown
            end
        end
    end
end)

local bubbleEvents = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do
    bubbleEvents:RegisterEvent(ev)
end
bubbleEvents:SetScript("OnEvent", function(self, event, msg)
    if not IconsEnabled() then return end
    local icon = IconFromMessage(msg)
    if icon then
        local status, secs, word = BubbleStatus(msg)
        local dtype
        if not status and msg:find(" On ", 1, true) then
            -- Aura ping: "[Spell] On Name 2:21m Left"
            local key = Loose(msg)
            local meta = auraMeta[key]
            auraMeta[key] = nil
            status = (meta and meta.harmful) and "debuff" or "buff"
            dtype = meta and meta.dtype
            local left = msg:match(" (%S+) Left$")
            secs = left and ParseSeconds(left)
        end
        bubbleJobs[#bubbleJobs + 1] = { plain = PlainText(msg), loose = Loose(msg), icon = icon,
            status = status, word = word, dtype = dtype,
            expires = secs and (GetTime() + secs) or nil, tries = 0 }
    end
end)

local function Say(unit, index, filter, whisper)
    local name, _, _, count, dtype, _, expires, _, _, _, spellId = UnitAura(unit, index, filter)
    if not name then return end

    local link = spellId and GetSpellLink(spellId) or name
    local who = UnitName(unit) or unit
    if unit == "player" then
        who = who .. " [ME]"
    end

    local msg = link
    if count and count > 1 then
        msg = msg .. " (x" .. count .. ")"
    end
    msg = msg .. " On " .. who
    if expires and expires > 0 then
        msg = msg .. " " .. FormatTime(expires - GetTime()) .. " Left"
    end

    local harmful = (filter and filter:find("HARMFUL")) and true or false
    local now = GetTime()
    for k, v in pairs(auraMeta) do
        if now - v.time > 30 then auraMeta[k] = nil end
    end
    auraMeta[Loose(msg)] = { harmful = harmful, dtype = harmful and dtype or nil, time = now }

    Send(msg, whisper)
end
local function OnAuraClick(self, button)
    local b = Effective("aura")
    if b.type ~= "click" or button ~= "LeftButton" or b.button ~= button
        or not ModsMatch(b.mods, HeldMods()) then return end
    local i = info[self]
    if i then Say(i.unit, i.index, i.filter) end
end

-- The buff/debuff under the mouse, for aura keybinds that aren't clicks
local function GetHoveredAura()
    local f = GetMouseFocus()
    local i = f and info[f]
    if i and GameTooltip:IsOwned(f) then return i end
    return nil
end

local function Track(tip, unit, index, filter)
    local owner = tip:GetOwner()
    if not owner then return end

    info[owner] = { unit = unit, index = index, filter = filter }

    if not hooked[owner] and owner.HasScript and owner:HasScript("OnMouseUp") then
        owner:HookScript("OnMouseUp", OnAuraClick)
        hooked[owner] = true
    end
end
hooksecurefunc(GameTooltip, "SetUnitAura",   function(tip, unit, index, filter) Track(tip, unit, index, filter) end)
hooksecurefunc(GameTooltip, "SetUnitBuff",   function(tip, unit, index)         Track(tip, unit, index, "HELPFUL") end)
hooksecurefunc(GameTooltip, "SetUnitDebuff", function(tip, unit, index)         Track(tip, unit, index, "HARMFUL") end)

-- Dungeon difficulty banner ------------------------------------------------

local function SayDifficulty()
    local name, instType, _, difficultyName, maxPlayers = GetInstanceInfo()
    if instType ~= "party" and instType ~= "raid" then return end

    local msg = (name or "Instance") .. " Difficulty: " .. (difficultyName or "Unknown")
    if maxPlayers and maxPlayers > 0 then
        msg = msg .. " (" .. maxPlayers .. " Players)"
    end

    Send(msg)
end

local function OnDifficultyClick(self, button)
    if button ~= "LeftButton" or not IsShiftKeyDown() then return end
    SayDifficulty()
end

local diffFrame = MiniMapInstanceDifficulty
if diffFrame then
    diffFrame:EnableMouse(true)
    diffFrame:HookScript("OnMouseUp", OnDifficultyClick)
end

-- Player / Target health + power ------------------------------------------

local lastVital = {}

local function SayVital(unit, kind, whisper)
    if not UnitExists(unit) then return end

    -- One press = one ping, however many frames receive the same click
    local now, key = GetTime(), unit .. kind
    if lastVital[key] and now - lastVital[key] < 0.25 then return end
    lastVital[key] = now

    local cur, max, label
    if kind == "health" then
        cur, max, label = UnitHealth(unit), UnitHealthMax(unit), "Health"
    else
        local _, token = UnitPowerType(unit)
        cur, max = UnitPower(unit), UnitPowerMax(unit)
        label = (token and _G[token]) or "Power"
    end
    if not max or max <= 0 then return end

    local who = UnitName(unit) or unit
    if unit == "player" then
        who = who .. " [ME]"
    end

    local pct = math.floor(cur / max * 100 + 0.5)
    local msg = who .. " " .. label .. ": " .. pct .. "%"

    if UnitIsDeadOrGhost(unit) then
        msg = who .. " is Dead"
    end

    Send(msg, whisper)
end

local function VitalFromCursor(frame, unit)
    local _, y = GetCursorPosition()
    y = y / frame:GetEffectiveScale()
    local mid = (frame:GetTop() + frame:GetBottom()) / 2
    SayVital(unit, y >= mid and "health" or "power")
end

-- Does this click match the Auras keybind (when that keybind is a click)?
local function VitalClickMatches(button)
    local b = Effective("aura")
    return b.type == "click" and button == b.button and ModsMatch(b.mods, HeldMods())
end

local vitalHooked = {}

local function HookUnitFrame(frame, unit)
    if not frame then return end

    local function OnClick(self, button)
        if not VitalClickMatches(button) then return end
        VitalFromCursor(frame, unit)
    end

    -- Bars (and other child frames) can catch the click before the main frame
    -- does, so hook them too, but skip aura buttons so those keep yelling their
    -- own aura. Each frame is hooked once: the bars are also children of the
    -- unit frame, hooking them twice made every click ping twice.
    local name = frame:GetName()
    local kids = { frame, _G[name .. "HealthBar"], _G[name .. "ManaBar"] }
    for _, child in ipairs({ frame:GetChildren() }) do
        local n = child:GetName()
        if not (n and n:lower():find("buff")) then
            kids[#kids + 1] = child
        end
    end
    for _, f in ipairs(kids) do
        if not vitalHooked[f] and f.HasScript and f:HasScript("OnMouseUp") then
            vitalHooked[f] = true
            f:HookScript("OnMouseUp", OnClick)
        end
    end
end

HookUnitFrame(PlayerFrame, "player")
HookUnitFrame(TargetFrame, "target")

-- Target mana zone above the debuffs ---------------------------------------
-- An invisible overlay over the bottom half of the target frame, sitting above
-- the buff/debuff icons. It only catches the mouse while Shift is held, so
-- normal clicks and aura tooltips keep working.

local manaZone = CreateFrame("Frame", "PingPongTargetManaZone", UIParent)
manaZone:SetPoint("TOPLEFT", TargetFrame, "LEFT", 0, 0)
manaZone:SetPoint("BOTTOMRIGHT", TargetFrame, "BOTTOMRIGHT", 0, 0)
manaZone:SetFrameStrata("HIGH")
manaZone:SetFrameLevel(TargetFrame:GetFrameLevel() + 50)
manaZone:EnableMouse(false)

manaZone:SetScript("OnUpdate", function(self)
    local b = Effective("aura")
    local want = b.type == "click" and ModsMatch(b.mods, HeldMods())
        and UnitExists("target") and MouseIsOver(self)
    if self:IsMouseEnabled() ~= (want and true or false) then
        self:EnableMouse(want and true or false)
    end
end)

manaZone:SetScript("OnMouseUp", function(self, button)
    if not VitalClickMatches(button) then return end
    SayVital("target", "power")
end)

-- Health / power under the mouse, for keybinds that aren't clicks ------------
-- Top half of the player/target frame = health, bottom half = power.

local VITAL_FRAMES = { { PlayerFrame, "player" }, { TargetFrame, "target" } }

local function IsInside(f, root)
    while f do
        if f == root then return true end
        f = f.GetParent and f:GetParent() or nil
    end
    return false
end

local function GetHoveredVital()
    local focus = GetMouseFocus()
    for _, v in ipairs(VITAL_FRAMES) do
        local frame, unit = v[1], v[2]
        if frame and frame:IsShown() and MouseIsOver(frame)
            and (focus == manaZone or IsInside(focus, frame)) then
            local _, y = GetCursorPosition()
            y = y / frame:GetEffectiveScale()
            local mid = (frame:GetTop() + frame:GetBottom()) / 2
            return unit, (y >= mid) and "health" or "power"
        end
    end
    return nil
end

-- Spell ready / cooldown ping (default: double-tap Shift) -------------------
-- Hover an action button and press the spell keybind:
--   Ready:       [Starfall] Is ready to use!!!
--   On cooldown: [Starfall] Is on Cooldown [2:21m]
--   Can't use it:[Starfall] Is not ready to use [you are stunned]
--                (also: dead, silenced, not enough mana/rage/energy/runes, ...)
--   Items/reagent spells also get the amount:  (x20 left)
--   Out of an item:  [Fish Feast] Is not ready (none left)
--
-- Press the override shortcut (default Ctrl + Shift) over a button to open the
-- override window with that spell/item already picked.
-- Keybinds are changed in the options window (/pp).

local DOUBLE_TAP_WINDOW = 0.35 -- seconds between the two Shift presses
local PING_COOLDOWN     = 0.75 -- ignore a second ping sent within this time
local spellPingEnabled = true

-- Only real action buttons and bag/bank items count. (Calling
-- ActionButton_CalculateAction on any other frame falls back to slot 1, which
-- is why pinging over the minimap or empty screen used to ping a spell.)
local ACTION_PATTERNS = {
    "^ActionButton%d+$", "^BonusActionButton%d+$",
    "^MultiBarBottomLeftButton%d+$", "^MultiBarBottomRightButton%d+$",
    "^MultiBarLeftButton%d+$", "^MultiBarRightButton%d+$",
}

local function IsActionButton(f)
    if type(f.action) == "number" then return true end
    if f.GetAttribute and type(f:GetAttribute("action")) == "number" then return true end
    local name = f:GetName()
    if name then
        for _, pat in ipairs(ACTION_PATTERNS) do
            if name:find(pat) then return true end
        end
    end
    return false
end

local function GetBagItem(f)
    local name = f:GetName()
    if not name then return nil end

    local bag, slot
    if name:find("^ContainerFrame%d+Item%d+$") then
        local parent = f:GetParent()
        if parent then bag, slot = parent:GetID(), f:GetID() end
    elseif name:find("^BankFrameItem%d+$") then
        bag, slot = -1, f:GetID()
    end
    if not bag or not slot then return nil end

    local link = GetContainerItemLink(bag, slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
        return { bag = bag, slot = slot, id = id, link = link }
    end
    return nil
end

-- Returns an action slot number, a bag item table, or nil (nothing to ping)
local function GetHoveredSlot()
    local f = GetMouseFocus()
    if not f or not f.GetName then return nil end

    local bagItem = GetBagItem(f)
    if bagItem then return bagItem end

    if not IsActionButton(f) then return nil end

    local slot = f.action
    if type(slot) ~= "number" and ActionButton_CalculateAction then
        local ok, v = pcall(ActionButton_CalculateAction, f)
        if ok then slot = v end
    end
    if type(slot) == "number" and HasAction(slot) then
        return slot
    end
    return nil
end

local function SpellLinkFor(id)
    local link = GetSpellLink(id)
    if link then return link end
    local name = GetSpellInfo(id)
    return name and ("[" .. name .. "]") or nil
end

local function ItemLinkFor(id)
    local name, link = GetItemInfo(id)
    if link then return link end
    return name and ("[" .. name .. "]") or ("[item:" .. id .. "]")
end

-- Clickable [Spell] link when possible, otherwise [Name]
local function GetActionName(slot)
    if type(slot) == "table" then return slot.link or ItemLinkFor(slot.id) end
    local k, real = TooltipTarget(slot)
    if k == "spell" then
        local l = SpellLinkFor(real)
        if l then return l end
    elseif k == "item" then
        return ItemLinkFor(real)
    end

    local name = PingPongScanTooltipTextLeft1:GetText()
    if name then return "[" .. name .. "]" end
    local text = GetActionText(slot)
    if text then return "[" .. text .. "]" end
    return nil
end

-- Returns kind ("spell" / "item" / "action"), id, isOverride
local function Resolve(slot)
    local key = ActionKey(slot)
    local o = key and GetOverrides()[key]
    if o and o.id then
        return o.kind, o.id, true
    end
    if type(slot) == "table" then return "item", slot.id, false end
    local k, real = TooltipTarget(slot)
    if k then return k, real, false end
    local t, id = GetActionInfo(slot)
    if (t == "spell" or t == "item") and id then
        return t, id, false
    end
    return "action", nil, false
end

-- Can you actually use it right now? --------------------------------------------
-- Returns a key of BLOCKS (dead, stunned, mana, ...) or nil when nothing stops you.

local POWER_KEY = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy",
                    [5] = "runes", [6] = "runic" }

local function SpellPower(id)
    local pt = id and select(6, GetSpellInfo(id))
    return pt
end

-- Which resource is missing: the spell's own cost type, else your current one
local function PowerKey(id)
    local key = POWER_KEY[SpellPower(id) or -1] or POWER_KEY[UnitPowerType("player")]
    return key or "unusable"
end

-- Text of everything on you that could stop you, as one lowercase string.
-- (3.3.5 has no "loss of control" API, so the debuff tooltips are read.)
local function DebuffText()
    local parts = {}
    for i = 1, 40 do
        if not UnitDebuff("player", i) then break end
        scan:ClearLines()
        scan:SetOwner(UIParent, "ANCHOR_NONE")
        scan:SetUnitDebuff("player", i)
        for l = 1, scan:NumLines() do
            local fs = _G["PingPongScanTooltipTextLeft" .. l]
            local t = fs and fs:GetText()
            if t then parts[#parts + 1] = t end
        end
    end
    return table.concat(parts, " "):lower()
end

-- { text found in a debuff tooltip, BLOCKS key, what it stops }
--   "all" = everything, "spell" = magic spells only, "physical" = non-magic only
local CC_RULES = {
    { "stunned",          "stunned",       "all" },
    { "fleeing in terror", "feared",       "all" },
    { "feared",           "feared",        "all" },
    { "horrified",        "feared",        "all" },
    { "asleep",           "asleep",        "all" },
    { "disoriented",      "disoriented",   "all" },
    { "confused",         "disoriented",   "all" },
    { "incapacitated",    "incapacitated", "all" },
    { "transformed",      "incapacitated", "all" },
    { "mind control",     "controlled",    "all" },
    { "charmed",          "controlled",    "all" },
    { "under the control", "controlled",   "all" },
    { "banished",         "banished",      "all" },
    { "silenced",         "silenced",      "spell" },
    { "pacified",         "pacified",      "physical" },
}
-- Abilities that work while you're crowd controlled
local CC_EXEMPT = { [59752] = true, [7744] = true } -- Every Man for Himself, Will of the Forsaken

local function IsEquippedTrinket(id)
    for _, s in ipairs({ 13, 14 }) do
        local link = GetInventoryItemLink("player", s)
        if link and tonumber(link:match("item:(%d+)")) == id then return true end
    end
    return false
end

local function HasBuffId(spellId)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
        if not name then return false end
        if id == spellId then return true end
    end
    return false
end

local function CCBlock(kind, id)
    if kind == "spell" and id and CC_EXEMPT[id] then return nil end
    if kind == "item" and id and IsEquippedTrinket(id) then return nil end -- PvP trinkets break CC

    local isSpell = (kind == "spell" and id) and true or false
    local magic = isSpell and SpellPower(id) == 0
    local text = DebuffText()
    for _, r in ipairs(CC_RULES) do
        if text:find(r[1], 1, true) then
            local scope = r[3]
            if scope == "all"
                or (scope == "spell" and magic)
                or (scope == "physical" and isSpell and not magic) then
                return r[2]
            end
        end
    end
    if HasBuffId(45438) then return "frozen" end -- Ice Block
    return nil
end

local function GetBlock(slot, kind, id, isOverride)
    if UnitIsDeadOrGhost("player") then return "dead" end

    local cc = CCBlock(kind, id)
    if cc then return cc end

    local usable, noPower
    if isOverride or type(slot) == "table" then
        if kind == "spell" and id then
            usable, noPower = IsUsableSpell(id)
        elseif kind == "item" and id then
            usable, noPower = IsUsableItem(id)
        else
            return nil
        end
    else
        usable, noPower = IsUsableAction(slot)
    end
    if noPower then return PowerKey(kind == "spell" and id or nil) end
    if not usable then return "unusable" end
    return nil
end

local lastPing = 0

local function PingSlot(slot, whisper)
    local now = GetTime()
    if now - lastPing < PING_COOLDOWN then return end

    local kind, id, isOverride = Resolve(slot)

    local name
    if isOverride then
        name = (kind == "spell") and SpellLinkFor(id) or ItemLinkFor(id)
    else
        name = GetActionName(slot)
    end
    if not name then return end

    -- Cooldown: check the real button / bag item AND the chosen replacement,
    -- and use whichever has the longest time left. (An override only changes
    -- the name; the button itself still knows its true cooldown.)
    local remaining = 0
    local function AddCooldown(start, duration)
        -- Ignore the global cooldown (1.5s or less) so it counts as ready
        if start and start > 0 and duration and duration > 1.5 then
            local left = (start + duration) - now
            if left > remaining then remaining = left end
        end
    end

    if type(slot) == "table" then
        AddCooldown(GetContainerItemCooldown(slot.bag, slot.slot))
    else
        AddCooldown(GetActionCooldown(slot))
    end

    if isOverride then
        if kind == "spell" then
            AddCooldown(GetSpellCooldown(id))
        else
            AddCooldown(GetItemCooldown(id))
            -- Equipped items (boots, trinkets, ...) keep their cooldown on the slot
            for i = 1, 19 do
                local link = GetInventoryItemLink("player", i)
                if link and tonumber(link:match("item:(%d+)")) == id then
                    AddCooldown(GetInventoryItemCooldown("player", i))
                end
            end
        end
    end

    -- Amount left (items, reagent spells, stackable actions)
    local count
    if kind == "item" then
        count = GetItemCount(id, false, true)
    elseif not isOverride then
        if (IsConsumableAction and IsConsumableAction(slot))
            or (IsStackableAction and IsStackableAction(slot)) then
            count = GetActionCount(slot)
        end
    elseif kind == "spell" and type(GetSpellCount) == "function" then
        local ok, c = pcall(GetSpellCount, id)
        if ok and c and c > 0 then count = c end
    end

    local msg
    if count and count <= 0 then
        msg = name .. " Is not ready (none left)"
    elseif remaining > 0 then
        msg = name .. " Is on Cooldown [" .. FormatTime(remaining) .. "]"
    else
        -- Off cooldown, but is something else stopping you right now?
        local block = GetBlock(slot, kind, id, isOverride)
        if block then
            msg = name .. " Is not ready to use [" .. BLOCKS[block][2] .. "]"
        else
            msg = name .. " Is ready to use!!!"
        end
    end
    if count and count > 0 then
        msg = msg .. " (x" .. count .. " left)"
    end

    lastPing = now
    Send(msg, whisper)
end

-- Override window (override shortcut, or "Override pinged spells" in /pp) ----

local MAX_RESULTS    = 10
local MAX_SPELL_ID   = 81000 -- highest spell ID scanned (3.3.5a ends around 80.8k)
local MAX_ITEM_ID    = 57000 -- highest item ID scanned
local SCAN_PER_FRAME = 2500  -- IDs checked per frame while indexing (no freezing)
local searchSlot, searchKey

local function Trim(s)
    s = s or ""
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- Game-wide index ------------------------------------------------------------
-- The client has no "list all spells/items" call, so every ID is checked once
-- (spread over a few frames) and the names are kept for searching.
-- Spells: every spell in the game. Items: every item your client has in its
-- item cache (anything you've seen/looted/linked); for others type the item ID
-- or shift-click the item link into the search box.

local idx = { spellIds = {}, spellLower = {}, spellDone = 0,
              itemIds = {},  itemLower = {},  itemDone = 0 }
local indexReady = false
local onProgress, onRetry -- assigned once the window exists

local function IndexPercent()
    return math.floor((idx.spellDone + idx.itemDone) / (MAX_SPELL_ID + MAX_ITEM_ID) * 100)
end

local indexFrame = CreateFrame("Frame")
indexFrame:Hide()
local indexFrames = 0
indexFrame:SetScript("OnUpdate", function(self)
    local s = idx.spellDone
    if s < MAX_SPELL_ID then
        local e = math.min(MAX_SPELL_ID, s + SCAN_PER_FRAME)
        local ids, low = idx.spellIds, idx.spellLower
        for id = s + 1, e do
            local name = GetSpellInfo(id)
            if name and name ~= "" then
                local c = #ids + 1
                ids[c] = id
                low[c] = name:lower()
            end
        end
        idx.spellDone = e
    end

    local t = idx.itemDone
    if t < MAX_ITEM_ID then
        local e = math.min(MAX_ITEM_ID, t + SCAN_PER_FRAME)
        local ids, low = idx.itemIds, idx.itemLower
        for id = t + 1, e do
            local name = GetItemInfo(id)
            if name and name ~= "" then
                local c = #ids + 1
                ids[c] = id
                low[c] = name:lower()
            end
        end
        idx.itemDone = e
    end

    if idx.spellDone >= MAX_SPELL_ID and idx.itemDone >= MAX_ITEM_ID then
        indexReady = true
        self:Hide()
    end

    indexFrames = indexFrames + 1
    if onProgress and (indexReady or indexFrames % 10 == 0) then onProgress() end
end)

-- First open builds everything; later opens only re-scan items (the item cache
-- grows as you play) which takes about half a second.
local function StartIndex()
    if indexReady then
        idx.itemIds, idx.itemLower, idx.itemDone = {}, {}, 0
        indexReady = false
    end
    indexFrame:Show()
end

local retryFrame = CreateFrame("Frame")
retryFrame:Hide()
retryFrame.t = 0
retryFrame:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t - elapsed
    if self.t <= 0 then
        self:Hide()
        if onRetry then onRetry() end
    end
end)

local function KnownSpellSet()
    local set = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = offset + 1, offset + numSpells do
            local link = GetSpellLink(i, BOOKTYPE_SPELL)
            local id = link and tonumber(link:match("spell:(%d+)"))
            if id then set[id] = true end
        end
    end
    return set
end

local function OwnedItemSet()
    local set = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then set[id] = true end
        end
    end
    for i = 1, 19 do
        local link = GetInventoryItemLink("player", i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then set[id] = true end
    end
    return set
end

local lastText, retries = "", 0

local function Search(text)
    text = Trim(text):lower()
    if text ~= lastText then lastText, retries = text, 0 end
    if text == "" then return {} end

    local known, owned = KnownSpellSet(), OwnedItemSet()
    local list = {}   -- best matches, sorted by key (lower = better)
    local byDupe = {} -- dupe key -> entry currently in list
    local pending = false

    local function Consider(kind, id, lname, score, isKnown)
        local key = score * 10000 + (isKnown and 0 or 5000) + math.min(#lname, 999)
        if #list >= MAX_RESULTS and key >= list[#list].key then return end

        local dupe
        if kind == "spell" then
            local _, rank = GetSpellInfo(id)
            dupe = "s" .. lname .. (rank or "") -- collapse same-name/same-rank copies
        else
            dupe = "i" .. id
        end

        local ex = byDupe[dupe]
        if ex then
            if key >= ex.key then return end
            for i = 1, #list do
                if list[i] == ex then table.remove(list, i) break end
            end
            byDupe[dupe] = nil
        end

        local entry = { kind = kind, id = id, key = key, dupe = dupe }
        local pos = #list + 1
        while pos > 1 and list[pos - 1].key > key do pos = pos - 1 end
        table.insert(list, pos, entry)
        byDupe[dupe] = entry
        if #list > MAX_RESULTS then
            local last = table.remove(list)
            byDupe[last.dupe] = nil
        end
    end

    local function AddById(kind, id)
        if kind == "spell" then
            local name = GetSpellInfo(id)
            if name then Consider("spell", id, name:lower(), 0, true) end
        else
            if GetItemInfo(id) then
                Consider("item", id, "", 0, true)
            else
                -- Not in the cache yet: ask the server, results update shortly
                scan:ClearLines()
                scan:SetOwner(UIParent, "ANCHOR_NONE")
                scan:SetHyperlink("item:" .. id)
                pending = true
            end
        end
    end

    -- A pasted / shift-clicked link: just that spell or item
    local k, v = text:match("(item):(%d+)")
    if not k then k, v = text:match("(spell):(%d+)") end
    local linked = k and tonumber(v)

    if linked then
        AddById(k, linked)
    else
        -- Typed an ID: offer both the spell and the item with that ID
        local num = tonumber(text)
        if num then
            AddById("spell", num)
            AddById("item", num)
        end

        -- Every spell in the game
        local ids, low = idx.spellIds, idx.spellLower
        for c = 1, #ids do
            local lname = low[c]
            local a = lname:find(text, 1, true)
            if a then
                local score = (lname == text) and 1 or ((a == 1) and 2 or 3)
                Consider("spell", ids[c], lname, score, known[ids[c]])
            end
        end

        -- Every cached item
        ids, low = idx.itemIds, idx.itemLower
        for c = 1, #ids do
            local lname = low[c]
            local a = lname:find(text, 1, true)
            if a then
                local score = (lname == text) and 1 or ((a == 1) and 2 or 3)
                Consider("item", ids[c], lname, score, owned[ids[c]])
            end
        end
    end

    if pending and retries < 4 then
        retries = retries + 1
        retryFrame.t = 0.8
        retryFrame:Show()
    end

    local results = {}
    for _, e in ipairs(list) do
        if e.kind == "spell" then
            local name, rank, icon = GetSpellInfo(e.id)
            local label = name or "?"
            if rank and rank ~= "" then label = label .. " (" .. rank .. ")" end
            label = label .. " |cff808080[" .. e.id .. "]|r"
            if known[e.id] then label = label .. " |cff00ff00*|r" end
            results[#results + 1] = { kind = "spell", id = e.id, name = label, icon = icon }
        else
            local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(e.id)
            local q = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            local label = ((q and q.hex) or "|cffffffff") .. (name or "?") .. "|r |cff808080[" .. e.id .. "]|r"
            if owned[e.id] then label = label .. " |cff00ff00*|r" end
            results[#results + 1] = { kind = "item", id = e.id, name = label, icon = icon }
        end
    end
    return results
end

local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local searchFrame = CreateFrame("Frame", "PingPongSearch", UIParent)
searchFrame:SetWidth(320)
searchFrame:SetHeight(390)
searchFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
searchFrame:SetFrameStrata("DIALOG")
searchFrame:SetMovable(true)
searchFrame:EnableMouse(true)
searchFrame:RegisterForDrag("LeftButton")
searchFrame:SetScript("OnDragStart", searchFrame.StartMoving)
searchFrame:SetScript("OnDragStop", searchFrame.StopMovingOrSizing)
searchFrame:SetBackdrop(DIALOG_BACKDROP)
searchFrame:Hide()
tinsert(UISpecialFrames, "PingPongSearch") -- Escape closes it

-- Any spell/item you hover can be picked with the first key of the override shortcut.
local BROWSE_EXTRA = 104 -- room for the help + hover lines

local title = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title:SetPoint("TOP", 0, -18)
title:SetText("PingPong: override pinged spells")

local current = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
current:SetPoint("TOP", title, "BOTTOM", 0, -4)
current:SetWidth(280)

local browseHelp = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
browseHelp:SetPoint("TOP", current, "BOTTOM", 0, -8)
browseHelp:SetWidth(280)

local hoverText = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
hoverText:SetPoint("TOP", browseHelp, "BOTTOM", 0, -8)
hoverText:SetWidth(280)

local box = CreateFrame("EditBox", "PingPongSearchBox", searchFrame, "InputBoxTemplate")
box:SetWidth(270)
box:SetHeight(20)
box:SetPoint("TOP", 0, -62)
box:SetAutoFocus(false)

local rows = {}

-- "[Starfall]", or "[Starfall] pings as [Heroism]" when it has an override
local function DescribeSlot(slot)
    local own = GetActionName(slot) or "?"
    local kind, id, isOverride = Resolve(slot)
    if isOverride then
        local link = (kind == "spell") and SpellLinkFor(id) or ItemLinkFor(id)
        return own .. " |cff808080pings as|r " .. tostring(link)
    end
    return own
end

local function UpdateCurrent()
    if not searchSlot then
        current:SetText("|cff808080No spell picked yet|r")
    else
        current:SetText("Editing: " .. DescribeSlot(searchSlot))
    end
end

local function Choose(data)
    if not data then return end
    if not searchKey then
        current:SetText("|cffff5555Pick a spell first: hover it and press "
            .. KeyLabel(FirstKey(Effective("edit"))) .. "|r")
        return
    end
    GetOverrides()[searchKey] = { kind = data.kind, id = data.id }
    local link = (data.kind == "spell") and SpellLinkFor(data.id) or ItemLinkFor(data.id)
    print("|cff00ff00PingPong|r now pings as " .. tostring(link) .. " on every button")
    -- Stay open so the next spell can be picked
    UpdateCurrent()
    box:SetText("")
    box:ClearFocus()
end

local function Refresh()
    local results = Search(box:GetText())
    for i = 1, MAX_RESULTS do
        local row, r = rows[i], results[i]
        if r then
            row.data = r
            row.icon:SetTexture(r.icon)
            row.text:SetText(((r.kind == "item") and "|cff9d9d9d[Item]|r " or "|cff71d5ff[Spell]|r ") .. r.name)
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end
end

for i = 1, MAX_RESULTS do
    local row = CreateFrame("Button", nil, searchFrame)
    row:SetWidth(276)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 22, -90 - (i - 1) * 24)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(20)
    row.icon:SetHeight(20)
    row.icon:SetPoint("LEFT", 0, 0)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetWidth(246)
    row.text:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnClick", function(self) Choose(self.data) end)
    row:Hide()
    rows[i] = row
end

box:SetScript("OnTextChanged", Refresh)

local function Layout()
    local extra = BROWSE_EXTRA
    searchFrame:SetHeight(390 + extra)
    box:ClearAllPoints()
    box:SetPoint("TOP", 0, -62 - extra)
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 22, -90 - extra - (i - 1) * 24)
    end
end
Layout()

local status = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 46)

local function UpdateStatus()
    if indexReady then
        status:SetText("|cff00ff00*|r = you know / own it")
    else
        status:SetText("Indexing game data... " .. IndexPercent() .. "%")
    end
end

onProgress = function()
    if searchFrame:IsShown() then
        UpdateStatus()
        Refresh()
    end
end
onRetry = function()
    if searchFrame:IsShown() then Refresh() end
end

-- Shift-clicking an item/spell link while the search box has focus pastes it
hooksecurefunc("ChatEdit_InsertLink", function(link)
    if link and GetCurrentKeyBoardFocus() == box then
        box:Insert(link)
    end
end)
box:SetScript("OnEscapePressed", function() searchFrame:Hide() end)
box:SetScript("OnEnterPressed", function() if rows[1] then Choose(rows[1].data) end end)

local clearBtn = CreateFrame("Button", nil, searchFrame, "UIPanelButtonTemplate")
clearBtn:SetWidth(130)
clearBtn:SetHeight(22)
clearBtn:SetPoint("BOTTOMLEFT", 22, 18)
clearBtn:SetText("Reset to default")
clearBtn:SetScript("OnClick", function()
    if searchKey then
        GetOverrides()[searchKey] = nil
        print("|cff00ff00PingPong|r override removed, it pings as itself again")
    end
    UpdateCurrent()
end)

local closeBtn = CreateFrame("Button", nil, searchFrame, "UIPanelButtonTemplate")
closeBtn:SetWidth(130)
closeBtn:SetHeight(22)
closeBtn:SetPoint("BOTTOMRIGHT", -22, 18)
closeBtn:SetText("Close")
closeBtn:SetScript("OnClick", function() searchFrame:Hide() end)

-- Browse mode: choose which spell/item the search result applies to
local function PickTarget(slot)
    searchSlot, searchKey = slot, ActionKey(slot)
    UpdateCurrent()
    box:SetText("")
    box:SetFocus()
end

local firstWasDown, hoverWait = false, 0
searchFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Pressing just the first key of the edit keybind picks the hovered spell.
    -- (A first key that isn't a modifier is a whole keybind on its own, which
    -- reaches OpenSearch below through its key binding.)
    local isDown = MOD_DOWN[FirstKey(Effective("edit"))]
    if isDown then
        local d = isDown() and true or false
        if d and not firstWasDown then
            local slot = GetHoveredSlot()
            if slot then PickTarget(slot) end
        end
        firstWasDown = d
    end

    hoverWait = hoverWait - elapsed
    if hoverWait <= 0 then
        hoverWait = 0.1
        local slot = GetHoveredSlot()
        hoverText:SetText("Hovering: " .. (slot and DescribeSlot(slot) or "|cff808080nothing|r"))
    end
end)

local function OpenBrowse()
    searchSlot, searchKey = nil, nil
    local edit = Effective("edit")
    browseHelp:SetText("Hover any spell or item on your bars or bags and press |cffffd100"
        .. KeyLabel(FirstKey(edit)) .. "|r to pick it, then search what it should ping as.\n"
        .. "Shortcut: hover a spell and press |cffffd100" .. BindText(edit) .. "|r to open this window on it.")
    UpdateCurrent()
    firstWasDown = true -- needs a fresh press
    searchFrame:Show()
    box:SetText("")
    box:ClearFocus()
    StartIndex()
    UpdateStatus()
    Refresh()
end

-- The override shortcut: the same window, with the hovered spell already picked
local function OpenSearch(slot)
    if not searchFrame:IsShown() then OpenBrowse() end
    PickTarget(slot)
end

-- Keybind detection ---------------------------------------------------------
-- Double-taps and modifier-only keybinds (Ctrl + Shift) can't be real WoW key
-- bindings, so the modifiers are watched every frame. Keybinds with a normal
-- key (Ctrl + Shift + M) become real override bindings, see ApplyBindings.

local rec -- the keybind being recorded in the options window (pings paused)

local function RunActions(acts)
    for _, act in ipairs(acts) do
        if act == "edit" then
            if spellPingEnabled then
                local slot = GetHoveredSlot()
                if slot then OpenSearch(slot) end
            end
        else
            -- Aura, spell and whisper keybinds all ping whatever is under the mouse
            local whisper = (act == "whisper")
            local a = GetHoveredAura()
            if not a and act == "aura" then
                local vu, vk = GetHoveredVital()
                if vu then SayVital(vu, vk, whisper) end
            end
            if a then
                Say(a.unit, a.index, a.filter, whisper)
            elseif act ~= "aura" and spellPingEnabled then
                local vu, vk = GetHoveredVital()
                if vu then
                    SayVital(vu, vk, whisper)
                else
                    local slot = GetHoveredSlot()
                    if slot then PingSlot(slot, whisper) end
                end
            end
        end
    end
end

local down, wasDown = {}, {}
local lastTap, lastTapTime = nil, 0

-- pressed: the modifier that just went down, or "many" if several did at once
local function OnModsPressed(pressed)
    local count = 0
    for _, m in ipairs(MOD_LIST) do
        if down[m] then count = count + 1 end
    end

    -- A tap only counts when that modifier is pressed on its own
    local isDouble = false
    if count == 1 then
        local now = GetTime()
        if lastTap == pressed and now - lastTapTime <= DOUBLE_TAP_WINDOW then
            isDouble, lastTap = true, nil
        else
            lastTap, lastTapTime = pressed, now
        end
    else
        lastTap = nil
    end

    local acts = {}
    for _, act in ipairs(ACTIONS) do
        local b = Effective(act)
        if (b.type == "mods" and ModsMatch(b.mods, down))
            or (isDouble and b.type == "double" and b.key == pressed) then
            acts[#acts + 1] = act
        end
    end
    RunActions(acts)
end

local pingFrame = CreateFrame("Frame")
pingFrame:SetScript("OnUpdate", function()
    down, wasDown = wasDown, down
    for _, m in ipairs(MOD_LIST) do down[m] = MOD_DOWN[m]() and true or nil end

    -- Don't react while typing in chat / the search box, or recording a keybind
    if GetCurrentKeyBoardFocus() or rec then
        lastTap = nil
        return
    end

    local pressed
    for _, m in ipairs(MOD_LIST) do
        if down[m] and not wasDown[m] then
            pressed = pressed and "many" or m
        end
    end
    if pressed then OnModsPressed(pressed) end
end)

local bindOwner = CreateFrame("Frame")
local keyButtons = {}
local bindPending = false

local function OnKeyButton(self) RunActions(self.actions) end

local function ApplyBindings()
    if InCombatLockdown() then
        bindPending = true -- key bindings can't change in combat, retry after
        return
    end
    bindPending = false
    ClearOverrideBindings(bindOwner)

    -- One button per key, so a keybind can run its action
    local groups, order = {}, {}
    for _, act in ipairs(ACTIONS) do
        local b = Effective(act)
        if b.type == "key" then
            local s = BindString(b)
            if not groups[s] then
                groups[s] = {}
                order[#order + 1] = s
            end
            table.insert(groups[s], act)
        end
    end
    for n, s in ipairs(order) do
        local btn = keyButtons[n]
        if not btn then
            btn = CreateFrame("Button", "PingPongKey" .. n, UIParent)
            btn:SetScript("OnClick", OnKeyButton)
            keyButtons[n] = btn
        end
        btn.actions = groups[s]
        SetOverrideBindingClick(bindOwner, false, s, btn:GetName())
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" or bindPending then ApplyBindings() end
end)

-- Options window (/pp) --------------------------------------------------------

local ACT_NAME = { aura = "Auras", spell = "Spells & items", whisper = "Whisper target",
                   edit = "Override shortcut" }

local opt = CreateFrame("Frame", "PingPongOptions", UIParent)
opt:SetWidth(430)
opt:SetHeight(376)
opt:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
opt:SetFrameStrata("HIGH") -- below the override window, which it opens
opt:SetMovable(true)
opt:EnableMouse(true)
opt:RegisterForDrag("LeftButton")
opt:SetScript("OnDragStart", opt.StartMoving)
opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
opt:SetBackdrop(DIALOG_BACKDROP)
opt:Hide()
tinsert(UISpecialFrames, "PingPongOptions")

local optTitle = opt:CreateFontString(nil, "ARTWORK", "GameFontNormal")
optTitle:SetPoint("TOP", 0, -18)
optTitle:SetText("PingPong Options")

local optMsg = opt:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
optMsg:SetPoint("BOTTOM", 0, 50)
optMsg:SetWidth(382)

local function OptMsg(text) optMsg:SetText(text or "") end

local function ShowTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
    local text = self.tipText
    if type(text) == "function" then text = text() end
    GameTooltip:AddLine(text, 1, 1, 1, 1)
    GameTooltip:Show()
end
local function HideTip() GameTooltip:Hide() end

local binders, tabs, pages, chanBtns = {}, {}, {}, {}
local currentTab = 1
local RefreshOptions, StopRecording

-- Tabs ----------------------------------------------------------------------
local TAB_NAMES = { "General", "Keybinds" }

for i = 1, #TAB_NAMES do
    local page = CreateFrame("Frame", nil, opt)
    page:SetPoint("TOPLEFT", opt, "TOPLEFT", 0, -74)
    page:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", 0, 0)
    pages[i] = page

    local t = CreateFrame("Button", "PingPongTab" .. i, opt, "UIPanelButtonTemplate")
    t:SetWidth(100)
    t:SetHeight(22)
    t:SetPoint("TOPLEFT", opt, "TOPLEFT", 24 + (i - 1) * 104, -42)
    t.label = TAB_NAMES[i]
    t:SetScript("OnClick", function()
        StopRecording()
        currentTab = i
        for n, p in ipairs(pages) do
            if n == i then p:Show() else p:Hide() end
        end
        RefreshOptions()
    end)
    tabs[i] = t
end
local genPage, keyPage = pages[1], pages[2]

local tabLine = opt:CreateTexture(nil, "ARTWORK")
tabLine:SetTexture(1, 1, 1, 0.15)
tabLine:SetHeight(1)
tabLine:SetPoint("TOPLEFT", 24, -68)
tabLine:SetPoint("TOPRIGHT", -24, -68)

-- The "!" holds all the how-to info
local infoBtn = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
infoBtn:SetWidth(26)
infoBtn:SetHeight(22)
infoBtn:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -24, -42)
infoBtn:SetText("|cffffd100!|r")
infoBtn.tipTitle = "Help"
infoBtn.tipText = "Hover any button or box for more info.\n\n"
    .. "|cffffd100Keybinds:|r click a keybind box, then press the keys you want. All of these work:\n"
    .. "  |cffffd100Double-tap|r a modifier: tap Shift (or Ctrl / Alt) twice quickly\n"
    .. "  |cffffd100Modifiers together|r: hold Ctrl + Shift\n"
    .. "  |cffffd1003-key combos|r: hold Ctrl + Shift, then press M (Ctrl + Shift + M)\n"
    .. "Esc cancels."
infoBtn:SetScript("OnEnter", ShowTip)
infoBtn:SetScript("OnLeave", HideTip)

-- General tab ---------------------------------------------------------------
local chanLabel = genPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
chanLabel:SetPoint("TOPLEFT", 24, -4)
chanLabel:SetText("Send pings to:")

for i, c in ipairs(CHANNELS) do
    local b = CreateFrame("Button", "PingPongChannel" .. c[1], genPage, "UIPanelButtonTemplate")
    b:SetWidth(60)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", 24 + (i - 1) * 62, -26)
    b.value, b.label = c[1], c[2]
    b.tipTitle, b.tipText = c[2], c[3]
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", HideTip)
    b:SetScript("OnClick", function(self)
        PingPongDB.channel = self.value
        RefreshOptions()
        OptMsg("Pings now go to: " .. self.label)
    end)
    chanBtns[i] = b
end

local genSep = genPage:CreateTexture(nil, "ARTWORK")
genSep:SetTexture(1, 1, 1, 0.15)
genSep:SetHeight(1)
genSep:SetPoint("TOPLEFT", 24, -62)
genSep:SetPoint("TOPRIGHT", -24, -62)

local overrideBtn = CreateFrame("Button", "PingPongOverrideButton", genPage, "UIPanelButtonTemplate")
overrideBtn:SetWidth(190)
overrideBtn:SetHeight(22)
overrideBtn:SetPoint("TOPLEFT", 24, -76)
overrideBtn:SetText("Override pinged spells")
overrideBtn.tipTitle = "Override pinged spells"
overrideBtn.tipText = function()
    return "Choose what a spell or item pings as.\n\n"
        .. "|cffffd100Why?|r Some buttons don't ping what you want: macros only ping their macro "
        .. "name, and trinkets, items that cast a spell or other ranks may link the wrong thing. "
        .. "An override makes it ping the spell/item you pick (with that one's cooldown), "
        .. "on any bar. Saved per character.\n\n"
        .. "|cffffd100Shortcut:|r hover a spell/item and press " .. BindText(Effective("edit"))
        .. " to open this window on it."
end
overrideBtn:SetScript("OnEnter", ShowTip)
overrideBtn:SetScript("OnLeave", HideTip)
overrideBtn:SetScript("OnClick", function()
    StopRecording()
    OpenBrowse()
end)

local iconCheck = CreateFrame("CheckButton", "PingPongIconCheck", genPage, "UICheckButtonTemplate")
iconCheck:SetPoint("TOPLEFT", 20, -106)
_G["PingPongIconCheckText"]:SetText("Show spell icons on pings")
iconCheck.tipTitle = "Spell icons"
iconCheck.tipText = "Puts the spell or item icon in front of pings you receive, in chat and "
    .. "on chat bubbles. Only PingPong's own pings get an icon, and only players with "
    .. "PingPong see it. Nothing extra is sent, so it works on servers that block icons."
iconCheck:SetScript("OnEnter", ShowTip)
iconCheck:SetScript("OnLeave", HideTip)
iconCheck:SetScript("OnClick", function(self)
    PingPongDB.icons = self:GetChecked() and true or false
    OptMsg("Spell icons " .. (PingPongDB.icons and "on" or "off"))
end)

-- Size boxes: type a number, press Enter (or click away) to save
local sizeBoxes = {}

local function SizeBoxCommit(self)
    local n = tonumber(self:GetText())
    local lim = Sizes.limits[self.key]
    if not n then
        OptMsg("|cffff5555Type a number (" .. lim[1] .. " to " .. lim[2] .. ").|r")
    else
        n = math.max(lim[1], math.min(lim[2], n))
        if self.key == "bubbleBorder" or self.key == "bubbleLine" then n = math.floor(n + 0.5) end
        PingPongDB.sizes = PingPongDB.sizes or {}
        PingPongDB.sizes[self.key] = n
        OptMsg(self.tipTitle .. " set to " .. n .. ". " .. self.appliesTo)
    end
    self:SetText(tostring(Sizes.get(self.key)))
end

local function MakeSizeBox(key, y, label, tip, appliesTo, xLabel, xBox)
    local fs = genPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", xLabel or 24, y - 4)
    fs:SetText(label)

    local b = CreateFrame("EditBox", "PingPongSize_" .. key, genPage, "InputBoxTemplate")
    b:SetWidth(44)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", xBox or 190, y)
    b:SetAutoFocus(false)
    b:SetMaxLetters(5)
    b.key, b.appliesTo, b.tipText = key, appliesTo, tip
    b.tipTitle = (label:gsub(":$", ""))
    b:SetScript("OnEnterPressed", function(self)
        SizeBoxCommit(self)
        self:ClearFocus()
    end)
    b:SetScript("OnEditFocusLost", function(self)
        if self:GetText() ~= tostring(Sizes.get(self.key)) then SizeBoxCommit(self) end
    end)
    b:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Sizes.get(self.key)))
        self:ClearFocus()
    end)
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", HideTip)
    sizeBoxes[#sizeBoxes + 1] = b
end

MakeSizeBox("bubbleIcon", -138, "Bubble icon size:",
    "Size of the spell icon next to a chat bubble, in pixels.\n\n|cffffd100Default: "
    .. Sizes.default.bubbleIcon .. "|r  (" .. Sizes.limits.bubbleIcon[1] .. " to "
    .. Sizes.limits.bubbleIcon[2] .. ")",
    "Shows on the next bubble.")

MakeSizeBox("bubbleText", -164, "Bubble text size:",
    "Size of the green Ready / red cooldown / red reason (Stunned, Mana...) text under the bubble icon.\n\n|cffffd100Default: "
    .. Sizes.default.bubbleText .. "|r  (" .. Sizes.limits.bubbleText[1] .. " to "
    .. Sizes.limits.bubbleText[2] .. ")",
    "Shows on the next bubble.")

-- In front of the text size box, same row
MakeSizeBox("bubbleBorder", -164, "Border:",
    "Thickness of the border around the bubble text (Ready / cooldown / aura timer).\n\n"
    .. "0 = no border, 1 = thin, 2 = thick.\n\n|cffffd100Default: " .. Sizes.default.bubbleBorder
    .. "|r  (" .. Sizes.limits.bubbleBorder[1] .. " to " .. Sizes.limits.bubbleBorder[2] .. ")",
    "Shows on the next bubble.", 252, 304)

MakeSizeBox("chatIcon", -190, "Chat icon size:",
    "Size of the spell icon in the chat window, as a multiple of the chat text height. "
    .. "2 is twice as tall as the text, 3 is three times.\n\n|cffffd100Default: "
    .. Sizes.default.chatIcon .. "|r  (" .. Sizes.limits.chatIcon[1] .. " to "
    .. Sizes.limits.chatIcon[2] .. ")",
    "Shows on the next ping in chat.")

MakeSizeBox("bubbleLine", -216, "Dispel line size:",
    "Thickness, in pixels, of the colored line behind a debuff's bubble icon. It only "
    .. "shows for dispellable debuffs: Magic is light blue, Poison green, Curse purple, "
    .. "Disease brown. 0 turns it off.\n\n|cffffd100Default: " .. Sizes.default.bubbleLine
    .. "|r  (" .. Sizes.limits.bubbleLine[1] .. " to " .. Sizes.limits.bubbleLine[2] .. ")",
    "Shows on the next bubble.")

-- Keybinds tab: recording ---------------------------------------------------
StopRecording = function()
    if not rec then return end
    rec.b:EnableKeyboard(false)
    rec.b:SetScript("OnUpdate", nil)
    rec = nil
    RefreshOptions()
end

-- Keep listening, but forget what was pressed so far
local function RecRetry(text)
    rec.order, rec.held, rec.tapKey = {}, {}, nil
    rec.b:SetText("|cffffd100Press keys...|r")
    OptMsg("|cffff5555" .. text .. "|r")
end

-- Held modifiers, in the order they were pressed
local function HeldInOrder()
    local mods = {}
    for _, m in ipairs(rec.order) do
        if MOD_DOWN[m]() then mods[#mods + 1] = m end
    end
    for _, m in ipairs(MOD_LIST) do -- held before the box started listening
        if MOD_DOWN[m]() and not Has(mods, m) then mods[#mods + 1] = m end
    end
    return mods
end

local function Commit(bind)
    local act, k = rec.b.act, Keys()
    if bind.type == "click" then
        if act ~= "aura" then
            return RecRetry("Clicks can't be used here (hover the box to see why). Press keys instead.")
        elseif bind.button ~= "LeftButton" then
            return RecRetry("Auras only work with left click. Hold a modifier and left click the box.")
        elseif #bind.mods == 0 then
            return RecRetry("Hold Shift, Ctrl or Alt while clicking, a plain click would ping all the time.")
        end
    end

    -- Two actions on the same keys would both fire
    local sig = BindSig(bind)
    for _, other in ipairs(ACTIONS) do
        if other ~= act and BindSig(Effective(other)) == sig then
            return RecRetry(BindText(bind) .. " is already the " .. ACT_NAME[other] .. " keybind.")
        end
    end

    k[act] = bind
    StopRecording()
    ApplyBindings()
    OptMsg("|cff00ff00Saved:|r " .. ACT_NAME[act] .. " = " .. BindText(bind))
end

-- Waiting for the second tap of a double-tap
local function RecUpdate(self)
    if rec and rec.tapKey and GetTime() - rec.tapTime > DOUBLE_TAP_WINDOW then
        local name = MOD_NAME[rec.tapKey]
        RecRetry(name .. " alone can't be a keybind. Tap it twice quickly, or hold it with other keys.")
    end
end

local function StartRecording(b)
    StopRecording()
    rec = { b = b, order = {}, held = {} }
    b:EnableKeyboard(true)
    b:SetScript("OnUpdate", RecUpdate)
    b:SetText("|cffffd100Press keys...|r")
    if b.act == "aura" then
        OptMsg("Press your keys, or hold a modifier and left click this box. Esc cancels.")
    else
        OptMsg("Press your keys now. Esc cancels.")
    end
end

local function BinderKeyDown(self, key)
    if not rec then return end
    if key == "ESCAPE" then
        StopRecording()
        OptMsg("Cancelled.")
        return
    end

    local m = MOD_OF[key]
    if not m then
        if key ~= "UNKNOWN" then Commit({ type = "key", mods = HeldInOrder(), key = key }) end
        return
    end

    if rec.tapKey then
        if rec.tapKey == m and GetTime() - rec.tapTime <= DOUBLE_TAP_WINDOW then
            Commit({ type = "double", key = m })
            return
        end
        rec.tapKey, rec.order, rec.held = nil, {}, {}
    end
    if not rec.held[m] then
        rec.held[m] = true
        if not Has(rec.order, m) then rec.order[#rec.order + 1] = m end
    end

    local parts = {}
    for i, x in ipairs(rec.order) do parts[i] = MOD_NAME[x] end
    self:SetText("|cffffd100" .. table.concat(parts, " + ") .. " + ...|r")
end

local function BinderKeyUp(self, key)
    local m = rec and MOD_OF[key]
    if not m or not rec.held[m] then return end
    rec.held[m] = nil
    if next(rec.held) then return end -- still holding something

    if #rec.order >= 2 then
        local mods = {}
        for i, x in ipairs(rec.order) do mods[i] = x end
        Commit({ type = "mods", mods = mods })
        return
    end
    -- A lone modifier: give it a moment for the second tap
    rec.tapKey, rec.tapTime = m, GetTime()
    self:SetText("|cffffd100" .. MOD_NAME[m] .. ", tap again...|r")
end

local function BinderClick(self, button)
    if not rec or rec.b ~= self then
        StartRecording(self)
        return
    end
    Commit({ type = "click", mods = HeldInOrder(), button = button })
end

local NO_CLICKS = "\n\n|cffffd100Why no mouse clicks?|r Clicking a spell or item button casts or uses it. "
    .. "The game handles that click itself, so PingPong never sees which key you held. Use keys instead."

local function MakeBinder(act, y, label, tipText)
    local fs = keyPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 24, y - 5)
    fs:SetText(label)

    local b = CreateFrame("Button", "PingPongBind_" .. act, keyPage, "UIPanelButtonTemplate")
    b:SetWidth(190)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", 150, y)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b.act, b.tipTitle, b.tipText = act, label:gsub(":$", ""), tipText
    b:SetScript("OnClick", BinderClick)
    b:SetScript("OnKeyDown", BinderKeyDown)
    b:SetScript("OnKeyUp", BinderKeyUp)
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", HideTip)
    binders[act] = b
    return b
end

-- Keybinds tab: rows --------------------------------------------------------
MakeBinder("aura", -6, "Auras:",
    "Pings the buff/debuff you click, or the health / power of the player and target "
    .. "frame (top half = health, bottom half = power).\n\n"
    .. "|cffffd100Left click only.|r Right click can't be used.\n"
    .. "To set a click, hold a modifier and left click this box.")

MakeBinder("spell", -36, "Spells & items:",
    "Hover a spell, item, aura, or the player / target frame and press this to ping it: "
    .. "ready, cooldown, time left, or health / power.\n\nIt works next to the Auras keybind, "
    .. "so both can be used at once." .. NO_CLICKS)

MakeBinder("whisper", -66, "Whisper target:",
    "Same as Spells & items, but it whispers your friendly target instead of "
    .. "using the ping channel." .. NO_CLICKS)

MakeBinder("edit", -96, "Override shortcut:", function()
    return "Hover a spell or item and press this to open the override window "
        .. "with that spell already picked.\n\n"
        .. "Inside the window, pressing only the first key (|cffffd100"
        .. KeyLabel(FirstKey(Effective("edit"))) .. "|r) picks the hovered spell." .. NO_CLICKS
end)

local resetBtn = CreateFrame("Button", nil, keyPage, "UIPanelButtonTemplate")
resetBtn:SetWidth(130)
resetBtn:SetHeight(22)
resetBtn:SetPoint("BOTTOMLEFT", opt, "BOTTOMLEFT", 22, 18)
resetBtn:SetText("Reset keybinds")
resetBtn.tipTitle = "Reset keybinds"
resetBtn.tipText = "Auras: " .. BindText(DEFAULT_KEYS.aura)
    .. "\nSpells & items: " .. BindText(DEFAULT_KEYS.spell)
    .. "\nWhisper target: " .. BindText(DEFAULT_KEYS.whisper)
    .. "\nOverride shortcut: " .. BindText(DEFAULT_KEYS.edit)
resetBtn:SetScript("OnEnter", ShowTip)
resetBtn:SetScript("OnLeave", HideTip)
resetBtn:SetScript("OnClick", function()
    StopRecording()
    local k = Keys()
    for act, def in pairs(DEFAULT_KEYS) do k[act] = CopyBind(def) end
    ApplyBindings()
    RefreshOptions()
    OptMsg("Keybinds reset to default.")
end)

local optClose = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
optClose:SetWidth(130)
optClose:SetHeight(22)
optClose:SetPoint("BOTTOMRIGHT", -22, 18)
optClose:SetText("Close")
optClose:SetScript("OnClick", function() opt:Hide() end)

RefreshOptions = function()
    for act, b in pairs(binders) do
        if not (rec and rec.b == b) then b:SetText(BindText(Effective(act))) end
    end
    -- The chosen tab / channel is gold and highlighted
    local function Mark(btn, on)
        if on then
            btn:SetText("|cffffd100" .. btn.label .. "|r")
            btn:LockHighlight()
        else
            btn:SetText(btn.label)
            btn:UnlockHighlight()
        end
    end
    for i, t in ipairs(tabs) do Mark(t, i == currentTab) end
    local ch = GetChannel()
    for _, b in ipairs(chanBtns) do Mark(b, b.value == ch) end
    iconCheck:SetChecked(IconsEnabled())
    for _, b in ipairs(sizeBoxes) do
        if not b:HasFocus() then b:SetText(tostring(Sizes.get(b.key))) end
    end
end

opt:SetScript("OnShow", function()
    OptMsg("")
    for n, p in ipairs(pages) do
        if n == currentTab then p:Show() else p:Hide() end
    end
    RefreshOptions()
end)
opt:SetScript("OnHide", StopRecording)

SLASH_PINGPONG1 = "/pp"
SLASH_PINGPONG2 = "/pingpong"
SlashCmdList["PINGPONG"] = function(msg)
    msg = Trim(msg):lower()
    if msg == "" or msg == "options" or msg == "config" then
        if opt:IsShown() then opt:Hide() else opt:Show() end
    elseif msg == "on" then
        spellPingEnabled = true
        print("|cff00ff00PingPong|r spell ping enabled")
    elseif msg == "off" then
        spellPingEnabled = false
        print("|cff00ff00PingPong|r spell ping disabled")
    elseif msg == "debug" then
        local slot = GetHoveredSlot()
        if type(slot) ~= "number" then
            print("|cff00ff00PingPong|r debug: hover an action button, then type /pp debug")
        else
            local t, id = GetActionInfo(slot)
            local k, real = TooltipTarget(slot)
            print("|cff00ff00PingPong|r debug: slot " .. slot)
            print("  GetActionInfo: " .. tostring(t) .. " " .. tostring(id)
                .. " -> " .. tostring(id and GetSpellInfo(id)))
            print("  tooltip: " .. tostring(k) .. " " .. tostring(real)
                .. " -> " .. tostring(real and GetSpellInfo(real)))
        end
    elseif msg == "bubble" then
        local n = 0
        for _, f in ipairs({ WorldFrame:GetChildren() }) do
            if not f:GetName() and f.GetRegions and f:IsShown() then
                local t = BubbleText(f)
                if t then
                    n = n + 1
                    print("|cff00ff00PingPong|r bubble " .. n .. ": " .. tostring(t):gsub("|", "||"):sub(1, 90))
                end
            end
        end
        if n == 0 then print("|cff00ff00PingPong|r no chat bubbles on screen, ping with Say/Yell first") end
    elseif msg == "clear" then
        local o = GetOverrides()
        for k in pairs(o) do o[k] = nil end
        print("|cff00ff00PingPong|r all button overrides removed for this character")
    else
        print("|cff00ff00PingPong|r: /pp - options & keybinds | /pp on | off | clear")
    end
end
