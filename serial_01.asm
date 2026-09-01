;--------------------------------------------------------------------------------------------------
; Serial_01.asm
; Jonathan Edwards
; August 24, 2026
;
; A program to establish Linux x86-64 routines for communicating with a peripheral
; via the serial bus. The serial device is a PIC16F877A configured to communicate with
; the computer with a USB-RS232 interface cable. Serial communications would have been
; established using the following line in the Linux terminal:
;
; stty -F /dev/ttyUSB0 9600 cs8 -cstopb -parenb -ixon -ixoff -crtscts raw -echo
;
; where /dev/ttyUSB0 can be replaced with the name of the serial device in use. The PIC
; microcontroller will be using my custom EEPROM programming software, EEPROM_02.asm
;
; format: serial_01
;
; program flow:
;
; 1) open up the serial port as a file for input and output
;
; 2) display a message on the screen
;
; 3) send bytes 'H', 0x0D, 0x0A to the PIC via serial port
;
; 4) delay for a small amount of time
;
; 5) read bytes from the serial port until there is nothing more to read
;
; 6) display what was read on the screen
;
; 7) delay for a small amount of time
;
; 8) close the serial port
;
; 9) return control to Linux
;
;
;--------------------------------------------------------------------------------------------------

global _start

section .data

SerPortName:	db	"/dev/ttyUSB0", 0
SerPortNameSz:	equ	$ - SerPortName
Prompt01:	db	"Serial_01.asm", 0
Prompt01Len:	equ	$ - Prompt01
Prompt02:	db	"A program by Jon Edwards", 0
Prompt02Len:	equ	$ - Prompt02
Prompt03:	db	"This program opens the serial port and sends a byte to the PIC", 0
Prompt03Len:	equ	$ - Prompt03
Prompt04:	db	"Then it reads the returned text and displays it on screen", 0
Prompt04Len:	equ	$ - Prompt04
Prompt05:	db	"Lastly it closes the serial port", 0
Prompt05Len:	equ	$ - Prompt05
CRLF:		db	0x0D, 0x0A
CRLFLen:	equ	$ - CRLF
Error01:	db	"Serial port open fail. Exiting.", 0
Error01Len:	equ	$ - Error01
Error02:	db	"Serial write fail. Exiting.", 0
Error02Len:	equ	$ - Error02
Error03:	db	"Serial read fail. Exiting.", 0
Error03Len:	equ	$ - Error03

section .bss

InputBuffer:	resb	256
InputPtr:	resb	1
SerialFD:	resq	1


OutputBuffer:	resb	8
OutputPtr:	resb	1

section .text
_start:
		; clear variables.
		xor	rax, rax
		mov	byte[rel InputPtr], al
		mov	byte[rel OutputPtr], al
		
		cld					; clear direction
		mov	rcx, 32				; set a counter to 32
		lea	rdi, [rel InputBuffer]		; point to the input buffer
		rep	stosq				; write 0x0000000000000000 to input buffer and dec rcx until rcx = 0
		
		mov	rcx, 1
		lea	rdi, [rel OutputBuffer]
		rep	stosq
		
		; display intro text
		lea	rsi, [rel Prompt01]		; prompt 1 of 5
		mov	rdx, Prompt01Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel Prompt02]		; prompt 2 of 5
		mov	rdx, Prompt02Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel Prompt03]		; prompt 3 of 5
		mov	rdx, Prompt03Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel Prompt04]		; prompt 4 of 5
		mov	rdx, Prompt04Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel Prompt05]		; prompt 5 of 5
		mov	rdx, Prompt05Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext

		; open the RS232 port as a read/write file to send data.
		
		lea	rdi, [rel SerPortName]
		mov	rsi, 2
		xor	rdx, rdx
		call	openfile
		test	rax, rax
		js	.fileerror
		mov	qword[rel SerialFD], rax
		
		; load the byte 'H' and then the CR/LF characters into the output buffer
		
		movzx	rbx, byte [rel OutputPtr]
		lea	rcx, [rel OutputBuffer]
		mov	rax, 0x48			; character 'H'
		mov	byte [rcx + rbx], al
		inc	rbx
		mov	rax, 0x0D			; character CR
		mov	byte [rcx + rbx], al
		inc	rbx
		mov	rax, 0x0A			; character LF
		mov	byte [rcx + rbx], al
		inc	rbx
		mov	byte [rel OutputPtr], bl
		
		; send the output buffer to the serial port
		
		movzx	rdx, byte [rel OutputPtr]
		mov	rdi, [rel SerialFD]
		lea	rsi, [rel OutputBuffer]
		call	writefile
		test	rax, rax
		js	.writeerror
		
		; read the bytes back that the PIC responds
		
		mov	edx, 0x01
		xor	rax, rax
		mov	byte [rel InputPtr], al
.readbyteloop:
		mov	rdi, [rel SerialFD]
		movzx	rbx, byte [rel InputPtr]
		lea	rsi, [rel InputBuffer]
		add	rsi, rbx
		call	readfile
		test	rax, rax
		js	.readerror
		jz	.readbyteloop
		inc	byte [rel InputPtr]
		movzx	rcx, byte [rel InputPtr]
		test	rcx, rcx
		jz	.endreading
		xor	rax, rax
		mov	al, [rsi]
		cmp	al, 0x04
		jne	.readbyteloop
		
.endreading:
		; now print the number of bytes read back
		mov	al, byte [rel InputPtr]
		lea	rsi, [rel InputBuffer]
		mov	rdx, rax
		call	printtext
		
		jmp	.closeport
		
.fileerror:
		lea	rsi, [rel Error01]		; display message for file (serial port) open fail
		mov	rdx, Error01Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		jmp	.exitprogram
		
.writeerror:
		lea	rsi, [rel Error02]		; display message for file write fail
		mov	rdx, Error02Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		jmp	.closeport
		
.readerror:
		lea	rsi, [rel Error03]		; display message for file read fail
		mov	rdx, Error03Len
		call	printtext
		lea	rsi, [rel CRLF]			; endline
		mov	rdx, CRLFLen
		call	printtext
		
.closeport:
		mov	rdi, [rel SerialFD]		; close the serial port
		call	closefile

.exitprogram:	
		mov	eax, 60				; set up the function to exit
  		xor	edi, edi			; and go back to the command line
  		syscall

;--------------------------------------------------------------------
; Subroutine: print text
; 
; Prints text to the terminal screen
; 
; Inputs: rsi - address of text to print
;	  rdx - number of bytes to print
; Destroys: RAX, RDI
; Outputs: none
;--------------------------------------------------------------------
printtext:
  		mov	eax, 1
  		mov	edi, 1
  		syscall
  		ret

;--------------------------------------------------------------------
; Subroutine: openfile
; 
; Opens a file 
; 
; Inputs: rsi - file flags (0 - read only, 1 - write only, 
;	        2 - read/write, 64 - create, 512 - truncate)
;	  rdi - 8-byte pointer to the filename
;	  rdx - file mode
; Destroys: RAX
; Outputs: RAX - file descriptor
;--------------------------------------------------------------------
openfile:
		mov	eax, 2				; rax = 2 sys_open
		syscall
		ret
		
;--------------------------------------------------------------------
; Subroutine: readfile
; 
; Reads bytes from the input file 
; 
; Inputs: rdx - number of bytes
;	  rdi - file descriptor
;	  rsi - address of input buffer 
; Destroys: RAX
; Outputs: RAX - > 0: number of bytes read
;	         = 0: end of file reached
;	         < 0: error
;--------------------------------------------------------------------
readfile:	xor	rax, rax			; rax = 0 sys_read
		syscall
		ret
		
;--------------------------------------------------------------------
; Subroutine: writefile
; 
; Writes bytes to the output file 
; 
; Inputs: rdx - number of bytes
;	  rdi - file descriptor
;	  rsi - address output buffer	  
; Destroys: RAX
; Outputs: RAX - > 0: number of bytes written
;	         < 0: error
;--------------------------------------------------------------------
writefile:	mov	eax, 1				; rax = 1 sys_write
		syscall
		ret

;--------------------------------------------------------------------
; Subroutine: closefile
; 
; Releases control of a file 
; 
; Inputs: rdi - file descriptor
; Destroys: RAX
; Outputs: none
;--------------------------------------------------------------------
closefile:	mov	rax, 3				; rax = 3 sys_close
		syscall
		ret
