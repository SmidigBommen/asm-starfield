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
stars    times N_STARS * 3 dw 0    ; 200 stars × 3 words
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

## Pitfalls

### 1. `dup` is not NASM syntax

MASM/TASM use `dup`. NASM uses `times`:

```nasm
; wrong (MASM syntax)
stars dw N_STARS * 3 dup(0)

; correct (NASM syntax)
stars times N_STARS * 3 dw 0
```

### 2. Two-operand `imul` overflows

`imul ax, FOV` gives a 16-bit truncated result. With X up to 16384 and FOV=200,
the product is 3,276,800 — way beyond 16-bit range (max 32767 signed).

Use the **single-operand** form instead, which puts the full 32-bit result in `DX:AX`:

```nasm
mov  bx, FOV
imul bx          ; DX:AX = AX * FOV  (no overflow)
```

Then divide the 32-bit result by 64 using `sar`/`rcr` pairs (one pair = one right shift
of the combined DX:AX value, carry flowing from DX into AX):

```nasm
sar  dx, 1
rcr  ax, 1       ; repeat 6 times to divide by 64
```

### 3. `idiv` uses DX as part of the dividend

`idiv reg` divides **DX:AX** by the operand. If you put Z in DX and then call
`idiv dx`, you are dividing by your own dividend's high word — immediate CPU fault.

Keep Z in `SI` or `DI` so it is never touched by the divide instruction.

### 4. Divide overflow when Z is small

`idiv` faults if the quotient doesn't fit in signed 16-bit (-32768 to 32767).
With Z=1 and a large X: 51200 / 1 = 51200 → overflow fault.

Fix: reset the star before Z gets small enough to cause this. In `move_star`,
reset when Z <= 8 rather than Z <= 0. Use the base pointer `bx` from
`star_offset` — not a hardcoded offset:

```nasm
move_star:
    mov  bx, [star_offset]
    sub  word [stars + bx + 4], STAR_SPEED
    cmp  word [stars + bx + 4], 8
    jg   .done
    ; reset star...
    mov  word [stars + bx + 4], MAX_Z   ; bx! not hardcoded
```

### 5. `loop` uses CX — don't let subroutines clobber it

The `loop` instruction decrements CX and jumps if CX != 0. If any subroutine
called inside the loop modifies CX, the loop counter is silently corrupted.

`draw_star` and `erase_star` both do `mov cx, [stars + bx + 2]` to load Y.
Using `loop` for the star iteration means CX becomes a Y coordinate after
the first star — the loop runs wild, accesses memory beyond the stars array,
eventually hits Z=0, and crashes with a divide fault.

Fix: drive the loop from `star_offset` in memory instead:

```nasm
    mov  word [star_offset], 0
.star_loop:
    call erase_star
    call move_star
    call draw_star
    add  word [star_offset], 6
    cmp  word [star_offset], N_STARS * 6
    jl   .star_loop
```

No CX involved. The routines already read `[star_offset]` themselves.

### 6. Hardcoded star offset in reset code

When `move_star` resets a star it must write to the *current* star's fields.
A hardcoded `[stars + 4]` always resets star 0's Z regardless of which star
is being processed. Every other star that dies keeps Z stuck at ≤ 8 forever,
eventually hitting zero and causing a divide fault.

Always use `[stars + bx + N]` where BX comes from `[star_offset]`.

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
