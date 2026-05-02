org 100h

; == CONSTants - no memory alloc ==
  N_STARS     equ 200
  MAX_Z       equ 255
  STAR_SPEED  equ 2
  FOV         equ 200
  CENTER_X    equ 160
  CENTER_Y    equ 100
  SPREAD      equ 4096 ; +-64 in real coordinates (x64 fixed-point)

start:
  ; set vga mode
  mov ax, 0013h 
  int 10h 
  
  ; point ES at vga buffer
  mov ax, 0A000h
  mov es, ax

  ; --- effect code --- 
  call setup_palette
  call init_stars

.mainloop:
  ; check for keypress (non-blocking)
  mov ah, 01h 
  int 16h       ; sets ZF if no key waiting
  jnz .done     ; key pressed - exit loop
  
  ; mov cx, N_STARS
  ; mov si, 0 
  mov word  [star_offset], 0 
.star_loop:
  ; mov [star_offset], si
  call erase_star
  call move_star
  call draw_star
  ; add si, 6
  add word [star_offset], 6
  cmp word [star_offset], N_STARS * 6 
  ; loop .star_loop
  jl  .star_loop

  call wait_vsync
  jmp .mainloop

.done:
  xor ah, ah 
  int 16h       ; consume keypress

  ; restore to text mode  
  mov ax, 0003h 
  int 10h 

  ; exit cleanly
  mov ax, 4C00h ; AH=4Ch (treminate), AL=00h (exit code)
  int 21h 

setup_palette:
  mov dx, 03C8h   ; DAC write index port? start
  mov al, 1       ; start at 1 , 0 is black
  out dx, al 

  mov dx, 03C9h   ; DAC data port
  mov cx, 63      ; shades
  xor bx, bx
.loop:
  inc bx
  mov al, bl
  out dx, al      ; R
  out dx, al      ; G
  out dx, al      ; B
  loop  .loop
  ret             ; return
; ----
; -- Random number gen --
; returns 0..32767 in AX
rand:
  mov   ax, [rand_seed]
  imul  ax, 25173
  add   ax, 13849
  mov   [rand_seed], ax
  and   ax, 7FFFh   ; positive 15bit value
  ret

; --- init star 0 only ---
init_stars:
  mov cx, N_STARS
  mov si, 0 
.loop:
  call rand
  sub ax, 3FFFh         ; shift range to -16383..+16383
  mov [stars + si],  ax  ; X 

  call rand
  sub ax, 3FFFh
  mov [stars + si + 2], ax    ; Y 

  call rand 
  and ax, 7Fh 
  add ax, 20                  ; Z in range 20..147
  mov [stars + si + 4],  ax   ; Z = far away
  
  add si, 6                   ; next star (3 words = 6 bytes)
  loop .loop
  ret

; --- project and draw star 0 ---
draw_star:
  ; load X,Y,Z  
  mov bx, [star_offset]
  mov ax, [stars + bx]
  mov cx, [stars + bx + 2]
  mov si, [stars + bx + 4]
  mov bx, ax

  ; screen_x = (X * FOV) / (Z * 64) + CENTER_X
  mov   ax, bx
  mov   bx, FOV 
  imul  bx
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1     ; x6 -- DX:AX now divided by 64 
  idiv  si  
  add   ax, CENTER_X
  push  ax

  ; screen_y = (Y * FOV) / (Z * 64) + CENTER_Y
  mov   ax, cx
  mov   bx, FOV 
  imul  bx
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  idiv  si
  add   ax, CENTER_Y

  ; offset = screen_y * 320 + screen_x
  mov   bx, ax 
  shl   ax, 6 
  shl   bx, 8 
  add   ax, bx
  pop   bx        ; screen_x 
  add   ax, bx 

  mov   di, ax
  mov   byte [es:di], 63    ; draw at max brightness
  ret 

erase_star:
  mov bx, [star_offset]
  mov ax, [stars + bx]
  mov cx, [stars + bx + 2]
  mov si, [stars + bx + 4]
  mov bx, ax

  ; screen_x = (X * FOV) / (Z * 64) + CENTER_X
  mov   ax, bx
  mov   bx, FOV 
  imul  bx
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1
  sar   dx, 1 
  rcr   ax, 1     ; x6 -- DX:AX now divided by 64 
  idiv  si  
  add   ax, CENTER_X
  push  ax

  ; screen_y = (Y * FOV) / (Z * 64) + CENTER_Y
  mov   ax, cx
  mov   bx, FOV 
  imul  bx
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  sar   dx, 1 
  rcr   ax, 1 
  idiv  si
  add   ax, CENTER_Y

  ; offset = screen_y * 320 + screen_x
  mov   bx, ax 
  shl   ax, 6 
  shl   bx, 8 
  add   ax, bx
  pop   bx        ; screen_x 
  add   ax, bx 

  mov   di, ax
  mov   byte [es:di], 0    ; draw black
  ret 
; ---

move_star:
  mov bx, [star_offset]
  sub word [stars + bx + 4], STAR_SPEED
  cmp word [stars + bx + 4], 8   ; reset before Z gets close enough to cause overflow
  jg  .done

  ; reset star at back 
  call rand
  sub ax, 3FFFh
  mov [stars + bx],  ax    ; new x 

  call rand
  sub ax, 3FFFh
  mov [stars + bx + 2],  ax    ; new y 

  mov word  [stars + bx + 4],  MAX_Z

.done:
  ret

wait_vsync:
  mov dx, 03DAh
.notblank:
  in    al, dx
  test  al, 08h 
  jnz .notblank
.blank:
  in    al, dx
  test  al, 08h 
  jz .blank
  ret


; == data section (in same segment) ==
  stars times   N_STARS * 3 dw 0 ; 200 stars * 3 words..
  rand_seed     dw  0ACEh ; any non-zero number
  star_offset   dw  0 

