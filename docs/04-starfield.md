# Starfield Effect

A classic demo effect: hundreds of stars flying toward the viewer,
simulating travel through space. The key is **3D perspective projection**
reduced to integer arithmetic.

---

## The Mental Model

Each star lives in 3D space with coordinates (X, Y, Z):

- X and Y are the star's position in the plane perpendicular to your view
- Z is the depth — how far away the star is
- Every frame, Z decreases (star moves toward you)
- When Z reaches 0 (or goes negative), reset the star at a new random position far away

---

## Perspective Projection

To turn 3D coordinates into a 2D screen position:

```
screen_x = (X / Z) * FOV + CENTER_X
screen_y = (Y / Z) * FOV + CENTER_Y
```

`FOV` is a scale factor controlling how wide the field of view feels.
`CENTER_X` and `CENTER_Y` are the vanishing point (usually screen center: 160, 100).

As Z gets smaller (star comes closer):
- The division result grows → star moves outward from center
- The star appears to accelerate as it approaches

---

## Star Brightness

Deeper stars (large Z) are dim. Close stars (small Z) are bright.
Map Z to a palette index:

```
brightness = MAX_Z - Z      (inverted: small Z = high brightness)
color_index = brightness / SCALE
```

We'll build a greyscale palette ramp in slots 1–63 (0 = black for background).

---

## Fixed-Point Representation

We have no FPU. X and Y need fractional parts to make motion smooth,
especially for distant stars that move less than 1 pixel per frame.

**Strategy**: store X and Y scaled by 64 (6 bits of fraction).

```
Real value 1.5  →  stored as  96   (1.5 × 64)
Real value 0.25 →  stored as  16   (0.25 × 64)
```

The projection then becomes:

```
screen_x = ((X_fixed / 64) * FOV) / Z + CENTER_X
         = (X_fixed * FOV) / (Z * 64) + CENTER_X
```

We'll use `IMUL` + `IDIV` for this — slow but correct, and fine for ~200 stars.

---

## Star Data Structure

Each star is 3 words (6 bytes):

```
offset 0:  X   (signed 16-bit, fixed-point ×64)
offset 2:  Y   (signed 16-bit, fixed-point ×64)
offset 4:  Z   (unsigned 16-bit, 1–MAX_Z)
```

Array of N_STARS stars packed together:

```nasm
N_STARS  equ  200
stars    dw   N_STARS * 3 dup(0)   ; 200 stars × 3 words
```

---

## Pseudo-Random Numbers

We need to scatter stars randomly. A simple **LCG** (Linear Congruential Generator):

```
seed = seed * 1103515245 + 12345
random_value = (seed >> 16) & 0x7FFF
```

In 16-bit ASM we'll use a 16-bit version:

```nasm
; updates [rand_seed], returns value in AX
rand:
    mov  ax, [rand_seed]
    imul ax, 25173          ; LCG multiplier
    add  ax, 13849          ; LCG increment
    mov  [rand_seed], ax
    ret
```

Not cryptographic, but plenty good enough for demo star scatter.

---

## Per-Frame Algorithm

```
for each star:
    erase old position (draw black pixel at last screen_x, screen_y)
    Z -= speed
    if Z <= 0:
        X = random(-SPREAD, +SPREAD)   (fixed-point)
        Y = random(-SPREAD, +SPREAD)   (fixed-point)
        Z = MAX_Z
    project: screen_x = (X * FOV) / Z + 160
             screen_y = (Y * FOV) / Z + 100
    if screen_x and screen_y are on screen:
        color = (MAX_Z - Z) / COLOR_SCALE + 1
        draw pixel at screen_x, screen_y with color
wait_vsync
```

Because we draw directly to the VGA buffer (no backbuffer for now),
we erase the old pixel before drawing the new one. This avoids needing
64KB of extra RAM for a backbuffer, at the cost of minor flicker on very
fast machines. We'll note where to add a backbuffer as an upgrade.

---

## Constants We'll Use

```nasm
N_STARS     equ  200
MAX_Z       equ  255
STAR_SPEED  equ  2
FOV         equ  200
CENTER_X    equ  160
CENTER_Y    equ  100
SPREAD      equ  4096       ; ±64 in real coords (×64 fixed-point)
```

---

## Palette Setup

We want 63 shades from near-black to white, stored in palette slots 1–63.
Slot 0 = black (background).

```
for i = 1 to 63:
    R = G = B = i           ; equal RGB = grey
    set palette[i] = (R, G, B)
```

For a blue-tinted starfield change to `R = i/2, G = i/2, B = i`.

---

## Implementation Roadmap

We'll build `src/starfield.asm` in these steps:

1. **Step 1** — skeleton: set mode 13h, draw one white pixel, wait for key, exit
2. **Step 2** — palette: load the greyscale ramp
3. **Step 3** — single star: init, project, draw one star (no movement)
4. **Step 4** — movement loop: animate one star flying toward viewer
5. **Step 5** — full field: 200 stars with random init and reset
6. **Step 6** — polish: tweak speed, FOV, depth coloring, maybe add a title scroller

---

Ready to start Step 1: [../src/starfield.asm](../src/starfield.asm)
