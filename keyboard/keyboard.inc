
cseg 
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99
    DB 0x92, 0x82, 0xF8, 0x80, 0x90
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E

; --- Macros from Keypad File ---
showBCD MAC
    mov A, %0
    anl a, #0fh
    movc A, @A+dptr
    mov %1, A
    mov A, %0
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov %2, A
ENDMAC

MYRLC MAC
    mov a, %0
    rlc a
    mov %0, a
ENDMAC

MYRRC MAC
    mov a, %0
    rrc a
    mov %0, a
ENDMAC

; Modified: key detected -> go validate/handle E/F/digit in one place
CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M
    mov R7, %1
    jnb %0, $ 
    setb c
    ljmp Keypad_HandleKey
CHECK_COL_%M:
ENDMAC


Configure_Keypad_Pins:
    orl P1MOD, #0b_01010100 ; P1.6, P1.4, P1.2 output
    orl P2MOD, #0b_00000001 ; P2.0 output
    anl P2MOD, #0b_10101011 ; P2.6, P2.4, P2.2 input
    anl P3MOD, #0b_11111110 ; P3.0 input 
    ret

Keypad:
    jb KEY.2, keypad_L0
    lcall Wait25ms 
    jb KEY.2, keypad_L0
    jnb KEY.2, $ 
    lcall Shift_Digits_Right
    clr c
    ret

keypad_L0:
    clr ROW1
    clr ROW2
    clr ROW3
    clr ROW4
    mov c, COL1
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Debounce
    clr c
    ret

Keypad_Debounce:
    lcall Wait25ms 
    mov c, COL1
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Key_Code
    clr c
    ret

Keypad_Key_Code:    
    setb ROW1
    setb ROW2
    setb ROW3
    setb ROW4
    jnb SWA.7, keypad_default
    ljmp keypad_90deg

keypad_default: 
    clr ROW1
    nop
    nop
    CHECK_COLUMN(COL1, #07H)
    CHECK_COLUMN(COL2, #08H)
    CHECK_COLUMN(COL3, #09H)
    CHECK_COLUMN(COL4, #0AH)
    setb ROW1
    nop
    nop
    clr ROW2
    CHECK_COLUMN(COL1, #04H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #06H)
    CHECK_COLUMN(COL4, #0BH)
    setb ROW2
    clr ROW3
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #02H)
    CHECK_COLUMN(COL3, #03H)
    CHECK_COLUMN(COL4, #0CH)
    setb ROW3
    clr ROW4
    CHECK_COLUMN(COL1, #0EH)
    CHECK_COLUMN(COL2, #00H)
    CHECK_COLUMN(COL3, #0FH)
    CHECK_COLUMN(COL4, #0DH)
    setb ROW4
    clr c
    ret

keypad_90deg:
    clr ROW1
    CHECK_COLUMN(COL1, #0AH)
    CHECK_COLUMN(COL2, #0BH)
    CHECK_COLUMN(COL3, #0CH)
    CHECK_COLUMN(COL4, #0DH)
    setb ROW1
    clr ROW2
    CHECK_COLUMN(COL1, #03H)
    CHECK_COLUMN(COL2, #06H)
    CHECK_COLUMN(COL3, #09H)
    CHECK_COLUMN(COL4, #0FH)
    setb ROW2
    clr ROW3
    CHECK_COLUMN(COL1, #02H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #08H)
    CHECK_COLUMN(COL4, #00H)
    setb ROW3
    clr ROW4
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #04H)
    CHECK_COLUMN(COL3, #07H)
    CHECK_COLUMN(COL4, #0EH)
    setb ROW4
    clr c
    ret


; -----------------------------------------------------------------------------
; Key handling (matches your sample logic)
;   E (0x0E) = CLEAR
;   F (0x0F) = ENTER -> validate 150..280 inclusive
;   0..9 valid digit -> CY=1 (main shifts left + beeps)
;   A..D (0x0A..0x0D) invalid -> ignore (CY=0)
; -----------------------------------------------------------------------------
Keypad_HandleKey:
    clr mf

    ; ---- Clear (E = 0x0E) ----
    mov a, R7
    cjne a, #0EH, KH_chk_enter
    lcall Clear_Buffer_bcd1
    clr c
    ret

KH_chk_enter:
    ; ---- Enter (F = 0x0F) ----
    mov a, R7
    cjne a, #0FH, KH_chk_digit
    lcall Validate_Input_bcd1
    clr c
    ret

KH_chk_digit:
    ; ---- Ignore A..D ----
    mov a, R7
    cjne a, #0AH, KH_chk_B
    clr c
    ret
KH_chk_B:
    mov a, R7
    cjne a, #0BH, KH_chk_C
    clr c
    ret
KH_chk_C:
    mov a, R7
    cjne a, #0CH, KH_chk_D
    clr c
    ret
KH_chk_D:
    mov a, R7
    cjne a, #0DH, KH_chk_0_9
    clr c
    ret

KH_chk_0_9:
    ; Accept only 0..9
    mov a, R7
    clr c
    subb a, #0AH        ; if R7 < 10 -> CY=1
    jc KH_digit_ok
    clr c
    ret

KH_digit_ok:
    setb c              ; tell main "valid key"
    ret


; -----------------------------------------------------------------------------
; Buffer ops on bcd1 (your project uses bcd1 for keypad digits)
; -----------------------------------------------------------------------------
Clear_Buffer_bcd1:
    mov bcd1+0, #00H
    mov bcd1+1, #00H
    mov bcd1+2, #00H
    mov bcd1+3, #00H
    mov bcd1+4, #00H
    lcall Display7seg
    ret


; -----------------------------------------------------------------------------
; Validate_Input_bcd1:
;   Implements your logic: valid if 150 <= value <= 280
;   We convert ONLY the lowest 3 digits from bcd1 into x (32-bit):
;     ones  = low nibble of bcd1+0
;     tens  = high nibble of bcd1+0
;     hund  = low nibble of bcd1+1
;   Then uses math32 comparisons: x_lt_y, x_gt_y and mf flag.
; -----------------------------------------------------------------------------
Validate_Input_bcd1:
    ; Build x = 100*hund + 10*tens + ones
    ; x is 32-bit little-endian: x+0 LSB

    ; ones in R0 (0..9)
    mov a, bcd1+0
    anl a, #0FH
    mov R0, a

    ; tens in R1 (0..9)
    mov a, bcd1+0
    swap a
    anl a, #0FH
    mov R1, a

    ; hundreds in R2 (0..9)
    mov a, bcd1+1
    anl a, #0FH
    mov R2, a

    ; x = 0
    mov x+0, #0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    ; x += ones
    mov a, R0
    mov x+0, a

    ; x += 10*tens
    ; compute 10*tens in a: (tens*8 + tens*2)
    mov a, R1
    mov b, a          ; b = tens
    mov a, b
    rl a              ; *2
    mov R3, a         ; R3 = 2*tens
    mov a, b
    rl a
    rl a
    rl a              ; *8
    add a, R3         ; *10
    add a, x+0
    mov x+0, a
    clr a
    addc a, x+1
    mov x+1, a

    ; x += 100*hundreds
    ; 100 = 64 + 32 + 4
    mov a, R2
    mov b, a          ; b = hundreds

    ; a = 4*hund
    mov a, b
    rl a
    rl a
    mov R3, a         ; R3 = 4*hund

    ; a = 32*hund
    mov a, b
    rl a
    rl a
    rl a
    rl a
    rl a
    mov R4, a         ; R4 = 32*hund

    ; a = 64*hund
    mov a, b
    rl a
    rl a
    rl a
    rl a
    rl a
    rl a
    ; now a = 64*hund
    add a, R4         ; +32*hund
    add a, R3         ; +4*hund => 100*hund
    add a, x+0
    mov x+0, a
    clr a
    addc a, x+1
    mov x+1, a
    clr a
    addc a, x+2
    mov x+2, a
    clr a
    addc a, x+3
    mov x+3, a

    ; ----- Range check: 150..280 -----
    Load_y(150)
    lcall x_lt_y
    jb mf, Range_Invalid_bcd1

    Load_y(280)
    lcall x_gt_y
    jb mf, Range_Invalid_bcd1

Range_Valid_bcd1:
    mov HEX5, #0xC1 ; V
    mov HEX4, #0x88 ; A
    mov HEX3, #0xC7 ; L
    mov HEX2, #0xF9 ; I
    mov HEX1, #0xA1 ; D
    mov HEX0, #0xFF ; blank
    lcall Wait3Seconds_kb
    lcall Clear_Buffer_bcd1
    ret

Range_Invalid_bcd1:
    mov HEX5, #0xF9 ; I
    mov HEX4, #0xAB ; N
    mov HEX3, #0xC1 ; V
    mov HEX2, #0x88 ; A
    mov HEX1, #0xC7 ; L
    mov HEX0, #0xFF ; blank
    lcall Wait3Seconds_kb
    lcall Clear_Buffer_bcd1
    ret


; ~3 seconds using Wait25ms from your main (120 * 25ms)
Wait3Seconds_kb:
    push acc
    mov a, #120
W3_kb:
    lcall Wait25ms
    djnz acc, W3_kb
    pop acc
    ret


Display7seg:
    mov dptr, #myLUT
    mov a, bcd1+3
    orl a, bcd1+4
    setb LEDRA.7 
    sjmp Display_L2
Display_L2:
    jnb key.3, Display_high_digits
    showBCD(bcd1+0, HEX0, HEX1)
    showBCD(bcd1+1, HEX2, HEX3)
    showBCD(bcd1+2, HEX4, HEX5)
    sjmp Display_end
Display_high_digits:
    showBCD(bcd1+3, HEX0, HEX1)
    showBCD(bcd1+4, HEX2, HEX3)
    mov HEX4, #0xff 
    mov HEX5, #0xff 
Display_end:
    ret

Shift_Digits_Left:
    mov R0, #4 
Shift_Digits_Left_L0:
    clr c
    MYRLC(bcd1+0)
    MYRLC(bcd1+1)
    MYRLC(bcd1+2)
    MYRLC(bcd1+3)
    MYRLC(bcd1+4)
    djnz R0, Shift_Digits_Left_L0
    mov a, R7
    orl a, bcd1+0
    mov bcd1+0, a
    ret

Shift_Digits_Right:
    mov R0, #4 
Shift_Digits_Right_L0:
    clr c
    MYRRC(bcd1+4)
    MYRRC(bcd1+3)
    MYRRC(bcd1+2)
    MYRRC(bcd1+1)
    MYRRC(bcd1+0)
    djnz R0, Shift_Digits_Right_L0
    ret
