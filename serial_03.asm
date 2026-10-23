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
;       requirements of a HEX file
;   f - error out if the file is invalid. Otherwise, pass on to the next step.
;
; 2) refresh the file counter (lseek) and establish serial connection with the PIC
;
; 3) write the program to EEPROM
;   0 - send a command for the ROM size
;   a - find the first data record
;   b - read the amount of bytes and the address. Read and ignore the type
;   c - set the PIC programming address to the record's beginning address
;   d - read the data bytes in the record and store them in a 64 byte buffer
;   e - if necessary, read another record until 64 bytes are in the buffer
;   f - send 64 bytes into the PIC's memory page for performing a page write
;   g - direct the PIC to perform a block write into ROM with the sent data
;   h - if more data exists in the file, keep reading and writing until we
;       reach the EOF record or pick up an EOF character.
;   i - print a display message stating that we wrote N bytes to ROM
;
;--------------------------------------------------------------------------------------------------

; Passdown log
; Date of last entry: 23 October 2026
;
; What was done: I wrote the code for responding to a PIC-reported fault into a subroutine
;		 and replaced the repetitive functions with calls to that routine. I also
;		 started a subroutine to analyze the fault code and produce the appropriate
;		 error message. Errors will almost certainly end in programs exiting.
;
; What is next:  Finish the error code handler. Write the code to perform a block write to
;		 the EEPROM. Once a block write is performed, come up with a way to display
;		 results and then end the program. In later versions, I could add a
;		 command to read the EEPROM and display the contents on screen. That's also
;		 a complex task to be done with this simpler programmer-controller.
;
; I don't know:  what else needs to be done with this program once the above is done. I still
;		 should write extra code to ensure I'm not butchering the intended address
;		 structure of the program. If I remember correctly, I placed the text dump
;		 for my program in a different area of ROM than the program code. I'm also
;		 going to need to place the code into defined areas when I make other tools
;		 for the monitor program to use.
;

global _start

section .data

  ; text to display on the screen.
  ; first section is usage.
  usage1:	db	"Format: serial_03 -s NN <inputfile.hex>", 0x0A, 0x0A
  u1len:	equ	$ - usage1
  usage2:	db	"Validates a HEX file and writes it to ROM via a PIC16F877A", 0x0A
  u2len:	equ	$ - usage2
  usage3:	db	"-s NN: enter a one or two-digit ROM size in kilobytes.", 0x0A
  u3len:	equ	$ - usage3
  usage4:	db	"inputfile.hex - an Intel HEX file containing code for loading into the ROM", 0x0A
  u4len:	equ	$ - usage4
  usage5:	db	"This is an accessory program to PIC16 Serial_02.asm", 0x0A
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
  error8:	db	"Error - internal error. You royally fucked up somehow.", 0x0A
  error8len:	equ	$ - error8
  
  success1:	db	"HEX file is valid.", 0x0A, 0x0A
  success1len:	equ	$ - success1
  success2:	db	"Number of valid records: "
  success2len:	equ	$ - success2
  success3:	db	"Number of invalid records: "
  success3len:	equ	$ - success3
  success4:	db	"Number of data bytes read: "
  success4len:	equ	$ - success4
  
  intro1:	db	"EEPROM Programmer Handler Software", 0x0A
  intro1len:	equ	$ - intro1
  intro2:	db	"By Jonathan Edwards", 0x0A
  intro2len:	equ	$ - intro2

  eofline:	db	":00000001FF", 0x0A
  eoflinelen:	equ	$ - eofline
  
  endl:		db	0x0A
  
  SerPortName:	db	"/dev/ttyUSB0", 0
  SerPortSize:	equ	$ - SerPortName
  SPErr01:	db	"Serial port open fail. Exiting.", 0
  SPErr01Len:	equ	$ - SPErr01
  SPErr02:	db	"Serial write fail. Exiting.", 0
  SPErr02Len:	equ	$ - SPErr02
  SPErr03:	db	"Serial read fail. Exiting.", 0
  SPErr03Len:	equ	$ - SPErr03

section .bss

  argc:		resq	1				; number of arguments on the command line
  arg1p:	resq	1				; pointer to -s flag
  arg2p:	resq	1				; pointer to kilobyte size entry
  arg3p:	resq	1				; pointer to input filename
  filename:	resb	64				; memory to store filename
  filenamelen:	resb	1				; memory to store filename length
  address:	resw	1				; memory address to write to (16-bit for 6502 type addressing)
  fd1:		resd	1				; to store the first file descriptor (data file)
  fd2:		resd	1				; to store second file descriptor (serial port)  
  inbuf:	resb	256				; empty bytes to be used for input data
  inputptr:	resb	1				; used to track position in the input buffer
  outbuf:	resb	64				; output buffer to be filled up with data
  outputptr:	resb	1				; used to track position in the output buffer
  byteqty:	resb	1				; number of bytes in the current record
  rectype:	resb	1				; used to record the type of record being read
  temp1:	resb	1				; temporary placeholder for one byte
  chksumtotal:	resb	1				; running total for checksum
  is_valid:	resb	1				; a flag that allows certain other functions to declare the file invalid
  rom_size	resb	1				; used to store the ROM size
  addr_change	resb	1				; -1 (0xFF) if we need to update the address before writing
  decimal_flag	resb	1				; 0 if we print decimal to screen, 1 to print to serial port
  PIC_status	resb	1				; used to return a fault code issued by the PIC

section .text

_start:
	; clear all of the memory that we are going to use.
	; this is commonly thought of as unnecessary, but
	; ensures we don't have to deal with leftover garbage
	; data when the program is hundreds of lines long
	mov	qword [rel argc], 0x0000000000000000
	mov	qword [rel arg1p], 0x0000000000000000
	mov	word [rel address], 0x0000
	mov	dword [rel fd1], 0x00000000
	mov	byte [rel inputptr], 0x00
	mov	byte [rel outputptr], 0x00
	mov	byte [rel byteqty], 0x00
	mov	byte [rel temp1], 0x00
	mov	byte [rel chksumtotal], 0x00
	mov	byte [rel rom_size], 0x00
	
.memclear:
	; batch clear the memory buffers before reading/writing
	; to them.
	cld
	mov	rax, 0x00
	mov	rcx, 0x100
	lea	rdi, [rel inbuf]
	rep	stosb
	mov	rcx, 0x40
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
	cmp	rbx, 4
	ja	.inputerror
	jb	.usageonly
	; save the location of the arguments in memory
	; arg1p - "-s" flag
	; arg2p - one or two ASCII characters to dictate the size of the ROM
	; arg3p - input file name
	mov	rsi, [rsp + 16]
	mov	qword [rel arg1p], rsi
	mov	rsi, [rsp + 24]
	mov	qword [rel arg2p], rsi
	mov	rsi, [rsp + 32]
	mov	qword [rel arg3p], rsi
	
.sizeflagvalidate:
	; part of the required input is a "size flag", which is "-s" or "-S"
	; immediately following the command. Failure to enter to command
	; correctly will result in an input error.
	xor	rax, rax
	mov	rbx, [rel arg1p]
	cmp	byte [rbx], 0x2D
	jne	.inputerror
	mov	al, [rbx + 1]
	and	al, 0xDF
	cmp	al, 0x53
	jne	.inputerror
	cmp	byte [rbx + 2], 0x00
	jne	.inputerror
	
.sizeread:
	; this code reads the entered size of ROM.
	; 
	; 1) read a byte at the second arg pointer
	; 2) subtract 48
	; 3) if the result is not 0-9, error out
	; 4) store the result in memory
	; 5) get the next chacter
	; 6) if it is a null char, jump to the next part
	; 7) otherwise, see if the third character is null
	; 8) if the second and third character aren't null, error out
	; 9) subtract 48 from the read byte
	; 10) if the result isn't 0-9, error out
	; 11) store the result in BL
	; 12) retrieve the stored memory byte into EAX, extend out with zeroes
	; 13) multiply EAX by 10 and store in EAX
	; 14) add the value stored in BL
	; 15) check if the resultant value is over 64 (error out if so)
	; 16) store the result in the memory location otherwise
	xor	rax, rax
	mov	rbx, [rel arg2p]
	mov	al, [rbx]
	sub	al, 0x30
	cmp	al, 0x09
	ja	.inputerror
	mov	[rel rom_size], al
	mov	al, [rbx + 1]
	test	al, al
	jz	.filenamereadsetup
	cmp	byte [rbx + 2], 0x00
	jne	.inputerror
	sub	al, 0x30
	cmp	al, 0x09
	ja	.inputerror
	mov	bl, al
	movzx	eax, byte [rel rom_size]
	imul	eax, eax, 10
	add	al, bl
	cmp	al, 0x40
	ja	.inputerror
	cmp	al, 0x00
	je	.inputerror
	mov	[rel rom_size], al
		
.filenamereadsetup:
	; set up rcx as a counter to measure string length
	; clear rax for handling the data
	; load rbx with the pointer stored in arg1p
	; load rdi with a pointer to filename
	xor	rcx, rcx
	xor	rax, rax
	mov	rbx, [rel arg3p]
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
	mov	[rel decimal_flag], 0x00
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success4len	
	lea	rsi, [rel success4]
	call	printtext
	mov	ax, r10w
	mov	[rel decimal_flag], 0x00
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	jmp	.refresh_file
	
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
	mov	[rel decimal_flag], 0x00
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success3len
	lea	rsi, [rel success3]
	call	printtext
	mov	ax, r9w
	mov	[rel decimal_flag], 0x00
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	mov	rdx, success4len
	lea	rsi, [rel success4]
	call	printtext
	mov	ax, r10w
	mov	[rel decimal_flag], 0x00
	call	printdecimal
	mov	rdx, 1
	lea	rsi, [rel endl]
	call	printtext
	jmp	.closefile

.refresh_file:
	; performs an LSEEK operation to reset the file read location
	; to the beginning of the file, then read a character
	; until we come upon the first ':'
	;
	; RAX - syscall 8
	; EDI - the file descriptor
	; RSI - 0 bytes offset from the origin
	; RDX - 0 for origin being the start of the file
	mov	rax, 8
	mov	edi, [rel fd1]
	xor	rsi, rsi
	xor	rdx, rdx
	syscall
	test	rax, rax
	js	.fileerror
	mov	rdx, 0x01
	mov	edi, [rel fd1]
	lea	rsi, [rel inbuf]
.refresh_file_loop:
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror	
	mov	al, [rsi]
	cmp	al, 0x3A
	jne	.refresh_file_loop
	
.serialport_open:
	lea	rdi, [rel SerPortName]
	mov	rsi, 2
	xor	rdx, rdx
	call	openfile
	test	rax, rax
	js	.serialerror_open
	mov	dword[rel fd2], eax
	
.declare_size:
	; before the PIC will do anything, I need to
	; make sure it knows the size of the ROM we are
	; writing to. Otherwise it will ignore all
	; other commands.
	;
	; 1) send "S ##/n" to the PIC. This lets the PIC
	;    know what size ROM we are working with.
	; 2) read the PIC response until we find either 6
	;    (success) or 21 (failure). 
	mov	al, 0x53
	mov	[rel temp1], al
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	call	writefile
	mov	al, 0x20
	mov	[rel temp1], al
	call	writefile
	xor	rax, rax
	mov	al, [rel rom_size]
	mov	byte [rel decimal_flag], 1
	call	printdecimal
	mov	al, 0x0D
	mov	[rel temp1], al
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	call	writefile
	; read the serial stream until we read the success/fail bytes
	call	PIC_Response
	jnc	.programming
	call	PIC_Fault
		
.programming:
	; prepare to program the PIC.
	; clear the input pointer and other variables
	;
	; inputptr is used by ReadIHEXByte
	; byteqty tracks the number of bytes in the current record
	; address is used to store the starting address of the current record
	; addr_change is a flag that indicates whether we need to update the address
	; r12 is a down counter that is used to determine how many bytes are left
	;
	mov	byte [rel inputptr], 0x00
	mov	byte [rel byteqty], 0x00
	mov	word [rel address], 0x0000
	mov	byte [rel addr_change], 0xFF
	xor	r12, r12
	
.programming_loop:
	; start reading the record
	; at this point we have already read the colon marking the
	; beginning of the record. When we come back to this point
	; we should be at the same point on the new record
	;
	; the first step is to read the record's byte quantity
	; (default is 0x20, or 32 bytes) and store it in memory. 
	; Store in R12 to use as a counter later
	call	ReadIHEXbyte
	jc	.readerror
	mov	byte [rel byteqty], al
	movzx	r12, byte [rel byteqty]
	
.programming_address:
	; read and stuff the address to the PIC
	;
	; the address is stored in sequential order in a HEX file,
	; but will be stored in little endian in memory. So,
	; we read and stuff the high address byte first
	; and then read and stuff the low byte
	;
	; we only do the next part if the later stages tell us to.
	; addr_change is set to -1 if we have to update the address
	; that keeps the program from updating it if we haven't
	; performed a write yet.
	;
	; once that is done, check if the address is within
	; the size of ROM and send it to the PIC. The PIC will
	; update its programming address
	call	ReadIHEXByte
	jc	.readerror
	mov	byte [rel address + 1], al
	call	ReadIHEXByte
	jc	.readerror
	mov	byte [rel address], al
	cmp	byte [rel addr_change], 0xFF
	jne	.programming_type
	; perform a check to see if the address is higher than
	; what we've alleged the ROM can handle
	;
	; example: ROM is 32 kB
	; device size is 0x20, or 0b00100000
	; maximum address is 0x7FFF
	; so, copy the device size into AL and multiply by four
	; AL = 0b10000000, or 0x80
	; compare the address high byte to AL. If AL is higher,
	; we have a valid address. If AL is equal or lower,
	; the address entered is not valid.
	;
	; if stated ROM size is 64 (unlikely), we treat every
	; address as valid and keep moving.
	;
	; note that this check does not validate whether a
	; 64-byte write operation will go over the edge of ROM.
	; that is performed by the PIC. 
	mov	al, byte [rel rom_size]
	cmp	al, 0x40
	je	.programming_address_writeaddress
	shl	al, 2
	cmp	al, byte [rel address + 1]
	jbe	; need to have an invalid address handler
	; otherwise, we send an "A" command with
	; the hexadecimal representation of the address bytes
	
.programming_address_writeaddress:
	; send the PIC a command to change the working address.
	; literally "A xxxx/n", where xxxx is the four-character
	; address we want to write. Then, clear the flag we
	; use to indicate an address write happens.
	mov	al, 0x41
	mov	[rel temp1], al
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	call	writefile
	mov	al, 0x20
	mov	[rel temp1], al
	call	writefile
	mov	al, [rel address + 1]
	and	al, 0xF0
	shr	al, 4
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	call	writefile
	mov	al, [rel address + 1]
	and	al, 0x0F
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	call	writefile
	mov	al, [rel address]
	and	al, 0xF0
	shr	al, 4
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	call	writefile
	mov	al, [rel address]
	and	al, 0x0F
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	call	writefile
	mov	al, 0x0D
	mov	[rel temp1], al
	call	writefile
	; clear the address change flag and set up the registers
	; to start reading the PIC's response
	mov	byte [rel addr_change], 0x00
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	
	; read the serial stream until we read the success/fail bytes
	call	PIC_Response
	jnc	.programming_type
	call	PIC_Fault	

.programming_type:
	; read the file type to see if we are at the end
	call	ReadIHEXByte
	jc	.readerror
	mov	byte [rel rectype], al
	cmp	al, 0x01
	jne	.programming_read_data
	jmp	; end of programming - we found the end of file record
	
.programming_read_data:
	; start reading data bytes from the record. Store them in the
	; output buffer. Keep going until we are out of bytes in the
	; current record or we hit 64 bytes in the buffer.
	;
	; 1) read two ASCII characters from the file. Convert to a byte value and
	;    store in AL
	; 2) if the read failed, error out
	; 3) place the output pointer value in RBX
	; 4) point to the buffer address in RSI
	; 5) store the value in AL into memory at RSI + RBX (outputbuffer[outputptr])
	; 6) decrement R12, the byte counter
	; 7) increment output pointer
	; 8) R12 = 0? if so, go to clearing the record and return to read the next one
	; 9) outputptr = 64? if so, go to writing the data to the PIC. Clear outputptr
	; 10) if neither are true, repeat all of these steps again
	call	ReadIHEXByte
	jc	.readerror
	movzx	rbx, byte [rel outputptr]
	lea	rsi, [rel outbuf]
	mov	byte [rsi + rbx], al
	inc	byte [rel outputptr]
	dec	r12
	jz	.programming_consume_endofrecord
	cmp	byte [rel outputptr], 0x40
	jne	.programming_read_data
	jmp	.programming_fill_page
	
.programming_consume_endofrecord:
	; read bytes from the file until one is ":". That aligns
	; us to the next record. Then checks if the output pointer
	; is 64, meaning we still have memory writing to do
	mov	rdx, 0x01
	mov	edi, [rel fd1]
	lea	rsi, [rel temp1]
	
.programming_consume_endofrecord_loop:
	call	readfile
	test	rax, rax
	js	.readerror
	jz	.eoferror
	cmp	byte [rel temp1], 0x3A
	jne	.programming_consume_endofrecord_loop
	cmp	byte [rel outputptr], 0x40
	je	.programming_fill_page
	jmp	.programming_loop
	
.programming_fill_page:
	; initialize registers to send data bytes to the PIC
	; R13 will count up until it equals outputptr
	; rax (well, AL) will get data from outbuf, convert it to
	; ASCII characters, and then have them sent over serial
	; to the PIC two at a time.
	xor	r13, r13
	xor	rax, rax
	; send the basic command to initiate the fill operation
	; 1) send characters "P", " ", and then the number of
	;    bytes to send in decimal. Finally, the end line
	;    character is sent.
	; 2) read characters from the serial port until we have
	;    the EOF message sent by the PIC, and make sure
	;    we get the success message.
	mov	al, 0x50
	mov	[rel temp1], al
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	call	writefile
	mov	al, 0x20
	mov	[rel temp1], al
	call	writefile
	; get the number of bytes we are going to write 
	mov	al, [rel outputptr]
	mov	byte [rel decimal_flag], 0x01
	call	printdecimal
	mov	al, 0x0D
	mov	[rel temp1], al
	call	writefile
	
	; read the serial stream until we read the success/fail bytes
	call	PIC_Response
	jnc	.programming_fill_sendbytes
	call	PIC_Fault	
	
.programming_fill_sendbytes:
	; set up the program for serial writing. R13 is a write
	; counter that stops writing when we meet the value
	; stored in outputptr
	mov	edx, 0x01
	mov	edi, [rel fd2]
	xor	rax, rax
	
.programming_fill_sendbytes_loop:
	; read a byte from the output buffer, translate it
	; into ASCII, and send it out on the serial port.
	; This happens twice, once for the high nibble and
	; then the low nibble.
	; 
	; Example - byte read is 0x3A.
	;
	; 1) - mask off the low nibble (0x30)
	; 2) - shift right four (0x03)
	; 3) - convert to ASCII (0x33, '3')
	; 4) - send '3' over serial
	; 5) - read the byte again (0x3A)
	; 6) - mask off the high nibble (0x0A)
	; 7) - convert to ASCII (0x41, 'A')
	; 8) - send 'A' over serial
	; 9) - increment R13
	; A) - if R13 equals outputptr, we are done
	; B) - if not, read the next byte and keep going
	;
	; below we read, convert, and send the first ASCII character
	;
	lea	rsi, [rel outbuf]
	mov	al, [rsi + r13]
	and	al, 0xF0
	shr	al, 4
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	lea	rsi, [rel temp1]
	call	writefile
	; now we do the second one
	lea	rsi, [rel outbuf]
	mov	al, [rsi + r13]
	and	al, 0x0F
	call	NibbletoASCII
	jc	.internalerror
	mov	[rel temp1], al
	lea	rsi, [rel temp1]
	call	writefile
	; writing is complete. Increment the byte counter
	; and see if we hit the limit.
	inc	r13
	cmp	r13b, [rel outputptr]
	jb	.programming_fill_sendbytes_loop
	; we make it here when R13 is equal to the number in
	; the output pointer. We are done sending bytes.

	; read the serial stream until we read the success/fail bytes
	call	PIC_Response
	jnc	.programming_write_ROM
	call	PIC_Fault	
	
.programming_write_ROM:
	; instruct PIC to write to the ROM
	
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
	
.serialerror_open:
	mov	rdx, SPErr01len
	lea	rsi, [rel SPErr01]
	call	printtext
	jmp	.closeserial
	
.serialerror_write:
	mov	rdx, SPErr02len
	lea	rsi, [rel SPErr02]
	call	printtext
	jmp	.closeserial

.serialerror_read:
	mov	rdx, SPErr03len
	lea	rsi, [rel SPErr03]
	call	printtext
	jmp	.closeserial
	
.internalerror:
	mov	rdx, error8len
	lea	rsi, [rel error8]
	call	printtext
	jmp	.closeserial
	
.closeserial:
	xor	rdi
	mov	edi, [rel fd2]
	call	closefile

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
; Byte Decimal_Flag - 0 to print to the screen, 1 to print to the serial port
; 
; Inputs: AX - binary value we want to print to screen/serial port
;	  Decimal_Flag - where to print the result
; Destroys: AX, BX, DX, Temp1
; Outputs: Printed characters to screen or serial port
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
		cmp	byte [rel decimal_flag], 0x00
		jnz	.printdecimal_next_serial
		call	printtext
		jmp	.printdecimal_next_finish
.printdecimal_next_serial:
		mov	edi, [rel fd2]
		call	writefile
.printdecimal_next_finish:
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
		cmp	byte [rel decimal_flag], 0x00
		jnz	.printdecimal_zerohandler_serial
		call	printtext
		jmp	.printdecimal_zerohandler_finish
.printdecimal_zerohandler_serial:
		mov	edi, [rel fd2]
		call	writefile
.printdecimal_zerohandler_finish:
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
		cmp	byte [rel decimal_flag], 0x00
		jnz	.printdecimal_end_serial
		call	printtext
		jmp	.printdecimal_end_finish
.printdecimal_end_serial:
		mov	edi, [rel fd2]
		call	writefile
.printdecimal_end_finish:	
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
; Inputs: AL - ASCII character representing a value from 0-15
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

;--------------------------------------------------------------------
; Subroutine: NibbletoASCII
; 
; Converts the lower four bits in AL to an ASCII character
; 
; Inputs: AL - 0x0000nnnn, where nnnn represents a value 0-15
; Destroys: AL
; Outputs: AL - ASCII character 0x30-0x39 or 0x41-0x46
; 	   Carry - set if read failed
;--------------------------------------------------------------------
NibbletoASCII:
	cmp	al, 0x0A
	jae	.NibbletoASCII_letter
	add	al, 0x30
	clc
	ret
.NibbletoASCII_letter:
	cmp	al, 0x0F
	ja	.NibbletoASCII_error
	add	al, 0x37
	clc
	ret
.NibbletoASCII_error:
	xor	al, al
	stc
	ret
	
;--------------------------------------------------------------------
; Subroutine: PIC_Response
; 
; Reads bytes from the serial data port until we receive a specific
; code given by the PIC. The PIC will send serial text messages to
; communicate with a user. After the text, a three-byte code is sent.
;
; A success code will be 0x060004.
;
; A failed code will be 0x15nn04, where nn is a fault code.
;
; Fault codes: 
;
; 0x01 - invalid input
; 0x02 - excessive input
; 0x03 - increment error
; 0x04 - decrement error
; 0x05 - ROM size not specified
; 0x06 - Address out of bounds
; 0x07 - Block excess demand error
; 0x08 - Block address invalid error
; 
; Inputs: none
; Destroys: EDX, EDI, RSI, RAX
; Outputs: Carry clear if PIC reports success
;	   Carry set if PIC sends an error code
;	   PIC_status contains the error code
;	   serial read errors exit the program
;--------------------------------------------------------------------
PIC_Response:
	mov	edx, 0x01
	mov	edi, [rel fd2]
	lea	rsi, [rel temp1]
	mov	byte [rel PIC_status], 0x00
.PIC_Response_loop:
	call	readfile
	test	rax, rax
	js	.serialerror_read
	jz	.serialerror_read
	cmp	byte [rel temp1], 0x06
	je	.PIC_Response_success
	cmp	byte [rel temp1], 0x15
	je	.PIC_Response_fail
	jmp	.PIC_Response_loop
.PIC_Response_success:
	call	readfile
	test	rax, rax
	js	.serialerror_read
	jz	.serialerror_read
	cmp	byte [rel temp1], 0x04
	jne	.PIC_Response_success
	clc
	ret
.PIC_Response_fail:
	call	readfile
	test	rax, rax
	js	.serialerror_read
	jz	.serialerror_read
	mov	al, [rel temp1]
	mov	[rel PIC_status], al
.PIC_Response_fail_01:
	call	readfile
	test	rax, rax
	js	.serialerror_read
	jz	.serialerror_read
	cmp	byte [rel temp1], 0x04
	jne	.PIC_Response_fail_01
	stc
	ret
	
;--------------------------------------------------------------------
; Subroutine: PIC_Fault
; 
; 
; Inputs: PIC_status contains the fault code read from the serial stream 
; Destroys: 
; Outputs: displays relevant error message and then exits program
;
;--------------------------------------------------------------------
PIC_Fault:
