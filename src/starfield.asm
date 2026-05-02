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
  
  call erase_star
  call move_star
  call draw_star
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
  call rand
  sub ax, 3FFFh         ; shift range to -16383..+16383
  mov [stars + 0],  ax  ; X 

  call rand
  sub ax, 3FFFh
  mov [stars + 2], ax    ; Y 

  mov word  [stars + 4],  MAX_Z ; Z = far away
  ret

; --- project and draw star 0 ---
draw_star:
  ; load X,Y,Z  
  mov bx, [stars + 0]
  mov cx, [stars + 2]
  mov si, [stars + 4]

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
  ; --- project and draw star 0 ---
  mov bx, [stars + 0]
  mov cx, [stars + 2]
  mov si, [stars + 4]

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
  sub word [stars + 4], STAR_SPEED
  cmp word [stars + 4], 8   ; reset before Z gets close enough to cause overflow
  jg  .done

  ; reset star at back 
  call rand
  sub ax, 3FFFh
  mov [stars + 0],  ax    ; new x 

  call rand
  sub ax, 3FFFh
  mov [stars + 2],  ax    ; new y 

  mov word  [stars + 4],  MAX_Z

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
  jnz .blank
  ret


; == data section (in same segment) ==
  stars times   N_STARS * 3 dw 0 ; 200 stars * 3 words..
  rand_seed     dw  0ACEh ; any non-zero number
