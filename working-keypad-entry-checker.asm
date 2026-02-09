$NOLIST
$MODMAX10
$LIST

;Reset
    CSEG at 0
    ljmp main_code

;Data Segments/Values
    DSEG at 30H
bcd:    ds 5    ; [cite_start]10-digit packed BCD buffer [cite: 5]
x:      ds 4    ; [cite_start]32-bit hex variable x [cite: 27]
y:      ds 4    ; [cite_start]32-bit hex variable y [cite: 42]
mf      bit 20h.0 ; [cite_start]Math flag used for comparisons [cite: 44]

$NOLIST
$include(math32.inc)
$LIST

;Segment Encodings
    CSEG

; Look-up table for 7-seg digits 0-F
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99
    DB 0x92, 0x82, 0xF8, 0x80, 0x90
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E

;Macros
showBCD_7seg MAC
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

CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M
    mov R7, %1
    jnb %0, $ 
    setb c
    ret
CHECK_COL_%M:
ENDMAC

;Subroutines
Display_7seg:
    mov dptr, #myLUT
    showBCD_7seg(bcd+0, HEX0, HEX1)
    showBCD_7seg(bcd+1, HEX2, HEX3)
    showBCD_7seg(bcd+2, HEX4, HEX5)
    ret

Wait3Seconds:
    push acc
    mov a, #120
Wait3Sec_Loop:
    lcall Wait25ms
    djnz acc, Wait3Sec_Loop
    pop acc
    ret

Wait25ms:
    mov R0, #15
L3b: 
    mov R1, #74
L2b: 
    mov R2, #250
L1b: 
    djnz R2, L1b 
    djnz R1, L2b 
    djnz R0, L3b 
    ret

Configure_Keypad_Pins:
    orl P1MOD, #0b_01010100 
    orl P2MOD, #0b_00000001 
    anl P2MOD, #0b_10101011 
    anl P3MOD, #0b_11111110 
    ret

;Validate if the buffer value falls in the range
Validate_Input:
    lcall bcd2hex ; Convert BCD to 32-bit hex in x [cite: 26, 27]
    Load_y(150) ; Load 150 into y [cite: 42]
    lcall x_lt_y ; Check if x < 150 [cite: 44]
    jb mf, Range_Invalid
    Load_y(280) ; [cite_start]Load 280 into y [cite: 42]
    lcall x_gt_y ; [cite_start]Check if x > 280 [cite: 45]
    jb mf, Range_Invalid

Range_Valid:
    mov HEX5, #0xC1 ; V
    mov HEX4, #0x88 ; A
    mov HEX3, #0xC7 ; L
    mov HEX2, #0xF9 ; I
    mov HEX1, #0xA1 ; D
    mov HEX0, #0xFF ; Blank
    lcall Wait3Seconds
    lcall Clear_Buffer
    ret

Range_Invalid:
    mov HEX5, #0xF9 ; I
    mov HEX4, #0xAB ; N
    mov HEX3, #0xC1 ; V
    mov HEX2, #0x88 ; A
    mov HEX1, #0xC7 ; L
    mov HEX0, #0xFF ; Blank
    lcall Wait3Seconds
    lcall Clear_Buffer
    ret

Clear_Buffer:
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov bcd+3, a
    mov bcd+4, a
    lcall Display_7seg
    ret

;Parse Keypad Input, check if valid
ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0
COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0

Keypad:
    jb KEY.1, keypad_L0
    lcall Wait25ms 
    jb KEY.1, keypad_L0
    jnb KEY.1, $ 
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
    clr ROW1
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #02H)
    CHECK_COLUMN(COL3, #03H)
    CHECK_COLUMN(COL4, #0AH)
    setb ROW1
    clr ROW2
    CHECK_COLUMN(COL1, #04H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #06H)
    CHECK_COLUMN(COL4, #0BH)
    setb ROW2
    clr ROW3
    CHECK_COLUMN(COL1, #07H)
    CHECK_COLUMN(COL2, #08H)
    CHECK_COLUMN(COL3, #09H)
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

Shift_Digits_Left:
    mov R0, #4 
Shift_Digits_Left_L0:
    clr c
    mov a, bcd+0
    rlc a
    mov bcd+0, a
    mov a, bcd+1
    rlc a
    mov bcd+1, a
    mov a, bcd+2
    rlc a
    mov bcd+2, a
    mov a, bcd+3
    rlc a
    mov bcd+3, a
    mov a, bcd+4
    rlc a
    mov bcd+4, a
    djnz R0, Shift_Digits_Left_L0
    mov a, R7
    orl a, bcd+0
    mov bcd+0, a
    ret

Shift_Digits_Right:
    mov R0, #4 
Shift_Digits_Right_L0:
    clr c
    mov a, bcd+4
    rrc a
    mov bcd+4, a
    mov a, bcd+3
    rrc a
    mov bcd+3, a
    mov a, bcd+2
    rrc a
    mov bcd+2, a
    mov a, bcd+1
    rrc a
    mov bcd+1, a
    mov a, bcd+0
    rrc a
    mov bcd+0, a
    djnz R0, Shift_Digits_Right_L0
    ret

;Main loop
main_code:
    mov SP, #7FH
    lcall Clear_Buffer
    lcall Configure_Keypad_Pins

forever:
    lcall Keypad 
    jnc forever
    cjne R7, #0EH, check_enter ; 0EH is 'E' (Asterisk)
    lcall Clear_Buffer
    sjmp forever

check_enter:
    cjne R7, #0FH, process_digit ; 0FH is 'F' (Hash)
    lcall Validate_Input
    sjmp forever

process_digit:
    mov a, R7
    cjne a, #0AH, skip_a ; Skip hex letters A-D
    sjmp forever
skip_a: 
    cjne a, #0BH, skip_b
    sjmp forever
skip_b: 
    cjne a, #0CH, skip_c
    sjmp forever
skip_c: 
    cjne a, #0DH, skip_d
    sjmp forever
skip_d:
    lcall Shift_Digits_Left
    lcall Display_7seg
    sjmp forever

end
