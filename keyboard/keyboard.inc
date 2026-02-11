
cseg 
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; 0 TO 4 
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; 4 TO 9 
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A to F
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

CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M
    mov R7, %1
    jnb %0, $ 
    setb c
    ret
CHECK_COL_%M:
ENDMAC


Configure_Keypad_Pins:
  ;goes from left to right, 7, 6, 5, 4, 3, 2, 1, 0
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
    jnb SWA.7, keypad_default;switch 7 changes the keypad 90 degrees CCW
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

Display7seg:
    mov dptr, #myLUT
    mov a, bcd1+3
    orl a, bcd1+4
   ; jz Display_L1
    setb LEDRA.7 
    sjmp Display_L2
;Display_L1:
 ;   clr LEDRA.7
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
    
    
