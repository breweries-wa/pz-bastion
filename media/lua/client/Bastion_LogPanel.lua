-- ============================================================
-- Bastion_LogPanel.lua  (media/lua/client/)
-- DEPRECATED — replaced by the Log tab inside BastionWindow.
-- Kept as a no-op stub so any saved references don't error.
-- ============================================================
print("[Bastion] LogPanel stub loaded (replaced by BastionWindow Log tab)")

BastionLogPanel = BastionLogPanel or {}
function BastionLogPanel.open(player)   if BastionWindow then BastionWindow.open(player) end end
function BastionLogPanel.close()        if BastionWindow then BastionWindow.close()       end end
function BastionLogPanel.toggle(player) if BastionWindow then BastionWindow.toggle(player) end end
