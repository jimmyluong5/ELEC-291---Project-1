$MODMAX10

; ========================= INTERRUPT VECTORS =========================
CSEG at 0
    ljmp mycode

org 000Bh
    ljmp Timer0_ISR        ; Speaker tone ISR

org 002Bh
    ljmp Timer2_ISR        ; NEW: System timer + PWM ISR

; ========================= DATA MEMORY =========================
DSEG at 30h
x:      ds 4
y:      ds 4
bcd:    ds 5
bcd1:   ds 5
state:  ds 1
sw_state: ds 1
prev_state: ds 1
beep_count: ds 1

; ---------- NEW PWM + TIME VARIABLES ----------
pwm_counterL: ds 1
pwm_counterH: ds 1
pwm_dutyL:    ds 1
pwm_dutyH:    ds 1
ms_counterL:  ds 1
ms_counterH:  ds 1
seconds:      ds 1

BSEG
mf: dbit 1
alarm_en_flag: dbit 1
ringing_flag: dbit 1
error_flag: dbit 1

; ========================= CONSTANTS =========================
FREQ    EQU 33333333
BAUD    EQU 115200
T2LOAD  EQU 65536-(FREQ/(32*BAUD))

; ---------- NEW PWM CONSTANTS ----------
HEATER_PIN  EQU P2.1
PWM_MAX     EQU 1000
T2_RATE     EQU 1000
T2_RELOAD   EQU (65536-(FREQ/(12*T2_RATE)))

; ========================= HARDWARE PINS =========================
BUTTON  EQU KEY.1
reset   equ P1.3
SPEAKER equ P1.5
ERROR_BTN EQU P3.7

ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0
COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0

sw0 equ SWA.0
sw1 equ SWA.1
sw2 equ SWA.2

$include(math32.asm)

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

; ========================= TIMER0 (SPEAKER) =========================
T0_RATE  EQU 4096
T0_RELOAD EQU (65536-(FREQ/(12*T0_RATE)))

Timer0_Init:
    mov a, TMOD
    anl a, #0F0h
    orl a, #01h
    mov TMOD, a
    mov TH0, #high(T0_RELOAD)
    mov TL0, #low(T0_RELOAD)
    setb ET0
    clr TR0
    ret

Timer0_ISR:
    mov TH0, #high(T0_RELOAD)
    mov TL0, #low(T0_RELOAD)
    cpl SPEAKER
    reti

; ========================= TIMER2 (PWM + CLOCK) =========================
Timer2_Init:
    mov a, T2CON
    anl a, #0FCh
    mov T2CON, a
    mov RCAP2H, #high(T2_RELOAD)
    mov RCAP2L, #low(T2_RELOAD)
    mov TH2,    #high(T2_RELOAD)
    mov TL2,    #low(T2_RELOAD)
    setb ET2
    setb TR2
    ret

Timer2_ISR:
    clr TF2
    push acc
    push psw

    inc ms_counterL
    mov a, ms_counterL
    jnz skip_msH
    inc ms_counterH
skip_msH:

    mov a, ms_counterL
    cjne a, #low(1000), skip_sec
    mov a, ms_counterH
    cjne a, #high(1000), skip_sec
    clr ms_counterL
    clr ms_counterH
    inc seconds
skip_sec:

    inc pwm_counterL
    mov a, pwm_counterL
    jnz skip_pwmH
    inc pwm_counterH
skip_pwmH:

    mov a, pwm_counterL
    cjne a, #low(PWM_MAX), compare_pwm
    mov a, pwm_counterH
    cjne a, #high(PWM_MAX), compare_pwm
    clr pwm_counterL
    clr pwm_counterH

compare_pwm:
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

; ========================= PWM CONTROL =========================
Set_PWM_Off:
    mov pwm_dutyL, #0
    mov pwm_dutyH, #0
    ret

Set_PWM_Full:
    mov pwm_dutyL, #low(PWM_MAX)
    mov pwm_dutyH, #high(PWM_MAX)
    ret

Set_PWM_Low:
    mov pwm_dutyL, #low(200)
    mov pwm_dutyH, #high(200)
    ret

Set_PWM_Med:
    mov pwm_dutyL, #low(500)
    mov pwm_dutyH, #high(500)
    ret

; ========================= AUTO FSM =========================
FSM_Control:
    mov a, state

s0: cjne a, #0, s1
    lcall Set_PWM_Off
    ret

s1: cjne a, #1, s2
    lcall Set_PWM_Full
    mov a, x+0
    clr c
    subb a, #150
    jnc s1_done
    mov state, #2
    clr seconds
s1_done:
    ret

s2: cjne a, #2, s3
    lcall Set_PWM_Low
    mov a, seconds
    clr c
    subb a, #60
    jnc s2_done
    mov state, #3
    clr seconds
s2_done:
    ret

s3: cjne a, #3, s4
    lcall Set_PWM_Full
    mov a, x+0
    clr c
    subb a, #220
    jnc s3_done
    mov state, #4
    clr seconds
s3_done:
    ret

s4: cjne a, #4, s5
    lcall Set_PWM_Med
    mov a, seconds
    clr c
    subb a, #30
    jnc s4_done
    mov state, #5
s4_done:
    ret

s5:
    lcall Set_PWM_Off
    mov a, x+0
    clr c
    subb a, #50
    jnc s5_done
    mov state, #0
s5_done:
    ret

; ========================= MAIN =========================
mycode:
    mov SP, #7FH
    mov P0MOD, #10101111b
    mov P1MOD, #10101010b
    anl P1MOD, #11110111b

    clr HEATER_PIN

    lcall Timer0_Init
    lcall Timer2_Init      ; NEW
    setb EA

forever:
    lcall FSM_Control      ; NEW automatic state machine
    sjmp forever

END
