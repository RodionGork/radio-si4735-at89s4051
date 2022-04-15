CLKREG EQU 8Fh

PIN_RST EQU P3.5
PIN_SCL EQU P3.4
PIN_SDA EQU P3.3

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

;================ counter in R2 (destroyed), 1 count ~ 20ms
WAIT: 
    MOV R3, #200
WAIT1:
    MOV R4, #200
    DJNZ R4, $
    DJNZ R3, WAIT1
    DJNZ R2, WAIT
    RET

;================ interrupt to reload UART (used as frequency generator)
ORG 23h
UART_INT:
    CLR SCON.1
    MOV SBUF, #55h
    RETI

MAIN:
    ACALL RADIO_INIT
    MOV DPTR, #CMD_POWER_UP_FM
    ACALL I2C_CMD
    CLR P1.0
MAIN1:
    MOV R2, #1
    ACALL WAIT
    ACALL I2C_RESPONSE
    MOV R2, #30
    ACALL WAIT
    RLC A
    JNC MAIN1
    CLR P1.2
    MOV R2, #30
    ACALL WAIT
    MOV DPTR, #CMD_SET_RCLK
    ACALL I2C_CMD
MAIN2:
    MOV R2, #1
    ACALL WAIT
    ACALL I2C_RESPONSE
    RLC A
    JNC MAIN2
    MOV P1, #0FBh

MAIN_LOOP:
    MOV R2, #20
    ACALL WAIT
    MOV P1, #0FFh
    JB P1.5, MAIN_NO_SEEK
    MOV P1, #0F7h
    MOV DPTR, #CMD_FM_SEEK_START
    ACALL I2C_CMD
MAIN3:
    MOV R2, #1
    ACALL WAIT
    ACALL I2C_RESPONSE
    RLC A
    JNC MAIN3
    MOV P1, #0FBh
MAIN_NO_SEEK:
    MOV R2, #20
    ACALL WAIT
    MOV P1, #0F0h
    SJMP MAIN_LOOP

;================ destroys R2, R3, R4
RADIO_INIT:
    CLR PIN_RST
    MOV R2, #3
    ACALL WAIT
    SETB PIN_RST
    MOV R2, #3
    ACALL WAIT
    RET

;================ destroys R1, R2, sends from code at DPTR
I2C_CMD:
    CLR A
    MOVC A, @A+DPTR
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
    RET

;================ destroys R1, R2, returns 1st byte in ACC
I2C_RESPONSE:
    CLR PIN_SDA
    ACALL I2C_DELAY
    CLR PIN_SCL
    ACALL I2C_DELAY
    MOV A, #23h
    ACALL I2C_WRITE
    XRL A, #0FFh
    RRC A
    MOV P1.2, C
    ACALL I2C_READ
    ACALL I2C_NACK
    SETB PIN_SCL
    ACALL I2C_DELAY
    SETB PIN_SDA
    ACALL I2C_DELAY
    RET
    

;================ destroys R1, sends from ACC
I2C_WRITE:
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
    RET

;================ destroys R1, returns ACC
I2C_READ:
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
    RET

;================ two entry points
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

;================ destroys R2
I2C_DELAY:
    MOV R2, 200
    DJNZ R2, $
    RET

;================ data
CMD_POWER_UP_FM:
    DB 3, 1, 0, 5
CMD_SET_RCLK:
    DB 6, 12h, 0, 2, 1, 7Ah, 12h
CMD_FM_SEEK_START:
    DB 2, 21h, 1100b

END
