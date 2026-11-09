# Cartridge Connection Issues

## Problem Description
Cartridge connection issues occur when the NES has trouble establishing proper electrical contact with the game cartridge. This results in games not starting, freezing, glitching, or displaying the blinking red light. These problems are extremely common due to the front-loading design of the original NES.

![[cartridge_connection.jpg]]

## Symptoms
- Games fail to start (blinking red light)
- Games start but freeze randomly
- Games glitch or display corrupted graphics
- Need to insert the cartridge multiple times to work
- Games only work when positioned a certain way
- System needs to be powered on and off repeatedly

## Common Causes
1. **Dirty game cartridge contacts**
2. **Dirty or oxidized 72-pin connector in the NES**
3. **Bent pins in the 72-pin connector**
4. **Weak tension in the 72-pin connector**
5. **Misaligned cartridge insertion**
6. **Corroded cartridge contacts**
7. **Damaged game PCB edge connectors**
8. **Dust or foreign objects in the cartridge slot**

## Required Tools
- Phillips screwdriver
- Flathead screwdriver (small)
- Security bit screwdriver (3.8mm, for opening NES cartridges)
- Isopropyl alcohol (90%+ concentration)
- Cotton swabs
- Microfiber cloth
- Rubber eraser (pencil eraser)
- Brass/copper cleaner (optional)
- Needle-nose pliers (for pin adjustment)

## Diagnostic Procedure

### Step 1: Check and Clean Game Cartridges
1. Inspect the cartridge edge connectors for:
   - Dirt or grime build-up
   - Corrosion (green or black spots)
   - Physical damage or deep scratches
   - Foreign substances

2. Clean the cartridge contacts:
   - Dip a cotton swab in isopropyl alcohol
   - Rub firmly along the copper/gold contacts
   - Allow to dry completely (about 5 minutes)
   - For stubborn oxidation, gently use a pencil eraser

![[cartridge_cleaning_method.jpg]]

### Step 2: Test Multiple Games
1. Try several different games if available
2. Note if all games have issues or just specific ones
3. If only certain games have problems, focus on cleaning those cartridges

### Step 3: Check the 72-Pin Connector
To access the connector:
1. Unplug the NES
2. Remove the six screws from the bottom of the console
3. Lift off the top half of the case
4. Remove the metal RF shield (7 screws)
5. Disconnect the ribbon cables for the controllers and power/reset
6. Remove the cartridge tray (4 screws)
7. Remove the 72-pin connector by pulling up firmly

![[connector_removal.jpg]]

### Step 4: Inspect the 72-Pin Connector
Look for:
1. Dirt or dust between the pins
2. Oxidation or corrosion on the pins
3. Bent or misaligned pins
4. Loose connection to the motherboard
5. Physical damage to the connector

## Common Solutions

### Solution 1: Cleaning Game Cartridges
Basic cleaning method:
1. Use cotton swabs and isopropyl alcohol
2. Clean both sides of the contact area
3. Allow to dry completely

For stubborn oxidation:
1. Gently use a rubber eraser on the contacts
2. Follow with isopropyl alcohol cleaning
3. For severe cases, consider brass/copper cleaner (carefully)

![[deep_cleaning_cartridge.jpg]]

### Solution 2: Cleaning the 72-Pin Connector
Method 1 - Without removal:
1. Wrap a thin cloth around a credit card
2. Moisten with isopropyl alcohol
3. Insert and remove from the connector several times
4. Allow to dry before testing

Method 2 - With removal:
1. Remove the connector as described above
2. Clean thoroughly with isopropyl alcohol and cotton swabs
3. Use a soft toothbrush for stubborn dirt
4. Allow to dry completely before reinstalling

![[connector_cleaning.jpg]]

### Solution 3: Adjusting the 72-Pin Connector
If cleaning doesn't work, adjust the pins for better contact:
1. Remove the 72-pin connector
2. Use a small needle or pin to gently bend each contact pin inward
3. Only bend about 5-10 degrees - be gentle!
4. The goal is to increase tension when a cartridge is inserted
5. Be consistent across all pins for even pressure

![[pin_adjustment_technique.jpg]]

### Solution 4: Boiling Method (Unconventional but Effective)
This helps restore the connector's springiness and clean it:
1. Remove the 72-pin connector
2. Boil in distilled water for 10-20 minutes
3. Remove and let dry completely (24+ hours minimum)
4. Reinstall and test

### Solution 5: Replacing the 72-Pin Connector
When cleaning and adjustment fail:
1. Purchase a replacement 72-pin connector
2. Remove the old connector
3. Install the new connector
4. Be aware that some replacement connectors are of varying quality

![[replacement_connector_options.jpg]]

## Cartridge Insertion Techniques

### The "Down and In" Method
1. Insert the cartridge fully down into the connector
2. Then push down again while pushing in toward the back
3. This creates better contact with the pins

### The "Wiggle" Method
1. Insert the cartridge
2. Wiggle gently side to side
3. Try different positions until the game starts

![[insertion_techniques.jpg]]

## Disabling the Lockout Chip
For consistent connection issues, disabling the lockout chip helps:
1. Locate the CIC/lockout chip (usually labeled "3193A")
2. Cut pin 4 of the chip (advanced) OR
3. Connect pins 4 and 7 with a piece of wire (safer method)

See the [[blinking-red-light|Blinking Red Light]] guide for detailed instructions.

## Prevention
1. Store games in protective cases or sleeves
2. Always insert and remove cartridges gently
3. Clean games periodically, especially if unused for long periods
4. Keep the console dust-free
5. Don't leave games inserted when not in use
6. Consider using a top-loader NES for valuable games

## Related Issues
- [[blinking-red-light|Blinking Red Light]]
- [[game-freezing-or-glitching|Game Freezing or Glitching]]
- [[72-pin-connector-replacement|72-Pin Connector Replacement]]
