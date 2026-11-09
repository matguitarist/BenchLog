# Clock Capacitor Leakage

## Problem Description
The original Xbox (versions 1.0-1.5) contains a clock capacitor that is prone to leakage. This capacitor's sole purpose is to maintain the system clock for a short period when the console is unplugged. When this capacitor leaks, the electrolyte can damage nearby traces and components on the motherboard, potentially causing permanent damage.

![[clock_capacitor_location.jpg]]

## Symptoms
- Console powers on but shows errors or boots inconsistently
- Green and red flashing lights (sometimes)
- Corrosion visible on the motherboard near the capacitor
- Time/date reset when console is unplugged
- Strange smell coming from the console

## Required Tools
- Torx screwdriver set (T10, T15, T20)
- Isopropyl alcohol (90%+ concentration)
- Cotton swabs
- Small needle-nose pliers
- Anti-static wrist strap
- Paper towels

## Identification Guide
The clock capacitor is typically a gold or black cylindrical component located near the IDE connector on the motherboard. Its exact position varies slightly between Xbox versions:

- **Versions 1.0-1.4**: Found near the IDE connector, usually gold in color, 1F 2.5V marking
- **Version 1.5**: Similar position but may be black
- **Version 1.6**: Uses a different type of capacitor that is not as prone to leakage (removal not recommended for v1.6)

![[clock_capacitor_versions.jpg]]

## Removal Procedure

### Step 1: Preparation
1. Unplug all cables from the Xbox
2. Discharge any static electricity by touching a grounded metal object
3. Place the Xbox on a clean, flat work surface
4. Put on your anti-static wrist strap

### Step 2: Opening the Case
1. Turn the Xbox upside down and remove the rubber feet to expose the screws
2. Use the T20 Torx screwdriver to remove the 6 case screws
3. Turn the Xbox right side up and carefully lift off the top cover

### Step 3: Remove the Hard Drive and DVD Drive
1. Disconnect the IDE and power cables from both drives
2. Remove the hard drive bracket screws (T10 Torx)
3. Remove the DVD drive bracket screws (T10 Torx)
4. Carefully lift both drives out of the case

### Step 4: Remove the Clock Capacitor
1. Locate the clock capacitor on the motherboard
2. **Method 1 (Recommended for mild or no visible leakage):**
   - Gently rock the capacitor back and forth with needle-nose pliers until it breaks free
   - Do NOT use excessive force that could damage the motherboard
   
3. **Method 2 (For stubborn capacitors):**
   - Use flush cutters to cut the capacitor leads as close to the motherboard as possible
   - Then desolder the remaining leads (recommended only if you have soldering experience)

![[capacitor_removal_technique.jpg]]

### Step 5: Clean the Affected Area
1. Inspect the area for any electrolyte residue (appears as a yellowish or greenish substance)
2. Dampen a cotton swab with isopropyl alcohol
3. Gently clean the area where the capacitor was mounted
4. Clean any visible corrosion or residue on surrounding components
5. Allow the area to fully dry (at least 15 minutes)

![[capacitor_cleanup.jpg]]

### Step 6: Reassembly
1. Reinstall the DVD drive and hard drive
2. Reconnect all cables
3. Replace the top cover
4. Turn the Xbox upside down and replace the 6 case screws
5. Replace the rubber feet

## Important Notes
- Version 1.6 Xboxes should NOT have the clock capacitor removed as it is required for proper operation
- After removal, your Xbox will need to be connected to the internet or manually set the time each time it's unplugged
- If significant damage is already present, trace repair may be necessary (see [[trace-corrosion|Trace Corrosion]] guide)
- Consider replacing other capacitors while you have the system open, especially if the Xbox is older than 15 years

## Preventative Measures
Even if your capacitor hasn't leaked yet, it's recommended to remove it from all version 1.0-1.5 Xboxes as a preventative measure. This will not affect normal operation if the console is regularly connected to the internet or if you don't mind setting the time manually.

## Related Issues
- [[trace-corrosion|Trace Corrosion]]
- [[power-supply-issues|Power Supply Issues]]
- [[frag-error|FRAG Error (Flashing Red and Green)]]
