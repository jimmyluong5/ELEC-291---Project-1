$MODMAX10

FSM1:    
	mov a, FSM1_state ;move the state into reg a.

FSM1_state0:
	cjne a, #0, FSM1_state1
	mov pwm, #0
	jb PB6, FSM1_state0_done
	jnb PB6, $ ; Wait for key release
	mov FSM1_state, #1
	
FSM1_state0_done:
	ljmp FSM1_FSM2

FSM1_state1:
	cjne a, #1, FSM1_state2
	mov pwm, #100
	mov sec, #0
	mov a, #150
	clr c
	subb a, temp
	jnc FSM1_state1_done
	mov FSM1_state, #2
	
FSM1_state1_done:
	ljmp FSM2
	
	
FSM1_state2:
	cjne a, #2, FSM1_state3
	mov pwm, #20
	mov a, #60
	clr c
	subb a, sec
	jnc FSM1_state2_done
	mov FSM1_state, #3
	
FSM1_state2_done:
	ljmp FSM2	

