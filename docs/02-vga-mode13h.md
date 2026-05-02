# VGA Mode 13h

The bread and butter of 90s PC demos. One INT call and you have a
320×200 framebuffer mapped directly into memory.

---

## Setting the Mode

```nasm
mov  ah, 00h        ; BIOS function: set video mode
mov  al, 13h        ; mode 13h
int  10h
```

To go back to text mode when done:

```nasm
mov  ah, 00h
mov  al, 03h        ; mode 03h = 80×25 text
int  10h
```

---

## The Framebuffer

Mode 13h maps the screen linearly starting at **segment 0xA000, offset 0**.

```
Physical address 0xA0000
One byte per pixel
320 bytes per row × 200 rows = 64,000 bytes total
```

To write a pixel at (x, y):

```
offset = y × 320 + x
write 1 byte (the color index) to ES:[offset]
```

In code, point ES at the VGA segment once and leave it there:

```nasm
mov  ax, 0A000h
mov  es, ax
```

Then writing pixel (x=10, y=5) with color 15:

```nasm
; offset = 5*320 + 10 = 1610
mov  di, 1610
mov  byte [es:di], 15
```

---

## The 256-Color Palette

The 256 color slots are **not fixed** — you define them. Each slot is
three 6-bit values (R, G, B), range 0–63.

To set palette entry N:

```nasm
mov  dx, 03C8h      ; DAC write index port
mov  al, N          ; color index to set
out  dx, al

mov  dx, 03C9h      ; DAC data port
mov  al, R          ; red   (0-63)
out  dx, al
mov  al, G          ; green (0-63)
out  dx, al
mov  al, B          ; blue  (0-63)
out  dx, al
```

Writing palette index 03C8h then three bytes to 03C9h automatically
advances to the next color slot, so loading the full palette is a tight loop.

### Default Palette

DOS sets up a default 256-color palette on mode set. The first 16 entries
match the classic CGA colors. For a starfield you'll want to define a
greyscale ramp or a blue-white gradient.

---

## Vertical Sync

Drawing directly to 0xA000 while the electron beam is scanning causes
**tearing** — you see a horizontal split where the old and new frame meet.

The fix: wait for VBlank before you start drawing.

```nasm
wait_vsync:
    mov  dx, 03DAh      ; VGA status register
.wait_notblank:
    in   al, dx
    test al, 08h        ; bit 3 = vertical retrace active
    jnz  .wait_notblank ; wait for it to END first (might be mid-blank)
.wait_blank:
    in   al, dx
    test al, 08h
    jz   .wait_blank    ; now wait for it to START
    ret
```

In a demo you typically:
1. Draw your frame into an **off-screen buffer** in normal RAM
2. Call `wait_vsync`
3. Copy the buffer to 0xA000 in one fast `REP MOVSB`

This gives you smooth, tear-free animation.

---

## Fast Buffer Copy

Copying 64,000 bytes from your back-buffer to VGA:

```nasm
; DS:SI  →  source buffer in regular RAM
; ES     →  0xA000 (set once at startup)

mov  si, backbuffer     ; source offset
xor  di, di             ; destination offset 0 in ES (= 0xA000:0000)
mov  cx, 32000          ; 32000 × 2 bytes = 64000 bytes
rep  movsw              ; copy word-by-word (faster than MOVSB)
```

---

## Clearing the Screen

```nasm
xor  di, di             ; start at offset 0
mov  cx, 32000
xor  ax, ax             ; color 0 (black)
rep  stosw              ; fill with AX, word by word
```

Or clear to any color by loading AL with the palette index and using
`rep stosb` (byte fill, CX = 64000).

---

## Pixel Address Formula

For 2D effects you'll compute pixel offsets constantly:

```
offset = y * 320 + x
```

Multiplying by 320 without `MUL` (which is slow):

```
320 = 256 + 64 = (y << 8) + (y << 6)
```

```nasm
; compute y*320 in AX, given y in BX
mov  ax, bx
shl  ax, 6          ; ax = y * 64
shl  bx, 8          ; bx = y * 256
add  ax, bx         ; ax = y * 320
add  ax, [x]        ; ax = y * 320 + x
```

No MUL needed, just shifts and adds.

---

Next: [03-dos-com-structure.md](03-dos-com-structure.md)
