-- ============================================================
-- Bastion_LogPanel.lua  (media/lua/client/)
-- Scrollable settlement log window.
-- Open via right-click → "Open Settlement Log", or call
-- BastionLogPanel.toggle(player).
-- ============================================================
print("[Bastion] LogPanel loading")

-- ── Constants ─────────────────────────────────────────────────────────────────

local PANEL_W   = 380
local PANEL_H   = 320
local TITLE_H   = 26
local LIST_H    = PANEL_H - TITLE_H - 10

-- Log-type colours  (r, g, b, a)
local LOG_COLORS = {
    standard  = { 0.85, 0.85, 0.85, 1.0 },
    warning   = { 1.0,  0.85, 0.3,  1.0 },
    critical  = { 1.0,  0.35, 0.35, 1.0 },
    arrival   = { 0.5,  1.0,  0.6,  1.0 },
    milestone = { 0.7,  0.6,  1.0,  1.0 },
}

-- ── Panel class ───────────────────────────────────────────────────────────────

BastionLogPanel = ISPanel:derive("BastionLogPanel")

function BastionLogPanel:new(x, y, player)
    local o = ISPanel.new(self, x, y, PANEL_W, PANEL_H)
    o.backgroundColor = { r=0.05, g=0.04, b=0.08, a=0.92 }
    o.borderColor     = { r=0.5,  g=0.4,  b=0.7,  a=0.9  }
    o.player          = player
    o.listbox         = nil
    return o
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function BastionLogPanel:createChildren()
    -- Title bar
    local titleLabel = ISLabel:new(8, 5, TITLE_H, "Settlement Log",
                                   0.8, 0.65, 1.0, 1.0, UIFont.Medium, true)
    titleLabel:initialise()
    self:addChild(titleLabel)

    -- Close button (top-right)
    local closeBtn = ISButton:new(PANEL_W - 26, 4, 22, 20, "✕", self,
                                  BastionLogPanel.onClose)
    closeBtn.borderColor     = { r=0.5, g=0.3, b=0.3, a=0.8 }
    closeBtn.backgroundColor = { r=0.2, g=0.1, b=0.1, a=0.8 }
    closeBtn:initialise()
    self:addChild(closeBtn)

    -- Scrolling list box
    local lb = ISScrollingListBox:new(4, TITLE_H + 4, PANEL_W - 8, LIST_H)
    lb:initialise()
    lb:instantiate()
    lb.itemheight         = 18
    lb.doDrawItem         = BastionLogPanel.drawLogItem
    lb.backgroundColor    = { r=0, g=0, b=0, a=0 }
    lb.borderColor        = { r=0.3, g=0.25, b=0.45, a=0.6 }
    self:addChild(lb)
    self.listbox = lb

    self:populate()
end

-- ── Populating the list ───────────────────────────────────────────────────────

function BastionLogPanel:populate()
    if not self.listbox then return end
    self.listbox:clear()

    local username = self.player and self.player:getUsername()
    if not username then return end

    local world = ModData.get(Bastion.DATA_KEY) or {}
    local rec   = world[username]
    if not rec or not rec.settlementLog then
        self.listbox:addItem("(no log entries yet)", { logType="standard", day=0, text="(no log entries yet)" })
        return
    end

    for _, entry in ipairs(rec.settlementLog) do
        local display = "[Day " .. (entry.day or 0) .. "]  " .. (entry.text or "")
        self.listbox:addItem(display, entry)
    end
end

-- ── Custom item draw callback ─────────────────────────────────────────────────
-- Called by ISScrollingListBox for each visible row.
-- `self` is the listbox; `y` is the top y in panel coords; `item` is the data.
function BastionLogPanel.drawLogItem(listbox, y, item, alt)
    if not item then return end

    local entry = item.item  -- ISScrollingListBox wraps data in item.item
    if not entry then return end

    local col = LOG_COLORS[entry.logType or "standard"] or LOG_COLORS.standard

    -- Alternating row tint for readability
    if alt then
        listbox:drawRect(0, y, listbox:getWidth(), listbox.itemheight,
                         0.04, 0.5, 0.4, 0.6)
    end

    listbox:drawText(item.text or "", 6, y + 2,
                     col[1], col[2], col[3], col[4], UIFont.Small)
end

-- ── Button handlers ───────────────────────────────────────────────────────────

function BastionLogPanel:onClose()
    -- ISButton passes its `target` as self, and we set target=panel,
    -- so self IS the panel here — remove it directly.
    self:removeFromUIManager()
    BastionLogPanel._instance = nil
end

-- ── Module API ────────────────────────────────────────────────────────────────

BastionLogPanel._instance = nil

function BastionLogPanel.open(player)
    if BastionLogPanel._instance then
        BastionLogPanel._instance:bringToTop()
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x  = math.floor((sw - PANEL_W) / 2)
    local y  = math.floor((sh - PANEL_H) / 2)

    local panel = BastionLogPanel:new(x, y, player)
    panel:initialise()
    panel:addToUIManager()
    BastionLogPanel._instance = panel
end

function BastionLogPanel.close()
    if BastionLogPanel._instance then
        BastionLogPanel._instance:removeFromUIManager()
        BastionLogPanel._instance = nil
    end
end

function BastionLogPanel.toggle(player)
    if BastionLogPanel._instance then
        BastionLogPanel.close()
    else
        BastionLogPanel.open(player)
    end
end

-- Note: PZ B42 does not expose an OnModDataTransmit event.
-- The log panel re-populates each time it is opened via toggle().

print("[Bastion] LogPanel done")
