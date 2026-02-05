-- Moes Star Ring Smart Knob Thermostat Edge Driver
-- Wall-mounted dial thermostat controller
-- Supports _TZE204_lpedvtvr

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"

local ThermostatMode = capabilities.thermostatMode
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local TemperatureMeasurement = capabilities.temperatureMeasurement
local Battery = capabilities.battery

-- Tuya cluster constants
local TUYA_CLUSTER = 0xEF00
local TUYA_SET_DATA = 0x00
local TUYA_REPORT_DATA = 0x01

-- Tuya DP (Data Point) constants
local DP_SYSTEM_MODE = 0x01
local DP_PRESET_MODE = 0x02
local DP_TEMPERATURE = 0x10
local DP_MIN_TEMP = 0x12
local DP_FACTORY_RESET = 0x1C
local DP_SENSOR_MODE = 0x20
local DP_MAX_TEMP = 0x22
local DP_CHILD_LOCK = 0x27
local DP_VALVE_STATE = 0x2F
local DP_DISPLAY_BRIGHTNESS = 0x30
local DP_SETPOINT = 0x32
local DP_TEMP_CALIBRATION = 0x65
local DP_EXTERNAL_TEMP = 0x6D
local DP_DEADZONE_TEMP = 0x6E
local DP_MAX_TEMP_LIMIT = 0x6F
local DP_MIN_TEMP_LIMIT = 0x70
local DP_ECO_TEMP = 0x71
local DP_SCREEN_TIME = 0x72
local DP_RGB_BACKLIGHT = 0x73
local DP_BATTERY = 0x23

local PRESET_MANUAL = 0
local PRESET_TEMP_MANUAL = 1
local PRESET_PROGRAM = 2
local PRESET_ECO = 3

local SENSOR_AIR = 0
local SENSOR_BOTH = 1
local SENSOR_FLOOR = 2

local SCREEN_OFF = 0
local SCREEN_SHORT = 1
local SCREEN_MEDIUM = 2
local SCREEN_LONG = 3

-- Helper functions
local function create_tuya_command(dp, data_type, data)
  local cmd_body = data_types.CharString("", false)
  cmd_body.value = string.char(dp) .. 
                   string.char(data_type) .. 
                   string.char(#data >> 8) .. 
                   string.char(#data & 0xFF) .. 
                   data
  return cmd_body
end

-- Tuya sequence number for commands
local tuya_seq_num = 0

local function send_tuya_command(device, dp, data_type, data)
  -- Increment sequence number
  tuya_seq_num = (tuya_seq_num + 1) % 65536
  
  -- Build Tuya payload: SeqNum (2 bytes) + DP + Type + Length + Data
  local seq_bytes = string.pack(">I2", tuya_seq_num)
  local payload = seq_bytes ..
                  string.char(dp) .. 
                  string.char(data_type) .. 
                  string.char(#data >> 8) .. 
                  string.char(#data & 0xFF) .. 
                  data
  
  device.log.info(string.format("Sending Tuya command - Seq: %d, DP: %d, Type: %d, Data length: %d", tuya_seq_num, dp, data_type, #data))
  
  -- Build address header
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(TUYA_CLUSTER),
    zb_const.HA_PROFILE_ID,
    TUYA_CLUSTER
  )
  
  -- Build ZCL header for cluster-specific command
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(TUYA_SET_DATA)
  })
  zclh.frame_ctrl:set_cluster_specific()
  
  -- Wrap payload in GenericBody (this is the key!)
  local payload_body = generic_body.GenericBody(payload)
  
  -- Build message body
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })
  
  -- Send the message
  device:send(messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  }))
end

-- Capability handlers
local function handle_thermostat_mode(driver, device, command)
  local mode = command.args.mode
  
  device.log.info("Setting thermostat mode to: " .. mode)
  
  if mode == "off" then
    send_tuya_command(device, DP_SYSTEM_MODE, 0x01, string.char(0))
  elseif mode == "heat" then
    send_tuya_command(device, DP_SYSTEM_MODE, 0x01, string.char(1))
    send_tuya_command(device, DP_PRESET_MODE, 0x04, string.char(PRESET_MANUAL))
  elseif mode == "auto" then
    send_tuya_command(device, DP_SYSTEM_MODE, 0x01, string.char(1))
    send_tuya_command(device, DP_PRESET_MODE, 0x04, string.char(PRESET_PROGRAM))
  else
    device.log.warn("Unsupported mode: " .. mode)
    return
  end
end

local function handle_heating_setpoint(driver, device, command)
  local setpoint_c = command.args.setpoint
  local setpoint_value = math.floor(setpoint_c * 10)
  
  device.log.info(string.format("Setting temperature to %.1f°C (raw value: %d)", setpoint_c, setpoint_value))
  
  local data = string.char((setpoint_value >> 24) & 0xFF) ..
               string.char((setpoint_value >> 16) & 0xFF) ..
               string.char((setpoint_value >> 8) & 0xFF) ..
               string.char(setpoint_value & 0xFF)
  
  send_tuya_command(device, DP_SETPOINT, 0x02, data)
end

-- Tuya cluster handler
local function tuya_handler(driver, device, zb_rx)
  device.log.info("=== TUYA HANDLER CALLED ===")
  
  local data = zb_rx.body.zcl_body.body_bytes
  
  device.log.info(string.format("Received data length: %d bytes", #data))
  
  -- Tuya messages have a 2-byte sequence/transaction ID before the DP data
  if #data < 6 then
    device.log.warn("Data too short, need at least 6 bytes")
    return
  end

  -- Skip first 2 bytes (sequence number), then parse DP
  local seq = (data:byte(1) << 8) | data:byte(2)
  local dp = data:byte(3)
  local data_type = data:byte(4)
  local data_len = (data:byte(5) << 8) | data:byte(6)
  local dp_data = data:sub(7, 6 + data_len)

  device.log.info(string.format("Seq: 0x%04X, DP: %d (0x%02X), Type: %d, Len: %d", seq, dp, dp, data_type, data_len))
  
  if dp == DP_TEMPERATURE then
    local temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                     (dp_data:byte(3) << 8) | dp_data:byte(4)
    local temp_c = temp_raw / 10
    device.log.info(string.format("DP16 Current temperature: %.1f°C (raw: %d)", temp_c, temp_raw))
    device:emit_event(TemperatureMeasurement.temperature({value = temp_c, unit = "C"}))
    device:emit_event(Battery.battery(math.min(100, math.max(0, temp_raw % 101))))
    
  elseif dp == DP_SETPOINT then
    local setpoint_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local setpoint_c = setpoint_raw / 10
    device.log.info(string.format("DP50 Target setpoint: %.1f°C (raw: %d)", setpoint_c, setpoint_raw))
    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = setpoint_c, unit = "C"}))
    
  elseif dp == DP_SYSTEM_MODE then
    local is_on = dp_data:byte(1) == 1
    if is_on then
      device:emit_event(ThermostatMode.thermostatMode("heat"))
    else
      device:emit_event(ThermostatMode.thermostatMode("off"))
    end
    
  elseif dp == DP_PRESET_MODE then
    local preset = dp_data:byte(1)
    if preset == PRESET_MANUAL or preset == PRESET_TEMP_MANUAL then
      device:emit_event(ThermostatMode.thermostatMode("heat"))
    elseif preset == PRESET_PROGRAM then
      device:emit_event(ThermostatMode.thermostatMode("auto"))
    elseif preset == PRESET_ECO then
      device:emit_event(ThermostatMode.thermostatMode("heat"))
    end
    
  elseif dp == DP_VALVE_STATE then
    local heating = dp_data:byte(1) == 0  -- Inverted: 0=heating, 1=idle
    device.log.info(string.format("Heating state: %s (raw: %d)", heating and "heating" or "idle", dp_data:byte(1)))
    device:set_field("heating_state", heating, {persist = true})
    
  elseif dp == DP_BATTERY then
    local battery_level = dp_data:byte(1)
    device.log.info(string.format("Battery: %d%%", battery_level))
    
  else
    device.log.debug(string.format("Unhandled DP: %d (type: %d, len: %d)", dp, data_type, data_len))
  end
end

-- Device lifecycle handlers
local function device_init(driver, device)
  device:set_field("tuya_initialized", false)
end

local function device_added(driver, device)
  device:emit_event(ThermostatMode.thermostatMode("heat"))
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = 20, unit = "C"}))
  device:emit_event(TemperatureMeasurement.temperature({value = 20, unit = "C"}))
  device:emit_event(Battery.battery(100))
  device:emit_event(ThermostatMode.supportedThermostatModes({"off", "heat", "auto"}))
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = {minimum = 5, maximum = 35}, unit = "C"}))
  
  device.thread:call_on_schedule(300, function()
    device.log.debug("Periodic refresh for history")
    device:refresh()
  end, "periodic_refresh")
  
  device:refresh()
end

local function device_info_changed(driver, device, event, args)
  if not device:get_field("tuya_initialized") then
    device:set_field("tuya_initialized", true)
    device:refresh()
  end
end

local function do_refresh(driver, device, command)
  device.log.info("Refreshing thermostat state")
  send_tuya_command(device, 0, 0, "")
end

-- Driver configuration
local moes_thermostat_driver = {
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.temperatureMeasurement,
    capabilities.battery,
    capabilities.refresh
  },
  
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = handle_thermostat_mode
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = handle_heating_setpoint
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [TUYA_REPORT_DATA] = tuya_handler,
        [TUYA_SET_DATA] = tuya_handler,
        [0x02] = tuya_handler
      }
    }
  },
  
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = device_info_changed
  },
  
  sub_drivers = {}
}

defaults.register_for_default_handlers(moes_thermostat_driver, moes_thermostat_driver.supported_capabilities)
local driver = ZigbeeDriver("moes-thermostat", moes_thermostat_driver)
driver:run()
