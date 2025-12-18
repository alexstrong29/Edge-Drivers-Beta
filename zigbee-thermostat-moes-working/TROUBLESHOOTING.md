# Troubleshooting: Driver Not Showing Up

## Step 1: Verify Driver is Installed

```bash
# List all installed drivers on your hub
smartthings edge:drivers:installed -H

# Or get more detail with JSON output
smartthings edge:drivers:installed <HUB_ID> -o json
```

Look for "Moes Star Ring Thermostat" in the list. If it's not there, it didn't install properly.

## Step 2: Check Driver Status

```bash
# Get your hub ID first
smartthings hubs

# Check driver installation status
smartthings edge:drivers:installed <HUB_ID>
```

The driver should show as "RUNNING" status.

## Step 3: Check Driver Logs

```bash
# Get the driver ID from step 1, then watch logs
smartthings edge:drivers:logcat <DRIVER_ID>
```

Look for any errors during startup.

## Common Issues and Fixes

### Issue 1: Driver Shows as "INSTALLED" but not "RUNNING"
**Solution:** Wait 1-2 minutes. Drivers can take time to fully start.

```bash
# Check status again after waiting
smartthings edge:drivers:installed <HUB_ID>
```

### Issue 2: Driver Not in List at All
**Solution:** Reinstall the driver

```bash
cd moes-star-thermostat
smartthings edge:drivers:package .
smartthings edge:drivers:install
```

Make sure you select the correct hub when prompted.

### Issue 3: Driver Shows but Won't Create Virtual Device
**Solution:** The driver might not support virtual devices, OR there's a profile issue.

Try this alternative approach - install without virtual device first:

```bash
# Just check if driver is running
smartthings edge:drivers:installed -H
```

If it shows as RUNNING, try pairing the actual device instead of creating a virtual one.

## Step 4: Alternative - Use Developer Workspace

If CLI isn't working, try the Developer Workspace:

1. Go to https://smartthings.developer.samsung.com/workspace
2. Create a new Edge Driver
3. Upload the driver files
4. Create a channel
5. Invite your hub to the channel
6. Install via SmartThings mobile app

## Step 5: Force Refresh the Hub

Sometimes the hub needs a refresh:

```bash
# Check hub status
smartthings hubs -o json

# The hub should show as "ONLINE"
```

If needed, restart your hub:
- Unplug the hub
- Wait 30 seconds
- Plug it back in
- Wait 2-3 minutes for it to come back online
- Check driver status again

## Step 6: Verify Package Contents

Make sure the package was created correctly:

```bash
cd moes-star-thermostat
smartthings edge:drivers:package .
```

You should see output like:
```
✔ Packaged driver successfully
```

If you see errors, there's a problem with the driver files.

## Step 7: Check for Conflicting Drivers

Sometimes other drivers can conflict:

```bash
# List all drivers
smartthings edge:drivers:installed <HUB_ID>
```

If you have other Tuya thermostat drivers installed, they might conflict. Try uninstalling them temporarily.

## Step 8: Manual Virtual Device Creation (Workaround)

If `virtualdevices:create` isn't working, you can try creating it via API:

```bash
# Get hub ID
HUB_ID=$(smartthings hubs --json | jq -r '.[0].deviceId')

# Get driver ID (replace with your actual driver ID from step 1)
DRIVER_ID="your-driver-id-here"

# Create device using the SmartThings API
smartthings devices:create \
  --label "Test Moes Thermostat" \
  --type VIRTUAL
```

## Still Not Working?

### Check Driver Validation

Run validation on the package:

```bash
cd moes-star-thermostat
smartthings edge:drivers:package . --validate
```

This will show any validation errors.

### Get Detailed Logs

```bash
# Turn on verbose logging
smartthings edge:drivers:logcat <DRIVER_ID> --all
```

Watch for any errors when the driver starts up.

### Last Resort: Simplify the Driver

If nothing works, we might need to simplify the driver or check for syntax errors in the Lua code.

Share the error messages from:
1. `smartthings edge:drivers:installed <HUB_ID>`
2. `smartthings edge:drivers:logcat <DRIVER_ID>`

And we can debug from there!
