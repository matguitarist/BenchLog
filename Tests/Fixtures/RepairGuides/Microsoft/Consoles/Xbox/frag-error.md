# FRAG Error (Flashing Red and Green)

## Problem Description
FRAG (Flashing Red And Green) is an error condition where the power LED on the Xbox alternates between red and green colors when powered on. This indicates a critical hardware failure that prevents the console from booting. FRAG errors occur during the early boot sequence when the system is performing hardware checks.

![[frag_error_led.jpg]]

## Symptoms
- The power LED alternates between red and green colors
- No video output is displayed on the TV/monitor
- No startup sound plays through the audio output
- No response to controller inputs
- Console may make normal fan and drive noise but won't boot

## Common Causes
1. **Faulty or improper power supply connection**
2. **Damaged or corroded traces on the motherboard** (often from clock capacitor leakage)
3. **Failed or improperly seated RAM chips**
4. **CPU/GPU overheating or bad solder joints** (cold solder joint)
5. **BIOS chip failure or corruption**
6. **Hard drive failure or connection issues**
7. **Damaged components from power surge**
8. **Modchip installation errors**

## Required Tools
- Torx screwdriver set (T10, T15, T20)
- Phillips screwdriver
- Multimeter
- Isopropyl alcohol (90%+ concentration)
- Cotton swabs
- Thermal paste
- Soldering iron and solder (for advanced repairs)
- Anti-static wrist strap

## Diagnostic Procedure

### Step 1: Power Supply Check
1. Unplug all cables from the Xbox
2. Inspect the power cable for damage
3. Try a different power outlet
4. If possible, test with a known-working Xbox power cable

### Step 2: Internal Inspection
1. Open the Xbox case (follow the steps in the [[clock-capacitor-leakage|Clock Capacitor Leakage]] guide)
2. Visually inspect the motherboard for:
   - Bulging or leaking capacitors
   - Corrosion or residue (especially around the clock capacitor)
   - Burn marks on components
   - Loose or disconnected cables

![[motherboard_inspection_points.jpg]]

### Step 3: Check for Clock Capacitor Damage
1. Locate the clock capacitor (see [[clock-capacitor-leakage|Clock Capacitor Leakage]] guide)
2. Check for leakage and clean any residue with isopropyl alcohol
3. Inspect surrounding traces for damage or corrosion

### Step 4: RAM Reseating/Testing
1. Locate the RAM chips (usually near the CPU)
2. Gently clean the RAM contacts with isopropyl alcohol
3. For advanced users: Test each RAM chip individually if possible

![[ram_location.jpg]]

### Step 5: CPU/GPU Thermal Issues
1. Remove the heatsinks from the CPU and GPU
2. Clean off old thermal paste with isopropyl alcohol
3. Check for cold solder joints (appear dull, cracked, or raised)
4. Apply fresh thermal paste and reseat the heatsinks securely

![[cpu_gpu_thermal_paste.jpg]]

### Step 6: Hard Drive Check
1. Disconnect and reconnect the hard drive cables
2. Ensure cables are not damaged
3. If possible, test with a known-working Xbox hard drive

## Common Solutions

### For Clock Capacitor Damage
1. Remove the leaking capacitor following the [[clock-capacitor-leakage|Clock Capacitor Leakage]] guide
2. Clean affected areas thoroughly
3. For advanced users: Repair damaged traces (see [[trace-corrosion|Trace Corrosion]] guide)

### For Thermal Issues
1. Replace thermal paste on CPU and GPU
2. Ensure heatsinks are properly mounted
3. Verify the fan is working correctly
4. For advanced users: Reflow solder on CPU/GPU (requires specialized equipment)

### For Power Supply Issues
1. Test voltage output with a multimeter
2. Replace power supply if faulty
3. Check for damaged components on the power input section of the motherboard

### For Hard Drive Issues
1. Try booting without the hard drive connected
2. If the console shows a different error (not FRAG), the hard drive may be the issue
3. For advanced users: Try rebuilding the hard drive with a working Xbox

## Error Code Diagnostic
The specific FRAG pattern can indicate different issues:

- **Constant alternating red/green**: General hardware failure
- **1 green flash, then red**: CPU issue
- **2 green flashes, then red**: RAM issue
- **3 green flashes, then red**: Hard drive issue
- **4 green flashes, then red**: Video encoder issue

![[frag_error_codes.jpg]]

## Advanced Repair Options
For persistent FRAG errors after trying the above solutions:

1. **Reballing/Reflowing**: For CPU/GPU solder joint issues (requires professional equipment)
2. **Trace repair**: Use conductive ink or wire to repair damaged traces
3. **Component replacement**: Replace damaged capacitors, resistors, or other components
4. **TSOP flashing**: Reprogram the BIOS (for modded consoles)

## Prevention
1. Regularly clean your Xbox to prevent dust buildup
2. Keep the console in a well-ventilated area
3. Remove the clock capacitor before it leaks (versions 1.0-1.5)
4. Use a surge protector to prevent power-related damage

## Related Issues
- [[clock-capacitor-leakage|Clock Capacitor Leakage]]
- [[power-supply-issues|Power Supply Issues]]
- [[hard-drive-failure|Hard Drive Failure]]
- [[overheating-problems|Overheating Problems]]
- [[trace-corrosion|Trace Corrosion]]
