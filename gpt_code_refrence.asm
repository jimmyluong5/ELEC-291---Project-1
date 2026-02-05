$MODMAX10

; ======================================================================================
; REFLOW OVEN CONTROLLER (CV-8052 on DE10-Lite) - SINGLE FILE
; - LCD on JP2 using P0 pins (your working mapping)
; - 4x4 Keypad logic EXACTLY based on your keypad test code + SAME PINS
; - PWM output pin does NOT reuse any of your keypad pins
; - Thermocouple path assumes: K-type -> OP07 gain ~300 -> DE10 ADC channel -> temperature
;   (If you later use a different sensor method, you only replace Read_Temperature section)
; ======================================================================================

; ==============================
; CLOCK
; ==============================
CLK                EQU 16600000          ; CV-8052 system clock (Hz)

; ==============================
; LCD (JP2 wiring YOU gave)
; ==============================
ELCD_RS            EQU P0.0              ; LCD RS -> P0.0
ELCD_E             EQU P0.2              ; LCD E  -> P0.2
ELCD_D4            EQU P0.7              ; LCD D4 -> P0.7
ELCD_D5            EQU P0.5              ; LCD D5 -> P0.5
ELCD_D6            EQU P0.3              ; LCD D6 -> P0.3
ELCD_D7            EQU P0.1              ; LCD D7 -> P0.1
; NOTE: LCD RW is tied to GND (not used)

; ==============================
; KEYPAD PINS (EXACT same pins as your keypad test program)
; ==============================
ROW1               EQU P1.2              ; Row 1 output
ROW2               EQU P1.4              ; Row 2 output
ROW3               EQU P1.6              ; Row 3 output
ROW4               EQU P2.0              ; Row 4 output

COL1               EQU P2.2              ; Col 1 input
COL2               EQU P2.4              ; Col 2 input
COL3               EQU P2.6              ; Col 3 input
COL4               EQU P3.0              ; Col 4 input

; ==============================
; PWM OUTPUT (SSR/Relay control)  (chosen to NOT conflict with keypad)
; ==============================
PWM_OUT            EQU P2.1              ; PWM output -> P2.1 (free pin)

; ==============================
; ADC CHANNEL (OP07 output into DE10 ADC)
; ==============================
ADC_CH             EQU 5                 ; pick channel 0..7 (change to your wiring)
                                          ; (You can change this later without touching rest)

; ==============================
; TIMER2 (1ms tick)
; ==============================
T2_RELOAD          EQU (65536-(CLK/1000)) ; reload for 1ms interrupt
T2_RELOAD_H        EQU high(T2_RELOAD)
T2_RELOAD_L        EQU low(T2_RELOAD)

; ==============================
; RAM VARIABLES
; ==============================
DSEG at 30H
; ---- math32 expects these as 4 bytes (DON’T change sizes) ----
x                 ds 4                   ; math32 operand/result X
y                 ds 4                   ; math32 operand Y
bcd               ds 5                   ; math32 BCD buffer

; ---- controller state ----
tempC             ds 1                   ; temperature in °C (0..255)
state             ds 1                   ; FSM state (0..5)
sec               ds 1                   ; seconds counter used by FSM (0..255)
count1msL         ds 1                   ; low byte of 1ms counter
count1msH         ds 1                   ; high byte of 1ms counter

; ---- reflow setpoints (edit via keypad) ----
soak_temp         ds 1                   ; °C
soak_time         ds 1                   ; seconds
reflow_temp       ds 1                   ; °C
reflow_time       ds 1                   ; seconds
cool_temp         ds 1                   ; °C

; ---- PWM compare threshold (0..1000) ----
pwm_ratioL        ds 1                   ; low byte (0..255)
pwm_ratioH        ds 1                   ; high byte (0..3) for up to 1000

; ---- keypad ----
key_code          ds 1                   ; latest key code (your keypad returns 0x00..0x0F)
edit_index        ds 1                   ; which setting is being edited (0..4)

BSEG
one_second_flag   dbit 1                 ; set every 1s in ISR
start_flag        dbit 1                 ; 1 = running the oven profile

; ==============================
; INCLUDE MATH + LCD LIBRARY
; ==============================
$include(math32.asm)                     ; 32-bit math library you uploaded
$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc)    ; your LCD 4-bit library
$LIST

; ======================================================================================
; INTERRUPT VECTORS
; ======================================================================================
CSEG at 0
    ljmp main                             ; reset jumps to main

ORG 002BH                                  ; Timer2 overflow vector
    ljmp Timer2_ISR                        ; jump to ISR

; ======================================================================================
; TIMER2 INIT (1ms tick) + PWM generation
; ======================================================================================
Timer2_Init:
    mov T2CON, #0                          ; stop timer2, auto-reload mode (device default style)
    mov RCAP2H, #T2_RELOAD_H               ; load reload high byte
    mov RCAP2L, #T2_RELOAD_L               ; load reload low byte
    mov TH2,    #T2_RELOAD_H               ; init current count high
    mov TL2,    #T2_RELOAD_L               ; init current count low
    clr a                                  ; clear A for init
    mov count1msL, a                       ; clear 1ms counter low
    mov count1msH, a                       ; clear 1ms counter high
    setb ET2                               ; enable timer2 interrupt
    setb TR2                               ; start timer2
    ret                                    ; return

; --------------------------
; Timer2 ISR runs every 1ms
; - increments 1ms counter
; - generates PWM on PWM_OUT using pwm_ratio (0..1000)
; - makes a 1-second flag and increments sec
; --------------------------
Timer2_ISR:
    clr TF2                                ; clear timer2 overflow flag
    push acc                               ; save ACC
    push psw                               ; save PSW

    ; ---- count1ms++ (16-bit) ----
    inc count1msL                          ; increment low byte
    mov a, count1msL                       ; read it to check overflow
    jnz no_ms_overflow                     ; if not zero, no overflow
    inc count1msH                          ; if overflow, increment high byte
no_ms_overflow:

    ; ---- PWM compare: if count1ms < pwm_ratio => PWM_OUT=1 else 0 ----
    ; Do (pwm_ratio - count1ms). If borrow -> count1ms > pwm_ratio.
    clr c                                  ; clear carry/borrow before subtract
    mov a, pwm_ratioL                      ; A = pwm_ratio low
    subb a, count1msL                      ; A = pwmL - msL
    mov a, pwm_ratioH                      ; A = pwm_ratio high
    subb a, count1msH                      ; A = pwmH - msH (includes borrow)
    ; If borrow happened, C=1 (meaning count1ms > pwm_ratio) => output should be 0
    cpl c                                  ; invert: C=1 means ON when count1ms < pwm_ratio
    mov PWM_OUT, c                         ; write PWM pin

    ; ---- 1000ms reached? -> set one_second_flag, reset ms counter, sec++ ----
    mov a, count1msL                       ; check low against low(1000)
    cjne a, #low(1000), isr_done           ; if not match, exit ISR
    mov a, count1msH                       ; check high against high(1000)
    cjne a, #high(1000), isr_done          ; if not match, exit ISR

    setb one_second_flag                   ; tell main loop “1s passed”
    clr a                                  ; A=0 for reset
    mov count1msL, a                       ; reset ms counter low
    mov count1msH, a                       ; reset ms counter high
    inc sec                                ; increment seconds for FSM timers

isr_done:
    pop psw                                ; restore PSW
    pop acc                                ; restore ACC
    reti                                   ; return from interrupt

; ======================================================================================
; SIMPLE DELAY (25ms) - copied style from your keypad test
; ======================================================================================
Wait25ms:
    mov R0, #15                            ; outer loop count
W25_L3:
    mov R1, #74                            ; middle loop count
W25_L2:
    mov R2, #250                           ; inner loop count
W25_L1:
    djnz R2, W25_L1                        ; inner delay
    djnz R1, W25_L2                        ; middle delay
    djnz R0, W25_L3                        ; outer delay
    ret                                    ; done

; ======================================================================================
; KEYPAD SCAN (BASED ON YOUR TEST CODE)
; - Returns: Carry=1 if key pressed, key_code in R7 (0x00..0x0F)
; - Uses the SAME ROW/COL pins you posted (no SWA.0, no KEY.1)
; ======================================================================================

CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M                    ; if column reads 1, not this key
    mov R7, %1                             ; else save key code into R7
    jnb %0, $                              ; wait until key released (debounce release)
    setb c                                 ; set carry = “key found”
    ret                                    ; return from Keypad routine
CHECK_COL_%M:
ENDMAC

Configure_Keypad_Pins:
    ; Rows outputs: P1.2, P1.4, P1.6, P2.0
    ; Columns inputs: P2.2, P2.4, P2.6, P3.0
    ; CV-8052 uses PxMOD: 1 = output, 0 = input
    ; Keep it explicit so you don’t accidentally enable P1.1 or P1.7.
    mov a, P1MOD                           ; read current P1 mode
    anl a, #0b_10101011                    ; clear bits 2,4,6 to 0 first (clean)
    orl a, #0b_01010100                    ; set bits 2,4,6 as outputs
    mov P1MOD, a                           ; write back P1 mode

    mov a, P2MOD                           ; read P2 mode
    anl a, #0b_10101011                    ; clear bits 0,2,4,6 to 0 (inputs)
    orl a, #0b_00000001                    ; set bit0 (ROW4) output
    ; NOTE: we also need PWM_OUT on P2.1 output, add it here:
    orl a, #0b_00000010                    ; set bit1 (PWM_OUT) output
    mov P2MOD, a                           ; write back P2 mode

    mov a, P3MOD                           ; read P3 mode
    anl a, #0b_11111110                    ; make P3.0 an input (bit0=0)
    mov P3MOD, a                           ; write back P3 mode

    ret                                    ; done

; Keypad routine (default layout only)
Keypad:
    ; ---- Make all rows low ----
    clr ROW1                               ; drive row1 low
    clr ROW2                               ; drive row2 low
    clr ROW3                               ; drive row3 low
    clr ROW4                               ; drive row4 low

    ; ---- If all columns are high => no key pressed ----
    mov c, COL1                            ; C = COL1
    anl c, COL2                            ; C = COL1 & COL2
    anl c, COL3                            ; C = C & COL3
    anl c, COL4                            ; C = C & COL4
    jnc Keypad_Debounce                    ; if any column is 0 -> key might be pressed
    clr c                                  ; no key => C=0
    ret                                    ; return

Keypad_Debounce:
    lcall Wait25ms                         ; wait to reject bouncing
    mov c, COL1                            ; check again
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Key_Code                    ; still low => real key
    clr c                                  ; bounce => no key
    ret

Keypad_Key_Code:
    ; ---- set all rows high first ----
    setb ROW1
    setb ROW2
    setb ROW3
    setb ROW4

    ; ---- check row1 ----
    clr ROW1
    CHECK_COLUMN(COL1, #01H)               ; 1
    CHECK_COLUMN(COL2, #02H)               ; 2
    CHECK_COLUMN(COL3, #03H)               ; 3
    CHECK_COLUMN(COL4, #0AH)               ; A
    setb ROW1

    ; ---- check row2 ----
    clr ROW2
    CHECK_COLUMN(COL1, #04H)               ; 4
    CHECK_COLUMN(COL2, #05H)               ; 5
    CHECK_COLUMN(COL3, #06H)               ; 6
    CHECK_COLUMN(COL4, #0BH)               ; B
    setb ROW2

    ; ---- check row3 ----
    clr ROW3
    CHECK_COLUMN(COL1, #07H)               ; 7
    CHECK_COLUMN(COL2, #08H)               ; 8
    CHECK_COLUMN(COL3, #09H)               ; 9
    CHECK_COLUMN(COL4, #0CH)               ; C
    setb ROW3

    ; ---- check row4 ----
    clr ROW4
    CHECK_COLUMN(COL1, #0EH)               ; *  (code 0x0E)
    CHECK_COLUMN(COL2, #00H)               ; 0
    CHECK_COLUMN(COL3, #0FH)               ; #  (code 0x0F)
    CHECK_COLUMN(COL4, #0DH)               ; D
    setb ROW4

    clr c                                  ; if we get here, no key found (shouldn’t happen)
    ret

; ======================================================================================
; THERMOCOUPLE READ (OP07 -> ADC -> tempC)
; - Uses DE10 ADC registers: ADC_C, ADC_H, ADC_L (same as ADC_to_voltage_7seg.asm)
; - Math based on your instructor note:
;   1) adc -> mV:      mV = adc * 5000 / 4096
;   2) mV -> uV:       uV = mV * 1000
;   3) temp_tc = uV / (GAIN*41)  where GAIN=300 => 300*41 = 12300
;   4) temp = temp_tc + cold_junction
; - Cold junction: use a constant now (CHANGE later if you measure it)
; ======================================================================================
GAIN_41           EQU 12300              ; 300 * 41
COLD_JUNC_C       EQU 22                 ; assume 22°C for now

Read_Temperature:
    ; ---- Select ADC channel for OP07 output ----
    mov a, #ADC_CH                         ; A = chosen ADC channel
    mov ADC_C, a                           ; tell ADC which channel to show

    ; ---- Load 12-bit ADC into x (32-bit) ----
    mov x+3, #0                            ; clear high bytes
    mov x+2, #0
    mov x+1, ADC_H                         ; ADC high byte
    mov x+0, ADC_L                         ; ADC low byte

    ; ---- x = (adc * 5000) / 4096  => millivolts ----
    Load_y(5000)                           ; y = 5000 (mV full scale)
    lcall mul32                            ; x = x * y
    Load_y(4096)                           ; y = 4096 (12-bit range)
    lcall div32                            ; x = x / y   (now x = mV)

    ; ---- x = x * 1000 => microvolts ----
    Load_y(1000)                           ; y = 1000
    lcall mul32                            ; x = x * 1000 (uV)

    ; ---- x = x / 12300 => °C from thermocouple (no cold junction yet) ----
    Load_y(GAIN_41)                        ; y = 12300
    lcall div32                            ; x = x / 12300

    ; ---- x = x + cold junction ----
    Load_y(COLD_JUNC_C)                    ; y = cold junction temperature
    lcall add32                            ; x = x + y

    ; ---- tempC = low byte of x ----
    mov tempC, x+0                         ; save final temp (0..255)

    ret                                    ; done

; ======================================================================================
; LCD DISPLAY (simple)
; Line1: "T:XXX S:X"
; Line2: "PWM:XXX"
; ======================================================================================
msg_t:    db 'T:',0
msg_s:    db ' S:',0
msg_pwm:  db 'PWM:',0

Send3Digits:                                  ; expects A = 0..255, prints XXX to LCD
    push acc                                   ; save A
    mov b, #100                                ; B=100
    div ab                                     ; A=hundreds, B=remainder
    orl a, #0x30                               ; to ASCII
    lcall ?WriteData                           ; print hundreds
    mov a, b                                   ; A=remainder
    mov b, #10                                 ; B=10
    div ab                                     ; A=tens, B=units
    orl a, #0x30                               ; to ASCII
    lcall ?WriteData                           ; print tens
    mov a, b                                   ; A=units
    orl a, #0x30                               ; to ASCII
    lcall ?WriteData                           ; print units
    pop acc                                    ; restore A
    ret

Show_Status:
    ; ---- Line 1: T:XXX S:X ----
    Set_Cursor(1,1)                            ; cursor row1 col1
    Send_Constant_String(#msg_t)               ; print "T:"
    mov a, tempC                               ; A=temp
    lcall Send3Digits                           ; print temp as 3 digits

    Send_Constant_String(#msg_s)               ; print " S:"
    mov a, state                               ; A=state (0..5)
    orl a, #0x30                               ; ASCII digit
    lcall ?WriteData                           ; print state digit

    ; ---- Line 2: PWM:XXX ----
    Set_Cursor(2,1)                            ; cursor row2 col1
    Send_Constant_String(#msg_pwm)             ; print "PWM:"
    ; show pwm% roughly = pwm_ratio /10 (since 0..1000 maps to 0..100%)
    ; compute (pwm_ratioH:L) / 10 using simple approx: only low byte is fine for display
    mov a, pwm_ratioL                          ; show low byte (good enough for testing)
    lcall Send3Digits                           ; print 000-255 (for now)
    ret

; ======================================================================================
; KEYPAD -> CONTROL LOGIC
; - A (0x0A) : START/STOP toggle
; - B (0x0B) : next edit field (0..4)
; - C (0x0C) : increment selected field
; - D (0x0D) : decrement selected field
; ======================================================================================
Handle_Key:
    mov a, key_code                            ; A = key_code

    cjne a, #0AH, chkB                         ; if not A, check B
    cpl start_flag                             ; toggle running flag
    clr sec                                   ; reset seconds timer
    ret

chkB:
    cjne a, #0BH, chkC                         ; if not B, check C
    inc edit_index                             ; move to next setting
    mov a, edit_index
    cjne a, #5, hb_done                         ; if <5 ok
    mov edit_index, #0                         ; wrap back to 0
hb_done:
    ret

chkC:
    cjne a, #0CH, chkD                         ; if not C, check D
    lcall Inc_Selected                         ; increment selected setpoint
    ret

chkD:
    cjne a, #0DH, hk_done                      ; if not D, done
    lcall Dec_Selected                         ; decrement selected setpoint
hk_done:
    ret

Inc_Selected:
    mov a, edit_index                          ; choose which variable to change
    cjne a, #0, inc1
    inc soak_temp
    ret
inc1:
    cjne a, #1, inc2
    inc soak_time
    ret
inc2:
    cjne a, #2, inc3
    inc reflow_temp
    ret
inc3:
    cjne a, #3, inc4
    inc reflow_time
    ret
inc4:
    inc cool_temp
    ret

Dec_Selected:
    mov a, edit_index
    cjne a, #0, dec1
    dec soak_temp
    ret
dec1:
    cjne a, #1, dec2
    dec soak_time
    ret
dec2:
    cjne a, #2, dec3
    dec reflow_temp
    ret
dec3:
    cjne a, #3, dec4
    dec reflow_time
    ret
dec4:
    dec cool_temp
    ret

; ======================================================================================
; FSM (0..5) - same idea as the older group code, but using tempC + Timer2 seconds
; - state0: idle (pwm=0) wait start_flag
; - state1: ramp to soak (pwm=100%) until temp >= soak_temp
; - state2: soak hold (pwm low) until sec >= soak_time
; - state3: ramp to reflow (pwm=100%) until temp >= reflow_temp
; - state4: reflow hold (pwm medium) until sec >= reflow_time
; - state5: cool (pwm=0) until temp <= cool_temp then back to idle
; ======================================================================================

; helper: set pwm_ratio = immediate 0..1000
SetPWM_Imm:                                     ; expects R6:R5 = value (H:L)
    mov pwm_ratioL, R5                          ; store low byte
    mov pwm_ratioH, R6                          ; store high byte
    ret

FSM:
    mov a, state                                ; A = current state

; ---------------- state 0: idle ----------------
st0:
    cjne a, #0, st1                              ; if not 0, go next
    mov R5, #0                                   ; pwm=0
    mov R6, #0
    lcall SetPWM_Imm
    jnb start_flag, fsm_done                      ; if not started, stay idle
    mov state, #1                                ; go to ramp soak
    clr sec                                      ; reset seconds timer
    clr one_second_flag                           ; clear flag
    sjmp fsm_done

; ---------------- state 1: ramp to soak ----------------
st1:
    cjne a, #1, st2
    mov R5, #low(1000)                           ; pwm=1000 (100%)
    mov R6, #high(1000)
    lcall SetPWM_Imm
    mov a, soak_temp                             ; A=soak_temp
    clr c
    subb a, tempC                                ; A = soak_temp - temp
    jnc fsm_done                                 ; if soak_temp >= temp, keep heating
    mov state, #2                                ; else reached soak -> go soak hold
    clr sec                                      ; reset seconds timer
    sjmp fsm_done

; ---------------- state 2: soak hold ----------------
st2:
    cjne a, #2, st3
    mov R5, #low(150)                            ; pwm about 15% (tune later)
    mov R6, #high(150)
    lcall SetPWM_Imm
    mov a, soak_time                             ; A=soak_time
    clr c
    subb a, sec                                  ; A = soak_time - sec
    jnc fsm_done                                 ; if time not done, stay
    mov state, #3                                ; else go ramp to reflow
    clr sec
    sjmp fsm_done

; ---------------- state 3: ramp to reflow ----------------
st3:
    cjne a, #3, st4
    mov R5, #low(1000)                           ; pwm=100%
    mov R6, #high(1000)
    lcall SetPWM_Imm
    mov a, reflow_temp
    clr c
    subb a, tempC
    jnc fsm_done                                 ; keep heating until reached
    mov state, #4                                ; reached reflow -> reflow hold
    clr sec
    sjmp fsm_done

; ---------------- state 4: reflow hold ----------------
st4:
    cjne a, #4, st5
    mov R5, #low(250)                            ; pwm about 25% (tune later)
    mov R6, #high(250)
    lcall SetPWM_Imm
    mov a, reflow_time
    clr c
    subb a, sec
    jnc fsm_done                                 ; hold until time done
    mov state, #5                                ; go cool
    sjmp fsm_done

; ---------------- state 5: cool ----------------
st5:
    ; if state==5, cool with pwm=0 until temp <= cool_temp
    mov R5, #0
    mov R6, #0
    lcall SetPWM_Imm
    mov a, tempC
    clr c
    subb a, cool_temp                            ; A = temp - cool_temp
    jnc fsm_done                                 ; if temp >= cool_temp keep cooling
    mov state, #0                                ; else done -> idle
    clr start_flag
    clr sec
fsm_done:
    ret

; ======================================================================================
; MAIN
; ======================================================================================
main:
    mov SP, #7FH                                ; init stack pointer
    clr a                                       ; A=0
    mov state, a                                ; state=0
    mov sec, a                                  ; sec=0
    mov edit_index, a                           ; edit index=0
    clr start_flag                               ; not running
    clr one_second_flag                          ; clear flag

    ; ---- Configure LCD pins as outputs on P0 ----
    mov P0MOD, #0b_10101111                     ; outputs: 0,1,2,3,5,7 (LCD lines)

    ; ---- Configure keypad + PWM pins ----
    lcall Configure_Keypad_Pins                 ; sets row outputs + col inputs + pwm pin output

    ; ---- Init Timer2 (1ms) ----
    lcall Timer2_Init                           ; start timer2 ISR

    ; ---- Init LCD in 4-bit mode ----
    lcall ELCD_4BIT                             ; LCD init sequence

    ; ---- Default profile values (edit later from keypad) ----
    mov soak_temp,   #150                       ; soak temp = 150C
    mov soak_time,   #60                        ; soak time = 60s
    mov reflow_temp, #220                       ; reflow temp = 220C
    mov reflow_time, #30                        ; reflow time = 30s
    mov cool_temp,   #50                        ; cool temp = 50C

    setb EA                                     ; enable global interrupts

forever:
    ; ---- Read temperature from ADC/OP07 ----
    lcall Read_Temperature                      ; updates tempC

    ; ---- If 1 second passed, one_second_flag is set (sec already incremented in ISR) ----
    ; (You can use the flag for once-per-second UI updates if you want)

    ; ---- Scan keypad ----
    lcall Keypad                                ; carry=1 if key, code in R7
    jnc no_key_press                            ; if no key, skip handler
    mov key_code, R7                            ; store key
    lcall Handle_Key                            ; start/stop/edit/inc/dec logic
no_key_press:

    ; ---- Run FSM every loop ----
    lcall FSM                                   ; updates state + pwm_ratio

    ; ---- Update LCD ----
    lcall Show_Status                            ; prints temp/state/pwm

    sjmp forever                                 ; loop forever

END
