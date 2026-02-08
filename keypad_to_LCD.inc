;this only contains the LCD logic for the keypad.

cseg
Configure_LCD_Pins:
	;LCD are outputs, so set the corresponding pin as output. 
 ;	mov P0MOD, #10101111b ;0 for input, 1 for output. 
  ;  mov P1MOD, #10000010b ;these override the rows of the keypad, resulting in rows 1-3 not working aside from row 4
    orl P0MOD, #10101111b ;logic OR, keeps the rows safe.
	ret

Initial_Message:  db 'LCD/Keypad test', 0

showBCD_7seg MAC
	; Display LSD
    mov A, %0
    anl a, #0fh
    movc A, @A+dptr
    mov %1, A
	; Display MSD
    mov A, %0
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov %2, A
ENDMAC

ASCII_table: db '0123456789ABCDEF'

showBCD_LCD MAC
	; Convert high part
	mov a, %0
	swap a ; exchange high and low parts
	anl a, #0xf ; mask off low part
	movc a, @a+dptr ; convert to ASCII
	lcall ?WriteData ; send to LCD	
	; Convert low part
	mov a, %0
	anl a, #0xf ; mask off high part
	movc a, @a+dptr ; convert to ASCII
	lcall ?WriteData ; Send to LCD
ENDMAC

Display_LCD:
	mov dptr, #ASCII_table
	Set_Cursor(2,1)
	;showBCD_LCD(bcd1+4)
	;showBCD_LCD(bcd1+3);just uncomment if you want to type more
	showBCD_LCD(bcd1+2)
	showBCD_LCD(bcd1+1)
	showBCD_LCD(bcd1+0)
	ret


