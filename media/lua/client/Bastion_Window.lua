-- ============================================================
-- Bastion_Window.lua  (media/lua/client/)
-- Unified tabbed Bastion management window.
-- Tabs: Overview | Settlers | Log | Settings
-- Open via: BastionWindow.open(player)
--           BastionWindow.toggle(player)
-- ============================================================
print("[Bastion] Window loading")

-- ── Constants ─────────────────────────────────────────────────────────────────

local WIN_W   = 500
local WIN_H   = 420
local TITLE_H = 24
local TAB_H   = 20   -- ISTabPanel tab-bar height
local CONT_H  = WIN_H - TITLE_H - TAB_H  -- height of each content panel

-- Log-entry colours  { r, g, b, a }
local LOG_COLORS = {
    standard   = { 0.85, 0.85, 0.85, 1.0 },
    warning    = { 1.0,  0.85, 0.3,  1.0 },
    critical   = { 1.0,  0.35, 0.35, 1.0 },
    arrival    = { 0.5,  1.0,  0.6,  1.0 },
    milestone  = { 0.7,  0.6,  1.0,  1.0 },
    suppressed = { 0.45, 0.45, 0.45, 1.0 },
}

-- ── Shared helpers ────────────────────────────────────────────────────────────

local function getModRec(player)
    if not player then return nil end
    local world = ModData.get(Bastion.DATA_KEY) or {}
    return world[player:getUsername()]
end

-- Returns r,g,b triple based on numeric value vs thresholds.
local function dayColor(v, good, warn)
    if v > good  then return 0.4,  1.0, 0.4
    elseif v >= warn then return 1.0,  0.9, 0.2
    else              return 1.0, 0.35, 0.35
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Overview Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionOverviewPanel = ISPanel:derive("BastionOverviewPanel")

function BastionOverviewPanel:new(w, h)
    local o = ISPanel.new(self, 0, 0, w, h)
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor     = { r=0, g=0, b=0, a=0 }
    o.rows            = {}   -- { text, r, g, b, indent }
    return o
end

function BastionOverviewPanel:populate(player)
    self.rows = {}
    local rec = getModRec(player)

    local function row(text, r, g, b, indent)
        table.insert(self.rows, {
            text   = text  or "",
            r      = r     or 0.85,
            g      = g     or 0.85,
            b      = b     or 0.85,
            indent = indent or false,
        })
    end

    if not rec then
        row("Establishing bastion...", 0.55, 0.55, 0.55)
        row("Close and re-open in a moment once the server responds.", 0.45, 0.45, 0.45)
        return
    end

    local settlers = rec.settlers or {}

    row("SETTLEMENT OVERVIEW", 0.8, 0.65, 1.0)
    row("")
    row("Settlers:  " .. #settlers)

    local fd = rec.foodDays or 0
    local fr, fg, fb = dayColor(fd, 7, 3)
    row(string.format("Food:      %.1f days", fd), fr, fg, fb)

    local wd = rec.waterDays or 0
    local wr, wg, wb = dayColor(wd, 7, 2)
    row(string.format("Water:     %.1f days", wd), wr, wg, wb)

    local ns = rec.noiseScore  or 0
    local nb = rec.noiseBudget or 6
    local nk = rec.noiseBudgetLevel or "Normal"
    local nr, ng, nbl
    if ns <= nb then nr, ng, nbl = 0.4, 1.0, 0.4
    elseif ns <= nb * 1.5 then nr, ng, nbl = 1.0, 0.9, 0.2
    else nr, ng, nbl = 1.0, 0.35, 0.35 end
    row(string.format("Noise:     %d / %d  [%s]", ns, nb, nk), nr, ng, nbl)

    if rec.happiness then
        row(string.format("Happiness: %d", rec.happiness))
    end
    if rec.resolve then
        row(string.format("Resolve:   %d", rec.resolve))
    end
    if rec.education and rec.education > 0 then
        row(string.format("Education: %d", rec.education))
    end
    row("")

    -- Last 3 log entries for a quick glance
    local log = rec.settlementLog or {}
    if #log > 0 then
        row("Recent activity:", 0.75, 0.65, 1.0)
        for i = math.max(1, #log - 2), #log do
            local e = log[i]
            if e then
                local col = LOG_COLORS[e.logType or "standard"] or LOG_COLORS.standard
                row("[Day " .. (e.day or 0) .. "] " .. (e.text or ""),
                    col[1], col[2], col[3], true)
            end
        end
    end
end

function BastionOverviewPanel:render()
    ISPanel.render(self)
    local y  = 8
    local dx = 10
    for _, r in ipairs(self.rows) do
        if r.text == "" then
            y = y + 7
        else
            local x = r.indent and (dx + 14) or dx
            self:drawText(r.text, x, y, r.r, r.g, r.b, 1.0, UIFont.Small)
            y = y + 15
        end
        if y > self.height - 6 then break end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Settlers Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionSettlersPanel = ISPanel:derive("BastionSettlersPanel")

function BastionSettlersPanel:new(w, h)
    local o = ISPanel.new(self, 0, 0, w, h)
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor     = { r=0, g=0, b=0, a=0 }
    o.listbox         = nil
    o.listH           = math.floor(h * 0.55)
    return o
end

function BastionSettlersPanel:createChildren()
    local lb = ISScrollingListBox:new(0, 0, self.width, self.listH)
    lb:initialise()
    lb:instantiate()
    lb.itemheight      = 18
    lb.doDrawItem      = BastionSettlersPanel.drawItem
    lb.backgroundColor = { r=0, g=0, b=0, a=0.3 }
    lb.borderColor     = { r=0.3, g=0.25, b=0.45, a=0.6 }
    self:addChild(lb)
    self.listbox = lb
end

function BastionSettlersPanel:populate(player)
    if not self.listbox then return end
    self.listbox:clear()
    local rec = getModRec(player)
    if not rec or not rec.settlers or #rec.settlers == 0 then
        self.listbox:addItem("(no settlers yet)", nil)
        return
    end
    for _, s in ipairs(rec.settlers) do
        local label = s.name
                      .. "  —  " .. (s.role or "?")
                      .. "  [" .. (s.mood or "Content") .. "]"
        self.listbox:addItem(label, s)
    end
end

function BastionSettlersPanel.drawItem(listbox, y, item, alt)
    if not item then return end
    local settler = item.item
    local r, g, b = 0.85, 0.85, 0.85
    if settler then
        if settler.mood == "Struggling" then r, g, b = 1.0, 0.9, 0.2
        elseif settler.mood == "Critical" then r, g, b = 1.0, 0.35, 0.35 end
    end
    if alt then
        listbox:drawRect(0, y, listbox:getWidth(), listbox.itemheight,
                         0.04, 0.5, 0.4, 0.6)
    end
    listbox:drawText(item.text or "", 6, y + 2, r, g, b, 1.0, UIFont.Small)
end

function BastionSettlersPanel:render()
    ISPanel.render(self)

    -- Detail pane background (below the list)
    local dy = self.listH + 4
    local dh = self.height - dy
    self:drawRect(0, dy, self.width, dh, 0.65, 0.04, 0.03, 0.07)

    -- Resolve selected settler
    local sel = nil
    if self.listbox
    and self.listbox.selected
    and self.listbox.selected >= 1 then
        local item = self.listbox.items[self.listbox.selected]
        if item then sel = item.item end
    end

    local y  = dy + 8
    local dx = 10

    if not sel or not sel.name then
        self:drawText("Select a settler above to view their profile.",
                      dx, y, 0.5, 0.5, 0.5, 0.8, UIFont.Small)
        return
    end

    -- Name / role header
    self:drawText(sel.name .. "  (" .. (sel.role or "?") .. ")",
                  dx, y, 0.85, 0.75, 1.0, 1.0, UIFont.Medium)
    y = y + 22

    -- Mood (colour-coded)
    local mood = sel.mood or "Content"
    local mr, mg, mb = 0.85, 0.85, 0.85
    if mood == "Struggling" then mr, mg, mb = 1.0, 0.9, 0.2
    elseif mood == "Critical" then mr, mg, mb = 1.0, 0.35, 0.35 end
    self:drawText("Mood: " .. mood, dx, y, mr, mg, mb, 1.0, UIFont.Small)
    y = y + 16

    self:drawText("Skill: " .. (sel.skillLevel or 1)
                  .. "   Trait: " .. (sel.traitTag or "none"),
                  dx, y, 0.75, 0.9, 0.75, 1.0, UIFont.Small)
    y = y + 16

    if sel.backstory and sel.backstory ~= "" then
        self:drawText(sel.backstory, dx, y, 0.8, 0.8, 0.8, 1.0, UIFont.Small)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Log Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionLogTabPanel = ISPanel:derive("BastionLogTabPanel")

function BastionLogTabPanel:new(w, h)
    local o = ISPanel.new(self, 0, 0, w, h)
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor     = { r=0, g=0, b=0, a=0 }
    o.listbox         = nil
    return o
end

function BastionLogTabPanel:createChildren()
    local lb = ISScrollingListBox:new(4, 4, self.width - 8, self.height - 8)
    lb:initialise()
    lb:instantiate()
    lb.itemheight      = 18
    lb.doDrawItem      = BastionLogTabPanel.drawItem
    lb.backgroundColor = { r=0, g=0, b=0, a=0.3 }
    lb.borderColor     = { r=0.3, g=0.25, b=0.45, a=0.6 }
    self:addChild(lb)
    self.listbox = lb
end

function BastionLogTabPanel:populate(player)
    if not self.listbox then return end
    self.listbox:clear()
    local rec = getModRec(player)
    if not rec or not rec.settlementLog or #rec.settlementLog == 0 then
        self.listbox:addItem("(no log entries yet)",
            { logType = "standard", day = 0, text = "(no log entries yet)" })
        return
    end
    for _, entry in ipairs(rec.settlementLog) do
        local display = "[Day " .. (entry.day or 0) .. "]  " .. (entry.text or "")
        self.listbox:addItem(display, entry)
    end
    -- Scroll to newest entry
    if self.listbox.vscroll then
        self.listbox.vscroll:setCurrentValue(
            self.listbox.vscroll.max or 0)
    end
end

function BastionLogTabPanel.drawItem(listbox, y, item, alt)
    if not item then return end
    local entry = item.item
    if not entry then return end
    local col = LOG_COLORS[entry.logType or "standard"] or LOG_COLORS.standard
    if alt then
        listbox:drawRect(0, y, listbox:getWidth(), listbox.itemheight,
                         0.04, 0.5, 0.4, 0.6)
    end
    listbox:drawText(item.text or "", 6, y + 2,
                     col[1], col[2], col[3], col[4] or 1.0, UIFont.Small)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionSettingsPanel = ISPanel:derive("BastionSettingsPanel")

function BastionSettingsPanel:new(w, h, player)
    local o = ISPanel.new(self, 0, 0, w, h)
    o.backgroundColor   = { r=0, g=0, b=0, a=0 }
    o.borderColor       = { r=0, g=0, b=0, a=0 }
    o.player            = player
    o.noiseBtns         = {}
    o.disbandBtn        = nil
    o.disbandConfirmBtn = nil
    return o
end

function BastionSettingsPanel:createChildren()
    local dx    = 14
    local btnW  = 90
    local gap   = 8
    local noiseY = 36

    -- One button per noise budget level
    for i, level in ipairs(Bastion.NOISE_BUDGET_LEVELS) do
        local bx  = dx + (i - 1) * (btnW + gap)
        local btn = ISButton:new(bx, noiseY, btnW, 24, level, self,
                                 BastionSettingsPanel.makeNoiseHandler(level))
        btn.noiseLevelTag   = level
        btn.borderColor     = { r=0.4, g=0.3, b=0.5, a=0.8 }
        btn.backgroundColor = { r=0.15, g=0.10, b=0.20, a=0.8 }
        btn:initialise()
        self:addChild(btn)
        table.insert(self.noiseBtns, btn)
    end

    local disbandY = 122

    -- First-click disband button
    self.disbandBtn = ISButton:new(dx, disbandY, 152, 24,
                                   "Disband Bastion",
                                   self, BastionSettingsPanel.onDisbandFirst)
    self.disbandBtn.borderColor     = { r=0.6, g=0.2, b=0.2, a=0.8 }
    self.disbandBtn.backgroundColor = { r=0.25, g=0.08, b=0.08, a=0.8 }
    self.disbandBtn:initialise()
    self:addChild(self.disbandBtn)

    -- Confirm button (hidden until first click)
    self.disbandConfirmBtn = ISButton:new(dx + 164, disbandY, 184, 24,
                                          "✓ Confirm — Disband Now",
                                          self, BastionSettingsPanel.onDisbandConfirm)
    self.disbandConfirmBtn.borderColor     = { r=0.9, g=0.2, b=0.2, a=1.0 }
    self.disbandConfirmBtn.backgroundColor = { r=0.45, g=0.05, b=0.05, a=0.9 }
    self.disbandConfirmBtn:initialise()
    self.disbandConfirmBtn:setVisible(false)
    self:addChild(self.disbandConfirmBtn)
end

-- Factory: captures loop variable correctly (Lua closure-in-loop issue).
-- ISButton calls onclick(target), so target = BastionSettingsPanel instance.
function BastionSettingsPanel.makeNoiseHandler(level)
    return function(target)
        if not target.player then return end
        sendClientCommand(target.player, Bastion.MOD_KEY, "SetNoiseBudget",
                          { level = level })
        -- Reset the confirm button if visible
        if target.disbandConfirmBtn then
            target.disbandConfirmBtn:setVisible(false)
        end
        if target.disbandBtn then
            target.disbandBtn:setVisible(true)
        end
    end
end

-- ISButton calls onclick(target) — colon syntax means self = target = panel. ✓
function BastionSettingsPanel:onDisbandFirst()
    self.disbandBtn:setVisible(false)
    self.disbandConfirmBtn:setVisible(true)
end

function BastionSettingsPanel:onDisbandConfirm()
    if not self.player then return end
    sendClientCommand(self.player, Bastion.MOD_KEY, "CollapseBastion", {})
    BastionWindow.close()
end

function BastionSettingsPanel:populate(player)
    self.player = player
    -- Reset disband state
    if self.disbandBtn        then self.disbandBtn:setVisible(true)  end
    if self.disbandConfirmBtn then self.disbandConfirmBtn:setVisible(false) end
end

function BastionSettingsPanel:render()
    ISPanel.render(self)

    -- Section label: Noise Budget
    self:drawText("Noise Budget", 14, 14, 0.75, 0.65, 1.0, 1.0, UIFont.Small)

    -- Highlight whichever noise button matches current setting
    local rec     = getModRec(self.player)
    local current = rec and rec.noiseBudgetLevel or "Normal"
    for _, btn in ipairs(self.noiseBtns) do
        if btn.noiseLevelTag == current then
            btn.backgroundColor = { r=0.35, g=0.22, b=0.55, a=0.95 }
        else
            btn.backgroundColor = { r=0.15, g=0.10, b=0.20, a=0.80 }
        end
    end

    -- Section label: Disband
    self:drawText("Disband Settlement",
                  14, 80, 0.65, 0.55, 0.55, 1.0, UIFont.Small)
    self:drawText("This is permanent. All settlers will disperse and the record will be erased.",
                  14, 96, 0.45, 0.45, 0.45, 0.9, UIFont.Small)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Window
-- ─────────────────────────────────────────────────────────────────────────────

BastionWindow = ISPanel:derive("BastionWindow")

function BastionWindow:new(x, y, player)
    local o = ISPanel.new(self, x, y, WIN_W, WIN_H)
    o.backgroundColor  = { r=0.05, g=0.04, b=0.08, a=0.92 }
    o.borderColor      = { r=0.5,  g=0.4,  b=0.7,  a=0.90 }
    o.player           = player
    o.dragging         = false
    o.dragMouseX       = 0
    o.dragMouseY       = 0
    o.dragWinX         = 0
    o.dragWinY         = 0
    o.refreshCounter   = 0
    o.tabs             = nil
    o.overviewPanel    = nil
    o.settlersPanel    = nil
    o.logPanel         = nil
    o.settingsPanel    = nil
    return o
end

function BastionWindow:createChildren()
    -- Close button in title bar (top-right)
    local closeBtn = ISButton:new(WIN_W - 26, 3, 22, 20, "x", self,
                                  BastionWindow.onClose)
    closeBtn.borderColor     = { r=0.5, g=0.3, b=0.3, a=0.8 }
    closeBtn.backgroundColor = { r=0.2, g=0.1, b=0.1, a=0.8 }
    closeBtn:initialise()
    self:addChild(closeBtn)

    -- ISTabPanel spanning below the title bar
    local tabs = ISTabPanel:new(0, TITLE_H, WIN_W, WIN_H - TITLE_H)
    tabs:initialise()

    -- Content panels (ISTabPanel will set their y = its tabHeight after addView)
    local ovPanel  = BastionOverviewPanel:new(WIN_W, CONT_H)
    local stPanel  = BastionSettlersPanel:new(WIN_W, CONT_H)
    local lgPanel  = BastionLogTabPanel:new(WIN_W, CONT_H)
    local sPanel   = BastionSettingsPanel:new(WIN_W, CONT_H, self.player)

    ovPanel:initialise()
    stPanel:initialise()
    lgPanel:initialise()
    sPanel:initialise()

    tabs:addView("Overview",  ovPanel)
    tabs:addView("Settlers",  stPanel)
    tabs:addView("Log",       lgPanel)
    tabs:addView("Settings",  sPanel)

    self:addChild(tabs)

    self.tabs          = tabs
    self.overviewPanel = ovPanel
    self.settlersPanel = stPanel
    self.logPanel      = lgPanel
    self.settingsPanel = sPanel
end

function BastionWindow:populate()
    local p = self.player
    if self.overviewPanel then self.overviewPanel:populate(p) end
    if self.settlersPanel then self.settlersPanel:populate(p) end
    if self.logPanel      then self.logPanel:populate(p)      end
    if self.settingsPanel then self.settingsPanel:populate(p) end
end

function BastionWindow:prerender()
    ISPanel.prerender(self)
    -- Title bar background
    self:drawRect(0, 0, WIN_W, TITLE_H, 0.95, 0.10, 0.08, 0.15)
    -- Title text
    self:drawText("Bastion", 10, 5, 0.8, 0.65, 1.0, 1.0, UIFont.Medium)
end

-- Close button callback: ISButton calls onclick(target), target = window. ✓
function BastionWindow:onClose()
    BastionWindow.close()
end

-- ── Dragging ──────────────────────────────────────────────────────────────────

function BastionWindow:onMouseDown(x, y)
    if y < TITLE_H then
        self.dragging   = true
        self.dragMouseX = getMouseX()
        self.dragMouseY = getMouseY()
        self.dragWinX   = self:getX()
        self.dragWinY   = self:getY()
    end
    return true
end

function BastionWindow:onMouseUp(x, y)
    self.dragging = false
    return true
end

function BastionWindow:update()
    ISPanel.update(self)

    -- Drag handling (done in update so it fires even when cursor leaves title bar)
    if self.dragging then
        if not Mouse.isButtonDown(Mouse.LEFT) then
            self.dragging = false
        else
            self:setX(self.dragWinX + (getMouseX() - self.dragMouseX))
            self:setY(self.dragWinY + (getMouseY() - self.dragMouseY))
        end
    end

    -- Auto-refresh every ~5 s so ModData changes arrive without a re-open
    self.refreshCounter = self.refreshCounter + 1
    if self.refreshCounter >= 150 then
        self.refreshCounter = 0
        self:populate()
    end
end

-- ── Module API ────────────────────────────────────────────────────────────────

BastionWindow._instance = nil

function BastionWindow.open(player)
    if BastionWindow._instance then
        BastionWindow._instance:bringToTop()
        BastionWindow._instance:populate()
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x  = math.floor((sw - WIN_W) / 2)
    local y  = math.floor((sh - WIN_H) / 2)

    local win = BastionWindow:new(x, y, player)
    win:initialise()
    win:addToUIManager()
    win:populate()
    BastionWindow._instance = win
end

function BastionWindow.close()
    if BastionWindow._instance then
        BastionWindow._instance:removeFromUIManager()
        BastionWindow._instance = nil
    end
end

function BastionWindow.toggle(player)
    if BastionWindow._instance then
        BastionWindow.close()
    else
        BastionWindow.open(player)
    end
end

print("[Bastion] Window done")
