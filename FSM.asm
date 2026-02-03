$MODMAX10




;key terms:
;cjne - compare and jump if not equal
;pwm - pulse wave modulation 
;subb - subtract with borrow
FSM:    
	mov a, FSM1_state ;move the state into reg a.

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

