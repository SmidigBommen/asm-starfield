# x86 Real Mode — Registers Refresh

A quick mental model reset before writing any code. You've seen this before,
so this is a map, not a lecture.

---

## General Purpose Registers

Each is 16-bit. The A/B/C/D registers split into high and low bytes.

```
AX  [AH | AL]   Accumulator     — math, I/O, return values
BX  [BH | BL]   Base            — often used as a memory pointer
CX  [CH | CL]   Counter         — LOOP instruction, REP prefix
DX  [DH | DL]   Data            — I/O port addresses, mul/div overflow
```

SI — Source Index      (string ops, general pointer)
DI — Destination Index (string ops, general pointer)
BP — Base Pointer      (stack frame base, but we'll rarely use it)
SP — Stack Pointer     (top of stack, don't clobber it)

---

## Segment Registers

Real mode uses a `segment:offset` address scheme.

```
Physical address = (segment × 16) + offset
```

```
CS  Code Segment    — where instructions live (IP walks through this)
DS  Data Segment    — default for most memory reads/writes
ES  Extra Segment   — second data window; we'll point this at 0xA000 (VGA)
SS  Stack Segment   — where SP/BP live
```

In a `.COM` file, **all four segments start at the same value** — DOS loads
everything into one segment. That simplifies life enormously.

---

## Instruction Pointer & Flags

```
IP      Points to the next instruction (you never set this directly)
FLAGS   Status bits set by ALU operations
```

Key flags you'll use:

| Flag | Name     | Set when...                        |
|------|----------|------------------------------------|
| ZF   | Zero     | result == 0                        |
| CF   | Carry    | unsigned overflow / borrow         |
| SF   | Sign     | result is negative                 |
| OF   | Overflow | signed overflow                    |

Conditional jumps check these: `JE` (ZF=1), `JNE` (ZF=0), `JL` (SF≠OF), etc.

---

## Instructions You'll Use Most

```nasm
MOV  dst, src       ; copy
ADD  dst, src       ; dst += src
SUB  dst, src       ; dst -= src
IMUL src            ; AX = AX * src  (signed)
IDIV src            ; AX = DX:AX / src, DX = remainder (signed)
SHL  dst, n         ; shift left  (multiply by 2^n)
SAR  dst, n         ; shift right arithmetic (divide by 2^n, keeps sign)

CMP  a, b           ; sets flags for a - b (doesn't store result)
JMP  label
JE   label          ; jump if equal      (ZF=1)
JNE  label          ; jump if not equal
JL   label          ; jump if less than  (signed)
JG   label          ; jump if greater    (signed)
LOOP label          ; CX -= 1, jump if CX != 0

PUSH reg            ; SP -= 2, write reg to [SS:SP]
POP  reg            ; read [SS:SP] into reg, SP += 2

INT  n              ; software interrupt (BIOS/DOS calls)
```

---

## Calling DOS / BIOS

Everything goes through `INT`:

```nasm
INT 10h     ; BIOS video services
INT 21h     ; DOS services
INT 08h     ; Timer (IRQ0, fires ~18.2× per second)
```

You set registers before the call to pass arguments, read registers after for
return values. Example — exit to DOS:

```nasm
mov  ah, 4Ch        ; DOS function: terminate
mov  al, 0          ; exit code
int  21h
```

---

## Addressing Modes (the ones that matter)

```nasm
mov  ax, 42         ; immediate: load the number 42
mov  ax, bx         ; register: copy BX into AX
mov  ax, [bx]       ; memory indirect: read word at address in BX
mov  ax, [bx + si]  ; base + index: useful for 2D array indexing
mov  ax, [myvar]    ; direct: read from a named label
```

---

## Fixed-Point Math (no FPU in our demo)

We have no floating-point hardware available (or we ignore it on purpose).
Division is slow and awkward. The trick: **scale integers by a power of 2**.

Use 8 bits of fraction: multiply your "real" values by 256.

```
0.5  →  128     (128 >> 8 == 0)
1.75 →  448     (448 >> 8 == 1)
```

Multiply two fixed-point values → result is scaled by 256², shift right 8 to
correct. We'll revisit this in the starfield doc with concrete examples.

---

Next: [02-vga-mode13h.md](02-vga-mode13h.md)
