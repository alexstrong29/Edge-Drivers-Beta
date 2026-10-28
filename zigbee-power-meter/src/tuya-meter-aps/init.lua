-- Copyright 2021 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- DP´s of Fingerbot plus -------
-- DP ---------Name---------Type---------Values ---------------------------CMD
-- 101 (0x65): MODE         Enum(04)     Click(0), Switch(1),Program(2)    0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 102 (0x66): Down MODE    Number(02)   50-100                            0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 103 (0x67): Sustain Time Number(02)   0s-10s                            0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 104 (0x68): Reverse      Enum(04)     Up-on(1)/Up-off(0)                0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 105 (0x69): Battery      Number(02)   0-100                             0x05 (PASIVE REPORT INTERVAL) or 0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 106 (0x6A): Up MODE      Number(02)   0-50                              0x06 (PROACTIVE REPORT VALUES CHANGES)
-- 107 (0x6B): On/off       Bool(1)      On-Off                            0x06 DP NO USADO, SE USA CLUSTER 0006 ATTRIBUTE 0000

local constants = require "st.zigbee.constants"
--local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local messages = require "st.zigbee.messages"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local zdo_messages = require "st.zigbee.zdo"

local ZigbeeZcl = require "st.zigbee.zcl"
local ZigbeeConstants = require "st.zigbee.constants"
local data_types = require "st.zigbee.data_types"
--local Messages = require "st.zigbee.messages"
local generic_body = require "st.zigbee.generic_body"
--local utils = require"st.utils"
local tariff = require "tuya-meter-aps.tariff"

local TUYA_CLUSTER = 0xEF00
local DP_TYPE_RAW = "\x00"
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"
local SeqNum = 0

local TUYA_METER_FINGERPRINTS = {
    { mfr = "_TZE284_81yrt3lo", model = "TS0601" }
}

local is_tuya_meter = function(opts, driver, device)
    for _, fingerprint in ipairs(TUYA_METER_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            return true
        end
    end
    return false
end

-- Send command to cluster EF00
local function SendCommand(device, DpId, Type, Value)
  local addrh = messages.AddressHeader(
    ZigbeeConstants.HUB.ADDR, 					-- Source Address
    ZigbeeConstants.HUB.ENDPOINT,				-- Source Endpoint
    device:get_short_address(),			-- Destination Address
    device:get_endpoint(TUYA_CLUSTER),	-- Destination Address
    ZigbeeConstants.HA_PROFILE_ID,				-- Profile Id
    TUYA_CLUSTER						-- Cluster Id
  )
  -- iquix use command 0x00. I use command 0x04 according tuya documment EF00
  --https://developer.tuya.com/en/docs/iot/tuya-zigbee-module-uart-communication-protocol?id=K9ear5khsqoty#dataFormat
  local zclh = ZigbeeZcl.ZclHeader({cmd = data_types.ZCLCommandId(0x04)})
  zclh.frame_ctrl:set_cluster_specific()	-- sets this frame control field to be cluster specific
  -- Make a payload body
  SeqNum = (SeqNum + 1) % 65536
  local strSeqNum = string.pack(">I2", SeqNum)  -- Pack the Sequence number to 2 bytes unsigned integer type with big endian.
  local LenOfValue = string.pack(">I2",string.len(Value))  -- Pack length of Value to 2 bytes unsigned integer type wiht big endian.
  local PayloadBody = generic_body.GenericBody(strSeqNum .. DpId .. Type .. LenOfValue .. Value)
  local MsgBody = ZigbeeZcl.ZclMessageBody({zcl_header = zclh, zcl_body = PayloadBody})
  local TxMsg = messages.ZigbeeMessageTx({address_header = addrh, body = MsgBody})
  device:send(TxMsg)
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
    end
  end
end

local function device_added(self, device)
  local _, cap_status = device:get_latest_state("main2", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME)
  if cap_status == nil then
    device:emit_event(capabilities.energyMeter.energy({value = 0, unit = "kWh" }))
  end
  local _, cap_status = device:get_latest_state("main", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME)
  if cap_status == nil then
    device.profile.components["main"]:emit_event(capabilities.energyMeter.energy({value = 0, unit = "kWh" }))
  end
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, 0xEF00, self.environment_info.hub_zigbee_eui))

  -- Read binding table
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )
  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({
                                                   zdo_body = binding_table_req
                                                 })
  local binding_table_cmd = messages.ZigbeeMessageTx({
                                                     address_header = addr_header,
                                                     body = message_body
                                                   })
  device:send(binding_table_cmd)

  --device:configure()
end
local function tuya_handler_direction_A(self, device, zb_rx)
   local direction = string.unpack(">I1", zb_rx.body.zcl_body.body_bytes, 7)  -- Should be 1-byte: 0=Forward, 1=Reverse
    -- Clamp A (outbuilding) only ever imports, so no contactSensor in the profile; just log the direction
    if device.preferences.logDebugPrint == true then
      print("<<<<<<<<<<<<<<< direction A", direction)
    end
end

-- Summary shows Clamp B (grid) power signed by direction, sign set by the powerSign preference
local function emit_grid_summary(device)
  local power = device:get_field("power_B")
  if power == nil then return end
  local exporting = (device:get_field("direction_B") or 0) ~= 0
  if power ~= 0 and (exporting == (device.preferences.powerSign ~= "1")) then
    power = -power
  end
  device.profile.components["summary"]:emit_event(capabilities.powerMeter.power({value = power, unit = "W" }))
end

local function tuya_handler_direction_B(self, device, zb_rx)
    local direction = string.unpack(">I1", zb_rx.body.zcl_body.body_bytes, 7)
    if direction == 0 then
        device.profile.components["main"]:emit_event(capabilities.contactSensor.contact.closed())  -- Forward
     else
        device.profile.components["main"]:emit_event(capabilities.contactSensor.contact.open())  -- Reverse
    end
    device:set_field("direction_B", direction)
    emit_grid_summary(device)
end

-- Night / day grid import: kWh imported from the grid in the current (or last) night and day period.
-- Each bucket resets to 0 when its period starts, so night shows last night's total during the day.
-- Grid export uses one flat rate and its tile shows today's export, reset at local midnight.
local TARIFF_KINDS = { "night", "day", "export" }
local TARIFF_COMPONENTS = { night = "gridNight", day = "gridDay", export = "gridExport" }
local TARIFF_RATE_PREFS = { night = "nightRate", day = "dayRate", export = "exportRate" } -- pence per kWh
local tariffCost = capabilities["dreamspace09858.tariffCost"]
local tariffEarnings = capabilities["dreamspace09858.tariffEarnings"]

local function tariff_settings(device)
  local start_min = tariff.parse_hhmm(device.preferences.nightStart) or 30  -- 00:30
  local end_min = tariff.parse_hhmm(device.preferences.nightEnd) or 330     -- 05:30
  return device.preferences.tariffTimeZone or "uk", start_min, end_min
end

-- Calendar totals per rate: "tariff_totals" = { day/month/year = { key = "2026-10-28",
--   cur = { night = {kwh, pence}, day = {...}, export = {...} }, last = same as cur or nil } }
-- Cost is added at the price in force when the energy is used, so a price change only affects later usage.
local tariffTotals = capabilities["dreamspace09858.tariffTotals"]
local TOTAL_ATTRIBUTES = {
  {"day", "cur", "today"}, {"day", "last", "yesterday"},
  {"month", "cur", "thisMonth"}, {"month", "last", "lastMonth"},
  {"year", "cur", "thisYear"}, {"year", "last", "lastYear"},
}

local function empty_bucket() return { night = {0, 0}, day = {0, 0}, export = {0, 0} } end

local function format_total(entry)
  if entry == nil then return "-" end
  return string.format("%.2f kWh  ·  £%.2f", entry[1], entry[2] / 100)
end

local function emit_tariff(device, kind)
  local component = device.profile.components[TARIFF_COMPONENTS[kind]]
  if component == nil then return end -- profile without the tariff components
  local kwh = device:get_field("tariff_" .. kind .. "_kwh") or 0
  local pence = device:get_field("tariff_" .. kind .. "_pence") or 0
  component:emit_event(capabilities.energyMeter.energy({value = math.floor(kwh * 100 + 0.5) / 100, unit = "kWh" }))
  local money = kind == "export" and tariffEarnings.earnings or tariffCost.cost
  component:emit_event(money({value = math.floor(pence + 0.5) / 100, unit = "£" }))
  local totals = device:get_field("tariff_totals") or {}
  for _, a in ipairs(TOTAL_ATTRIBUTES) do
    local scope = totals[a[1]]
    component:emit_event(tariffTotals[a[3]]({value = format_total(scope and scope[a[2]] and scope[a[2]][kind])}))
  end
end

local function emit_all_tariffs(device)
  for _, kind in ipairs(TARIFF_KINDS) do emit_tariff(device, kind) end
end

-- Moves this day / month / year into "last" when the local calendar rolls over; true if anything changed
local function roll_totals(totals, keys)
  local changed = false
  for scope, key in pairs(keys) do
    local t = totals[scope]
    if t == nil then
      totals[scope] = { key = key, cur = empty_bucket() }
      changed = true
    elseif t.key ~= key then
      print(string.format("<<< Tariff totals: %s %s finished, now %s", scope, t.key, key))
      totals[scope] = { key = key, cur = empty_bucket(), last = t.cur }
      changed = true
    else
      -- totals saved before a rate was added
      for _, kind in ipairs(TARIFF_KINDS) do
        if t.cur[kind] == nil then t.cur[kind] = {0, 0}; changed = true end
      end
    end
  end
  return changed
end

local function reset_tile(device, kind)
  device:set_field("tariff_" .. kind .. "_kwh", 0, {persist = true})
  device:set_field("tariff_" .. kind .. "_pence", 0, {persist = true})
end

-- Starts a new bucket when the period or calendar day changes; returns the current import period ("night" or "day")
local function update_tariff_period(device)
  local zone, start_min, end_min = tariff_settings(device)
  local now = os.time()
  local kind, id, mins = tariff.period(now, zone, start_min, end_min)
  local keys = tariff.local_keys(now, zone)
  local totals = device:get_field("tariff_totals") or {}
  local rolled = roll_totals(totals, keys)
  if rolled then device:set_field("tariff_totals", totals, {persist = true}) end
  if device:get_field("tariff_period_id") ~= id then
    print(string.format("<<< Tariff period now %s (local %02d:%02d, zone %s)", id, mins // 60, mins % 60, zone))
    device:set_field("tariff_period_id", id, {persist = true})
    reset_tile(device, kind)
    emit_tariff(device, kind)
  elseif device.preferences.logDebugPrint == true then
    print(string.format("<<< Tariff period %s (local %02d:%02d, zone %s)", id, mins // 60, mins % 60, zone))
  end
  if device:get_field("tariff_export_period_id") ~= keys.day then
    device:set_field("tariff_export_period_id", keys.day, {persist = true})
    reset_tile(device, "export")
    emit_tariff(device, "export")
  end
  if rolled then emit_all_tariffs(device) end
  return kind
end

-- direction: "import" (Clamp B forward energy) or "export" (Clamp B reverse energy);
-- counter: that energy counter in kWh, only ever increases
local function add_grid_energy(device, direction, counter)
  local kind = update_tariff_period(device)
  if direction == "export" then kind = "export" end
  local last_key = "tariff_last_" .. direction
  local last = device:get_field(last_key)
  if last ~= nil and counter >= last then
    local kwh = counter - last
    local pence = kwh * (tonumber(device.preferences[TARIFF_RATE_PREFS[kind]]) or 0)
    local prefix = "tariff_" .. kind
    device:set_field(prefix .. "_kwh", (device:get_field(prefix .. "_kwh") or 0) + kwh, {persist = true})
    device:set_field(prefix .. "_pence", (device:get_field(prefix .. "_pence") or 0) + pence, {persist = true})
    local totals = device:get_field("tariff_totals")
    for _, scope in ipairs({"day", "month", "year"}) do
      local entry = totals[scope].cur[kind]
      entry[1], entry[2] = entry[1] + kwh, entry[2] + pence
    end
    device:set_field("tariff_totals", totals, {persist = true})
  end
  -- first reading, or the counter went backwards (meter reset): just resync
  device:set_field(last_key, counter, {persist = true})
  emit_tariff(device, kind)
end

local function start_tariff_timer(device)
  local timer = device:get_field("tariff_timer")
  if timer then device.thread:cancel_timer(timer) end
  update_tariff_period(device)
  emit_all_tariffs(device)
  -- check every minute so buckets reset on time even if no energy report arrives
  device:set_field("tariff_timer", device.thread:call_on_schedule(60, function() update_tariff_period(device) end, "tariff_timer"))
end

local function tuya_handler_energy_fwd_A(self, device, zb_rx)
 local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
  device.profile.components["main3"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
end
local function tuya_handler_energy_fwd_B(self, device, zb_rx)
 local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
  device.profile.components["main4"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
end
local function tuya_handler_energy_rev_A(self, device, zb_rx)
 local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
  device.profile.components["main5"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
  add_grid_energy(device, "import", energy)
end
local function tuya_handler_energy_rev_B(self, device, zb_rx)
 local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
  device.profile.components["main6"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
  add_grid_energy(device, "export", energy)
end

local function tuya_handler_power_total(self, device, zb_rx)
 -- DP 115: Total Power (A+B), signed, 0.1W
 local power = string.unpack(">i4", zb_rx.body.zcl_body.body_bytes, 7)/10
  print("<<<<<<<<<<<<<<< tuya_handler_power", power)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< power-offset", power)
  end
  -- not emitted: the summary shows signed grid power instead (see emit_grid_summary)
end
local function tuya_handler_energy_A(self, device, zb_rx)
  -- DP  (0x01) Energy consumption byte 7, len 4 and divided by 100 for real value in kwh
  local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
  device.profile.components["main2"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
  
end
local function tuya_handler_power_A(self, device, zb_rx)
 local power = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/10
  print("<<<<<<<<<<<<<<< tuya_handler_power", power)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< power-offset", power)
  end
  device.profile.components["main2"]:emit_event(capabilities.powerMeter.power({value = power, unit = "W" }))
end

local function tuya_handler_current_A(self, device, zb_rx)
  -- DP  (0x01) Energy consumption byte 7, len 4 and divided by 100 for real value in kwh
  local current = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_current", current)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< current-offset", current)
  end
  device.profile.components["main2"]:emit_event(capabilities.currentMeasurement.current({value = current, unit = "A" }))
end
local function tuya_handler_energy_B(self, device, zb_rx)
  -- DP  (0x01) Energy consumption byte 7, len 4 and divided by 100 for real value in kwh
  local energy = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy-offset", energy)
  end
 
  device.profile.components["main"]:emit_event(capabilities.energyMeter.energy({value = energy, unit = "kWh" }))
end
local function tuya_handler_power_B(self, device, zb_rx)
 local power = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/10
  print("<<<<<<<<<<<<<<< tuya_handler_power", power)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< power-offset", power)
  end
  device.profile.components["main"]:emit_event(capabilities.powerMeter.power({value = power, unit = "W" }))
  device:set_field("power_B", power)
  emit_grid_summary(device)
end

local function tuya_handler_current_B(self, device, zb_rx)
  -- DP  (0x01) Energy consumption byte 7, len 4 and divided by 100 for real value in kwh
  local current = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/100
  print("<<<<<<<<<<<<<<< tuya_handler_current", current)

  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< current-offset", current)
  end
  device.profile.components["main"]:emit_event(capabilities.currentMeasurement.current({value = current, unit = "A" }))
end
local function tuya_handler_power_direction(self, device, zb_rx)
  -- DP 102 (0x66) GenericBody byte 7 is value current direction (0 or 1)
  local power_direction = zb_rx.body.zcl_body.body_bytes:byte(7)
  if power_direction == 1 then -- power produced
    if device.preferences.powerSign == "1" then --"Export->Positive and Import->Negative"
      power_direction = 1 --power export, positive power
    else
      power_direction = -1  -- power consumed, negative power
    end
  else -- power consumed, power_direction == 0
    if device.preferences.powerSign == "1" then --"Export->Negative and Import->Positive"
      power_direction = -1 -- power export, negative power
    else
      power_direction = 1 -- power consumed, positive power
    end
  end
  print("<<< Power Direction = ", power_direction)
  device:set_field("power_direction", power_direction)
end



local function tuya_handler_voltage(self, device, zb_rx)
  -- DP  (0x71) Voltage -- byte 7, len 4 and divided by 100 for real value in kwh
  local voltage = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7)/10
  print("<<<<<<<<<<<<<<< tuya_handler_energy", voltage)


  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< voltage-offset", voltage)
  end
  device.profile.components["main2"]:emit_event(capabilities.voltageMeasurement.voltage({value = voltage, unit = "V" }))
end


local function tuya_handler_produced_energy(self, device, zb_rx)
  -- DP 2 (0x02) energy_produced, byte 7, len 4 and divided by 100 for real value in kwh

  local energy_produced = string.unpack(">I4", zb_rx.body.zcl_body.body_bytes, 7) / 100
  print("<<<<<<<<<<<<<<< tuya_handler_energy", energy_produced)
  local offset = device:get_field("energy_offset_produced") or 0
  if energy_produced < offset then
    --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
    offset = 0
    device:set_field("energy_offset_produced", offset, {persist = true})
  end
  energy_produced = energy_produced - offset
  if device.preferences.logDebugPrint == true then
    print("<<<<<<<<<<<<<<< energy_produced-offset=", energy_produced)
  end
  device:emit_event(capabilities.energyMeter.energy({value = energy_produced, unit = "kWh" }))
end

-- Tuya report handler
local function tuya_handler(self, device, zb_rx)
  print("<<<< Tuya handler >>>>")
local dp_table = {
    -- Core Power Measurements
    [0x73] = tuya_handler_power_total,    -- DP 115: Total Power (A+B), signed, 0.1W
    [0x65] = tuya_handler_power_A,        -- DP 101: Power A, unsigned, 0.1W
    [0x69] = tuya_handler_power_B,        -- DP 105: Power B, unsigned, 0.1W
    
    -- Power Direction
    [0x66] = tuya_handler_direction_A,    -- DP 102: Direction A (0=Forward, 1=Reverse)
    [0x68] = tuya_handler_direction_B,    -- DP 104: Direction B (0=Forward, 1=Reverse) ⚠️ MISSING
    
    -- Energy Measurements (Forward/Reverse)
    [0x6A] = tuya_handler_energy_fwd_A,   -- DP 106: Forward Energy A, 0.01kWh ⚠️ MISSING
    [0x6B] = tuya_handler_energy_rev_A,   -- DP 107: Reverse Energy A, 0.01kWh ⚠️ MISSING  
    [0x6C] = tuya_handler_energy_fwd_B,   -- DP 108: Forward Energy B, 0.01kWh ⚠️ MISSING
    [0x6D] = tuya_handler_energy_rev_B,   -- DP 109: Reverse Energy B, 0.01kWh ⚠️ MISSING
    
    -- Power Factor
    -- [0x6E] = tuya_handler_power_factor_A, -- DP 110: Power Factor A, x100 ⚠️ MISSING
    -- [0x79] = tuya_handler_power_factor_B, -- DP 121: Power Factor B, x100 ⚠️ MISSING
    
    -- Basic Electrical Measurements  
    -- [0x6F] = tuya_handler_frequency,      -- DP 111: AC Frequency, x100
    [0x70] = tuya_handler_voltage,        -- DP 112: Voltage A, x100
    [0x71] = tuya_handler_current_A,      -- DP 113: Current A, x100
    [0x72] = tuya_handler_current_B,      -- DP 114: Current B, x100
}

  -- cluster: 0xEF00 in this device:
  -- ZCLCommandId: 0x02 >, GenericBody: 00 11 66 04 00 01 00 > >
  -- dp in this device 0x66 and byte 7 is power direction 00 = consumed, 001 = produced

  -- ZCLCommandId: 0x02 >, GenericBody:  00 CB 06 00 00 08 09 28 00 00 BE 00 00 1D > >
  -- dp 0x06, raw type. byte 12,13 14 is power raw value (1D = 29w)
  -- Positive power = exported or produced power
  -- negative power = imported or Consumed power

  -- DP 06 (0x06) GenericBody byte 7, len 2 byte for voltage value / 10
  -- DP 06 (0x06) GenericBody byte 9, len 3 byte for current value / 1000

  -- ZCLCommandId: 0x02 >, GenericBody: 00 DE 01 02 00 04 00 00 00 04 > >
  -- dp 0x01, integer type. byte 10, len 4, is energy consumed /100 in kwh, 08 = 40wh

  -- ZCLCommandId: 0x02 >, GenericBody: 00 DE 02 02 00 04 00 00 00 08 > >
  -- dp 0x02, integer type. byte 10, len 4 is energy produced /100 in kwh, 08 = 80wh

  -- ZCLCommandId: 0x02 >, GenericBody: 00 EE 65 02 00 04 00 00 00 1D > >
  -- dp 0x65 and byte 7, len 4 is power value = value (1D = 29w)
  -- same value of dp 0x06 in integer type (0x02)
  
  local dp = zb_rx.body.zcl_body.body_bytes:byte(3)
  local type = zb_rx.body.zcl_body.body_bytes:byte(4)
  local value_len = zb_rx.body.zcl_body.body_bytes:byte(6)
  local body_len = zb_rx.body_length.value
  if device.preferences.logDebugPrint == true then
    print("<<< dp =",dp)
    print("<<< type =", type)
    print("<<< dp value len =", value_len)
    print("<<< body len =", body_len)
  end

  local dp_handler = dp_table[dp]
  if dp_handler then
    dp_handler(self, device, zb_rx)
  end

end

-- Reset energy values
local function resetEnergyMeter_handler(driver, device, command)
  local _,last_reading = device:get_latest_state(command.component, capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME, 0, {value = 0, unit = "kWh"})
  for kind, component in pairs(TARIFF_COMPONENTS) do
    if command.component == component then
      reset_tile(device, kind)
      emit_tariff(device, kind)
      return
    end
  end
  if command.component == "main2" then
    if last_reading.value ~= 0 then
      local offset = device:get_field("energy_offset_produced") or 0
      device:set_field("energy_offset_produced", last_reading.value+offset, {persist = true})
    end
  else
    if last_reading.value ~= 0 then
      local offset = device:get_field("energy_offset_energyConsumption") or 0
      device:set_field("energy_offset_energyConsumption", last_reading.value+offset, {persist = true})
    end
  end
  device:emit_component_event({id = command.component}, capabilities.energyMeter.energy({value = 0.0, unit = "kWh"}))
end

--- do_driverSwitched
local function do_driverSwitched(self, device) --23/12/23
  print("<<<< DriverSwitched >>>>")
   device.thread:call_with_delay(3, function(d)
     do_configure(self, device)
   end, "configure") 
 end

local function device_init(self, device)
  start_tariff_timer(device)
end

-- night start/end, time zone or prices may have changed
local function info_changed(self, device, event, args)
  update_tariff_period(device)
  emit_all_tariffs(device)
end

local tuya_meter = {
  NAME = "Tuya meter bidirectional",
  capability_handlers = {
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = resetEnergyMeter_handler,
    },
  },
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x02] = tuya_handler,
        --[0x06] = tuya_handler,
      }
    },
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    added = device_added,
    driverSwitched = do_driverSwitched,
    doConfigure = do_configure
  },
  can_handle = is_tuya_meter
}

return tuya_meter