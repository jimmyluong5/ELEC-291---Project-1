$NOLIST
$MODMAX10
$LIST

;=========================================================
; CLOCK + TIMERS
;=========================================================
CLK           EQU 33333333

TIMER0_RATE   EQU 4096
TIMER0_RELOAD EQU ((65536-(CLK/(12*TIMER0_RATE))))

TIMER2_RATE   EQU 15 ;we can always change the timer 2 rate 
TIMER2_RELOAD EQU ((65536-(CLK/(12*TIMER2_RATE))))

; Piezo / speaker output pin (matches working_speaker_fsm.asm)
SOUND_OUT     EQU P2.1
PWM           EQU P2.7

KEY_STAR      EQU 0x0E      ; *
KEY_POUND     EQU 0x0F      ; #

; FSM buttons (DE10-Lite KEYs are active-low)
FSM_NEXT_BTN  EQU KEY.1      ; KEY1: advance state
FSM_RESET_BTN EQU KEY.3      ; KEY3: reset to state 0

; LCD value field start column (3-char field at col 11..13)
VALUE_COL     EQU 11

;=========================================================
; VECTORS
;=========================================================
org 0x0000
    ljmp main
org 0x000B
    ljmp Timer0_ISR
org 0x002B
    ljmp Timer2_ISR

;=========================================================
; DATA
;=========================================================
dseg at 0x30
PWM_counter:  ds 1
PWM_duty:     ds 1

bcd:          ds 5          ; packed BCD digit buffer (typed digits go here)
param_index:  ds 1          ; 0..4
sec_div:      ds 1           ; counts 0..14 for 1 second tick from TIMER2_RATE=15
stale_secs:   ds 1           ; seconds temp unchanged
last_temp:    ds 2           ; last temp snapshot
current_temp: ds 2


; parameters you enter (stored as bcd+0/bcd+1 snapshots)
soak_temp:    ds 2
soak_time:    ds 2
reflow_temp:  ds 2
reflow_time:  ds 2

; --- FSM state variables (run after profile ready) ---
state:        ds 1          ; 0..6
prev_state:   ds 1
beep_count:   ds 1          ; remaining extra beeps to play

bseg
blank_flag:   dbit 1         ; 1 = nothing typed yet
mode_duty:    dbit 1         ; 1 = duty menu (SW4 ON)
fsm_started:  dbit 1         ; 1 once we enter FSM mode
ringing_flag: dbit 1         ; 1 when alarm tone is active (don't interrupt)
error_flag:       dbit 1     ; 1 = oven error condition detected
error_beep_sent:  dbit 1     ; 1 = we've already queued the 10-pulse error beep for this error event
one_sec_flag:     dbit 1     ; set once per second by Timer2 ISR

cseg

;=========================================================
; LCD wiring (your current wiring)
;=========================================================
LCD_RS equ P0.0
LCD_E  equ P0.2
LCD_D4 equ P0.7
LCD_D5 equ P0.5
LCD_D6 equ P0.3
LCD_D7 equ P0.1

$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc) ; ELCD_4BIT, Set_Cursor, WriteData, WriteCommand, Send_Constant_String, Wait_Milli_Seconds
$include(Read_keypad.inc)            ; Keypad, Configure_Keypad_Pins, Shift_Digits_Left (uses R7)
$LIST

;=========================================================
; STRINGS (all <= 10 chars before VALUE_COL so they don't overwrite)
;=========================================================
soaktemp_str:    db 'SOAK Tmp:',0      ; 9 chars
soaktime_str:    db 'SOAK time:',0     ; 10 chars
reflowtemp_str:  db 'REFL Tmp:',0      ; 8 chars
reflowtime_str:  db 'REFL time:',0     ; 9 chars
duty_str:        db 'DUTY (%):',0      ; 9 chars
profile_ready:   db 'PROFILE READY',0

help_param:      db '0-999 *=ENT#CLR',0 ; 15 chars
help_duty:       db '0-100 *=SET#CLR',0 ; 15 chars
help_done:       db '*=RST #=CLR     ',0 ; 16 chars (pads)

; --- FSM state messages (LCD line 1) ---
state0_msg:     db 'State: 0',0
state1_msg:     db 'State: 1',0
state2_msg:     db 'State: 2',0
state3_msg:     db 'State: 3',0
state4_msg:     db 'State: 4',0
state5_msg:     db 'State: 5',0
state6_msg:     db 'State: 6',0

;=========================================================
; 7-SEG LUT (0..9)
;=========================================================
T_7seg:
    DB 0xC0,0xF9,0xA4,0xB0,0x99
    DB 0x92,0x82,0xF8,0x80,0x90

;=========================================================
; TIMER0
;=========================================================
Timer0_Init:
    ; Preserve Timer1 config (upper nibble) and set Timer0 to mode 1 (16-bit)
    mov a, TMOD
    anl a, #0F0h
    orl a, #01h
    mov TMOD, a
    mov TH0,#high(TIMER0_RELOAD)
    mov TL0,#low(TIMER0_RELOAD)
    setb ET0
    clr  TR0            ; OFF by default (turn on only when beeping)
    ret

Timer0_ISR:
    clr TF0
    push acc
    push psw

    mov TH0,#high(TIMER0_RELOAD)
    mov TL0,#low(TIMER0_RELOAD)
    cpl SOUND_OUT

    pop psw
    pop acc
    reti

;=========================================================
; TIMER2 PWM
;=========================================================
Timer2_Init:
    mov T2CON,#0
    mov TH2,#high(TIMER2_RELOAD)
    mov TL2,#low(TIMER2_RELOAD)
    mov RCAP2H,#high(TIMER2_RELOAD)
    mov RCAP2L,#low(TIMER2_RELOAD)

    mov PWM_counter,#0
    mov PWM_duty,#0

    setb ET2
    setb TR2
    ret

Timer2_ISR:
    clr TF2
    push acc
    push psw

    mov a,PWM_counter
    jnz p1x
    setb PWM
p1x:
    cjne a,PWM_duty,p2x
    clr PWM
p2x:
    inc a
    cjne a,#100,p3x
    mov a,#0
p3x:
    mov PWM_counter,a
    
        ; ---- 1-second tick generator (Timer2 at 15 Hz) ----
    inc sec_div
    mov a, sec_div
    cjne a, #15, t2_no_1s
    mov sec_div, #0
    setb one_sec_flag
t2_no_1s:


    pop psw
    pop acc
    reti

;=========================================================
; CLEAR INPUT
;=========================================================
Clear_Input:
    clr a
    mov bcd+0,a
    mov bcd+1,a
    mov bcd+2,a
    mov bcd+3,a
    mov bcd+4,a
    setb blank_flag
    ret

;=========================================================
; LCD HELPERS
;=========================================================
LCD_Clear:
    WriteCommand(#01h)
    Wait_Milli_Seconds(#2)
    ret

LCD_ClearValueArea:
    Set_Cursor(1,VALUE_COL)
    WriteData(#' ')
    WriteData(#' ')
    WriteData(#' ')
    ret

LCD_ClearLine2:
    Set_Cursor(2,1)
    mov R0,#16
L2C1:
    WriteData(#' ')
    djnz R0,L2C1
    ret

;=========================================================
; GET LSD 3 DIGITS FROM BCD INTO R0/R1/R2
; R0=hundreds, R1=tens, R2=units
;=========================================================
Get_LSD3:
    ; units
    mov a,bcd+0
    anl a,#0Fh
    mov R2,a

    ; tens
    mov a,bcd+0
    swap a
    anl a,#0Fh
    mov R1,a

    ; hundreds
    mov a,bcd+1
    anl a,#0Fh
    mov R0,a
    ret

;=========================================================
; WriteDigitA: prints A (0..9) as ASCII digit
;=========================================================
WriteDigitA:
    cjne a,#0,WD1
    WriteData(#'0')
    ret
WD1: cjne a,#1,WD2
    WriteData(#'1')
    ret
WD2: cjne a,#2,WD3
    WriteData(#'2')
    ret
WD3: cjne a,#3,WD4
    WriteData(#'3')
    ret
WD4: cjne a,#4,WD5
    WriteData(#'4')
    ret
WD5: cjne a,#5,WD6
    WriteData(#'5')
    ret
WD6: cjne a,#6,WD7
    WriteData(#'6')
    ret
WD7: cjne a,#7,WD8
    WriteData(#'7')
    ret
WD8: cjne a,#8,WD9
    WriteData(#'8')
    ret
WD9:
    WriteData(#'9')
    ret

;=========================================================
; LCD_ShowInput: right-aligned 3-char field (always shows up to 3 digits)
; 5 -> "  5", 90 -> " 90", 150 -> "150"
;=========================================================
LCD_ShowInput:
    lcall LCD_ClearValueArea
    jb blank_flag, LSI_done

    lcall Get_LSD3

    mov a,R0
    jnz LSI_3
    mov a,R1
    jnz LSI_2

LSI_1:
    Set_Cursor(1,VALUE_COL+2)
    mov a,R2
    lcall WriteDigitA
    sjmp LSI_done

LSI_2:
    Set_Cursor(1,VALUE_COL+1)
    mov a,R1
    lcall WriteDigitA
    mov a,R2
    lcall WriteDigitA
    sjmp LSI_done

LSI_3:
    Set_Cursor(1,VALUE_COL)
    mov a,R0
    lcall WriteDigitA
    mov a,R1
    lcall WriteDigitA
    mov a,R2
    lcall WriteDigitA

LSI_done:
    ret

;=========================================================
; HEX_ShowInput: show current input on HEX2 HEX1 HEX0 (no leading zeros)
;=========================================================
HEX_ShowInput:
    mov dptr,#T_7seg
    jb blank_flag, HX_blank

    lcall Get_LSD3

    ; hundreds
    mov a,R0
    jz HX_h_blank
    movc a,@a+dptr
    mov HEX2,a
    sjmp HX_tens
HX_h_blank:
    mov HEX2,#0FFh

HX_tens:
    mov a,R1
    jnz HX_t_show
    mov a,R0
    jz  HX_t_blank
HX_t_show:
    mov a,R1
    movc a,@a+dptr
    mov HEX1,a
    sjmp HX_units
HX_t_blank:
    mov HEX1,#0FFh

HX_units:
    mov a,R2
    movc a,@a+dptr
    mov HEX0,a

    mov HEX3,#0FFh
    mov HEX4,#0FFh
    mov HEX5,#0FFh
    ret

HX_blank:
    mov HEX0,#0FFh
    mov HEX1,#0FFh
    mov HEX2,#0FFh
    mov HEX3,#0FFh
    mov HEX4,#0FFh
    mov HEX5,#0FFh
    ret

;=========================================================
; LCD_Update:
; - if mode_duty=1 -> DUTY menu
; - else -> parameter menu based on param_index
;=========================================================
LCD_Update:
    lcall LCD_Clear
    lcall LCD_ClearLine2

    jb mode_duty, LCD_DUTY

    ; ---- parameter menu ----
    mov a,param_index
    cjne a,#0,Lp1
    Set_Cursor(1,1)
    Send_Constant_String(#soaktemp_str)
    Set_Cursor(2,1)
    Send_Constant_String(#help_param)
    lcall LCD_ShowInput
    ret
    
LCD_DUTY:
    Set_Cursor(1,1)
    Send_Constant_String(#duty_str)
    Set_Cursor(2,1)
    Send_Constant_String(#help_duty)
    lcall LCD_ShowInput
    ret
    
        
Lp1:
    cjne a,#1,Lp2
    Set_Cursor(1,1)
    Send_Constant_String(#soaktime_str)
    Set_Cursor(2,1)
    Send_Constant_String(#help_param)
    lcall LCD_ShowInput
    ret
Lp2:
    cjne a,#2,Lp3
    Set_Cursor(1,1)
    Send_Constant_String(#reflowtemp_str)
    Set_Cursor(2,1)
    Send_Constant_String(#help_param)
    lcall LCD_ShowInput
    ret
Lp3:
    cjne a,#3,Lp4
    Set_Cursor(1,1)
    Send_Constant_String(#reflowtime_str)
    Set_Cursor(2,1)
    Send_Constant_String(#help_param)
    lcall LCD_ShowInput
    ret
Lp4:
    Set_Cursor(1,1)
    Send_Constant_String(#profile_ready)
    Set_Cursor(2,1)
    Send_Constant_String(#help_done)
    lcall LCD_ClearValueArea
    ret



;=========================================================
; Save_Param: store current input into current parameter variable
;=========================================================
Save_Param:
    mov a,param_index
    cjne a,#0,sp1
    mov soak_temp+0,bcd+0
    mov soak_temp+1,bcd+1
    ret
sp1:
    cjne a,#1,sp2
    mov soak_time+0,bcd+0
    mov soak_time+1,bcd+1
    ret
sp2:
    cjne a,#2,sp3
    mov reflow_temp+0,bcd+0
    mov reflow_temp+1,bcd+1
    ret
sp3:
    mov reflow_time+0,bcd+0
    mov reflow_time+1,bcd+1
    ret

;=========================================================
; Apply_Duty_From_BCD (0..100 clamp) -> PWM_duty
; uses LSD3 digits in bcd
;=========================================================
Apply_Duty_From_BCD:
    lcall Get_LSD3           ; R0 hundreds, R1 tens, R2 units

    ; if hundreds >= 2 -> clamp 100
    mov a,R0
    cjne a,#2,AD_chk_ge2
    sjmp AD_clamp100
AD_chk_ge2:
    jnc AD_clamp100          ; if A >= 2

    ; if hundreds == 1 then only allow 100
    mov a,R0
    jz AD_0_99
    mov a,R1
    orl a,R2
    jnz AD_clamp100
    mov PWM_duty,#100
    ret

AD_0_99:
    ; duty = tens*10 + units
    mov a,R1
    mov b,#10
    mul ab                   ; A = tens*10
    add a,R2
    mov PWM_duty,a
    ret

AD_clamp100:
    mov PWM_duty,#100
    ret

;=========================================================
; Menu_Sync_With_SW4:
; SWA.4 = 1 -> duty menu
; SWA.4 = 0 -> param menu AND force PWM_duty=0
; If menu changes, clear input + refresh LCD + HEX.
;=========================================================
Menu_Sync_With_SW4:
    ; read SW4 into C
    mov c, SWA.4

    ; if SW4=0 -> force PWM_duty=0 always
    jc MSW_sw_on
    mov PWM_duty,#0

MSW_sw_on:
    ; compare with mode_duty
    mov a,#0
    jb mode_duty, MSW_md1
    ; mode_duty=0
    jnc MSW_no_change        ; SW4=0 and mode=0
    ; SW4=1 but mode=0 -> change
    setb mode_duty
    clr  fsm_started
    lcall Clear_Input
    lcall LCD_Update
    lcall HEX_ShowInput
    ret

MSW_md1:
    ; mode_duty=1
    jc MSW_no_change         ; SW4=1 and mode=1
    ; SW4=0 but mode=1 -> change
    clr mode_duty
    clr  fsm_started
    lcall Clear_Input
    lcall LCD_Update
    lcall HEX_ShowInput
    ret

MSW_no_change:
    ret

;=========================================================
; Handle_Key:
; - digits: update bcd + show on LCD+HEX
; - #: clear input + clear LCD field + blank HEX
; - *:
;    if duty menu: apply PWM_duty (0..100 clamp), stay in duty menu
;    else param menu:
;       if param_index==4 -> restart to 0
;       else save param and advance
;=========================================================
Handle_Key:
    mov a,R7

    ; CLEAR (#)
    cjne a,#KEY_POUND,HK_star
    lcall Clear_Input
    lcall LCD_ShowInput
    lcall HEX_ShowInput
    ret

HK_star:
    ; ENTER (*)
    cjne a,#KEY_STAR,HK_digit

    jb mode_duty, HK_star_duty

    ; ---- parameter menu star ----
    mov a,param_index
    cjne a,#4,HK_param_save
    ; at DONE screen: restart parameters
    mov param_index,#0
    clr fsm_started
    lcall Clear_Input
    lcall LCD_Update
    lcall HEX_ShowInput
    ret

HK_param_save:
    lcall Save_Param
    inc param_index
    lcall Clear_Input
    lcall LCD_Update
    lcall HEX_ShowInput
    ret

HK_star_duty:
    lcall Apply_Duty_From_BCD
    lcall Clear_Input
    lcall LCD_Update
    lcall HEX_ShowInput
    ret

HK_digit:
    ; accept only 0..9 (ignore A,B,C,D)
    mov a,R7
    cjne a,#0Ah,HK_maybe
    ret
HK_maybe:
    jc HK_ok
    ret
HK_ok:
    clr blank_flag
    lcall Shift_Digits_Left   ; uses R7 nibble
    lcall LCD_ShowInput
    lcall HEX_ShowInput
    ret


;=========================================================
; BEEP ONCE (short) using Timer0 tone
;=========================================================
Beep_Once:
    ; If alarm already ringing, don't interrupt it
    jb  ringing_flag, BO_done

    setb TR0
    Wait_Milli_Seconds(#50)
    Wait_Milli_Seconds(#50)     ; ~100ms ON
    clr  TR0
    clr  SOUND_OUT
BO_done:
    ret

;-----------------------------------------
; Loud_Beep_Once: same tone, includes a gap after the beep
;-----------------------------------------
Loud_Beep_Once:
    setb TR0
    Wait_Milli_Seconds(#50)
    Wait_Milli_Seconds(#50)     ; ~100ms ON
    clr  TR0
    clr  SOUND_OUT
    Wait_Milli_Seconds(#50)
    Wait_Milli_Seconds(#50)     ; ~100ms gap
    ret

;-----------------------------------------
; Do_ExtraBeeps: play one extra beep per call while beep_count > 0
;-----------------------------------------
Do_ExtraBeeps:
    mov a, beep_count
    jz  DEB_done
    lcall Loud_Beep_Once
    dec beep_count
DEB_done:
    ret



;=========================================================
; Trigger_Error_Once:
;   If error_flag is set and we haven't already queued beeps,
;   queue EXACTLY 10 pulses via beep_count and latch it.
;=========================================================
Trigger_Error_Once:
    jb  error_flag, te_check_latch
    ; no error -> clear latch so a future error event can beep again
    clr error_beep_sent
    ret

te_check_latch:
    jb  error_beep_sent, te_done
    setb error_beep_sent
    mov  beep_count, #10     ; EXACTLY 10 pulses (do not change)
te_done:
    ret



;-----------------------------------------
; Alarm control (continuous tone via Timer0)
;-----------------------------------------
Alarm_On:
    setb ringing_flag
    setb TR0
    ret

Alarm_Off:
    clr ringing_flag
    clr TR0
    clr SOUND_OUT
    ret


;=========================================================
; Update_State_Display: prints "State: X" on LCD line 1
;=========================================================
Update_State_Display:
    Set_Cursor(1,1)
    mov a,state
    cjne a,#0,usd1
    Send_Constant_String(#state0_msg)
    ret
usd1:
    cjne a,#1,usd2
    Send_Constant_String(#state1_msg)
    ret
usd2:
    cjne a,#2,usd3
    Send_Constant_String(#state2_msg)
    ret
usd3:
    cjne a,#3,usd4
    Send_Constant_String(#state3_msg)
    ret
usd4:
    cjne a,#4,usd5
    Send_Constant_String(#state4_msg)
    ret
usd5:
    cjne a,#5,usd6
    Send_Constant_String(#state5_msg)
    ret
usd6:
    Send_Constant_String(#state6_msg)
    ret

;=========================================================
; FSM_RunStep:
; - Only active when param_index==4 and SW4 is OFF (mode_duty=0)
; - KEY3 resets to state 0
; - KEY1 advances 0->6 then wraps to 0
; - On state change: update LCD line 1 + beep once
;=========================================================
FSM_RunStep:
    ; one-time init when entering FSM mode
    jb  fsm_started, fsm_inputs
    setb fsm_started
    mov state,#0
    mov prev_state,#0
    lcall LCD_Clear
    lcall LCD_ClearLine2
    lcall Update_State_Display
    mov beep_count,#0
        mov stale_secs,#0
    mov sec_div,#0
    clr one_sec_flag

    clr ringing_flag

fsm_inputs:
    ; RESET (KEY3)
           ; plays one queued pulse per FSM call
      ; if error just happened, queue 10 pulse
    
    
        ; ---- 60s "temperature not changing" detection ----
    jnb one_sec_flag, fsm_no_1s
    clr one_sec_flag

    ; if current_temp != last_temp -> reset stale counter
  ; compare low byte
mov a, current_temp
cjne a, last_temp, temp_changed

; compare high byte
mov a, current_temp+1
cjne a, last_temp+1, temp_changed

; ---- unchanged this second ----
inc stale_secs
mov a, stale_secs
cjne a, #60, fsm_no_1s
setb error_flag
sjmp fsm_no_1s

temp_changed:
    ; copy BOTH bytes correctly
    mov a, current_temp
    mov last_temp, a
    mov a, current_temp+1
    mov last_temp+1, a

    clr error_flag
    mov stale_secs, #0

fsm_no_1s:
lcall Trigger_Error_Once
    
    
    jb  FSM_RESET_BTN, fsm_chk_next
    Wait_Milli_Seconds(#20)     ; debounce
    jb  FSM_RESET_BTN, fsm_chk_next

    mov state,#0
    mov a,#0
    mov prev_state,a
    lcall Update_State_Display
    mov beep_count,#0
fsm_wait_rst_rel:
    jnb FSM_RESET_BTN, fsm_wait_rst_rel
    ret

fsm_chk_next:
    ; NEXT (KEY1)
    jb  FSM_NEXT_BTN, fsm_done
    Wait_Milli_Seconds(#20)
    jb  FSM_NEXT_BTN, fsm_done

    inc state
    mov a,state
    cjne a,#7,fsm_no_wrap
    mov state,#0
fsm_no_wrap:

    ; state change?
    mov a,state
    cjne a,prev_state,fsm_changed
    sjmp fsm_wait_next_rel

fsm_changed:
    mov prev_state,a
    lcall Update_State_Display

    ; Always do a single beep on any state transition
    lcall Beep_Once

    ; Load extra-beep pattern (do NOT change pulse counts):
    ; - State 5 => total 5 beeps (1 already done + 4 extra)
    ; - State 6 => total 10 beeps (1 already done + 9 extra)
    
        mov beep_count, #0
    mov a, state
    cjne a, #5, fsm_wait_next_rel
    mov beep_count, #4       ; total 5 pulses at state 5 (1 + 4)

fsm_wait_next_rel:
    jnb FSM_NEXT_BTN, fsm_wait_next_rel
fsm_done:
    ret


;=========================================================
; MAIN
;=========================================================
main:
    mov SP,#7Fh

    ; P0.7,5,3,2,1,0 outputs (D7,D6,D5,E,D4,RS)
    mov P0MOD,#10101111b
    mov P1MOD,#10000010b
    ; ensure P1.5 is an output for the piezo speaker
    orl P1MOD,#00100000b
    mov P2MOD,#10000010b

    clr error_flag
    clr error_beep_sent
    clr one_sec_flag
    mov sec_div, #0
    mov stale_secs, #0
    mov last_temp, #0         ; will get overwritten on first temp change
    mov last_temp+1, #0


    ; init state
    clr a
    mov param_index,a
    clr mode_duty
    clr  fsm_started

    lcall Clear_Input
    lcall Configure_Keypad_Pins

    ; timers/interrupts
    lcall Timer0_Init
    lcall Timer2_Init
    setb PWM
    setb EA

    ; LCD init + first screen
    lcall LCD_4BIT
    lcall LCD_Update
    lcall HEX_ShowInput

loop:
    ; keep menu synced to SW4 every loop
   
    
    lcall Do_ExtraBeeps
    lcall Menu_Sync_With_SW4

    ; If profile is ready and we're in param menu, run the 0..6 FSM instead of keypad entry
    jb  mode_duty, not_fsm
    mov a,param_index
    cjne a,#4,not_fsm
    lcall FSM_RunStep
    sjmp loop

not_fsm:
    lcall Keypad
    jnc loop
    ; Beep once on every keypad keypress
    lcall Beep_Once
    lcall Handle_Key
    sjmp loop

END
