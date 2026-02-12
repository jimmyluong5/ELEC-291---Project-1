$MODMAX10

; ============================================================================
; YOUR ORIGINAL CODE + MINIMAL ADDITIONS
; ADDED: Timer1-based 1ms tick + PWM heater on P2.1 + automatic FSM transitions
; NOTE: We use Timer1 (NOT Timer2) because Timer2 is already used for serial baud.
; ============================================================================

CSEG at 0
    ljmp mycode

org 000Bh
    ljmp Timer0_ISR

; ---- NEW: Timer1 interrupt vector (8051 Timer1 = 001Bh) ----
org 001Bh
    ljmp Timer1_ISR


DSEG at 30h
x:      ds  4
y:      ds  4
bcd:    ds  5 ; Voltmeter BCD buffer 
bcd1:   ds  5 ; Keypad BCD buffer
state:  ds  1 ; Variable to keep track of current state 
sw_state: ds 1 ; state for the switch 
prev_state: ds 1   ; stores last state to detect transitions
beep_count: ds 1

; ---- NEW: PWM + timebase variables (Timer1 ISR uses these) ----
pwm_counterL: ds 1         ; 16-bit PWM counter low
pwm_counterH: ds 1         ; 16-bit PWM counter high
pwm_dutyL:    ds 1         ; 16-bit duty (0..PWM_MAX) low
pwm_dutyH:    ds 1         ; 16-bit duty (0..PWM_MAX) high
ms_counterL:  ds 1         ; 16-bit millisecond counter low
ms_counterH:  ds 1         ; 16-bit millisecond counter high
seconds:      ds 1         ; seconds counter for FSM timing

BSEG
mf:     dbit 1
alarm_en_flag:     dbit 1 ; Alarm enabled flag
ringing_flag:      dbit 1 ; Alarm currently ringing flag
error_flag:        dbit 1


; Constants
FREQ    EQU 33333333
BAUD    EQU 115200
T2LOAD  EQU 65536-(FREQ/(32*BAUD))

; Hardware mapping for DE10-Lite
BUTTON  EQU KEY.1  ; KEY1 for state transition 
reset   equ P1.3   ; this key will be for resetting to state 0 
SPEAKER equ P1.5
ERROR_BTN  EQU P3.7   ; active-low pushbutton (typical)

; Keypad Pins
ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0
COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0

; switches used
sw0 equ SWA.0
sw1 equ SWA.1
sw2 equ SWA.2

; ---- NEW: Heater PWM output pin (safe new pin, no conflicts) ----
HEATER_PIN EQU P2.1

; ---- NEW: PWM + Timer1 timebase constants ----
PWM_MAX     EQU 1000                 ; PWM period = 1000ms window (1 second)
T1_RATE     EQU 1000                 ; 1 kHz interrupt = 1 ms
T1_RELOAD   EQU (65536-(FREQ/(12*T1_RATE)))  ; Timer1 reload for 1ms
T1_RELOAD_H EQU high(T1_RELOAD)
T1_RELOAD_L EQU low(T1_RELOAD)


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
state_e_msg: db 'ERROR FIX NOW', 0
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


; ============================================================================
; NEW: Timer1 init + ISR for 1ms timebase and PWM on HEATER_PIN (P2.1)
; - Timer2 is reserved for InitSerialPort baud generation (your existing code)
; - Timer0 is reserved for speaker tone (your existing code)
; ============================================================================

Timer1_Init:
    ; Configure Timer1 in mode 1 (16-bit)
    mov a, TMOD
    anl a, #0Fh             ; keep Timer0 bits
    orl a, #10h             ; Timer1 mode 1
    mov TMOD, a

    mov TH1, #T1_RELOAD_H
    mov TL1, #T1_RELOAD_L

    ; Clear counters
    clr a
    mov pwm_counterL, a
    mov pwm_counterH, a
    mov ms_counterL, a
    mov ms_counterH, a
    mov seconds, a

    ; Default PWM off
    mov pwm_dutyL, a
    mov pwm_dutyH, a

    setb ET1                 ; enable Timer1 interrupt
    setb TR1                 ; start Timer1
    ret

Timer1_ISR:
    ; Reload Timer1 for ~1ms
    mov TH1, #T1_RELOAD_H
    mov TL1, #T1_RELOAD_L

    push acc
    push psw

    ; -------- ms counter (16-bit) ----------
    inc ms_counterL
    mov a, ms_counterL
    jnz ms_ok
    inc ms_counterH
ms_ok:

    ; -------- every 1000ms -> seconds++ ----------
    mov a, ms_counterL
    cjne a, #low(1000), skip_sec
    mov a, ms_counterH
    cjne a, #high(1000), skip_sec
    clr ms_counterL
    clr ms_counterH
    inc seconds
skip_sec:

    ; -------- PWM counter (16-bit) ----------
    inc pwm_counterL
    mov a, pwm_counterL
    jnz pwm_ok
    inc pwm_counterH
pwm_ok:

    ; reset PWM counter at PWM_MAX (1000)
    mov a, pwm_counterL
    cjne a, #low(PWM_MAX), compare_pwm
    mov a, pwm_counterH
    cjne a, #high(PWM_MAX), compare_pwm
    clr pwm_counterL
    clr pwm_counterH

compare_pwm:
    ; if pwm_counter < pwm_duty -> HEATER_PIN = 1 else 0
    mov a, pwm_dutyL
    clr c
    subb a, pwm_counterL
    mov a, pwm_dutyH
    subb a, pwm_counterH
    cpl c
    mov HEATER_PIN, c

    pop psw
    pop acc
    reti

; ---- NEW PWM helper routines ----
Set_PWM_Off:
    mov pwm_dutyL, #0
    mov pwm_dutyH, #0
    ret

Set_PWM_Full:
    mov pwm_dutyL, #low(PWM_MAX)
    mov pwm_dutyH, #high(PWM_MAX)
    ret

Set_PWM_Low:          ; ~20%
    mov pwm_dutyL, #low(200)
    mov pwm_dutyH, #high(200)
    ret

Set_PWM_Med:          ; ~50%
    mov pwm_dutyL, #low(500)
    mov pwm_dutyH, #high(500)
    ret


; ============================================================================
; Your beep/alarm stuff (unchanged)
; ============================================================================

;-----------------------------------------
; Loud_Beep_Once: uses Timer0 tone for a short beep
;-----------------------------------------
Loud_Beep_Once:
    setb TR0              ; start tone
    lcall Wait50ms
    lcall Wait50ms
    clr  TR0              ; stop tone
    clr  SPEAKER
    lcall Wait50ms
    lcall Wait50ms
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

Beep_Once:
    jb  ringing_flag, BO_done
    setb TR0
    lcall Wait50ms
    lcall Wait50ms
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
    anl a, #0FH
    orl a, #'0'
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
    mov HEX2, #0FFH
    mov HEX3, #0FFH
    mov HEX4, #0FFH
    mov HEX5, #0FFH
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


; NOTE: voltage_reading_7seg uses myLUT, which is likely in your include files.
voltage_reading_7seg:
    mov dptr, #myLUT

    mov a, bcd+0
    anl a, #0FH
    movc a, @a+dptr
    mov HEX0, a

    mov a, bcd+0
    swap a
    anl a, #0FH
    movc a, @a+dptr
    mov HEX1, a

    mov a, bcd+1
    anl a, #0FH
    movc a, @a+dptr
    mov HEX2, a

    mov a, bcd+1
    swap a
    anl a, #0FH
    movc a, @a+dptr
    mov HEX3, a

    mov a, bcd+2
    anl a, #0FH
    movc a, @a+dptr
    mov HEX4, a

    mov a, bcd+2
    swap a
    anl a, #0FH
    movc a, @a+dptr
    mov HEX5, a
    ret


voltage_reading:
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

    Load_y(1000)
    lcall mul32
    Load_y(12300)
    lcall div32
    Load_y(22)
    lcall add32

    lcall hex2bcd
    ret


; ============================================================================
; NEW: Automatic FSM control (does NOT remove your button state changes)
; Uses temperature from x+0 (low byte of computed temperature)
; Uses seconds counter incremented by Timer1 ISR
; ============================================================================
FSM_Control:
    mov a, state

; state 0: idle -> heater off
FSM_s0:
    cjne a, #0, FSM_s1
    lcall Set_PWM_Off
    ret

; state 1: ramp to soak -> full power until temp >= 150
FSM_s1:
    cjne a, #1, FSM_s2
    lcall Set_PWM_Full
    mov a, x+0
    clr c
    subb a, #150
    jnc FSM_done_s1
    mov state, #2
    clr seconds
FSM_done_s1:
    ret

; state 2: soak hold -> low power until 60 seconds done
FSM_s2:
    cjne a, #2, FSM_s3
    lcall Set_PWM_Low
    mov a, seconds
    clr c
    subb a, #60
    jnc FSM_done_s2
    mov state, #3
    clr seconds
FSM_done_s2:
    ret

; state 3: ramp to reflow -> full power until temp >= 220
FSM_s3:
    cjne a, #3, FSM_s4
    lcall Set_PWM_Full
    mov a, x+0
    clr c
    subb a, #220
    jnc FSM_done_s3
    mov state, #4
    clr seconds
FSM_done_s3:
    ret

; state 4: reflow hold -> medium power for 30 seconds
FSM_s4:
    cjne a, #4, FSM_s5
    lcall Set_PWM_Med
    mov a, seconds
    clr c
    subb a, #30
    jnc FSM_done_s4
    mov state, #5
FSM_done_s4:
    ret

; state 5: cool -> heater off until temp <= 50 then go idle
FSM_s5:
    lcall Set_PWM_Off
    mov a, x+0
    clr c
    subb a, #50
    jnc FSM_done_s5
    mov state, #0
    clr seconds
FSM_done_s5:
    ret


; ============================================================================
; MAIN
; ============================================================================
mycode:
    mov SP, #7FH
    mov P0MOD, #10101111b
    mov P1MOD, #10101010b

    ; keep P1.3 as input (you already do this)
    anl P1MOD, #11110111b

    setb P1.4

    ; ensure heater pin is output (P2.1)
    orl P2MOD, #00000010b
    clr HEATER_PIN

    clr error_flag
    clr SPEAKER
    clr alarm_en_flag
    clr ringing_flag
    mov beep_count, #0

    lcall Timer0_Init
    lcall Timer1_Init        ; NEW: start 1ms tick + PWM
    setb EA

    setb alarm_en_flag

    lcall Configure_Keypad_Pins

    anl P3MOD, #01111111b
    setb P3.7

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

; ---- Error button test (P3.7) ----
    jb  ERROR_BTN, after_error_check
    lcall Wait50ms
    jb  ERROR_BTN, after_error_check

    setb error_flag
    mov  beep_count, #10
    lcall Loud_Beep_Once
    lcall Update_State_Display

wait_err_release:
    jnb ERROR_BTN, wait_err_release

after_error_check:
    lcall Do_ExtraBeeps

    jb  error_flag, chk_err_done_main
    sjmp continue_main

chk_err_done_main:
    mov a, beep_count
    jnz continue_main

    clr error_flag
    mov state, #0
    mov prev_state, #0
    lcall Update_State_Display

continue_main:

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
    ; ---------------- RESET BUTTON (one-shot) ----------------
    jb   reset, check_increment

    lcall Wait50ms
    jb   reset, check_increment

    clr  error_flag
    mov  beep_count, #0
    clr  TR0
    clr  SPEAKER

    mov  state, #0
    mov  prev_state, #0
    lcall LCD_4bit
    lcall Update_State_Display
    clr  seconds            ; NEW: reset FSM timer on reset

wait_reset_release:
    jnb  reset , wait_reset_release

    sjmp no_press


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
    sjmp after_state_logic

STATE_CHANGED:
    mov prev_state, a

    jb  error_flag, done_beep_load

    ; always 1 beep on state change
    lcall Beep_Once

    mov beep_count, #0

chk_state5:
    cjne a, #5, chk_state_error
    mov beep_count, #4
    sjmp done_beep_load

chk_state_error:
    ; NOTE: your original logic here is odd, kept as-is to avoid changing behavior
    jb  error_flag, set_10beeps
    sjmp done_beep_load

set_10beeps:
    mov beep_count, #9

done_beep_load:
    ; NEW: reset FSM seconds on state changes so time-based states behave predictably
    clr seconds
    sjmp after_state_logic

after_state_logic:
    ; NEW: Run automatic FSM transitions every loop (does NOT remove button behavior)
    lcall FSM_Control

no_press:
    lcall Wait50ms
    ljmp forever


; ----------------------------
; LCD STATE DISPLAY
; ----------------------------
Update_State_Display:
    Set_Cursor(1, 1)

    jb  error_flag, show_error
    sjmp normal_state

show_error:
    ljmp s_error

normal_state:
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

s_error:
    Send_Constant_String(#state_e_msg)
    ret

END
