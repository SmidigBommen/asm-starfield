# Tutorial: Building the Starfield Step by Step

This document walks through how `src/starfield.asm` was built — what we added
at each step, what broke, and why. Read the concept docs first (01–04), then
use this as a companion when reading the source.

---

## Toolchain Setup

You need two tools:

```bash
brew install nasm        # assembler
# DOSBox-X already installed via brew
```

Assemble and run workflow:

```bash
nasm -f bin starfield.asm -o starfield.com
```

`-f bin` produces a raw binary — no file format headers, just machine code.
DOSBox-X mounts your project folder and runs the `.COM` directly.

To disassemble and inspect the output:

```bash
ndisasm -b 16 -o 100h starfield.com | head -40
```

---

## Step 1 — Skeleton: Mode 13h + One Pixel

**Goal**: prove the full toolchain works end to end.

A `.COM` file always starts with `org 100h` — DOS loads it at offset 0x100 in
the segment (the first 256 bytes are the PSP). All four segment registers
(CS, DS, ES, SS) point to the same segment in a `.COM`, so there is no segment
setup to do.

```nasm
org  100h

start:
    mov  ax, 0013h      ; set VGA mode 13h (320x200, 256 colors)
    int  10h

    mov  ax, 0A000h     ; point ES at the VGA framebuffer
    mov  es, ax

    mov  di, 32160      ; offset for pixel at (160, 100): 100*320+160
    mov  byte [es:di], 15   ; color 15 = white in default DOS palette

    xor  ah, ah
    int  16h            ; wait for keypress

    mov  ax, 0003h      ; restore text mode
    int  10h

    mov  ax, 4C00h      ; exit to DOS
    int  21h
```

You should see a single white dot at screen center. If you do, mode set,
framebuffer addressing, and the toolchain are all working.

---

## Step 2 — Greyscale Palette

**Goal**: own the palette so we can use depth-based star brightness later.

The VGA DAC has 256 color slots, each three 6-bit values (R, G, B, range 0–63).
Write the starting index to port `0x3C8`, then send R/G/B bytes to `0x3C9`.
The DAC auto-advances to the next slot after every three bytes.

We load slots 1–63 with equal R=G=B=i (greyscale). Slot 0 stays black.

```nasm
setup_palette:
    mov  dx, 03C8h
    mov  al, 1          ; start at entry 1
    out  dx, al

    mov  dx, 03C9h
    mov  cx, 63
    xor  bx, bx
.loop:
    inc  bx
    mov  al, bl
    out  dx, al         ; R
    out  dx, al         ; G
    out  dx, al         ; B
    loop .loop
    ret
```

Change the pixel draw to use color 63 (our new brightest white). The dot
should look identical — but now we control the palette.

---

## Step 3 — Single Star: Init and Projection

**Goal**: place one star in 3D space and project it to the screen.

### Random numbers

We need random X and Y. A simple 16-bit LCG (Linear Congruential Generator):

```nasm
rand:
    mov  ax, [rand_seed]
    imul ax, 25173      ; two-operand imul is fine here: result stays small
    add  ax, 13849
    mov  [rand_seed], ax
    and  ax, 7FFFh      ; keep positive (15-bit)
    ret
```

`rand` returns 0–32767 in AX. To get a signed range for X/Y:

```nasm
call rand
sub  ax, 3FFFh          ; shift to -16383..+16384
```

### Projection — the arithmetic trap

The projection formula is:

```
screen_x = (X_fp * FOV) / (Z * 64) + CENTER_X
```

The naive approach `imul ax, FOV` (two-operand) gives a **16-bit truncated
result**. With X up to 16384 and FOV=200, the product is 3,276,800 — this
silently overflows 16 bits and gives garbage coordinates.

The fix: use single-operand `imul bx` which puts the **full 32-bit result in
DX:AX**. Then shift the 32-bit pair right by 6 (÷64) using `sar`/`rcr` pairs:

```nasm
mov  ax, bx             ; AX = X
mov  bx, FOV
imul bx                 ; DX:AX = X * FOV  (32-bit, no overflow)
sar  dx, 1
rcr  ax, 1              ; shift DX:AX right 1 (carry flows DX → AX)
; ... repeat 5 more times for a total of 6 shifts (÷64)
idiv si                 ; AX = result  (Z is in SI, not DX!)
```

`sar`/`rcr` is the 16-bit way to right-shift a value that spans two registers.
`sar dx, 1` shifts DX right arithmetically and its lowest bit falls into the
carry flag. `rcr ax, 1` rotates AX right through carry, so that bit lands in
AX's highest position. Together they perform one arithmetic right shift of the
combined 32-bit DX:AX.

### The DX register trap

`idiv reg` divides **DX:AX** by the operand. If Z is in DX, you are dividing by
your own dividend's high word — an immediate CPU fault.

Always keep Z in `SI` or another register that `idiv` does not touch.

---

## Step 4 — Animation Loop

**Goal**: make the star fly toward the viewer and reset when it passes.

### Loop structure

```nasm
.mainloop:
    mov  ah, 01h
    int  16h            ; non-blocking keypress check
    jnz  .done          ; key waiting — exit

    call erase_star     ; paint black at current position
    call move_star      ; update Z (and reset if needed)
    call draw_star      ; paint white at new position
    call wait_vsync
    jmp  .mainloop
```

Order matters: **erase first, then move, then draw**. This way you always
erase where the star *was* before repositioning it.

### Erasing

`erase_star` is identical to `draw_star` except it writes color 0 (black)
instead of 63. It projects the current position and clears that pixel.
Since erase happens before move, it uses the same Z as the previous draw.

### Moving and resetting

```nasm
move_star:
    sub  word [stars + 4], STAR_SPEED
    cmp  word [stars + 4], 8    ; reset before Z gets too small
    jg   .done
    ; ... assign new random X, Y and reset Z to MAX_Z
```

The minimum Z threshold (8) is important. `idiv` faults if the quotient
overflows 16-bit signed range (-32768 to 32767). With Z=1 and a large X,
the quotient can reach 51200 — which overflows and crashes immediately.

Resetting at Z=8 keeps the quotient safely within range and the visual
difference is imperceptible (the star would be off screen anyway).

### Vertical sync

```nasm
wait_vsync:
    mov  dx, 03DAh
.notblank:
    in   al, dx
    test al, 08h
    jnz  .notblank      ; loop while bit 3 SET (still in retrace)
.blank:
    in   al, dx
    test al, 08h
    jz   .blank         ; loop while bit 3 CLEAR (retrace not started)
    ret
```

Two phases: first wait for any current retrace to *end*, then wait for the
next retrace to *begin*. This guarantees you start your frame right at the
top of the blank period.

**Common mistake**: using `jnz` for both loops. The second loop then jumps
back to the first when retrace starts, and the routine never returns cleanly.
The second loop must use `jz`.

---

## What's Next

- **Step 5**: expand `init_stars` and the main loop to handle all 200 stars
- **Step 6**: add depth-based color (use `(MAX_Z - Z) / 4 + 1` as the palette index)
- **Future**: replace erase/draw with a full backbuffer + `rep movsw` for flicker-free animation

---

Previous: [04-starfield.md](04-starfield.md)
