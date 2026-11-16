; ============================================================================
; PIXJAGD – "Pixelfehler-Jagd" fuer GeoWorks Ensemble 1.x (dt. 1.2.x)
; Code-Ressource (res2) der App-Geode. Gebaut mit tools/build_game.py:
;   nasm -f bin  -> Rohcode; jede Kernel-Ruf-Stelle (KC n) wird als
;   KERNEL/FAR_PTR-Relocation (Export-Nr. n des 1.x-Kernels) eingetragen.
; Aufrufkonvention der Methoden (wie BOUNCE 1.x): DS = dgroup, Rueckkehr RETF.
; Kernel-Nummern wurden aus BOUNCE/UHR/SPINTEXT/CRAZY/ICON-ED 1.x abgeleitet.
; ============================================================================
BITS 16
ORG 0

; ---- Kernel-Exportnummern (GEOS 1.x, Protokoll 622) ------------------------
K_GeodeGetProcessHandle equ 149
K_TimerStart            equ 182
K_TimerStop             equ 183
K_TimerGetCount         equ 186
K_GrTextWidth           equ 200
K_GrCreateState         equ 211
K_GrDestroyState        equ 212
K_GrDrawText            equ 330
K_GrFillRect            equ 336
K_GrSetAreaColor        equ 355
K_GrSetTextColor        equ 359
K_GrSetFont             equ 366
K_GrBeginUpdate         equ 446
K_ObjCallSuperNoLock    equ 489
K_GrEndUpdate           equ 447

MSG_TICK        equ 0C01h
TIMER_EVENT_ONE_SHOT equ 4
FONT_SANS       equ 1200h

; ---- Spielfeld -------------------------------------------------------------
PW      equ 480             ; Breite
PH      equ 320             ; Hoehe
HUDH    equ 24              ; HUD-Hoehe
SPR     equ 30              ; Sprite 10x10 Pixel, Faktor 3
SC      equ 3
MAXB    equ 10
BG      equ 0               ; schwarz
GAMESEC equ 60

; Bug-Struktur
B_ACT   equ 0   ; 0 frei, 1 lebt, 2 Splat
B_TYPE  equ 2   ; 0 normal 1 turbo 2 gold 3 bluescreen
B_X     equ 4
B_Y     equ 6
B_DX    equ 8
B_DY    equ 10
B_OX    equ 12
B_OY    equ 14
B_LIFE  equ 16
B_SIZE  equ 18

%assign KRC 0
%macro KC 1
    db 9Ah
..@KR_%[KRC]: dw %1, 0
%assign KRC KRC+1
%endmacro

; ---- dgroup-Variablen (liegen in res1 ab DBASE, vom Builder genullt) --------
absolute DBASE
v_win       resw 1
v_gs        resw 1
v_tmrId     resw 1
v_tmrHan    resw 1
v_state     resw 1      ; 0 Titel, 1 Spiel, 2 Ende
v_paused    resw 1
v_seed      resw 1
v_last      resw 1
v_elapsed   resw 1      ; Ticks (1/60 s) Spielzeit
v_score     resw 1
v_combo     resw 1
v_hits      resw 1
v_misses    resw 1
v_frame     resw 1
v_hud       resw 1      ; HUD neu zeichnen
v_redraw    resw 1      ; alles neu zeichnen
v_saying    resw 1      ; Offset (cs) des Spruchs
v_flash     resw 1      ; Bluescreen-Restdauer (Frames)
v_enddly    resw 1
v_secshown  resw 1
v_spawncd   resw 1
v_curcol    resw 1
v_pal       resw 1
v_tx        resw 1
v_ty        resw 1
v_delta     resw 1
v_nspawn    resw 1
v_numbuf    resb 8
v_bugs      resb MAXB*B_SIZE
v_end:

section .text
; ============================================================================
; Methoden-Einspruenge (Offsets landen in der Klassentabelle in res1)
; ============================================================================
; MSG 0049h (EXPOSED): CX = Fenster
M_Exposed:
    push bx
    push si
    push di
    push es
    cmp word [v_win], 0
    jne .have
    mov [v_win], cx
.have:
    mov di, [v_win]
    KC K_GrCreateState
    KC K_GrBeginUpdate
    mov [v_gs], di
    mov byte [v_curcol], 0FFh
    call DrawFull
    mov di, [v_gs]
    KC K_GrEndUpdate
    KC K_GrDestroyState
    cmp word [v_tmrHan], 0
    jne .x
    KC K_TimerGetCount
    mov [v_last], ax
    xor [v_seed], ax
    call ArmTimer
.x: pop es
    pop di
    pop si
    pop bx
    retf

; MSG 0057h (View-Fenster wird geschlossen): CX = Fenster
M_WinClosed:
    push ax
    push cx
    push dx
    push bp
    cmp cx, [v_win]
    jne .x
    mov word [v_win], 0
    call StopTimer
.x: pop bp
    pop dx
    pop cx
    pop ax
    push ds
    pop es
    mov di, CLASSOFF
    KC K_ObjCallSuperNoLock         ; wie BOUNCE: Superklasse informieren
    retf

; MSG 0A03h (CLOSE_APPLICATION): Timer stoppen, kein Zustandsblock
M_CloseApp:
    call StopTimer
    mov word [v_win], 0
    xor cx, cx
    retf

; MSG 0C00h (Spiel laeuft/Pause aus der Liste): CL = 0 -> Pause
M_Pause:
    xor ax, ax
    or cl, cl
    jnz .run
    inc ax
.run:
    mov [v_paused], ax
    cmp word [v_state], 1
    jne .x
    mov ax, s_pause
    cmp word [v_paused], 0
    jne .s
    mov ax, s_resume
.s: mov [v_saying], ax
    mov word [v_hud], 1
.x: retf

; MSG 00C3h (START_SELECT): CX,DX = Dokumentkoordinaten
M_Click:
    push bx
    push si
    push di
    mov ax, [v_state]
    cmp ax, 1
    je .play
    cmp ax, 2
    jne .start
    cmp word [v_enddly], 0
    jne .done
.start:
    call StartGame
    jmp .done
.play:
    cmp word [v_paused], 0
    jne .done
    cmp word [v_flash], 0
    jne .done
    cmp dx, HUDH
    jl .done
    ; von oben (zuletzt gezeichnet) nach unten suchen
    mov si, v_bugs + (MAXB-1)*B_SIZE
    mov bx, MAXB
.lp:
    cmp word [si+B_ACT], 1
    jne .nx
    mov ax, [si+B_X]
    sub ax, 3
    cmp cx, ax
    jl .nx
    add ax, SPR+6
    cmp cx, ax
    jge .nx
    mov ax, [si+B_Y]
    sub ax, 3
    cmp dx, ax
    jl .nx
    add ax, SPR+6
    cmp dx, ax
    jge .nx
    call HitBug
    jmp .done
.nx:
    sub si, B_SIZE
    dec bx
    jnz .lp
    ; daneben
    inc word [v_misses]
    mov word [v_combo], 1
    mov ax, NMISS
    call Rand
    shl ax, 1
    mov bx, ax
    mov ax, [cs:missTab+bx]
    mov [v_saying], ax
    mov word [v_hud], 1
.done:
    pop di
    pop si
    pop bx
    mov ax, 8000h           ; MRF_PROCESSED
    retf

; MSG 0C01h (Timer-Tick)
M_Tick:
    push bx
    push si
    push di
    push es
    mov word [v_tmrHan], 0  ; One-Shot ist abgelaufen
    cmp word [v_win], 0
    je .out
    KC K_TimerGetCount
    mov dx, ax
    sub ax, [v_last]
    mov [v_last], dx
    cmp ax, 30
    jbe .dok
    mov ax, 30              ; nach langer Pause nicht springen
.dok:
    mov [v_delta], ax
    mov di, [v_win]
    KC K_GrCreateState
    mov [v_gs], di
    mov byte [v_curcol], 0FFh
    cmp word [v_redraw], 0
    je .nored
    call DrawFull
.nored:
    mov ax, [v_state]
    cmp ax, 1
    je .play
    ; Titel / Ende: Ueberschrift in Regenbogenfarben
    cmp word [v_enddly], 0
    je .nodly
    dec word [v_enddly]
.nodly:
    test word [v_frame], 3
    jnz .fin
    call DrawBigTitle
    test word [v_frame], 15
    jnz .fin
    cmp word [v_state], 0
    jne .fin
    call DrawLegend
    jmp .fin
.play:
    cmp word [v_paused], 0
    jne .hud
    cmp word [v_flash], 0
    je .noflash
    dec word [v_flash]
    jnz .fin
    mov word [v_redraw], 1  ; Bluescreen vorbei -> naechster Tick zeichnet neu
    jmp .fin
.noflash:
    mov ax, [v_delta]
    add [v_elapsed], ax
    ; Restzeit
    mov ax, [v_elapsed]
    xor dx, dx
    mov cx, 60
    div cx
    mov cx, GAMESEC
    sub cx, ax
    jg .tok
    call EndGame
    jmp .fin
.tok:
    cmp cx, [v_secshown]
    je .ts
    mov [v_secshown], cx
    mov word [v_hud], 1
.ts:
    call Spawner
    call UpdateBugs
.hud:
    cmp word [v_hud], 0
    je .fin
    call DrawHud
.fin:
    mov di, [v_gs]
    KC K_GrDestroyState
    inc word [v_frame]
    call ArmTimer
.out:
    pop es
    pop di
    pop si
    pop bx
    retf

; ============================================================================
; Timer
; ============================================================================
ArmTimer:
    cmp word [v_win], 0
    je .x
    KC K_GeodeGetProcessHandle      ; -> BX
    xor si, si
    mov al, TIMER_EVENT_ONE_SHOT
    mov cx, 2
    mov dx, MSG_TICK
    xor di, di
    KC K_TimerStart                 ; -> AX id, BX handle
    mov [v_tmrId], ax
    mov [v_tmrHan], bx
.x: ret

StopTimer:
    mov bx, [v_tmrHan]
    or bx, bx
    jz .x
    mov ax, [v_tmrId]
    KC K_TimerStop
    mov word [v_tmrHan], 0
.x: ret

; ============================================================================
; Spiellogik
; ============================================================================
StartGame:
    mov di, v_bugs
    mov cx, MAXB*B_SIZE/2
.cl: mov word [di], 0
    add di, 2
    loop .cl
    xor ax, ax
    mov [v_score], ax
    mov [v_hits], ax
    mov [v_misses], ax
    mov [v_elapsed], ax
    mov [v_flash], ax
    mov [v_spawncd], ax
    mov word [v_secshown], 0FFFFh
    mov word [v_combo], 1
    mov word [v_state], 1
    mov word [v_saying], s_go
    mov word [v_redraw], 1
    mov word [v_hud], 1
    KC K_TimerGetCount
    xor [v_seed], ax
    ret

EndGame:
    mov word [v_state], 2
    mov word [v_redraw], 1
    mov word [v_enddly], 30
    ret

; Zufall (xorshift16): AX = n -> AX in [0,n)
Rand:
    push bx
    push cx
    push dx
    mov bx, ax
    mov ax, [v_seed]
    or ax, ax
    jnz .s
    mov ax, 0ACE1h
.s: mov dx, ax
    mov cl, 7
    shl dx, cl
    xor ax, dx
    mov dx, ax
    mov cl, 9
    shr dx, cl
    xor ax, dx
    mov dx, ax
    mov cl, 8
    shl dx, cl
    xor ax, dx
    mov [v_seed], ax
    xor dx, dx
    div bx
    mov ax, dx
    pop dx
    pop cx
    pop bx
    ret

; Treffer auf Bug DS:SI
HitBug:
    inc word [v_hits]
    mov ax, [si+B_TYPE]
    cmp ax, 3
    jne .good
    ; Bluescreen-Bug!
    mov word [si+B_ACT], 0
    sub word [v_score], 25
    jns .bs1
    mov word [v_score], 0
.bs1:
    dec word [v_hits]
    inc word [v_misses]
    mov word [v_combo], 1
    mov word [v_flash], 45
    mov word [v_saying], s_blue
    mov word [v_hud], 1
    call DrawBluescreen
    ret
.good:
    mov bx, ax
    shl bx, 1
    mov ax, [cs:typePts+bx]
    mul word [v_combo]
    add [v_score], ax
    mov word [si+B_ACT], 2
    mov word [si+B_LIFE], 8
    ; Spruch
    cmp word [si+B_TYPE], 2
    jne .nogold
    mov word [v_saying], s_gold
    jmp .cmb
.nogold:
    cmp word [v_combo], 3
    jb .rnd
    mov word [v_saying], 0FFFFh     ; Combo-Anzeige
    jmp .cmb
.rnd:
    mov ax, NHIT
    call Rand
    shl ax, 1
    mov bx, ax
    mov ax, [cs:hitTab+bx]
    mov [v_saying], ax
.cmb:
    cmp word [v_combo], 5
    jae .c5
    inc word [v_combo]
.c5:
    mov word [v_hud], 1
    ; Splat sofort zeichnen
    push si
    call MakeGS
    pop si
    mov ax, [si+B_X]
    mov bx, [si+B_Y]
    mov word [v_pal], palSplat
    mov si, spr_splat
    call DrawSprite
    call FreeGS
    ret

; temporaerer GState ausserhalb des Ticks
MakeGS:
    mov di, [v_win]
    KC K_GrCreateState
    mov [v_gs], di
    mov byte [v_curcol], 0FFh
    ret
FreeGS:
    mov di, [v_gs]
    KC K_GrDestroyState
    ret

DrawBluescreen:
    cmp word [v_win], 0
    je .x
    call MakeGS
    call DrawBlueScr
    call FreeGS
.x: ret

; Neue Bugs erzeugen
Spawner:
    cmp word [v_spawncd], 0
    je .go
    dec word [v_spawncd]
    ret
.go:
    ; level = elapsed/600 (0..5)
    mov ax, [v_elapsed]
    xor dx, dx
    mov cx, 600
    div cx
    mov bp, ax
    ; Ziel = 3 + elapsed/480
    mov ax, [v_elapsed]
    xor dx, dx
    mov cx, 480
    div cx
    add ax, 3
    cmp ax, MAXB
    jbe .t
    mov ax, MAXB
.t: mov cx, ax
    ; lebende zaehlen, freien Slot suchen
    xor dx, dx
    xor di, di
    mov si, v_bugs
    mov bx, MAXB
.lp:
    cmp word [si+B_ACT], 0
    jne .busy
    or di, di
    jnz .nx
    mov di, si
    jmp .nx
.busy:
    inc dx
.nx:
    add si, B_SIZE
    dec bx
    jnz .lp
    cmp dx, cx
    jae .x
    or di, di
    jz .x
    mov si, di
    ; Cooldown
    mov ax, bp
    shl ax, 1
    mov cx, 22
    sub cx, ax
    mov [v_spawncd], cx
    ; Typ
    mov ax, 100
    call Rand
    mov bx, 2               ; gold
    cmp ax, 7
    jb .ty
    mov bx, 3               ; bluescreen
    cmp ax, 19
    jb .ty
    mov bx, 1               ; turbo
    cmp ax, 40
    jb .ty
    xor bx, bx
.ty:
%ifdef TESTFREEZE
    mov bx, [v_nspawn]             ; Testvariante: Typen reihum 3,2,1,0
    inc word [v_nspawn]
    not bx
    and bx, 3
%endif
    mov [si+B_TYPE], bx
    shl bx, 1
    mov ax, [cs:typeLife+bx]
%ifdef TESTFREEZE
    xor ax, ax                     ; Testvariante: niemand haut ab
%endif
    mov [si+B_LIFE], ax
    ; Geschwindigkeit = Basis + Zufall(2) + level/2
    mov ax, 2
    call Rand
    add ax, [cs:typeSpeed+bx]
    mov cx, bp
    shr cx, 1
    add ax, cx
    mov cx, ax
    push cx
    mov ax, 2
    call Rand
    pop cx
    or ax, ax
    jz .p1
    neg cx
.p1: mov [si+B_DX], cx
    mov ax, 3
    call Rand
    push ax
    mov ax, [si+B_DX]
    or ax, ax
    jns .ab
    neg ax
.ab:
    pop cx
    ; dy = |dx| - zufall(3) (min 1) mit zufaelligem Vorzeichen
    sub ax, cx
    jg .d1
    mov ax, 1
.d1: mov cx, ax
    push cx
    mov ax, 2
    call Rand
    pop cx
    or ax, ax
    jz .p2
    neg cx
.p2: mov [si+B_DY], cx
    ; Position
    mov ax, PW-SPR
    call Rand
    mov [si+B_X], ax
    mov [si+B_OX], ax
    mov ax, PH-SPR-HUDH-2
    call Rand
    add ax, HUDH+2
    mov [si+B_Y], ax
    mov [si+B_OY], ax
    mov word [si+B_ACT], 1
%ifdef TESTFREEZE
    mov word [si+B_DX], 0          ; Testvariante: Bugs stehen still
    mov word [si+B_DY], 0
%endif
.x: ret

; Bugs bewegen und zeichnen
UpdateBugs:
    mov si, v_bugs
    mov cx, MAXB
.lp:
    push cx
    push si
    mov ax, [si+B_ACT]
    or ax, ax
    jz .nx
    cmp ax, 2
    jne .alive
    dec word [si+B_LIFE]
    jnz .nx
    mov word [si+B_ACT], 0
    mov ax, [si+B_X]
    mov bx, [si+B_Y]
    mov cx, ax
    add cx, SPR
    mov dx, bx
    add dx, SPR
    call FillBG
    jmp .nx
.alive:
    mov ax, [si+B_LIFE]
    or ax, ax
    jz .move
    dec word [si+B_LIFE]
    jnz .move
    ; Lebenszeit um -> verschwinden
    mov word [si+B_ACT], 0
    cmp word [si+B_TYPE], 2
    jne .gone
    mov word [v_saying], s_goldgone
    mov word [v_hud], 1
    mov word [v_combo], 1
.gone:
    mov ax, [si+B_X]
    mov bx, [si+B_Y]
    mov cx, ax
    add cx, SPR
    mov dx, bx
    add dx, SPR
    call FillBG
    jmp .nx
.move:
    ; gelegentlich Richtung wechseln
%ifdef TESTFREEZE
    jmp .nt2
%endif
    mov ax, 40
    call Rand
    or ax, ax
    jnz .nt
    neg word [si+B_DX]
.nt:
    mov ax, 40
    call Rand
    or ax, ax
    jnz .nt2
    neg word [si+B_DY]
.nt2:
    mov ax, [si+B_X]
    add ax, [si+B_DX]
    jns .xl
    xor ax, ax
    neg word [si+B_DX]
.xl:
    cmp ax, PW-SPR
    jle .xr
    mov ax, PW-SPR
    neg word [si+B_DX]
.xr:
    mov [si+B_X], ax
    mov ax, [si+B_Y]
    add ax, [si+B_DY]
    cmp ax, HUDH+2
    jge .yt
    mov ax, HUDH+2
    neg word [si+B_DY]
.yt:
    cmp ax, PH-SPR
    jle .yb
    mov ax, PH-SPR
    neg word [si+B_DY]
.yb:
    mov [si+B_Y], ax
    call EraseTrail
    ; Animationsphase
    mov bx, [si+B_TYPE]
    shl bx, 1
    mov dx, [cs:typePal+bx]
    mov [v_pal], dx
    mov ax, [v_frame]
    shr ax, 1
    shr ax, 1
    mov dx, si
    shr dx, 1
    add ax, dx              ; Beinphase je Bug versetzt
    mov di, spr_bugA
    test al, 1
    jz .fa
    mov di, spr_bugB
.fa:
    mov ax, [si+B_X]
    mov bx, [si+B_Y]
    mov [si+B_OX], ax
    mov [si+B_OY], bx
    mov si, di
    call DrawSprite
.nx:
    pop si
    pop cx
    add si, B_SIZE
    dec cx
    jnz .lp
    ret

; Altes Rechteck minus neues Rechteck loeschen (DS:SI = Bug)
EraseTrail:
    mov ax, [si+B_OX]
    mov bx, [si+B_OY]
    mov cx, [si+B_X]
    cmp cx, ax
    je .ny
    jg .right
    ; nach links: Streifen [x+SPR, ox+SPR)
    add cx, SPR
    mov ax, cx
    mov cx, [si+B_OX]
    add cx, SPR
    jmp .hx
.right:
    ; nach rechts: Streifen [ox, x)
.hx:
    mov dx, bx
    add dx, SPR
    push si
    call FillBG
    pop si
.ny:
    mov ax, [si+B_OX]
    mov bx, [si+B_OY]
    mov dx, [si+B_Y]
    cmp dx, bx
    je .x
    jg .down
    add dx, SPR
    mov bx, dx
    mov dx, [si+B_OY]
    add dx, SPR
    jmp .hy
.down:
.hy:
    mov cx, ax
    add cx, SPR
    push si
    call FillBG
    pop si
.x: ret

; ============================================================================
; Zeichnen (DI wird aus v_gs geholt)
; ============================================================================
; AX,BX,CX,DX Rechteck in Hintergrundfarbe
FillBG:
    push ax
    mov al, BG
    call SetArea
    pop ax
    mov di, [v_gs]
    KC K_GrFillRect
    ret

; AL = Farbe (nur setzen, wenn anders)
SetArea:
    cmp al, [v_curcol]
    je .x
    mov [v_curcol], al
    mov di, [v_gs]
    xor ah, ah
    KC K_GrSetAreaColor
.x: ret

; Rechteck AX,BX,CX,DX in Farbe [v_tx]
FillCol:
    push ax
    mov al, [v_tx]
    mov byte [v_curcol], 0FFh
    call SetArea
    pop ax
    mov di, [v_gs]
    KC K_GrFillRect
    ret

; Sprite: CS:SI Runs, AX,BX = Position, [v_pal] = Palette (cs)
DrawSprite:
    mov [v_tx], ax
    mov [v_ty], bx
    mov byte [v_curcol], 0FFh
.lp:
    mov al, [cs:si]
    cmp al, 0FFh
    je .x
    ; Farbe
    mov bl, [cs:si+3]
    xor bh, bh
    add bx, [v_pal]
    mov al, [cs:bx]
    call SetArea
    ; top = ty + row*3
    mov al, [cs:si]
    xor ah, ah
    mov bx, ax
    shl ax, 1
    add ax, bx
    add ax, [v_ty]
    mov bx, ax
    mov dx, ax
    add dx, SC
    ; left = tx + col*3
    mov al, [cs:si+1]
    xor ah, ah
    mov cx, ax
    shl ax, 1
    add ax, cx
    add ax, [v_tx]
    ; right = left + len*3
    mov cl, [cs:si+2]
    xor ch, ch
    push ax
    mov ax, cx
    shl ax, 1
    add cx, ax
    pop ax
    add cx, ax
    push si
    mov di, [v_gs]
    KC K_GrFillRect
    pop si
    add si, 4
    jmp .lp
.x: ret

; Text: CS:SI String, AX,BX Position, CL Farbe, DX Groesse
Text:
    push ax
    push bx
    push si
    mov di, [v_gs]
    push cx
    mov cx, FONT_SANS
    xor ah, ah
    KC K_GrSetFont
    pop ax
    xor ah, ah
    KC K_GrSetTextColor
    pop si
    pop bx
    pop ax
    push ds
    push cs
    pop ds
    xor cx, cx
    KC K_GrDrawText
    pop ds
    ret

; zentrierter Text: CS:SI, BX = y, CL Farbe, DX Groesse
TextC:
    push bx
    push cx
    push si
    mov di, [v_gs]
    mov cx, FONT_SANS
    xor ah, ah
    KC K_GrSetFont
    push dx
    push ds
    push cs
    pop ds
    mov cx, 0FFFFh
    KC K_GrTextWidth            ; -> DX
    pop ds
    mov ax, PW
    sub ax, dx
    sar ax, 1
    pop dx
    pop si
    pop cx
    pop bx
    jmp Text

; Zahl AX -> ds:v_numbuf (dezimal), zeichnen bei [v_tx],[v_ty]
DrawNum:
    call NumStr
    mov di, [v_gs]
    mov ax, [v_tx]
    mov bx, [v_ty]
    xor cx, cx
    KC K_GrDrawText
    ret

; Zahl AX -> DS:SI (nullterminiert in v_numbuf)
NumStr:
    mov di, v_numbuf+7
    mov byte [di], 0
    mov cx, 10
.lp:
    xor dx, dx
    div cx
    add dl, '0'
    dec di
    mov [di], dl
    or ax, ax
    jnz .lp
    mov si, di
    ret

DrawFull:
    mov word [v_redraw], 0
    mov byte [v_curcol], 0FFh
    mov ax, [v_state]
    cmp ax, 1
    je .play
    ; Hintergrund
    mov al, BG
    call SetArea
    xor ax, ax
    xor bx, bx
    mov cx, PW
    mov dx, PH
    mov di, [v_gs]
    KC K_GrFillRect
    cmp word [v_state], 2
    je .end
    call DrawTitleScr
    ret
.end:
    call DrawEndScr
    ret
.play:
    cmp word [v_flash], 0
    je .pl
    call DrawBlueScr
    ret
.pl:
    mov al, BG
    call SetArea
    xor ax, ax
    mov bx, HUDH
    mov cx, PW
    mov dx, PH
    mov di, [v_gs]
    KC K_GrFillRect
    call DrawHud
    ; Bugs neu zeichnen (Position = alte Position)
    ret

DrawHud:
    mov word [v_hud], 0
    mov byte [v_tx], 7
    xor ax, ax
    xor bx, bx
    mov cx, PW
    mov dx, HUDH
    call FillCol
    mov byte [v_tx], 8
    xor ax, ax
    mov bx, HUDH-2
    mov cx, PW
    mov dx, HUDH
    call FillCol
    mov si, s_pts
    mov ax, 6
    mov bx, 4
    mov cl, 1
    mov dx, 12
    call Text
    mov word [v_tx], 56
    mov word [v_ty], 4
    mov ax, [v_score]
    call DrawNum
    mov si, s_time
    mov ax, 110
    mov bx, 4
    mov cl, 1
    mov dx, 12
    call Text
    mov word [v_tx], 145
    mov word [v_ty], 4
    mov ax, [v_secshown]
    cmp ax, GAMESEC
    jbe .tv
    mov ax, GAMESEC
.tv:
    call DrawNum
    ; Spruch
    mov si, [v_saying]
    cmp si, 0FFFFh
    jne .say
    mov si, s_combo
    mov ax, 185
    mov bx, 4
    mov cl, 4
    mov dx, 12
    call Text
    mov word [v_tx], 233
    mov word [v_ty], 4
    mov ax, [v_combo]
    call DrawNum
    ret
.say:
    or si, si
    jz .x
    mov ax, 185
    mov bx, 4
    mov cl, 4
    mov dx, 12
    call Text
.x: ret

DrawBigTitle:
    mov ax, [v_frame]
    shr ax, 1
    shr ax, 1
    and ax, 7
    add al, 9               ; Farben 9..15 (+16 -> 9)
    cmp al, 16
    jb .c
    mov al, 12
.c: mov cl, al
    mov si, s_title
    mov bx, 18
    cmp word [v_state], 2
    jne .t
    mov si, s_end
    mov bx, 30
.t: mov dx, 36
    call TextC
    ret

DrawTitleScr:
    call DrawBigTitle
    mov si, s_t1
    mov bx, 70
    mov cl, 15
    mov dx, 14
    call TextC
    mov si, s_t2
    mov bx, 90
    mov cl, 15
    mov dx, 14
    call TextC
    mov si, s_t3
    mov bx, 262
    mov cl, 11
    mov dx, 12
    call TextC
    mov si, s_start
    mov bx, 288
    mov cl, 14
    mov dx, 14
    call TextC
    call DrawLegend
    mov si, s_l1
    mov ax, 150
    mov bx, 128
    mov cl, 12
    mov dx, 12
    call Text
    mov si, s_l2
    mov ax, 150
    mov bx, 160
    mov cl, 13
    mov dx, 12
    call Text
    mov si, s_l3
    mov ax, 150
    mov bx, 192
    mov cl, 14
    mov dx, 12
    call Text
    mov si, s_l4
    mov ax, 150
    mov bx, 224
    mov cl, 9
    mov dx, 12
    call Text
    ret

; vier Beispiel-Bugs, Beine wackeln
DrawLegend:
    xor bp, bp
.lp:
    push bp
    mov bx, bp
    shl bx, 1
    mov ax, [cs:typePal+bx]
    mov [v_pal], ax
    mov si, spr_bugA
    test word [v_frame], 16
    jz .a
    mov si, spr_bugB
.a: mov ax, bp
    mov cl, 5
    shl ax, cl              ; *32
    add ax, 120
    mov bx, ax
    mov ax, 105
    call DrawSprite
    pop bp
    inc bp
    cmp bp, 4
    jb .lp
    ret

DrawEndScr:
    call DrawBigTitle
    mov si, s_endpts
    mov bx, 100
    mov cl, 15
    mov dx, 24
    call TextC
    ; Zahl zentriert unter "Punkte"
    mov di, [v_gs]
    mov al, 14
    xor ah, ah
    KC K_GrSetTextColor
    mov ax, [v_score]
    call NumStr
    mov di, [v_gs]
    mov cx, 0FFFFh
    KC K_GrTextWidth
    mov ax, PW
    sub ax, dx
    sar ax, 1
    mov bx, 130
    xor cx, cx
    KC K_GrDrawText
    ; Bewertung
    mov ax, [v_score]
    mov si, s_r1
    cmp ax, 100
    jb .r
    mov si, s_r2
    cmp ax, 300
    jb .r
    mov si, s_r3
    cmp ax, 600
    jb .r
    mov si, s_r4
.r: mov bx, 175
    mov cl, 10
    mov dx, 18
    call TextC
    mov si, s_hits
    mov ax, 150
    mov bx, 210
    mov cl, 7
    mov dx, 12
    call Text
    mov word [v_tx], 205
    mov word [v_ty], 210
    mov ax, [v_hits]
    call DrawNum
    mov si, s_miss
    mov ax, 240
    mov bx, 210
    mov cl, 7
    mov dx, 12
    call Text
    mov word [v_tx], 325
    mov word [v_ty], 210
    mov ax, [v_misses]
    call DrawNum
    mov si, s_endfun
    mov bx, 240
    mov cl, 13
    mov dx, 14
    call TextC
    mov si, s_again
    mov bx, 285
    mov cl, 14
    mov dx, 14
    call TextC
    ret

DrawBlueScr:
    mov byte [v_tx], 1
    xor ax, ax
    mov bx, HUDH
    mov cx, PW
    mov dx, PH
    call FillCol
    mov byte [v_tx], 7
    mov ax, 205
    mov bx, 70
    mov cx, 275
    mov dx, 90
    call FillCol
    mov si, s_bs0
    mov bx, 72
    mov cl, 1
    mov dx, 14
    call TextC
    mov si, s_bs1
    mov ax, 40
    mov bx, 120
    mov cl, 15
    mov dx, 14
    call Text
    mov si, s_bs2
    mov ax, 40
    mov bx, 145
    mov cl, 15
    mov dx, 14
    call Text
    mov si, s_bs3
    mov ax, 40
    mov bx, 190
    mov cl, 15
    mov dx, 14
    call Text
    mov si, s_bs4
    mov ax, 40
    mov bx, 215
    mov cl, 15
    mov dx, 14
    call Text
    ret

; ============================================================================
; Konstanten
; ============================================================================
typePts:   dw 10, 20, 50, 0
typeSpeed: dw 1, 3, 5, 1
typeLife:  dw 0, 0, 80, 140
typePal:   dw palNorm, palTurbo, palGold, palBlue
;            bg  body dots head eye legs  Y   W
palNorm:  db 0, 12,  0,   8,  15, 7,   14, 15
palTurbo: db 0, 13,  5,   8,  14, 7,   14, 15
palGold:  db 0, 14,  6,   6,  15, 14,  14, 15
palBlue:  db 0, 9,   15,  1,  15, 11,  14, 15
palSplat: db 0, 12,  0,   8,  15, 7,   14, 15

%include "sprites.inc"
%include "strings.inc"
