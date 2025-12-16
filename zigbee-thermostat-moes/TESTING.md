# Testing the Moes Star Ring Thermostat Driver

## Method 1: Using SmartThings CLI (Virtual Device)

### Step 1: Install the Driver
First, make sure your driver is installed on your hub:
```bash
cd moes-star-thermostat
smartthings edge:drivers:package .
smartthings edge:drivers:install
```

### Step 2: Get Your Driver ID
List installed drivers to find the driver ID:
```bash
smartthings edge:drivers:installed -H
```

Look for "Moes Star Ring Thermostat" and note its ID (looks like: `12345678-1234-1234-1234-123456789abc`)

### Step 3: Create a Virtual Device
```bash
smartthings virtualdevices:create -H
```

You'll be prompted for:
1. **Hub** - Select your hub
2. **Driver** - Select "Moes Star Ring Thermostat" 
3. **Device Name** - Enter something like "Test Moes Thermostat"
4. **Device Label** - Enter a friendly name
5. **Profile** - Select "thermostat"

The virtual device will appear in your SmartThings app immediately!

## Method 2: Using the API (Alternative)

If you prefer the API approach, you can use this command structure:

```bash
# First get your hub ID
smartthings hubs -o json

# Then get your driver ID
smartthings edge:drivers:installed <HUB_ID> -o json

# Create the virtual device
smartthings virtualdevices:create \
  --hub <HUB_ID> \
  --driver <DRIVER_ID> \
  --name "Test Moes Thermostat" \
  --label "Test Moes Thermostat" \
  --profile thermostat
```

## Testing the Device

Once created, you can:

1. **In the SmartThings App:**
   - See the device with temperature display
   - Adjust the heating setpoint
   - Change modes (Off/Heat/Auto)
   - View battery level

2. **Test Commands via CLI:**
   ```bash
   # Get device ID
   smartthings devices -o json
   
   # Set heating setpoint to 21°C
   smartthings devices:commands <DEVICE_ID> main thermostatHeatingSetpoint setHeatingSetpoint 21
   
   # Change mode to heat
   smartthings devices:commands <DEVICE_ID> main thermostatMode setThermostatMode heat
   
   # Refresh device
   smartthings devices:commands <DEVICE_ID> main refresh refresh
   ```

3. **Check Live Logs:**
   ```bash
   smartthings edge:drivers:logcat <DRIVER_ID>
   ```

## Important Notes

⚠️ **Virtual Device Limitations:**
- The virtual device won't actually communicate with real hardware
- Temperature readings won't update automatically (they're simulated)
- You won't see actual Tuya cluster messages in the logs
- Commands will execute but won't trigger real heating

✅ **What You CAN Test:**
- UI appearance in SmartThings app
- Capability handlers (setpoint, mode changes)
- Driver logic and command formatting
- Integration with automations and scenes
- The overall user experience

## Removing the Test Device

When you're done testing:

```bash
# List devices to get the device ID
smartthings devices

# Delete the virtual device
smartthings devices:delete <DEVICE_ID>
```

Or simply remove it from the SmartThings app (Settings → Delete Device).

## Real Device Testing

To test with your actual Moes Star Ring thermostat:

1. Remove the virtual device first
2. Put the real thermostat in pairing mode (hold both buttons for 5 seconds)
3. Add it through the SmartThings app
4. The driver will automatically match based on the fingerprint

The real device will show actual temperature readings and control your heating system!
