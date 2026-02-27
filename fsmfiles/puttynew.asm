;-------------------------------------------------------------------------------
; Serial temperature line for PuTTY/screen
; Outputs: "Temp: XXXC\r\n"
;-------------------------------------------------------------------------------
Serial_Send_Temp_Line:
    mov dptr, #String_temp_line
    lcall SendString

    ; Convert current_temp to BCD (same as LCD)
    mov x, current_temp
    mov x+1, current_temp+1
    mov x+2, current_temp+2
    mov x+3, current_temp+3
    lcall hex2bcd

    mov R7, #0          ; printed_flag = 0

    ; Print Hundreds (if non-zero)
    mov a, bcd+1
    anl a, #0x0F
    jz Serial_Skip_Hundreds
    add a, #0x30
    lcall putchar
    mov R7, #1
Serial_Skip_Hundreds:

    ; Print Tens (if non-zero or if hundreds already printed)
    mov a, bcd+0
    swap a
    anl a, #0x0F
    jnz Serial_Print_Tens
    mov a, R7
    jz Serial_Skip_Tens
Serial_Print_Tens:
    mov a, bcd+0
    swap a
    anl a, #0x0F
    add a, #0x30
    lcall putchar
    mov R7, #1
Serial_Skip_Tens:

    ; Print Ones (always)
    mov a, bcd+0
    anl a, #0x0F
    add a, #0x30
    lcall putchar

    ; Print 'C' and newline
    mov a, #'C'
    lcall putchar
    mov a, #0DH     ; CR
    lcall putchar
    mov a, #0AH     ; LF
    lcall putchar
    ret

NEW FUCNTION!!!1
;-------------------------------------------------------------------------------
; Serial temperature line for PuTTY/screen
; Outputs: "Temp: XXXC\r\n"
;-------------------------------------------------------------------------------
Serial_Send_Temp_Line:
    mov dptr, #String_temp_line
    lcall SendString

    ; Convert current_temp to BCD (same as LCD)
    mov x, current_temp
    mov x+1, current_temp+1
    mov x+2, current_temp+2
    mov x+3, current_temp+3
    lcall hex2bcd

    mov R7, #0          ; printed_flag = 0

    ; Print Hundreds (if non-zero)
    mov a, bcd+1
    anl a, #0x0F
    jz Serial_Skip_Hundreds
    add a, #0x30
    lcall putchar
    mov R7, #1
Serial_Skip_Hundreds:

    ; Print Tens (if non-zero or if hundreds already printed)
    mov a, bcd+0
    swap a
    anl a, #0x0F
    jnz Serial_Print_Tens
    mov a, R7
    jz Serial_Skip_Tens
Serial_Print_Tens:
    mov a, bcd+0
    swap a
    anl a, #0x0F
    add a, #0x30
    lcall putchar
    mov R7, #1
Serial_Skip_Tens:

    ; Print Ones (always)
    mov a, bcd+0
    anl a, #0x0F
    add a, #0x30
    lcall putchar

    ; Print 'C' and newline
    mov a, #'C'
    lcall putchar
    mov a, #0DH     ; CR
    lcall putchar
    mov a, #0AH     ; LF
    lcall putchar
    ret

THEN CALL IT
