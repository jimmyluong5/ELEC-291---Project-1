; ssr_pwm.asm - Timer-based PWM for SSR control
; 
$NOLIST
$MODMAX10
$LIST

CLK           EQU 33333333
TIMER0_RATE   EQU 1000     ; 1000Hz = 1ms tick
TIMER0_RELOAD EQU ((65536-(CLK/(12*TIMER0_RATE))))

SSR_PIN       EQU P0.3

; Reset vector
org 0x0000
    ljmp main

; Timer0 interrupt vector
org 0x000B
	ljmp Timer0_ISR

dseg at 0x30
PWM_counter:  ds 1    ; Counts 0-99 for PWM cycle
PWM_DUTY:     ds 1    ; Current duty cycle 0-100

cseg

;-------------------------------------------------
; Timer0 Init - 1ms interrupt for PWM
;-------------------------------------------------
Timer0_Init:
	mov a, TMOD
	anl a, #0xF0      ; Clear Timer0 bits, keep Timer1
	orl a, #0x01      ; Timer0 mode 1 (16-bit)
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb ET0          ; Enable Timer0 interrupt
	setb TR0          ; Start Timer0
	ret

;-------------------------------------------------
; Timer0 ISR - PWM logic runs every 1ms
; PWM period = 100ms (100 x 1ms)
;-------------------------------------------------
Timer0_ISR:
	; Reload timer (no auto-reload in mode 1)
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	
	push acc
	push psw
	
	; Increment counter
	inc PWM_counter
	mov a, PWM_counter
	cjne a, #100, Check_Duty
	mov PWM_counter, #0   ; Reset at 100
	
Check_Duty:
	; If counter < duty, SSR ON; else OFF
	mov a, PWM_counter
	clr c
	subb a, PWM_DUTY      ; A = counter - duty
	jnc SSR_Off_ISR       ; If counter >= duty, turn off
	setb SSR_PIN
	sjmp ISR_Done
	
SSR_Off_ISR:
	clr SSR_PIN
	
ISR_Done:
	pop psw
	pop acc
	reti

;-------------------------------------------------
; Set_Power - Set oven power percentage
; Input: A = power level (0-100)
; 0 = off, 100 = full power
;-------------------------------------------------
Set_Power:
	; Limit input to 0-100
	push acc
	clr c
	subb a, #101
	pop acc
	jc Power_OK       ; If A < 101, its valid
	mov a, #100       ; Clamp to 100
Power_OK:
	mov PWM_DUTY, a
	ret

;-------------------------------------------------
; Convenient functions for FSM states
;-------------------------------------------------
Power_Full:
	mov a, #100
	lcall Set_Power
	ret
	
Power_Half:
	mov a, #50
	lcall Set_Power
	ret

Power_Off:
	mov a, #0
	lcall Set_Power
	clr SSR_PIN       ; Immediate off
	ret

; Emergency stop - stops everything and freezes
Emergency_Stop:
	clr TR0           ; Stop Timer0
	clr EA            ; Disable all interrupts
	mov PWM_DUTY, #0
	clr SSR_PIN
	mov LEDRA, #0xFF  ; All LEDs on = error
Emergency_Freeze:
	sjmp Emergency_Freeze

; Check emergency button (KEY.0)
Check_Emergency:
	jb KEY.0, No_Emergency
	ljmp Emergency_Stop
No_Emergency:
	ret


; 7-seg lookup for display
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99
    DB 0x92, 0x82, 0xF8, 0x80, 0x90

Display_Power:
	push acc
	mov dptr, #myLUT
	; Display tens
	mov a, PWM_DUTY
	mov b, #10
	div ab
	movc a, @a+dptr
	mov HEX1, a
	; Display ones
	mov a, b
	movc a, @a+dptr
	mov HEX0, a
	pop acc
	ret

;-------------------------------------------------
; Main - Test program
;-------------------------------------------------
main:
    mov SP, #0x7F
    
    ; Configure SSR pin as output
    orl P0MOD, #00001000b
    clr SSR_PIN
    
    ; Init variables
    mov PWM_counter, #0
    mov PWM_DUTY, #0
    
    ; Clear 7-seg
    mov HEX0, #0xFF
    mov HEX1, #0xFF
    mov HEX2, #0xFF
    mov HEX3, #0xFF
    mov HEX4, #0xFF
    mov HEX5, #0xFF
    mov LEDRA, #0
    mov LEDRB, #0
    
    ; Init timer
    lcall Timer0_Init
    setb EA           ; Enable global interrupts
    
forever:
	; Read switches for power level (0-100)
	mov a, SWA
	anl a, #0x7F      ; Mask to 0-127
	
	; Cap at 100 (preserve A with push/pop)
	push acc
	clr c
	subb a, #101      ; Is a >= 101?
	pop acc           ; Restore original value
	jc Valid_Power    ; If a < 101, use it
	mov a, #100       ; Else cap at 100
	
Valid_Power:
	lcall Set_Power
	
	; Display current power
	lcall Display_Power
	
	; Show SSR state on LED0
	mov c, SSR_PIN
	mov LEDRA.0, c
	
	; Check emergency stop button
	lcall Check_Emergency
	
    ljmp forever
    
END
