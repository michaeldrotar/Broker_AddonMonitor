local addonName = ...

local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibQTip = LibStub("LibQTip-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local format = string.format

local FORMAT_NUMBER = "%.1f"
local FORMAT_GREEN = "|cff66dd66%s|r"
local FORMAT_GOLD = "|cffffd200%s|r"
local FORMAT_ORANGE = "|cffff5533%s|r"
local FORMAT_RED = "|cffdd6666%s|r"

local total_elapsed = 0
local isProfiling = GetCVar("scriptProfile") == "1"
local tooltip
local tooltipFont

local columns = {"name", "memory", "memorydiff"}
local sort = "memory"
if isProfiling then
  columns[#columns + 1] = "cpu"
  columns[#columns + 1] = "cpudiff"
  sort = "cpu"
end

local formatters
formatters = {
  name = function(value)
    return value
  end,
  memory = function(value)
    local suffix = format(FORMAT_GOLD, "KB")
    if math.abs(value) > 999 then
      value = value / 1024
      suffix = format(FORMAT_ORANGE, "MB")
    end
    return format("%.1f %s", value, suffix)
  end,
  memorydiff = function(value)
    if value < 0 then
      return format(FORMAT_GREEN, formatters.memory(value))
    elseif value > 0 then
      return format(FORMAT_RED, formatters.memory(value))
    end
  end,
  cpu = function(value)
    local suffix = format(FORMAT_GOLD, "ms")
    if math.abs(value) > 9999 then
      value = value / 1000
      suffix = format(FORMAT_ORANGE, "s")
    end
    return format("%.1f %s", value, suffix)
  end,
  cpudiff = function(value)
    if value < 0 then
      return format(FORMAT_GREEN, formatters.cpu(value))
    elseif value > 0 then
      return format(FORMAT_RED, formatters.cpu(value))
    end
  end,
}

local totals = {
  cpu = 0,
  cpudiff = 0,
  memory = 0,
  memorydiff = 0,
  framerate = 0,
  latency = 0,
  children = 0
}

local addons = {}
for i = 1, GetNumAddOns() do
  id, name = GetAddOnInfo(i)
  addons[i] = {
    id = id,
    name = name,
    cpu = 0,
    cpudiff = 0,
    memory = 0,
    memorydiff = 0,
    parent = nil,
    children = 0,
  }
end

for _, child in next, addons do
  for _, parent in next, addons do
    if child.id ~= parent.id and string.find(child.id, parent.id) == 1 then
      if parent.parent then
        parent.parent.children = parent.parent.children + parent.children
        parent.children = 0
        parent = parent.parent
      end
      child.parent = parent
      parent.children = parent.children + 1
      totals.children = totals.children + 1
      break
    end
  end
end

local broker
broker = LibDataBroker:NewDataObject(L["Addon Monitor"], {
  type = "data source",
  OnClick = function(anchor, button)
    if button == "LeftButton" then
      if IsControlKeyDown() then
        SetCVar("scriptProfile", isProfiling and "0" or "1")
        ReloadUI()
        return
      end

      local index
      for key, value in next, columns do
        if value == sort then
          index = key
          break
        end
      end
      if index == #columns then
        index = 0
      end
      sort = columns[index + 1]
      --broker.OnLeave(anchor)
      --m.broker.OnEnter(anchor)
      if tooltip then
        LibQTip:Release(tooltip)
        broker.OnEnter(anchor)
      else
        update()
      end
    end
  end,
  OnEnter = function(anchor)
    tooltip = LibQTip:Acquire(addonName.."Tooltip")
    tooltip:SmartAnchorTo(anchor);
    tooltip:SetAutoHideDelay(0.1, anchor);
    update()
    tooltip:Show()
    tooltip.OnRelease = function(self)
      tooltip = nil
    end
  end,
  OnLeave = function(anchor)
  end,
})

function sorter(a, b)
  local default = a.id < b.id
  a, b = a[sort], b[sort]
  if a == b or type(a) ~= "number" then
    return default
  end
  return a > b
end

local filename, height, flags
local font = CreateFont(addonName.."Font")
local totalsFont = CreateFont(addonName.."FontTotals")
local baseFont = CreateFont(addonName.."FontBase")
function update()
  if isProfiling then
    UpdateAddOnCPUUsage()
  end
  UpdateAddOnMemoryUsage()

  totals.cpu = 0
  totals.cpudiff = 0
  totals.memory = 0
  totals.memorydiff = 0

  for _, addon in next, addons do
    if not addon.parent then
      addon.lastcpu = addon.cpu
      addon.lastmemory = addon.memory
      addon.cpu = 0
      addon.memory = 0
    end
  end

  for _, addon in next, addons do
    cpu = isProfiling and GetAddOnCPUUsage(addon.id) or 0
    memory = GetAddOnMemoryUsage(addon.id) or 0

    if addon.parent then
      addon = addon.parent
    end

    addon.cpu = addon.cpu + cpu
    addon.memory = addon.memory + memory

    totals.cpu = totals.cpu + cpu
    totals.memory = totals.memory + memory
  end

  for _, addon in next, addons do
    if not addon.parent then
      addon.cpudiff = addon.cpu - addon.lastcpu
      addon.memorydiff = addon.memory - addon.lastmemory

      totals.cpudiff = totals.cpudiff + addon.cpudiff
      totals.memorydiff = totals.memorydiff + addon.memorydiff
    end
  end

  table.sort(addons, sorter);

  broker.text = formatters[sort](totals[sort]) or L["Addon Monitor"]

  local line
  if tooltip then
    if tooltip:GetLineCount() == 0 then
      filename, height, flags = tooltip:GetFont():GetFont()
      baseFont:SetFont(filename, height, flags)
      totalsFont:SetFont(filename, height * 1.1, flags)
      tooltip:SetColumnLayout(#columns, "LEFT", "RIGHT", "RIGHT", "RIGHT", "RIGHT", "RIGHT");
      for _, addon in next, addons do
        if not addon.parent then
          tooltip:AddLine("")
        end
      end
      tooltip:AddLine(format(L["%d addons"], #addons - totals.children)) -- totals
    end

    local highest, lowest, range, ratio
    if sort ~= "name" then
      highest = addons[1][sort]
      lowest = addons[#addons][sort]
      if lowest < 0 then
        lowest = 0
      end
      range = highest - lowest
    end

    local total = totals[sort]
    local value

    line = 0
    for _, addon in next, addons do
      if not addon.parent then
        line = line + 1
        value = addon[sort]

        font = CreateFont(addonName.."FontLine"..line)
        if sort == "name" then
          font:SetFont(filename, height, flags)
        else
          -- ratio = ((addon[sort] - lowest) / range)
          -- ratio = 1 + ((ratio * 0.7) - 0.1)
          ratio = (value - lowest) / range
          if ratio < 0 then
            ratio = 0
          end
          ratio = 0.7 + (0.8 * ratio)
          font:SetFont(filename, height * ratio, flags)
        end

        for i, column in next, columns do
          tooltip:SetCell(line, i, formatters[column](addon[column]) or "", font)
        end
      end
    end

    line = line + 1
    for i, column in next, columns do
      if totals[column] then
        tooltip:SetCell(line, i, formatters[column](totals[column]), totalsFont)
      end
    end
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(self, elapsed)
  total_elapsed = total_elapsed + elapsed
  if total_elapsed > 2.5 then
    total_elapsed = total_elapsed % 2.5
    update()
  end
end)
