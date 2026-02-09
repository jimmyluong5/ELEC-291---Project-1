$MODMAX10

CSEG at 0
    ljmp mycode
    
    org 000Bh
    ljmp Timer0_ISR

DSEG at 30h
x:      ds  4
y:      ds  4
bcd:    ds  5 ; Voltmeter BCD buffer 
bcd1:   ds  5 ; Keypad BCD buffer
state:  ds  1 ; Variable to keep track of current state 
sw_state: ds 1 ; state for the switch 
prev_state: ds 1   ; stores last state to detect transitions
beep_count: ds 1

BSEG
mf:     dbit 1
alarm_en_flag:     dbit 1 ; Alarm enabled flag
ringing_flag:      dbit 1 ; Alarm currently ringing flag


; Constants
FREQ    EQU 33333333
BAUD    EQU 115200
T2LOAD  EQU 65536-(FREQ/(32*BAUD))

; Hardware mapping for DE10-Lite
BUTTON  EQU KEY.1  ; KEY1 for state transition 
reset   equ P1.3   ; this key will be for resetting to state 0 
SPEAKER equ P1.5

; Keypad Pins
ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0
COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0


;switches used
sw0 equ SWA.0 ;this will be used to display the temperature reading 
sw1 equ SWA.1 ;used to display the voltage
sw2 equ SWA.2 ;used to display the timer
;reading an individual switch
;jb sw0, switch_is_up ;jump to this label when the switch is high
;jnb sw0, switch_is_down ;jump to this label when the switch is low

;reading multiple switches at the same time
;mov a, SWA ;moving the switch values from the SWA register into the accumulator
;anl a, #00001111b ;only read the first 4 switch values only. (SW0 to SW4)

 


$include(math32.asm)

; LCD Pin Mapping 
LCD_RS equ P0.0 
LCD_E  equ P0.2 
LCD_D4 equ P0.7
LCD_D5 equ P0.5
LCD_D6 equ P0.3
LCD_D7 equ P0.1 

$NOLIST
$include(LCD_4bit_DE10Lite_no_RW1.inc)
$include(keyboard.inc)
$include(keypad_to_LCD.inc)
$LIST

; Strings for the FSM 
state0_msg: db 'State: 0', 0
state1_msg: db 'State: 1', 0
state2_msg: db 'State: 2', 0
state3_msg: db 'State: 3 ', 0
state4_msg: db 'State: 4', 0
state5_msg: db 'State: 5', 0
state6_msg: db 'State: 6 ', 0
test_msg: db 'test', 0
clear_msg: db '                       ', 0



; --- Integrated Subroutines ---


T0_RATE  EQU 4096
T0_RELOAD EQU (65536-(FREQ/(12*T0_RATE)))


Timer0_Init:
    mov a, TMOD
    anl a, #0F0h
    orl a, #01h          ; Timer0 mode 1 (16-bit)
    mov TMOD, a

    mov TH0, #high(T0_RELOAD)
    mov TL0, #low(T0_RELOAD)

    setb ET0             ; enable Timer0 interrupt
    clr  TR0             ; OFF by default
    ret

Timer0_ISR:
    mov TH0, #high(T0_RELOAD)
    mov TL0, #low(T0_RELOAD)
    cpl SPEAKER
    reti
    
    
    
;-----------------------------------------
; Loud_Beep_Once: uses Timer0 tone for a short beep
;-----------------------------------------
Loud_Beep_Once:
    setb TR0              ; start tone
    lcall Wait50ms        ; ON time (adjust)
    clr  TR0              ; stop tone
    clr  SPEAKER
    lcall Wait50ms        ; gap between beeps (adjust)
    ret



Alarm_On:
setb ringing_flag
setb TR0
ret

Alarm_Off:
clr ringing_flag
clr TR0
clr SPEAKER
ret


; Short beep using the SAME loud timer tone:
; (Turn TR0 on briefly, then off)
Beep_Once:
    ; if alarm already ringing, don’t interrupt it
    jb  ringing_flag, BO_done

    setb TR0
    lcall Wait50ms       ; beep length (change to Wait25ms if you want shorter)
    clr  TR0
    clr  SPEAKER
BO_done:
    ret

Do_ExtraBeeps:
    mov a, beep_count
    jz  DEB_done
    lcall Loud_Beep_Once
    dec beep_count
DEB_done:
    ret




InitSerialPort: 
    clr TR2
    mov T2CON, #30H
    mov RCAP2H, #high(T2LOAD)
    mov RCAP2L, #low(T2LOAD)
    setb TR2
    mov SCON, #52H
    ret

Wait50ms: 
    mov R0, #30
x_L3: mov R1, #74
x_L2: mov R2, #250
x_L1: djnz R2, x_L1
    djnz R1, x_L2
    djnz R0, x_L3
    ret

Wait25ms:
    mov R0, #15
L3_y: mov R1, #74
L2_y: mov R2, #250
L1_y: djnz R2, L1_y 
    djnz R1, L2_y 
    djnz R0, L3_y 
    ret

Display_Voltage_LCD: 
    Set_Cursor(2,1)
    mov a, #'V'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData
    mov a, bcd+1
    swap a
    anl a, #0FH ;ensures we have a number between 0-9
    orl a, #'0' ;because 0FH = 0000 1111
    lcall ?WriteData
    mov a, #'.'
    lcall ?WriteData
    mov a, bcd+1
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    mov a, bcd+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    mov a, bcd+0
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    ret

clear7seg:
	mov HEX0, #0FFH
	mov HEX1, #0FFH
	MOV HEX2, #0FFH
	MOV HEX3, #0FFH
	MOV HEX4, #0FFH
	MOV HEX5, #0FFH
ret

turnoff_leds:
	clr LEDRA.0
	clr LEDRA.1
	clr LEDRA.2
	clr LEDRA.3
	clr LEDRA.4
	clr LEDRA.5
	clr LEDRA.6
	clr LEDRA.7

ret

voltage_reading_7seg:
	;after we call hex2bcd, the value of the voltage is stored in x
	;the value of x is stored in bcd spread out through 4 bytes
	;need to convert these decimal numbers in the bcd to the look up table
	
	;need to use the accumulator register
	mov dptr, #myLUT
	
	;display digit 0 and 1 from (bcd+0)
	mov a, bcd+0
	anl a, #0FH
	movc a, @a+dptr ;movc is moving a constant, which is at address a+address of data ptr
	;or getting the pattern from the look up table
	mov HEX0, a ;send the value to the hex0
	
	mov a, bcd+0
	swap a ;need to get the higher part ex. 1111 0000	
	anl a, #0FH
	movc a, @a+dptr
	mov HEX1, a
	
	;repeat with the other bcd all the way to bcd+2
	
	mov a, bcd+1
	anl a, #0FH
	movc a, @a+dptr ;movc is moving a constant, which is at address a+address of data ptr
	;or getting the pattern from the look up table
	mov HEX2, a ;send
	
	mov a, bcd+1
	swap a ;need to get the higher part ex. 1111 0000	
	anl a, #0FH
	movc a, @a+dptr
	mov HEX3, a
	
	mov a, bcd+2
	anl a, #0FH
	movc a, @a+dptr ;movc is moving a constant, which is at address a+address of data ptr
	;or getting the pattern from the look up table
	mov HEX4, a ;send
	
	mov a, bcd+2
	swap a ;need to get the higher part ex. 1111 0000	
	anl a, #0FH
	movc a, @a+dptr
	mov HEX5, a
ret



voltage_reading:
    ; --- Part 2: Voltmeter Logic --- 
    mov a, SWA 
    anl a, #0x07
    mov ADC_C, a
    
    mov x+3, #0
    mov x+2, #0
    mov x+1, ADC_H
    mov x+0, ADC_L
    
    Load_y(5000)
    lcall mul32
    Load_y(4096)
    lcall div32
    
    Load_y(1000) ;convert to microvolts
    lcall mul32
    Load_y(12300);41*300 (gain of 300, replace with actual gain after)multipled by thermocouple wire temp change.
    lcall div32
    Load_y(22) ;cold junction temperature
    lcall add32
    ;after this, the result is stored in bcd spread out through 4 bytes.
    
    lcall hex2bcd
   ;lcall Display_Voltage_LCD 
ret


; --- Main Program ---

mycode:
    mov SP, #7FH
    mov P0MOD, #10101111b
    mov P1MOD, #10101010b
    anl P1MOD, #11110111b   ; <-- clear bit3 => P1.3 becomes INPUT
    setb P1.3               ; optional: leave it high / pull-up style behavior


    clr SPEAKER
    clr alarm_en_flag
    clr ringing_flag
    mov beep_count, #0

    lcall Timer0_Init
    setb EA

    setb alarm_en_flag

    lcall Configure_Keypad_Pins
    lcall turnoff_leds
    lcall InitSerialPort
    lcall LCD_4BIT

    mov ADC_C, #0x80
    lcall Wait50ms

    mov state, #0
    mov prev_state, #0
    lcall Update_State_Display

    mov sw_state, #0

forever:
    ; play any queued extra beeps (non-blocking-ish, one per loop)
    lcall Do_ExtraBeeps

    ; keypad
    lcall Keypad
    jnc check_mode
    lcall Shift_Digits_Left
    lcall Beep_Once

check_mode:
    jb SWA.6, mode_LCD
    clr LEDRA.6
    lcall turnoff_leds
    lcall Display7seg
    lcall voltage_reading
    lcall Display_Voltage_LCD
    ljmp fsm_part

mode_LCD:
    setb LEDRA.6
    lcall clear7seg
    lcall turnoff_leds
    lcall Display_LCD
    lcall voltage_reading
    lcall voltage_reading_7seg
    ljmp fsm_part

fsm_part:
    ; reset -> state 0
    jb reset, check_increment
    lcall Wait50ms
    jb reset, check_increment
    mov state, #0
    lcall Update_State_Display
wait_reset_release:
    jnb reset, wait_reset_release
    ljmp no_press

check_increment:
    jb BUTTON, no_press
    lcall Wait50ms
    jb BUTTON, no_press

    inc state
    mov a, state
    cjne a, #7, skip_reset
    mov state, #0
skip_reset:
    lcall Update_State_Display

wait_release:
    jnb BUTTON, wait_release

    ; ----------------------------
    ; STATE CHANGE LOGIC
    ; ----------------------------
    mov a, state
    cjne a, prev_state, STATE_CHANGED
    sjmp no_press

  STATE_CHANGED:
    mov prev_state, a

    ; always 1 beep on state change
    lcall Beep_Once

    ; default no extra beeps
    mov beep_count, #0

    ; state 1 ? total 5 beeps (1 already done + 4)
    ;cjne a, #1, chk_state5
    ;mov beep_count, #4
    ;sjmp done_beep_load

chk_state5:
    ; state 5 ? total 5 beeps (same pattern)
    cjne a, #5, chk_state6
    mov beep_count, #4
    sjmp done_beep_load

chk_state6:
    ; state 6 ? total 10 beeps
    cjne a, #6, done_beep_load
    mov beep_count, #9

done_beep_load:
    sjmp no_press


no_press:
    lcall Wait50ms
    ljmp forever

; ----------------------------
; LCD STATE DISPLAY
; ----------------------------
Update_State_Display:
    Set_Cursor(1, 1)
    mov a, state
    cjne a, #0, s1
    Send_Constant_String(#state0_msg)
    ret
s1: cjne a, #1, s2
    Send_Constant_String(#state1_msg)
    ret
s2: cjne a, #2, s3
    Send_Constant_String(#state2_msg)
    ret
s3: cjne a, #3, s4
    Send_Constant_String(#state3_msg)
    ret
s4: cjne a, #4, s5
    Send_Constant_String(#state4_msg)
    ret
s5: cjne a, #5, s6
    Send_Constant_String(#state5_msg)
    ret
s6:
    Send_Constant_String(#state6_msg)
    ret

END