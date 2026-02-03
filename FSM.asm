$MODMAX10


CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

ORG 0x0000
	ljmp main

;key terms:
;cjne - compare and jump if not equal
;pwm - pulse wave modulation 
;subb - subtract with borrow

temp_message:     db 'Temperature', 0

DSEG at 30H
x: ds 1 ;x and y are 4 bytes (32 bits)
y: ds 1 
curr_temp: ds 1
temp_soak: ds 1
temp_reflow: ds 1
time_soak: ds 1
time_reflow: ds 1
FSM_state: ds 1

BSEG
mf: dbit 1 ;flag
start: dbit 1
shut_down: dbit 1
FSM_state: dbit 3


$include(math32.asm)

cseg
; These 'equ' must match the wiring between the DE10Lite board and the LCD!
; P0 is in connector JPIO.  Check "CV-8052 Soft Processor in the DE10Lite Board: Getting
; Started Guide" for the details.
ELCD_RS equ P0.0   ; instead of 1.7
; ELCD_RW equ Px.x ; Not used.  Connected to ground 
ELCD_E  equ P0.2 ; instead of 1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1
$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$LIST



Display_Voltage_7seg:
	
	mov dptr, #myLUT

	mov a, bcd+1
	swap a
	anl a, #0FH
	movc a, @a+dptr
	anl a, #0x7f ; Turn on decimal point
	mov HEX3, a
	
	mov a, bcd+1
	anl a, #0FH
	movc a, @a+dptr
	mov HEX2, a

	mov a, bcd+0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX1, a
	
	mov a, bcd+0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX0 , a 
	
	ret




FSM:    
	mov a, FSM_state ;move the state into reg a.

FSM_state0:
	cjne a, #0, FSM_state1 ;if a is not 0 move to state1
	mov pwm, #0 ;in state 0 turn this off - power is 0%
	jb PB6, FSM_state0_done, ;when we click the button 
	jnb PB6, $  ; Wait for key release
	mov FSM_state, #1
	
FSM_state0_done:
	ljmp FSM2

FSM_state1:
	cjne a, #1, FSM_state2
	mov pwm, #100 ;set power to 100
	mov sec, #0 ;set the timer to 0
	mov a, #150 ;this is the soak temperature (at 150C)
	clr c ;clear the carry 
	subb a, temp ;
	jnc FSM_state1_done ;jump if no carry, 
	mov FSM_state, #2
	
FSM_state1_done:
	ljmp FSM2
	
	
FSM_state2:
	cjne a, #2, FSM_state3
	mov pwm, #20
	mov a, #60
	clr c
	subb a, sec
	jnc FSM_state2_done
	mov FSM_state, #3
	
FSM_state2_done:
	ljmp FSM2	


main: 
;initialize the states
	clr FSM_state ;we start in state 0.

mov sp, #0x7f
clr a


Set_Cursor(2, 1)
Send_Constant_String(#temp_message)

forever:
lcall FSM
ljump forever

end
