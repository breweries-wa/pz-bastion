-- ============================================================
-- Bastion_Window.lua  (media/lua/client/)
-- Unified tabbed Bastion management window.
-- Tabs: Overview | Settlers | Log | Settings
-- Resizable: drag the bottom-right grip.
-- Open via: BastionWindow.open(player)
--           BastionWindow.toggle(player)
-- ============================================================
print("[Bastion] Window loading")

-- ── Constants ─────────────────────────────────────────────────────────────────

local DEF_W   = 500
local DEF_H   = 440
local MIN_W   = 400
local MIN_H   = 320
local TITLE_H = 30    -- room for UIFont.Medium title text
local TAB_H   = 28    -- room for UIFont.Small tab labels
local CONT_Y  = TITLE_H + TAB_H   -- 58 — top edge of content area
local GRIP    = 14    -- bottom-right resize handle size

local TABS = { "Overview", "Settlers", "Log", "Settings" }

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

local function dayColor(v, good, warn)
    if     v > good then return 0.4,  1.0, 0.4
    elseif v >= warn then return 1.0,  0.9, 0.2
    else              return 1.0, 0.35, 0.35
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Overview Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionOverviewPanel = ISPanel:derive("BastionOverviewPanel")

function BastionOverviewPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor     = { r=0, g=0, b=0, a=0 }
    o.rows            = {}
    return o
end

function BastionOverviewPanel:populate(player)
    self.rows = {}
    local rec = getModRec(player)

    local function row(text, r, g, b, indent)
        table.insert(self.rows, {
            text   = text   or "",
            r      = r      or 0.85,
            g      = g      or 0.85,
            b      = b      or 0.85,
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

    local wd   = rec.waterDays        or 0
    local pool = rec.settlerWaterPool or 0
    local wr, wg, wb = dayColor(wd, 7, 2)
    if pool > 0.05 then
        row(string.format("Water:     %.1f days  (%.1f from settler pool)", wd, pool), wr, wg, wb)
    else
        row(string.format("Water:     %.1f days", wd), wr, wg, wb)
    end

    local ns = rec.noiseScore  or 0
    local nb = rec.noiseBudget or 6
    local nk = rec.noiseBudgetLevel or "Normal"
    local nr, ng, nbl
    if ns <= nb then nr, ng, nbl = 0.4, 1.0, 0.4
    elseif ns <= nb * 1.5 then nr, ng, nbl = 1.0, 0.9, 0.2
    else nr, ng, nbl = 1.0, 0.35, 0.35 end
    row(string.format("Noise:     %d / %d  [%s]", ns, nb, nk), nr, ng, nbl)

    if rec.happiness then row(string.format("Happiness: %d", rec.happiness)) end
    if rec.resolve   then row(string.format("Resolve:   %d", rec.resolve))   end
    if rec.education and rec.education > 0 then
        row(string.format("Education: %d", rec.education))
    end

    if rec.cachedWaterSource ~= nil or rec.cachedHeatSource ~= nil then
        row("")
        row("Infrastructure:", 0.75, 0.65, 1.0)
        local wsR = rec.cachedWaterSource and 0.4 or 1.0
        local wsG = rec.cachedWaterSource and 1.0 or 0.35
        local wsB = rec.cachedWaterSource and 0.4 or 0.35
        row("  Water source: " .. (rec.cachedWaterSource and "found" or "NOT FOUND"), wsR, wsG, wsB, true)
        local hsR = rec.cachedHeatSource and 0.4 or 1.0
        local hsG = rec.cachedHeatSource and 1.0 or 0.35
        local hsB = rec.cachedHeatSource and 0.4 or 0.35
        row("  Heat source:  " .. (rec.cachedHeatSource  and "found" or "NOT FOUND"), hsR, hsG, hsB, true)
        if rec.cachedHasAnimals then
            row("  Animals:      present", 0.4, 1.0, 0.4, true)
        end
    end

    local yield = rec.virtualYield
    if yield then
        local hasAny = false
        for k, v in pairs(yield) do
            if type(v) == "number" and v > 0 then hasAny = true; break end
        end
        if hasAny then
            row("")
            row("Settler production (pending):", 0.75, 0.65, 1.0)
            local displayList = (Bastion and Bastion.YIELD_DISPLAY) or {}
            local shown = {}
            for _, entry in ipairs(displayList) do
                local v = yield[entry.key]
                if v and v > 0 then
                    row(string.format("  %-22s %d", entry.label .. ":", math.floor(v)), 0.75, 0.9, 0.75, true)
                    shown[entry.key] = true
                end
            end
            for k, v in pairs(yield) do
                if not shown[k] and type(v) == "number" and v > 0 then
                    row(string.format("  %-22s %d", k .. ":", math.floor(v)), 0.75, 0.9, 0.75, true)
                end
            end
            row("  (Item claiming coming in a future update)", 0.45, 0.45, 0.45, true)
        end
    end

    row("")
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

function BastionSettlersPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
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

function BastionSettlersPanel:doResize(w, h)
    self:setWidth(w)
    self:setHeight(h)
    self.listH = math.floor(h * 0.55)
    if self.listbox then
        self.listbox:setWidth(w)
        self.listbox:setHeight(self.listH)
    end
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
        if     settler.mood == "Struggling" then r, g, b = 1.0, 0.9,  0.2
        elseif settler.mood == "Critical"   then r, g, b = 1.0, 0.35, 0.35 end
    end
    if alt then
        listbox:drawRect(0, y, listbox:getWidth(), listbox.itemheight, 0.04, 0.5, 0.4, 0.6)
    end
    listbox:drawText(item.text or "", 6, y + 2, r, g, b, 1.0, UIFont.Small)
end

function BastionSettlersPanel:render()
    ISPanel.render(self)
    local dy = self.listH + 4
    local dh = self.height - dy
    self:drawRect(0, dy, self.width, dh, 0.65, 0.04, 0.03, 0.07)

    local sel = nil
    if self.listbox and self.listbox.selected and self.listbox.selected >= 1 then
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

    self:drawText(sel.name .. "  (" .. (sel.role or "?") .. ")",
                  dx, y, 0.85, 0.75, 1.0, 1.0, UIFont.Medium)
    y = y + 22

    local mood = sel.mood or "Content"
    local mr, mg, mb = 0.85, 0.85, 0.85
    if     mood == "Struggling" then mr, mg, mb = 1.0, 0.9,  0.2
    elseif mood == "Critical"   then mr, mg, mb = 1.0, 0.35, 0.35 end
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

function BastionLogTabPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
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

function BastionLogTabPanel:doResize(w, h)
    self:setWidth(w)
    self:setHeight(h)
    if self.listbox then
        self.listbox:setWidth(w - 8)
        self.listbox:setHeight(h - 8)
    end
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
    local log = rec.settlementLog
    for i = #log, 1, -1 do
        local entry   = log[i]
        local display = "[Day " .. (entry.day or 0) .. "]  " .. (entry.text or "")
        self.listbox:addItem(display, entry)
    end
    if self.listbox.vscroll then
        self.listbox.vscroll:setCurrentValue(self.listbox.vscroll.max or 0)
    end
end

function BastionLogTabPanel.drawItem(listbox, y, item, alt)
    if not item then return end
    local entry = item.item
    if not entry then return end
    local col = LOG_COLORS[entry.logType or "standard"] or LOG_COLORS.standard
    if alt then
        listbox:drawRect(0, y, listbox:getWidth(), listbox.itemheight, 0.04, 0.5, 0.4, 0.6)
    end
    listbox:drawText(item.text or "", 6, y + 2,
                     col[1], col[2], col[3], col[4] or 1.0, UIFont.Small)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings Tab
-- ─────────────────────────────────────────────────────────────────────────────

BastionSettingsPanel = ISPanel:derive("BastionSettingsPanel")

function BastionSettingsPanel:new(x, y, w, h, player)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor   = { r=0, g=0, b=0, a=0 }
    o.borderColor       = { r=0, g=0, b=0, a=0 }
    o.player            = player
    o.noiseBtns         = {}
    o.disbandBtn        = nil
    o.disbandConfirmBtn = nil
    return o
end

function BastionSettingsPanel:createChildren()
    local dx     = 14
    local btnW   = 90
    local gap    = 8
    local noiseY = 36

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

    local disbandY = 136

    self.disbandBtn = ISButton:new(dx, disbandY, 152, 24,
                                   "Disband Bastion",
                                   self, BastionSettingsPanel.onDisbandFirst)
    self.disbandBtn.borderColor     = { r=0.6, g=0.2, b=0.2, a=0.8 }
    self.disbandBtn.backgroundColor = { r=0.25, g=0.08, b=0.08, a=0.8 }
    self.disbandBtn:initialise()
    self:addChild(self.disbandBtn)

    self.disbandConfirmBtn = ISButton:new(dx + 164, disbandY, 160, 24,
                                          "Confirm Disband",
                                          self, BastionSettingsPanel.onDisbandConfirm)
    self.disbandConfirmBtn.borderColor     = { r=0.9, g=0.2, b=0.2, a=1.0 }
    self.disbandConfirmBtn.backgroundColor = { r=0.45, g=0.05, b=0.05, a=0.9 }
    self.disbandConfirmBtn:initialise()
    self.disbandConfirmBtn:setVisible(false)
    self:addChild(self.disbandConfirmBtn)
end

function BastionSettingsPanel.makeNoiseHandler(level)
    return function(target)
        if not target.player then return end
        sendClientCommand(target.player, Bastion.MOD_KEY, "SetNoiseBudget", { level = level })
        if target.disbandConfirmBtn then target.disbandConfirmBtn:setVisible(false) end
        if target.disbandBtn        then target.disbandBtn:setVisible(true)         end
    end
end

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
    if self.disbandBtn        then self.disbandBtn:setVisible(true)  end
    if self.disbandConfirmBtn then self.disbandConfirmBtn:setVisible(false) end
end

function BastionSettingsPanel:render()
    ISPanel.render(self)

    self:drawText("Noise Budget", 14, 14, 0.75, 0.65, 1.0, 1.0, UIFont.Small)

    local rec     = getModRec(self.player)
    local current = rec and rec.noiseBudgetLevel or "Normal"
    for _, btn in ipairs(self.noiseBtns) do
        if btn.noiseLevelTag == current then
            btn.backgroundColor = { r=0.35, g=0.22, b=0.55, a=0.95 }
        else
            btn.backgroundColor = { r=0.15, g=0.10, b=0.20, a=0.80 }
        end
    end

    -- Disband section — two lines so text stays within window width
    self:drawText("Disband Settlement", 14, 80, 0.65, 0.55, 0.55, 1.0, UIFont.Small)
    self:drawText("This is permanent. All settlers will disperse",
                  14, 98, 0.45, 0.45, 0.45, 0.9, UIFont.Small)
    self:drawText("and the settlement record will be erased.",
                  14, 113, 0.45, 0.45, 0.45, 0.9, UIFont.Small)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Window
-- ─────────────────────────────────────────────────────────────────────────────

BastionWindow = ISPanel:derive("BastionWindow")

function BastionWindow:new(x, y, player)
    local o = ISPanel.new(self, x, y, DEF_W, DEF_H)
    o.backgroundColor = { r=0.05, g=0.04, b=0.08, a=0.92 }
    o.borderColor     = { r=0.5,  g=0.4,  b=0.7,  a=0.90 }
    o.player          = player
    -- Window size (mutable for resize)
    o.winW            = DEF_W
    o.winH            = DEF_H
    -- Drag state
    o.dragging        = false
    o.dragMouseX      = 0
    o.dragMouseY      = 0
    o.dragWinX        = 0
    o.dragWinY        = 0
    -- Resize state
    o.resizing        = false
    o.resizeOriginMX  = 0
    o.resizeOriginMY  = 0
    o.resizeOriginW   = 0
    o.resizeOriginH   = 0
    -- Refresh
    o.refreshCounter  = 0
    -- Tab state
    o.currentTab      = "Overview"
    -- Child references
    o.closeBtn        = nil
    o.overviewPanel   = nil
    o.settlersPanel   = nil
    o.logPanel        = nil
    o.settingsPanel   = nil
    return o
end

function BastionWindow:createChildren()
    local contH = self.winH - CONT_Y

    -- Close button
    local closeBtn = ISButton:new(self.winW - 26, 4, 22, 22, "x", self, BastionWindow.onClose)
    closeBtn.borderColor     = { r=0.5, g=0.3, b=0.3, a=0.8 }
    closeBtn.backgroundColor = { r=0.2, g=0.1, b=0.1, a=0.8 }
    closeBtn:initialise()
    self:addChild(closeBtn)
    self.closeBtn = closeBtn

    -- Content panels
    local ovPanel = BastionOverviewPanel:new(0, CONT_Y, self.winW, contH)
    local stPanel = BastionSettlersPanel:new(0, CONT_Y, self.winW, contH)
    local lgPanel = BastionLogTabPanel:new(0, CONT_Y, self.winW, contH)
    local sPanel  = BastionSettingsPanel:new(0, CONT_Y, self.winW, contH, self.player)

    ovPanel:initialise()
    stPanel:initialise()
    lgPanel:initialise()
    sPanel:initialise()

    self:addChild(ovPanel)
    self:addChild(stPanel)
    self:addChild(lgPanel)
    self:addChild(sPanel)

    stPanel:setVisible(false)
    lgPanel:setVisible(false)
    sPanel:setVisible(false)

    self.overviewPanel = ovPanel
    self.settlersPanel = stPanel
    self.logPanel      = lgPanel
    self.settingsPanel = sPanel
end

-- ── Layout update (called after resize) ──────────────────────────────────────

function BastionWindow:updateLayout()
    local contH = self.winH - CONT_Y
    self:setWidth(self.winW)
    self:setHeight(self.winH)

    if self.closeBtn then
        self.closeBtn:setX(self.winW - 26)
    end
    if self.overviewPanel then
        self.overviewPanel:setWidth(self.winW)
        self.overviewPanel:setHeight(contH)
    end
    if self.settlersPanel then self.settlersPanel:doResize(self.winW, contH) end
    if self.logPanel      then self.logPanel:doResize(self.winW, contH)      end
    if self.settingsPanel then
        self.settingsPanel:setWidth(self.winW)
        self.settingsPanel:setHeight(contH)
    end
end

-- ── Tab selection ─────────────────────────────────────────────────────────────

function BastionWindow:selectTab(name)
    self.currentTab = name
    if self.overviewPanel then self.overviewPanel:setVisible(name == "Overview") end
    if self.settlersPanel then self.settlersPanel:setVisible(name == "Settlers") end
    if self.logPanel      then self.logPanel:setVisible(name == "Log")           end
    if self.settingsPanel then self.settingsPanel:setVisible(name == "Settings") end
    self:populate()
end

-- ── Data refresh ──────────────────────────────────────────────────────────────

function BastionWindow:populate()
    local p = self.player
    if self.overviewPanel then self.overviewPanel:populate(p) end
    if self.settlersPanel then self.settlersPanel:populate(p) end
    if self.logPanel      then self.logPanel:populate(p)      end
    if self.settingsPanel then self.settingsPanel:populate(p) end
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

function BastionWindow:prerender()
    ISPanel.prerender(self)

    local tabW = math.floor(self.winW / #TABS)

    -- Title bar
    self:drawRect(0, 0, self.winW, TITLE_H, 0.95, 0.10, 0.08, 0.15)
    self:drawText("Bastion", 10, 7, 0.8, 0.65, 1.0, 1.0, UIFont.Medium)

    -- Tab bar background
    self:drawRect(0, TITLE_H, self.winW, TAB_H, 0.95, 0.07, 0.06, 0.20)

    -- Tab buttons
    for i, name in ipairs(TABS) do
        local tx      = (i - 1) * tabW
        local isActive = (self.currentTab == name)
        if isActive then
            self:drawRect(tx, TITLE_H, tabW, TAB_H, 0.9, 0.22, 0.16, 0.38)
            -- Top highlight line on active tab
            self:drawRect(tx, TITLE_H, tabW, 2, 0.9, 0.6, 0.9, 0.8)
        else
            self:drawRect(tx, TITLE_H, tabW, TAB_H, 0.9, 0.10, 0.08, 0.18)
        end
        -- Separator between tabs
        if i > 1 then
            self:drawRect(tx, TITLE_H + 4, 1, TAB_H - 8, 0.8, 0.4, 0.3, 0.5)
        end
        local tr = isActive and 1.0 or 0.70
        local tg = isActive and 0.9 or 0.65
        local tb = isActive and 1.0 or 0.85
        self:drawText(name, tx + 8, TITLE_H + 8, tr, tg, tb, 1.0, UIFont.Small)
    end

    -- Hairline below tab bar
    self:drawRect(0, CONT_Y - 1, self.winW, 1, 0.9, 0.4, 0.3, 0.4)

    -- Resize grip (bottom-right corner)
    local gx = self.winW - GRIP
    local gy = self.winH - GRIP
    self:drawRect(gx,     gy,     GRIP, 1,    0.55, 0.45, 0.7, 0.6)
    self:drawRect(gx,     gy + 4, GRIP, 1,    0.55, 0.45, 0.7, 0.6)
    self:drawRect(gx,     gy + 8, GRIP, 1,    0.55, 0.45, 0.7, 0.6)
    self:drawRect(gx + 4, gy,     1,    GRIP, 0.55, 0.45, 0.7, 0.6)
    self:drawRect(gx + 8, gy,     1,    GRIP, 0.55, 0.45, 0.7, 0.6)
end

-- ── Mouse handling ────────────────────────────────────────────────────────────

function BastionWindow:onMouseDown(x, y)
    -- Resize handle (bottom-right corner)
    if x >= self.winW - GRIP and y >= self.winH - GRIP then
        self.resizing       = true
        self.resizeOriginMX = getMouseX()
        self.resizeOriginMY = getMouseY()
        self.resizeOriginW  = self.winW
        self.resizeOriginH  = self.winH
        return true
    end

    -- Tab bar
    if y >= TITLE_H and y < CONT_Y then
        local tabW = math.floor(self.winW / #TABS)
        local idx  = math.floor(x / tabW) + 1
        if idx >= 1 and idx <= #TABS then
            self:selectTab(TABS[idx])
        end
        return true
    end

    -- Title bar drag
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
    self.resizing = false
    return true
end

function BastionWindow:update()
    ISPanel.update(self)

    if self.resizing then
        if not Mouse.isButtonDown(Mouse.LEFT) then
            self.resizing = false
        else
            local newW = math.max(MIN_W, self.resizeOriginW + (getMouseX() - self.resizeOriginMX))
            local newH = math.max(MIN_H, self.resizeOriginH + (getMouseY() - self.resizeOriginMY))
            if newW ~= self.winW or newH ~= self.winH then
                self.winW = newW
                self.winH = newH
                self:updateLayout()
            end
        end
    elseif self.dragging then
        if not Mouse.isButtonDown(Mouse.LEFT) then
            self.dragging = false
        else
            self:setX(self.dragWinX + (getMouseX() - self.dragMouseX))
            self:setY(self.dragWinY + (getMouseY() - self.dragMouseY))
        end
    end

    self.refreshCounter = self.refreshCounter + 1
    if self.refreshCounter >= 150 then
        self.refreshCounter = 0
        self:populate()
    end
end

-- ── Close button callback ─────────────────────────────────────────────────────

function BastionWindow:onClose()
    BastionWindow.close()
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
    local x  = math.floor((sw - DEF_W) / 2)
    local y  = math.floor((sh - DEF_H) / 2)

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
