# Quadkey Format Analysis

## Provided Sample Data

```
1656756156
1656755952
1656755952
1656755952
1656756136
1656755956
1656755964
1656755964
1656755952
1656757568
1656757568
1656755960
1656755952
1656757524
1656756152
1656755964
1656757524
1656757524
1656756136
1656757524
```

## Observations

### 1. Value Range
- Minimum: ~1,656,755,952
- Maximum: ~1,656,757,568
- All values start with: **1656755*** or **1656756*** or **1656757***
- Range: ~1,616 different values in sample
- Format: 10-digit integers

### 2. Encoding Analysis

#### Traditional Quadkey (Base-4 String)
Traditional quadkeys are base-4 strings (digits 0-3):
- Level 15: 15 characters, e.g., "021301230123012"
- If stored as integer: Would have each digit 0-3
- Maximum level 15 as integer: 3333333333333333 (base-4) = 4^15 - 1 = **1,073,741,823**

**❌ Your values exceed this maximum! (1.65 billion > 1.07 billion)**

This means your `main_quadkey` is **NOT** a traditional base-4 quadkey string stored as integer.

#### Possible Encodings:

### Option 1: Morton Code (Z-Order Curve) - MOST LIKELY
Morton encoding interleaves X and Y tile coordinates into a single integer.

For level 15:
- X coordinate: 0 to 2^15-1 = 0 to 32,767 (15 bits)
- Y coordinate: 0 to 2^15-1 = 0 to 32,767 (15 bits)
- Morton code: Interleave bits = 30 bits total
- Maximum: 2^30 - 1 = 1,073,741,823

**❌ Your values still exceed this!**

Unless... your system uses more than 15 bits per coordinate?

### Option 2: Tile Index (X * MaxY + Y) - ALSO LIKELY
Linear tile index formula: `tile_index = x * (2^zoom) + y`

For level 15:
- Max X = 2^15 = 32,768
- Max Y = 2^15 = 32,768
- tile_index = x * 32768 + y
- Your value: 1,656,756,156

Solving for x and y:
```
1656756156 / 32768 = 50,568.8...
x = 50,568
y = 1656756156 - (50568 * 32768) = 1656756156 - 1656987648 = negative!
```

**❌ Doesn't work with level 15**

### Option 3: Different Zoom Level?

Let me try higher zoom levels:

**Level 16** (16 bits per coordinate):
- tile_index = x * 65536 + y
- 1656756156 / 65536 = 25,284.18...
- x = 25,284
- y = 1656756156 - (25284 * 65536) = 1656756156 - 1656680448 = 75,708
- ✅ Both x and y are within 0-65535 range!

**Level 17** (17 bits per coordinate):
- tile_index = x * 131072 + y
- 1656756156 / 131072 = 12,642.09...
- x = 12,642
- y = 1656756156 - (12642 * 131072) = 37,852
- ✅ Both within range

### Option 4: Google Maps / Slippy Map Tile Numbers
Similar to option 2 but uses: `tile_index = y * (2^zoom) + x` (swapped)

For level 16:
- 1656756156 / 65536 = 25,284.18...
- y = 25,284
- x = 75,708
- ✅ Works!

### Option 5: Quadkey with Offset or Base
Perhaps there's a base offset:
```
main_quadkey = base_offset + actual_quadkey
```

### Option 6: Single Coordinate (Not Full Quadkey)
Perhaps `main_quadkey` stores only:
- The X coordinate at level 15+
- Or Y coordinate at level 15+
- Combined with another field for full location

---

## Analysis: Most Likely Encoding

Given the value range (~1.65 billion), the most likely scenarios are:

### Scenario A: Level 16 Tile Index ⭐ MOST LIKELY
```
main_quadkey = x * 2^16 + y  (where x, y are level 16 tile coordinates)

Example: 1656756156
x = 1656756156 / 65536 = 25,284
y = 1656756156 % 65536 = 75,708

For level 15: divide both x and y by 2
x_l15 = 25284 / 2 = 12,642
y_l15 = 75708 / 2 = 37,854

For level 12: divide by 2^4 = 16
x_l12 = 25284 / 16 = 1,580
y_l12 = 75708 / 16 = 4,731

Reconstruct level 12 quadkey:
main_quadkey_l12 = x_l12 * 2^12 + y_l12
                 = 1580 * 4096 + 4731
                 = 6471680 + 4731
                 = 6,476,411
```

### Scenario B: Morton Code with Higher Precision
If using more than 15 bits per coordinate.

### Scenario C: Custom Encoding
Organization-specific encoding scheme.

---

## Conversion Formulas (Depends on Encoding)

### If Tile Index (Scenario A):

```sql
-- Extract x, y at level 16 (assuming main_quadkey is level 16)
x_l16 = FLOOR(main_quadkey / 65536)
y_l16 = main_quadkey % 65536

-- Convert to level 12
x_l12 = FLOOR(x_l16 / 16)  -- 16 = 2^(16-12)
y_l12 = FLOOR(y_l16 / 16)

-- Reconstruct level 12 quadkey
main_quadkey_l12 = x_l12 * 4096 + y_l12  -- 4096 = 2^12

-- Or as a single expression:
main_quadkey_l12 = FLOOR(main_quadkey / 65536 / 16) * 4096 + 
                   FLOOR((main_quadkey % 65536) / 16)
                 = FLOOR(main_quadkey / 1048576) * 4096 + 
                   FLOOR((main_quadkey % 65536) / 16)
```

### If Morton Code:

```sql
-- Unmask x and y
x = unmask_morton(main_quadkey)
y = unmask_morton(main_quadkey >> 1)

-- Convert to level 12
x_l12 = x >> 3  -- shift right 3 bits (15-12 = 3)
y_l12 = y >> 3

-- Re-encode Morton
main_quadkey_l12 = mask_morton(x_l12, y_l12)
```

### If Simple String-based (Scenario from earlier):

```sql
-- This is WRONG for your data but included for completeness
main_quadkey_l12 = FLOOR(main_quadkey / 1000)
```

---

## 🔍 CRITICAL: Need Clarification

To determine the correct conversion formula, please provide:

### Option 1: Run this query
```sql
SELECT 
    main_quadkey,
    ST_X(geometry_lla::geometry) as longitude,
    ST_Y(geometry_lla::geometry) as latitude,
    -- If you have conversion functions:
    -- quadkey_int_to_x(main_quadkey, 15) as x_coord,
    -- quadkey_int_to_y(main_quadkey, 15) as y_coord,
    -- quadkey_int_to_tile_x(main_quadkey, 15) as tile_x,
    -- quadkey_int_to_tile_y(main_quadkey, 15) as tile_y
FROM signs 
WHERE main_quadkey IS NOT NULL 
  AND geometry_lla IS NOT NULL
LIMIT 5;
```

### Option 2: Check your codebase
Look for functions that:
- Compute `main_quadkey` from coordinates
- Convert `main_quadkey` to tile coordinates
- Convert `main_quadkey` to different zoom levels
- Convert between `main_quadkey` and quadkey strings

### Option 3: Ask your team
- How is `main_quadkey` computed?
- What zoom level is it actually at?
- What encoding scheme is used?
- Is there existing code to convert between levels?

---

## Test Calculations

### Test 1: String-based Division
```
1656756156 / 1000 = 1,656,756.156
FLOOR = 1,656,756
```

### Test 2: Tile Index Level 16 → Level 12
```
x = 1656756156 / 65536 = 25,284
y = 1656756156 % 65536 = 75,708

x_l12 = 25284 / 16 = 1,580.25 → 1,580
y_l12 = 75708 / 16 = 4,731.75 → 4,731

main_quadkey_l12 = 1580 * 4096 + 4731 = 6,476,411
```

### Test 3: Morton Code Approach
```
main_quadkey = 1656756156
Binary: 01100010110000101101000100011100

If level 15 Morton (30 bits):
Need to deinterleave and shift...
(Complex bitwise operations required)
```

---

## Recommended Next Steps

**CRITICAL:** Without knowing the exact encoding, we cannot write the correct conversion formula.

### Immediate Actions:

1. **Identify the encoding method** used for `main_quadkey`
2. **Provide sample data with coordinates** so we can reverse-engineer the formula
3. **Check for existing conversion functions** in your codebase
4. **Test conversion formulas** using the test script provided

### Once Encoding is Confirmed:

1. Choose appropriate column strategy (stored vs. generated)
2. Write correct conversion formula
3. Generate migration scripts
4. Test partition pruning behavior

---

## Temporary Assumption for Script Generation

**Until confirmed, I'll assume:**
- `main_quadkey` is at level 15 or 16
- Uses tile index encoding: `quadkey = x * 2^zoom + y`
- Conversion to level 12 requires coordinate extraction and reconstruction

**But this MUST be verified before running migration!**
