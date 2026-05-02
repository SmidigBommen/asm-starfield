# DOS .COM File Structure

A `.COM` file is the simplest executable format DOS supports.
No headers, no segments table — just raw machine code loaded at offset 0x100.

---

## Why 0x100?

When DOS loads a `.COM` file it first fills the first 256 bytes (0x000–0x0FF)
of the segment with the **PSP** (Program Segment Prefix) — a small structure
DOS uses to pass environment info, command-line arguments, and file handles.

Your code starts immediately after, at offset **0x100**.

Tell NASM about this:

```nasm
org  100h
```

This is always the first line of a `.COM` source file. It tells the assembler
that label addresses start at 0x100, so forward references come out correct.

---

## All Segments Are the Same

In a `.COM` file, DOS loads everything into **one segment**:

```
CS = DS = ES = SS = (the segment DOS picked)
```

You don't set up segments yourself. The only exception: for VGA we manually
point **ES** to 0xA000. Everything else (your variables, your stack, your
code) lives in the same segment you started in.

---

## Stack

DOS gives you a stack automatically. SP starts somewhere around 0xFFFE and
grows downward. You don't need to set it up. Just don't blow past your data
with a deep call chain — in a demo this is rarely an issue.

---

## Minimal .COM Template

```nasm
org  100h

start:
    ; === your code here ===

    ; exit cleanly
    mov  ax, 4C00h      ; AH=4Ch (terminate), AL=00 (exit code)
    int  21h

; === data section (lives after code in the same segment) ===
myvar dw 0
```

That's the entire boilerplate. No `.section`, no linker script, no entry
point declaration beyond the label at the top.

---

## Assembling and Running

On macOS, assemble with NASM:

```bash
nasm -f bin demo.asm -o demo.com
```

`-f bin` = raw binary output, no file format wrapping.

In DOSBox-X, mount your project folder and run it:

```
MOUNT C /path/to/asm-demo1
C:
CD SRC
DEMO.COM
```

Or add a `dosbox-x.conf` (we'll do this later) that auto-mounts on launch.

---

## Checking Your Output

```bash
ndisasm -b 16 -o 100h demo.com | head -30
```

`ndisasm` ships with NASM. `-b 16` = 16-bit mode, `-o 100h` = pretend
the file starts at offset 0x100. Useful for debugging when something jumps
to the wrong place.

---

## Data Declarations

```nasm
myword  dw  0           ; 16-bit word, initialized to 0
mybyte  db  255         ; 8-bit byte
myarray db  64 dup(0)   ; 64 bytes, all zero
mystr   db  'hello', 0  ; null-terminated string
```

Variables declared after your code are in the same segment. Access them
with their label name — NASM resolves the offset automatically.

```nasm
mov  ax, [myword]       ; read it
mov  [myword], ax       ; write it
```

---

## A Complete "Set Mode and Exit" Skeleton

This is the foundation every demo in this project will build on:

```nasm
org  100h

start:
    ; set VGA mode 13h
    mov  ax, 0013h
    int  10h

    ; point ES at VGA framebuffer
    mov  ax, 0A000h
    mov  es, ax

    ; ---- effect code goes here ----

    ; wait for a keypress before exiting
    xor  ah, ah
    int  16h            ; BIOS keyboard: wait for key

    ; restore text mode
    mov  ax, 0003h
    int  10h

    ; exit to DOS
    mov  ax, 4C00h
    int  21h
```

We'll paste this into `src/starfield.asm` as our starting point.

---

Next: [04-starfield.md](04-starfield.md)
