;--------------------------------------------------------------------------------------------------
; Serial_03.asm
; Jonathan Edwards
; September 19, 2026
;
; this program adds the function of the first and second programs. We validate an Intel HEX
; data file and then push it to the PIC16, 64 bytes at a time. Then we send a command to program
; those 64 bytes into EEPROM. This is the final part in a tool chain that allows us to send
; data automatically into the ROM without having to type every byte. That was a pain in the ass.
;
; syntax: serial_03 -s NN filename.hex
;
; -s is a flag to dictate size of the EEPROM. This is followed by a 2-digit decimal value
;    of the ROM size in kilobytes. There is no default value. If the user fails to enter
;    the size then we error out. Fuck 'em.
;
; filename must be a valid Intel HEX file. I am using this program for 65C02 assembly programming
; with the Ben Eater computer. It is possible others might find other uses for this program so
; I will leave it open ended. All you need is a way to get your raw binary files converted to
; Intel HEX. I can provide more assistance if needed.
;
; program flow:
;
; 1) validate the HEX file
;   a - verify we have the correct arguments.
;   b - convert the ASCII text for the size argument into a numerical value and
;       store it in memory
;   c - read the filename entered and ensure the last four characters are ".HEX"
;   d - open the file, error out if this fails
;   e - read through the file, ensuring it has data records and fits the general
;       
;
;
;
;--------------------------------------------------------------------------------------------------

global _start

section .data

  ; text to display on the screen.
  ; first section is usage.
  usage1:	db	"Format: serial_02 <inputfile.hex>", 0x0A, 0x0A
  u1len:	equ	$ - usage1
  usage2:	db	"Checks a HEX file to ensure it contains valid formatting", 0x0A
  u2len:	equ	$ - usage2
  usage3:	db	"and data. This code will be used later to screen software", 0x0A
  u3len:	equ	$ - usage3
  usage4:	db	"before entering it into ROM for a 6502 computer.", 0x0A
  u4len:	equ	$ - usage4
  usage5:	db	"Only *.hex files are considered valid", 0x0A
  u5len:	equ	$ - usage5
  
  op1:		db	"Opening file name: "
  op1len:	equ	$ - op1
  
  error1:	db	"Error - invalid file name.", 0x0A
  error1len:	equ	$ - error1
  error2:	db	"Error - read failed.", 0x0A
  error2len:	equ	$ - error2
  error3:	db	"Error - write failed.", 0x0A
  error3len:	equ	$ - error3
  error4:	db	"Error - HEX file not valid", 0x0A
  error4len:	equ	$ - error4
  error5:	db	"Error - input invalid.", 0x0A
  error5len:	equ	$ - error5
  error6:	db	"Error - problem opening file.", 0x0A
  error6len:	equ	$ - error6
  error7:	db	"Error - no HEX data in file.", 0x0A
  error7len:	equ	$ - error7
  
  success1:	db	"HEX file is valid.", 0x0A, 0x0A
  success1len:	equ	$ - success1
  success2:	db	"Number of valid records: "
  success2len:	equ	$ - success2
  success3:	db	"Number of invalid records: "
  success3len:	equ	$ - success3
  success4:	db	"Number of data bytes read: "
  success4len:	equ	$ - success4
  
  intro1:	db	"Hex Validation Software", 0x0A
  intro1len:	equ	$ - intro1
  intro2:	db	"By Jonathan Edwards", 0x0A
  intro2len:	equ	$ - intro2

  eofline:	db	":00000001FF", 0x0A
  eoflinelen:	equ	$ - eofline
  
  endl:		db	0x0A

section .bss

  argc:		resq	1				; number of arguments on the command line
  arg1p:	resq	1				; pointer to filename
  filename:	resb	64				; memory to store filename
  filenamelen:	resb	1				; memory to store filename length
  address:	resw	1				; memory address to write to (16-bit for 6502 type addressing)
  fd1:		resd	1				; to store the first file descriptor  
  inbuf:	resb	256				; empty bytes to be used for input data
  inputptr:	resb	1				; used to track position in the input buffer
  outbuf:	resb	256				; output buffer to be filled up with data
  outputptr:	resb	1				; used to track position in the output buffer
  byteqty:	resb	1				; number of bytes in the current record
  rectype:	resb	1				; used to record the type of record being read
  temp1:	resb	1				; temporary placeholder for one byte
  chksumtotal:	resb	1				; running total for checksum
  is_valid:	resb	1				; a flag that allows certain other functions to declare the file invalid

section .text

_start:
	; clear all of the memory that we are going to use.
	; this is commonly thought of as unnecessary, but
	; ensures we don't have to deal with leftover garbage
	; data when the program is hundreds of lines long

	xor	rax, rax
	mov	qword [rel argc], rax
	mov	qword [rel arg1p], rax
	mov	word [rel address], ax
	mov	dword [rel fd1], eax
	mov	byte [rel inputptr], al
	mov	byte [rel outputptr], al
	mov	byte [rel byteqty], al
	mov	byte [rel temp1], al
	mov	byte [rel chksumtotal], al
	
.memclear:
	; batch clear the memory buffers before reading/writing
	; to them.
	cld
	mov	rcx, 0x100
	lea	rdi, [rel inbuf]
	rep	stosb
	mov	rcx, 0x100
	lea	rdi, [rel outbuf]
	rep	stosb
	mov	rcx, 0x40
	lea	rdi, [rel filename]
	rep	stosb

.intromessages:
	; load and print two intro messages
	mov	rdx, intro1len	
	lea	rsi, [rel intro1]
	call	printtext
	mov	rdx, intro2len
	lea	rsi, [rel intro2]
	call	printtext

.arghandler:
	; start handling the argument. Get it into RBX and then
	; store it in memory
	mov	rbx, [rsp]
	mov	qword [rel argc], rbx
	cmp	rbx, 2
	ja	.inputerror
	jb	.usageonly
	; save the location of the argument in memory
	mov	rsi, [rsp + 16]
	mov	qword [rel arg1p], rsi
	; set up rcx as a counter to measure string length
	; clear rax for handling the data
	; load rbx with the pointer stored in arg1p
	; load rdi with a pointer to filename
	xor	rcx, rcx
	xor	rax, rax
	mov	rbx, [rel arg1p]
	lea	rdi, [rel filename]
	
.filenamereadloop:
	; read the argument filename one character at a time until we read
	; a null character. Store each byte in memory and increment rcx
	; or if we exceed 64 characters
	mov	al, [rbx + rcx]
	mov	byte [rdi + rcx], al
	cmp	al, 0x00
	jz	.filenamereaddone
	inc	rcx
	cmp	rcx, 0x40
	je	.filenamereaddone
	jmp	.filenamereadloop
	
.filenamereaddone:
	; check if at least 5 characters were entered, error out if not
	; store the length of the filename in memory
	cmp	cl, 5
	jb	.filenameerror
	mov	byte [rel filenamelen], cl
	xor	rax, rax
	
.fileextcheck:
	; check the last four characters of the filename for ".hex"
	; at this point, CL equals the length of the file name
	; 
	; 1) get the character at address of filename plus RCX
	; 2) AND that character with 0xDF (0b11011111) to clear bit 5
	;    which turns any lower-case letter upper case
	; 3) check if the character is 'X'
	; 4) if not, jump to invalid input
	; 5) if so, decrement RCX and check again for 'E', 'H', and '.'
	; 6) if all checks pass, fall to the next code segment
	;
	dec	rcx
	mov	al, byte [rdi + rcx]
	and	al, 0xDF
	cmp	al, 0x58
	jne	.filenameerror
	dec	rcx
	mov	al, byte [rdi + rcx]
	and	al, 0xDF
	cmp	al, 0x45
	jne	.filenameerror
	dec	rcx
	mov	al, byte [rdi + rcx]
	and	al, 0xDF
	cmp	al, 0x48
	jne	.filenameerror
	dec	rcx
	mov	al, byte [rdi + rcx]
	cmp	al, 0x2E
	jne	.filenameerror
	
.openthefilealready:
	; if all of the checks so far have passed, open the file
	; and display a message stating we are doing so
	mov	rdx, op1len	
	lea	rsi, [rel op1]
	call	printtext
	movzx	rdx, byte [rel filenamelen]
	lea	rsi, [rel filename]
	call	printtext
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	xor	rsi, rsi
	lea	rdi, [rel filename]
	xor	rdx, rdx
	call	openfile
	test	rax, rax
	js	.fileerror
	mov	dword [rel fd1], eax

.readingsetup:
	; clear registers and get ready to start pulling data from the file.
	; RBX keeps track of the current line
	; RCX is a input buffer pointer which wraps around at 255
	; R8 keeps track of the number of valid records
	; R9 keeps track of the number of invalid records
	; R10 keeps track of the number of bytes in the file
	; R12 is a counter to keep track of reading bytes in the data section
	xor	rbx, rbx
	xor	rcx, rcx
	xor	rdx, rdx
	xor	r8, r8
	xor	r9, r9
	xor	r10, r10
	xor	r12, r12
	
.initialread:
	; skip past any information in the HEX file before the first record. Normally
	; this won't exist, but if someone like me decides to input some commentary
	; ahead of the records, this will skip over it.
	;
	; flow: input a byte from the file and store it in the input buffer.
	;       increment RCX. Does RCX = 0x100? If so, RCX = 0x00. Is the
	;       byte 0x3A (':')? If so, fall through and read a record. If
	;       not, loop around and try again.
	mov	rdx, 0x01
	mov	edi, [rel fd1]
	lea	rsi, [rel inbuf]
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror
	; the following code is commented out - until we reach a byte that is ':',
	; we don't need to store anything. Just read something in store it in
	; inbuf[0]. Once we reach the beginning of a record, we care about what's
	; written in there
	;
	; inc	rcx
	; cmp	rcx, 0x100
	; jb	.initialread2
	; xor	rcx, rcx
.initialread2:
	mov	al, [rsi]
	cmp	al, 0x3A
	jne	.initialread

.recordloop_main:
	; this loop handles the entirety of one record.
	; 1) read the size of the record in bytes
	; 2) read the address of the start of the record
	; 3) read the record type
	; 4) read the number of data bytes in the record, confirm they match the size
	; 5) calculate the checksum
	; 6) read the record's checksum and see if it matches
	mov	byte [rel chksumtotal], 0x00
.recordloop_size:
	; read the quantity of bytes in the current line
	; this number gets added into the checksum
	call	ReadIHEXByte
	jc	.recordloop_error
	mov	byte [rel byteqty], al
	add	byte [rel chksumtotal], al
.recordloop_address:
	; read the address bytes (two of them) and
	; store them in little-endian
	; this number gets added into the checksum
	call	ReadIHEXByte
	jc	.recordloop_error
	mov	byte [rel address + 1], al
	add	byte [rel chksumtotal], al
	call	ReadIHEXByte
	jc	.recordloop_error
	mov	byte [rel address], al
	add	byte [rel chksumtotal], al
.recordloop_type:
	; read the type byte. If it's 1, skip reading
	; data bytes and go to the checksum. Otherwise,
	; go to reading bytes. We are going to treat
	; non-zero data records as valid for now. I won't
	; be using any of them.
	; this number gets added into the checksum.
	call	ReadIHEXByte
	jc	.recordloop_error
	mov	byte [rel rectype], al
	add	byte [rel chksumtotal], al
	cmp	al, 0x01
	je	.recordloop_data_checksum
.recordloop_data_init:
	; set R12 as a counter equal to the quantity used
	; in the record size step. If it's zero, go to
	; the checksum step
	movzx	r12, byte [rel byteqty]
	test	r12, r12
	jz	.recordloop_data_checksum
.recordloop_data_read:
	; read one of the data bytes and add into the
	; checksum total. Increment R10 to account for the
	; byte and decrement R12. If R12 is not zero,
	; do it all again.
	call	ReadIHEXByte
	jc	.recordloop_error
	add	byte [rel chksumtotal], al
	inc	r10
	dec	r12
	jnz	.recordloop_data_read
.recordloop_data_checksum:
	; checksum total is a single byte in memory. All
	; additions to this will result in an overflow
	; so the low byte of the sum will be contained
	; by the time we reach this point.
	; 
	; if we read the checksum byte and add it to this
	; total, the result will be zero for a valid
	; record. If it is not, count a bad record.
	call	ReadIHEXByte
	jc	.recordloop_error
	add	byte [rel chksumtotal], al
	jz	.recordloop_valid
	jmp	.recordloop_error
.recordloop_error:
	; error handling - error code contained in AL
	; add one to the counter for invalid records
	; and go to the next one
	inc	r9
	jmp	.recordloop_nextline
.recordloop_valid:
	; if everything worked out, add one to the
	; valid records counter. Check if the record
	; type is 1 - if so we go to the EOF handler.
	; Otherwise fall through to the next line
	; handler. 
	inc	r8
	mov	al, [rel rectype]
	cmp	al, 0x01
	je	.recordloop_eof
.recordloop_nextline:
	; input one character. It should be 0x0A or 0x0D.
	; reading 0x0A jumps directly to the third step, while
	; 0x0D reads the next byte, expecting it to be 0x0A.
	mov	rdx, 0x01
	mov	edi, [rel fd1]
	lea	rsi, [rel inbuf]
	movzx	rcx, byte [rel inputptr]
	add	rsi, rcx
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror
	mov	al, [rsi]
	cmp	al, 0x0A
	je	.recordloop_nextline3
	cmp	al, 0x0D
	je	.recordloop_nextline2
	inc	byte [rel is_valid]
	jmp	.recordloop_nextline
.recordloop_nextline2:
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror
	mov	al, [rsi]
	cmp	al, 0x0A
	je	.recordloop_nextline3
	inc	byte [rel is_valid]
	jmp	.recordloop_nextline2
.recordloop_nextline3:
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror
	mov	al, [rsi]
	cmp	al, 0x3A
	je	.recordloop_main
	inc	byte [rel is_valid]
	jmp	.recordloop_nextline3
.recordloop_eof:
	test	r9, r9
	jz	.printresults
	inc	byte [rel is_valid]
	jmp	.printresults
	
.printresults:
	cmp	byte [rel is_valid], 0
	jne	.printfailure
	mov	rdx, success1len	
	lea	rsi, [rel success1]
	call	printtext
	mov	rdx, success2len	
	lea	rsi, [rel success2]
	call	printtext
	mov	ax, r8w
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success4len	
	lea	rsi, [rel success4]
	call	printtext
	mov	ax, r10w
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	jmp	.closefile
	
.printfailure:
	mov	rdx, error4len
	lea	rsi, [rel error4]
	call	printtext
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success2len
	lea	rsi, [rel success2]
	call	printtext
	mov	ax, r8w
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success3len
	lea	rsi, [rel success3]
	call	printtext
	mov	ax, r9w
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success4len
	lea	rsi, [rel success4]
	call	printtext
	mov	ax, r10w
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	jmp	.closefile	
	
.usageonly:
	; with no input, the program displays a message
	; explaining how to use the program
	mov	rdx, u1len	
	lea	rsi, [rel usage1]
	call	printtext
	mov	rdx, u2len
	lea	rsi, [rel usage2]
	call	printtext
	mov	rdx, u3len	
	lea	rsi, [rel usage3]
	call	printtext
	mov	rdx, u4len
	lea	rsi, [rel usage4]
	call	printtext
	mov	rdx, u5len
	lea	rsi, [rel usage5]
	call	printtext
	jmp	.exitprogram

.inputerror:
	inc	byte [rel is_valid]
	mov	rdx, error5len
	lea	rsi, [rel error5]
	call	printtext
	jmp	.exitprogram

.filenameerror:
	inc	byte [rel is_valid]
	mov	rdx, error1len
	lea	rsi, [rel error1]
	call	printtext
	jmp	.exitprogram

.fileerror:
	inc	byte [rel is_valid]
	mov	rdx, error6len
	lea	rsi, [rel error6]
	call	printtext
	jmp	.exitprogram
	
.eoferror:
	inc	byte [rel is_valid]
	mov	rdx, error7len
	lea	rsi, [rel error7]
	call	printtext
	jmp	.closefile

.readerror:
	inc	byte [rel is_valid]
	mov	rdx, error2len
	lea	rsi, [rel error2]
	call	printtext
	jmp	.closefile

.closefile:
	xor	rdi, rdi
	mov	edi, [rel fd1]
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
; Subroutine: print decimal
; 
; Prints an ASCII representation of a number loaded in AX. Limited
; to values 0 - 65,535.
;
; BH - counts how many characters are printed
; BL - counts what character to print
; DX - contains the subtraction value
; 
; Inputs: AX - binary value we want to print to screen
; Destroys: AX, BX, DX, Temp1
; Outputs: Printed characters to screen
;--------------------------------------------------------------------
printdecimal:
		; initialize registers
		; make DX = 10,000 for first go
		xor	rbx, rbx
		xor	rdx, rdx
		mov	dx, 0x2710
.printdecimal_loop:
		; check if there's anything in the current numerical place
		; by subtracting. If the carry flag sets, we have run out
		; of value in that decimal place. Go to next segment.
		sub	ax, dx
		jc	.printdecimal_next
		inc	bl
		jmp	.printdecimal_loop
.printdecimal_next:
		; restore AX so we can do more math on it following an
		; overflow. See if BL incremented at all. If so, make
		; an ASCII character out of it and print it. If BL
		; is zero, check if we have printed any characters
		; previously. If we have, print a place holder zero.
		; If we have not, then skip it and go to the next
		; numerical place.
		add	ax, dx
		test	bl, bl
		jz	.printdecimal_zerohandler
		add	bl, 0x30
		mov	[rel temp1], bl
		lea	rsi, [rel temp1]
		push	rdx
		push	rax
		mov	rdx, 0x01
		call	printtext
		pop	rax
		pop	rdx
		inc	bh
		jmp	.printdecimal_check10K
.printdecimal_zerohandler:
		; we get here if zero was the number in the current
		; numerical place. Decide whether or not to print
		; a placeholder zero.
		test	bh, bh
		jz	.printdecimal_check10K
		mov	bl, 0x30
		mov	[rel temp1], bl
		lea	rsi, [rel temp1]
		push	rdx
		push	rax
		mov	rdx, 0x01
		call	printtext
		pop	rax
		pop	rdx
		inc	bh
.printdecimal_check10K:
		; if DX = 10,000, make DX = 1,000
		; also clear BL for the next loop
		; around.
		xor	bl, bl
		cmp	dx, 0x2710
		jne	.printdecimal_check1K
		mov	dx, 0x3E8
		jmp	.printdecimal_loop
.printdecimal_check1K:
		; if DX = 1,000, make DX = 100
		cmp	dx, 0x3E8
		jne	.printdecimal_check100
		mov	dx, 0x64
		jmp	.printdecimal_loop
.printdecimal_check100:
		; if DX = 100, make DX = 10
		cmp	dx, 0x64
		jne	.printdecimal_check10
		mov	dx, 0x0A
		jmp	.printdecimal_loop
.printdecimal_check10:
		; if DX = 10, make DX = 1
		cmp	dx, 0x0A
		jne	.printdecimal_end
		mov	dx, 0x01
		jmp	.printdecimal_loop
.printdecimal_end:
		; make sure DX = 1. Check if any
		; characters were printed. If there
		; were not, print a single zero. If
		; there were, then just exit routine.
		cmp	dx, 0x01
		jne	.printdecimal_error
		test	bh, bh
		jnz	.printdecimal_goback
		mov	bl, 0x30
		mov	[rel temp1], bl
		lea	rsi, [rel temp1]
		push	rdx
		push	rax
		mov	rdx, 0x01
		call	printtext
		pop	rax
		pop	rdx
.printdecimal_goback:
		; just go back to where we came from
  		ret
.printdecimal_error:
		; should never happen, but if DX != 1
		; after the whole process, some code
		; to handle it would go here. Probably
		; doesn't need to be any.
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
		
;--------------------------------------------------------------------
; Subroutine: ReadIHEXByte
; 
; Retrieve two ASCII characters from a HEX file and place the equivalent
; value in memory.  
; 
; Inputs: none
; Destroys: RAX
; Outputs: AL - the value of the two hexadecimal ASCII characters
;	   Carry - set if operation failed
;--------------------------------------------------------------------	
ReadIHEXByte:
		; 1) read a byte from the file
		; 2) error out if failed or EOF
		; 3) clear rax and load the read byte into al
		; 4) convert al into the character's value
		; 5) shift left four times and store in memory
		; 6) read a second byte
		; 7) error out if failed or EOF
		; 8) clear rax and load the read byte into al
		; 9) convert al into the character's value
		; A) OR al with the byte stored in temp1
		;
		; fail conditions:
		; 1} (AL = FF) the read operation was a failure or a non-HEX byte was read
		; 2} (AL = FE) EOF encountered where it shouldn't have
		mov	rdx, 1
		mov	edi, [rel fd1]
		lea	rsi, [rel inbuf]
		movzx	rcx, byte [rel inputptr]
		add	rsi, rcx
		call	readfile
		test	rax, rax
		js	.ReadIHEXByte_fail_1
		jz	.ReadIHEXByte_fail_2
		xor	rax, rax
		mov	al, byte [rsi]
		call	ASCIItoHEX
		jc	.ReadIHEXByte_fail_1
		shl	al, 4
		mov	[rel temp1], al
		inc	byte [rel inputptr]
		movzx	rcx, byte [rel inputptr]
		lea	rsi, [rel inbuf]
		add	rsi, rcx
		call	readfile
		test	rax, rax
		js	.ReadIHEXByte_fail_1
		jz	.ReadIHEXByte_fail_2
		xor	rax, rax
		mov	al, byte [rsi]
		call	ASCIItoHEX
		jc	.ReadIHEXByte_fail_1
		or	al, [rel temp1]
		inc	byte [rel inputptr]
		clc
		ret
.ReadIHEXByte_fail_1:
		mov	al, 0xFF
		stc
		ret
.ReadIHEXByte_fail_2:
		mov	al, 0xFE
		stc	
		ret
		
;--------------------------------------------------------------------
; Subroutine: ASCIItoHEX
; 
; Converts an ASCII value hexadecimal character in AL to its respective
; numerical value, returns it in the lower nibble of AL   
; 
; Inputs: AL - hexadecimal character used to 
; Destroys: AL
; Outputs: AL - value of hexadecimal character
; 	   Carry - set if read failed
;--------------------------------------------------------------------
ASCIItoHEX:
		; check if the character is between '0' and '9'. If so,
		; handle a number character. If it is above, AND it with
		; a bit mask to force upper case and check if it is in
		; range of 'A' through 'F'. If so, handle a letter.
		;
		; In all other cases, indicate a failure by setting the
		; carry flag.
		cmp	al, 0x30
		jb	.ASCIItoHEX_fail
		cmp	al, 0x39
		jbe	.ASCIItoHEX_number
		and	al, 0xDF
		cmp	al, 0x41
		jb	.ASCIItoHEX_fail
		cmp	al, 0x46
		ja	.ASCIItoHEX_fail
		sub	al, 0x37
		clc
		ret
.ASCIItoHEX_number:
		sub	al, 0x30
		clc
		ret
.ASCIItoHEX_fail:
		stc
		ret
