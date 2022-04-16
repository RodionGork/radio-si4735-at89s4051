CLKREG EQU 8Fh

PIN_RST EQU P3.5
PIN_SCL EQU P3.4
PIN_SDA EQU P3.3

BTN_UP EQU P1.5
BTN_MID EQU P1.6
BTN_DOWN EQU P1.7
BTN_VIEW EQU P3.7

LED_0 EQU P1.0
LED_1 EQU P1.1
LED_2 EQU P1.2
LED_3 EQU P1.3
LED_R EQU P1.4
LEDS_ALL EQU P1

RESPONSE_AREA EQU 70h

ORG 0
START:
    MOV SCON, #01000000b ; UART mode 1 (8bit, variable baud, receive disabled)
    MOV PCON, #80h
	MOV TMOD, #00100000b ; T1 mode 2 (autoreload)
	MOV TH1, #0FFh ; T1 autoreload value, output frq = 24mhz/24/(256-TH1)/16 (X2=0, SCON1=1)
	MOV TCON, #01000000b ; T1 on
	MOV IE, #90h ; enable interrupts, enable uart interrupt
	MOV SBUF, #55h
	SJMP MAIN

;================ interrupt to reload UART (used as frequency generator)
ORG 23h
UART_INT:
    CLR SCON.1
    MOV SBUF, #55h
    RETI

;================ counter in R2 (destroyed), 1 count ~ 20ms
WAIT:
    PUSH AR3
    PUSH AR4
WAIT0:
    MOV R3, #200
WAIT1:
    MOV R4, #200
    DJNZ R4, $
    DJNZ R3, WAIT1
    DJNZ R2, WAIT0
    POP AR4
    POP AR3
    RET

;================ Main Routine
ORG 40h
MAIN:
    ACALL RADIO_INIT

MAIN_LOOP:
    MOV R2, #5
    ACALL WAIT
    MOV LEDS_ALL, #0FFh
    CLR A
    JNB BTN_UP, MAIN_SEEK
    CPL A
    JNB BTN_DOWN, MAIN_SEEK
    SJMP MAIN_NO_SEEK
MAIN_SEEK:
    ACALL RADIO_SEEK
    SJMP MAIN_NO_BUTTONS
MAIN_NO_SEEK:
    JB BTN_VIEW, MAIN_NO_VIEW
    ACALL RADIO_SHOW_FREQ
    SJMP MAIN_NO_BUTTONS
MAIN_NO_VIEW:
MAIN_NO_BUTTONS:
    MOV R2, #5
    ACALL WAIT
    CLR LED_3
    SJMP MAIN_LOOP

;================ Radio reset, power-up, set frequency
RADIO_INIT:
    PUSH AR2
    ; engage RST to ensure restart
    CLR PIN_RST
    MOV R2, #3
    ACALL WAIT
    SETB PIN_RST
    MOV R2, #3
    ACALL WAIT
    ; powerup receiver - lights led #0
    CLR LED_0
    MOV DPTR, #CMD_POWER_UP_FM
    ACALL SEND_CMD_AND_WAIT
    SETB LED_0
    ; set real chip frequeny value - lights led #1
    CLR LED_1
    MOV DPTR, #CMD_SET_RCLK
    ACALL SEND_CMD_AND_WAIT
    SETB LED_1
    ; tune to band start
    CLR LED_2
    MOV DPTR, #CMD_SET_FM_TUNE_BOTTOM
    ACALL SEND_CMD_AND_WAIT
    MOV DPTR, #CMD_SET_FM_TUNE_SPACING
    ACALL SEND_CMD_AND_WAIT
    MOV DPTR, #CMD_SET_FM_TUNE_RSSI_TSHLD
    ACALL SEND_CMD_AND_WAIT
    MOV DPTR, #CMD_FM_TUNE_FREQ
    ACALL SEND_CMD_AND_WAIT
    SETB LED_2
    POP AR2
    RET

;================
RADIO_SEEK:
    CLR LED_2
    MOV DPTR, #CMD_FM_SEEK_START
    JZ RADIO_SEEK_UP
    MOV DPTR, #CMD_FM_SEEK_START_DN
RADIO_SEEK_UP:
    ACALL SEND_CMD_AND_WAIT
RADIO_SEEK_WAIT:
    MOV DPTR, #CMD_GET_INT_STATUS
    ACALL SEND_CMD_AND_WAIT
    JNB ACC.0, RADIO_SEEK_WAIT
    SETB LED_2
    RET

;================
RADIO_SHOW_FREQ:
    PUSH AR0
    PUSH AR2
    MOV DPTR, #CMD_FM_TUNE_STATUS
    ACALL SEND_CMD_AND_WAIT
    MOV R0, #(RESPONSE_AREA+1)
    MOV R2, #5
SHOW_FREQ_1:
    CALL DIV_BY_10
    PUSH ACC
    DJNZ R2, SHOW_FREQ_1
    MOV R2, #5
SHOW_FREQ_2:
    POP ACC
    CALL SHOW_NIBBLE
    DJNZ R2, SHOW_FREQ_2
    POP AR2
    POP AR0
    RET

;================
SHOW_NIBBLE:
    PUSH ACC
    PUSH AR2
    ANL A, #0Fh
    XRL A, #0Fh
    ORL A, #0E0h
    MOV P1, A
    MOV R2, #13
    CALL WAIT
    MOV P1, #0FFh
    MOV R2, #7
    CALL WAIT
    POP AR2
    POP ACC
    RET

;================ sends command from code at DPTR (destroyed), waits for response (returned in ACC and RESPONSE_AREA)
SEND_CMD_AND_WAIT:
    PUSH AR2
    PUSH AR5
    CLR A
    MOVC A, @A+DPTR
    SWAP A
    ANL A, #0Fh
    MOV R5, A
    ACALL I2C_CMD
SEND_CMD_WAIT_LOOP:
    MOV R2, #1
    ACALL WAIT
    ACALL I2C_RESPONSE
    JNB ACC.7, SEND_CMD_WAIT_LOOP
    POP AR5
    POP AR2
    RET

;================ sends command from code at DPTR (destroyed)
I2C_CMD:
    PUSH AR3
    PUSH AR4
    CLR A
    MOVC A, @A+DPTR
    ANL A, #0Fh
    MOV R3, A
    CLR PIN_SDA
    ACALL I2C_DELAY
    CLR PIN_SCL
    ACALL I2C_DELAY
    MOV A, #22h
    ACALL I2C_WRITE
    MOV R4, #1
I2C_CMD_LOOP:
    MOV A, R4
    INC R4
    MOVC A, @A+DPTR
    ACALL I2C_WRITE
    DJNZ R3, I2C_CMD_LOOP
    SETB PIN_SCL
    ACALL I2C_DELAY
    SETB PIN_SDA
    ACALL I2C_DELAY
    POP AR4
    POP AR3
    RET

;================ reads (1+R5) bytes from I2C to "RESPONSE_AREA", 1st byte also in ACC, R5 destroyed
I2C_RESPONSE:
    PUSH AR0
    CLR PIN_SDA
    ACALL I2C_DELAY
    CLR PIN_SCL
    ACALL I2C_DELAY
    MOV A, #23h
    ACALL I2C_WRITE
    ACALL I2C_READ
    JNB ACC.7, I2C_RESP_DONE
    PUSH ACC
    MOV R0, #RESPONSE_AREA
I2C_RESP_NEXT:
    MOV A, R5
    JZ I2C_RESP_DONE
    ACALL I2C_ACK
    ACALL I2C_READ
    MOV @R0, A
    INC R0
    DEC R5
    SJMP I2C_RESP_NEXT
I2C_RESP_DONE:
    ACALL I2C_NACK
    SETB PIN_SCL
    ACALL I2C_DELAY
    SETB PIN_SDA
    ACALL I2C_DELAY
    POP ACC
    POP AR0
    RET

;================ sends byte from ACC via I2C
I2C_WRITE:
    PUSH AR1
    MOV R1, #8
I2C_WRITE_LOOP:
    RLC A
    MOV PIN_SDA, C
    ACALL I2C_DELAY
    SETB PIN_SCL
    ACALL I2C_DELAY
    CLR PIN_SCL
    ACALL I2C_DELAY
    DJNZ R1, I2C_WRITE_LOOP
    SETB PIN_SDA
    ACALL I2C_DELAY
    SETB PIN_SCL
    ACALL I2C_DELAY
    MOV C, PIN_SDA
    CLR A
    RLC A
    CLR PIN_SCL
    ACALL I2C_DELAY
    CLR PIN_SDA
    ACALL I2C_DELAY
    POP AR1
    RET

;================ reads byte from I2C to ACC
I2C_READ:
    PUSH AR1
    MOV R1, #8
    SETB PIN_SDA
    ACALL I2C_DELAY
I2C_READ_LOOP:
    SETB PIN_SCL
    ACALL I2C_DELAY
    MOV C, PIN_SDA
    RLC A
    CLR PIN_SCL
    ACALL I2C_DELAY
    DJNZ R1, I2C_READ_LOOP
    CLR PIN_SDA
    ACALL I2C_DELAY
    POP AR1
    RET

;================ sending I2C ACK or NACK - two entry points
I2C_ACK:
    CLR PIN_SDA
    SJMP I2C_ACK_NACK
I2C_NACK:
    SETB PIN_SDA
I2C_ACK_NACK:
    ACALL I2C_DELAY
    SETB PIN_SCL
    ACALL I2C_DELAY
    CLR PIN_SCL
    ACALL I2C_DELAY
    CLR PIN_SDA
    ACALL I2C_DELAY
    RET

;================ small delay between I2C signal changes
I2C_DELAY:
    PUSH AR2
    MOV R2, 200
    DJNZ R2, $
    POP AR2
    RET

;================
DIV_BY_10:
    MOV A, @R0
    MOV B, #10
    DIV AB
    MOV @R0, A
    INC R0
    MOV A, @R0
    ANL A, #0F0h
    ORL A, B
    SWAP A
    MOV B, #10
    DIV AB
    SWAP A
    XCH A, @R0
    SWAP A
    ANL A, #0F0h
    ORL A, B
    SWAP A
    MOV B, #10
    DIV AB
    ORL A, @R0
    MOV @R0, A
    MOV A, B
    DEC R0
    RET

;================ data
CMD_POWER_UP_FM:
    DB 3, 1, 0, 5
CMD_GET_REV:
    DB 1+80h, 10h
CMD_SET_RCLK:
    DB 6, 12h, 0, 2, 1, 7Ah, 12h
CMD_SET_FM_TUNE_BOTTOM:
    DB 6, 12h, 0, 14h, 0, 19h, 00h ; from 64MHz
CMD_SET_FM_TUNE_SPACING:
    DB 6, 12h, 0, 14h, 2, 0h, 05h  ; spacing 50kHz
CMD_SET_FM_TUNE_RSSI_TSHLD:
    DB 6, 12h, 0, 14h, 4, 0h, 05h  ;
CMD_GET_INT_STATUS:
    DB 1, 14h
CMD_FM_TUNE_FREQ:
    DB 4, 20h, 0, 22h, 2Eh ; 87.5
CMD_FM_SEEK_START:
    DB 2, 21h, 1100b
CMD_FM_SEEK_START_DN:
    DB 2, 21h, 100b
CMD_FM_TUNE_STATUS:
    DB 2+70h, 22h, 0

END
