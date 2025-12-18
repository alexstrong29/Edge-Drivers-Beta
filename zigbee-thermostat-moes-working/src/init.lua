-- Moes Star Ring Smart Knob Thermostat Edge Driver
-- Wall-mounted dial thermostat controller
-- Supports _TZE204_lpedvtvr

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"

local ThermostatMode = capabilities.thermostatMode
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local TemperatureMeasurement = capabilities.temperatureMeasurement
local Battery = capabilities.battery

-- Tuya cluster constants
local TUYA_CLUSTER = 0xEF00
local TUYA_SET_DATA = 0x00
local TUYA_REPORT_DATA = 0x01
local TUYA_SET_TIME = 0x24

-- Tuya DP (Data Point) constants for Moes Star Ring thermostat
local DP_MODE = 0x04
local DP_SETPOINT = 0x10
local DP_TEMPERATURE = 0x18
local DP_BATTERY = 0x23
local DP_CHILD_LOCK = 0x28
local DP_WINDOW_DETECTION = 0x68
local DP_HEATING_STATE = 0x6C  -- Relay/heating state rather than valve position

local MODE_OFF = 0
local MODE_AUTO = 1
local MODE_MANUAL = 2

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

local function convert_temp_to_setpoint(temp_c)
  -- Convert temperature to format expected by thermostat (likely in 0.5°C steps)
  return math.floor(temp_c * 2)
end

local function convert_setpoint_to_temp(setpoint)
  -- Convert from thermostat format to Celsius
  return setpoint / 2
end

-- Capability handlers
local function handle_thermostat_mode(driver, device, command)
  local mode = command.args.mode
  local tuya_mode
  
  if mode == "off" then
    tuya_mode = MODE_OFF
  elseif mode == "auto" then
    tuya_mode = MODE_AUTO
  elseif mode == "heat" then
    tuya_mode = MODE_MANUAL
  else
    device.log.warn("Unsupported mode: " .. mode)
    return
  end
  
  local data = string.char(tuya_mode)
  local cmd_body = create_tuya_command(DP_MODE, 0x04, data) -- 0x04 = enum type
  
  device:send(zcl_clusters.basic_id, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body)
end

local function handle_heating_setpoint(driver, device, command)
  local setpoint_c = command.args.setpoint
  local setpoint_value = convert_temp_to_setpoint(setpoint_c)
  
  local data = string.char(setpoint_value >> 24) ..
               string.char((setpoint_value >> 16) & 0xFF) ..
               string.char((setpoint_value >> 8) & 0xFF) ..
               string.char(setpoint_value & 0xFF)
  
  local cmd_body = create_tuya_command(DP_SETPOINT, 0x02, data) -- 0x02 = value type
  
  device:send(zcl_clusters.basic_id, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body)
  
  -- Optimistically update the setpoint
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = setpoint_c, unit = "C"}))
end

-- Tuya cluster handler
local function tuya_handler(driver, device, zb_rx)
  local data = zb_rx.body.zcl_body.body_bytes
  
  if #data < 4 then
    return
  end
  
  local dp = data:byte(1)
  local data_type = data:byte(2)
  local data_len = (data:byte(3) << 8) | data:byte(4)
  
  if #data < 4 + data_len then
    return
  end
  
  local dp_data = data:sub(5, 4 + data_len)
  
  if dp == DP_TEMPERATURE then
    -- Temperature in 0.1°C units
    local temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                     (dp_data:byte(3) << 8) | dp_data:byte(4)
    local temp_c = temp_raw / 10
    device:emit_event(TemperatureMeasurement.temperature({value = temp_c, unit = "C"}))
    
  elseif dp == DP_SETPOINT then
    local setpoint_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local setpoint_c = convert_setpoint_to_temp(setpoint_raw)
    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = setpoint_c, unit = "C"}))
    
  elseif dp == DP_MODE then
    local mode = dp_data:byte(1)
    local mode_string
    
    if mode == MODE_OFF then
      mode_string = "off"
    elseif mode == MODE_AUTO then
      mode_string = "auto"
    elseif mode == MODE_MANUAL then
      mode_string = "heat"
    end
    
    if mode_string then
      device:emit_event(ThermostatMode.thermostatMode(mode_string))
    end
    
  elseif dp == DP_BATTERY then
    local battery_level = dp_data:byte(1)
    device:emit_event(Battery.battery(battery_level))
  end
end

-- Device lifecycle handlers
local function device_init(driver, device)
  device:set_field("tuya_initialized", false)
end

local function device_added(driver, device)
  -- Set default capabilities
  device:emit_event(ThermostatMode.thermostatMode("heat"))
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = 20, unit = "C"}))
  device:emit_event(TemperatureMeasurement.temperature({value = 20, unit = "C"}))
  device:emit_event(Battery.battery(100))
  
  -- Set supported modes
  device:emit_event(ThermostatMode.supportedThermostatModes({"off", "heat", "auto"}))
  
  -- Trigger a refresh to get actual values from device
  device:refresh()
end

local function device_info_changed(driver, device, event, args)
  -- Refresh device state on info change
  if not device:get_field("tuya_initialized") then
    device:set_field("tuya_initialized", true)
    device:refresh()
  end
end

local function do_refresh(driver, device, command)
  -- Request current state from device
  device:send(zcl_clusters.basic_id, TUYA_CLUSTER, TUYA_REPORT_DATA, data_types.CharString(""))
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
        [TUYA_REPORT_DATA] = tuya_handler
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
