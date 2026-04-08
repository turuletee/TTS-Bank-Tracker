-- TTS Bank Tracker (Three Tank Strat)
-- Tracks guild bank contributions on a weekly cycle (Tue 10:00 PST -> Tue 09:59 PST)

local TTSBT = LibStub("AceAddon-3.0"):NewAddon("TTSBankTracker", "AceConsole-3.0", "AceEvent-3.0")
_G.TTSBT = TTSBT -- expose for in-game debugging via /dump TTSBT

local defaults = {
    profile = {
        minContribution = 0,    -- gold required per tracked player per week
        trackedPlayers = {},    -- [playerName] = true
        weeklyHistory = {},     -- [weekStartTimestamp] = { [playerName] = copperContributed }
        installTime = 0,        -- set on first run, used to bound how far back the user can pick week 1
        -- firstWeekStart: timestamp of the user-chosen "week 1" Tuesday. Absent until configured.
    },
}

function TTSBT:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("TTSBankTrackerDB", defaults, true)
    if (self.db.profile.installTime or 0) == 0 then
        self.db.profile.installTime = time()
    end
    self:RegisterChatCommand("ttsbt", "HandleSlashCommand")
    self:Print("loaded. Type /ttsbt for commands.")
end

function TTSBT:OnEnable()
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self.TrackedPlayers:RequestRosterUpdate()
end

function TTSBT:GUILD_ROSTER_UPDATE()
    self.TrackedPlayers:InvalidateRosterCache()
end

-- ----------------------------------------------------------------------
-- Slash command dispatcher
-- ----------------------------------------------------------------------

local HELP_TEXT = "commands: |cffffff00status|r, |cffffff00week|r, |cffffff00track <name>|r, |cffffff00untrack <name>|r, |cffffff00tracked|r, |cffffff00roster [rankIndex] [search]|r, |cffffff00ranks|r"

function TTSBT:HandleSlashCommand(input)
    input = (input or ""):trim()
    if input == "" then
        self:Print(HELP_TEXT)
        return
    end
    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = rest or ""

    if cmd == "status" then
        self:Print("addon is alive. Tracked players: " .. self.TrackedPlayers:Count())
    elseif cmd == "week" then
        self:PrintWeekInfo()
    elseif cmd == "track" then
        self:CmdTrack(rest)
    elseif cmd == "untrack" then
        self:CmdUntrack(rest)
    elseif cmd == "tracked" then
        self:CmdListTracked()
    elseif cmd == "roster" then
        self:CmdRoster(rest)
    elseif cmd == "ranks" then
        self:CmdRanks()
    else
        self:Print("unknown command: " .. cmd)
        self:Print(HELP_TEXT)
    end
end

function TTSBT:CmdTrack(name)
    name = (name or ""):trim()
    if name == "" then self:Print("usage: /ttsbt track <name>") return end
    self.TrackedPlayers:Add(name)
    self:Print("now tracking: " .. name)
end

function TTSBT:CmdUntrack(name)
    name = (name or ""):trim()
    if name == "" then self:Print("usage: /ttsbt untrack <name>") return end
    if self.TrackedPlayers:Remove(name) then
        self:Print("untracked: " .. name)
    else
        self:Print("not tracked: " .. name)
    end
end

function TTSBT:CmdListTracked()
    local list = self.TrackedPlayers:List()
    if #list == 0 then
        self:Print("no players tracked yet")
        return
    end
    self:Print("|cffffff00Tracked players (" .. #list .. ")|r:")
    for _, name in ipairs(list) do
        self:Print("  " .. name)
    end
end

function TTSBT:CmdRoster(args)
    if not IsInGuild() then self:Print("not in a guild") return end
    local filters = {}
    for token in (args or ""):gmatch("%S+") do
        local n = tonumber(token)
        if n then filters.rankIndex = n
        else filters.nameQuery = token end
    end
    local roster = self.TrackedPlayers:GetRoster(filters)
    if #roster == 0 then
        self:Print("no roster results (try /ttsbt roster after a few seconds; roster fetch is async)")
        self.TrackedPlayers:RequestRosterUpdate()
        return
    end
    self:Print("|cffffff00Roster (" .. #roster .. ")|r:")
    for i = 1, math.min(#roster, 30) do
        local m = roster[i]
        local marker = self.TrackedPlayers:IsTracked(m.name) and "|cff33ff99[*]|r " or "    "
        self:Print(string.format("%s%s |cff999999(%s, lvl %d)|r", marker, m.name, m.rankName or "?", m.level or 0))
    end
    if #roster > 30 then
        self:Print("  ... and " .. (#roster - 30) .. " more (use filters to narrow)")
    end
end

function TTSBT:CmdRanks()
    if not IsInGuild() then self:Print("not in a guild") return end
    local ranks = self.TrackedPlayers:GetRanks()
    if #ranks == 0 then
        self:Print("no ranks loaded yet, try again in a moment")
        self.TrackedPlayers:RequestRosterUpdate()
        return
    end
    self:Print("|cffffff00Guild ranks|r:")
    for _, r in ipairs(ranks) do
        self:Print(string.format("  [%d] %s", r.index, r.name))
    end
end

-- Helper for sanity-checking the WeekEngine math from in-game.
function TTSBT:PrintWeekInfo()
    local W = self.WeekEngine
    local now = time()
    local currentStart = W:GetCurrentWeekStart()
    local currentEnd = W:GetWeekEnd(currentStart)
    self:Print("|cffffff00Current week|r")
    self:Print("  start: " .. W:FormatWeek(currentStart))
    self:Print("  end:   " .. date("!%Y-%m-%d %I:%M %p PST", (currentEnd + 1) - 8 * 3600) .. " (exclusive)")
    self:Print("  now:   " .. date("!%Y-%m-%d %I:%M %p PST", now - 8 * 3600))
    if self.db.profile.firstWeekStart then
        local idx = W:GetWeekIndex(currentStart, self.db.profile.firstWeekStart)
        self:Print("  index: week " .. idx .. " (since first tracked week)")
    else
        self:Print("  first tracked week not set yet")
    end
    self:Print("  install: " .. date("!%Y-%m-%d %I:%M %p PST", self.db.profile.installTime - 8 * 3600))
end
