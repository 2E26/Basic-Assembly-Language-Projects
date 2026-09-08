;--------------------------------------------------------------------------------------------------
; Serial_02.asm
; Jonathan Edwards
; September 01, 2026
;
; this program opens a file in the Intel Hex format and validates it. This performs the first step
; in my process of handling hex files and passing them to a PIC16F877A for programming. The code
; will be directly passed into the next serial program where everything is put together.
;
; Intel Hex Format: ":LLAAAATTDDDD...DDDDCC"
;
; usage: serial_02 input.hex
;
; program flow:
;
; 1) process the argument and load it as a string. Use the string to open a file with this filename
;
; 2) if the file open is successful, read the file until the byte retrieved is 0x3A (':'), which
;    begins a record. If not, jump to step 8
;
; 3) read the first two characters after ':', which indicate how many data bytes are in the line.
;    The default record contains 32 (0x20) bytes. All reads following a colon character will happen
;    two bytes at a time. These two bytes are understood to be ASCII characters representing
;    hexadecimal values. A read will also involve a conversion into numerical data.
;
; 4) read the next four characters, store them in address memory.
;
; 5) read the next two characters. Most of the time this will be 0x00. If it is 0x01, that indicates
;    an EOF record. This tells us that the file is completely done. Otherwise keep going.
;
; 6) set a counter equal to the first byte in the record. Then read character pairs and translate
;    into bytes until the counter is zero. Ensure there are only two characters left.
;
; 7) read the checksum characters. Calculate a checksum based on every read byte in the line, then
;    check if it matches what was just read. If so, count as a valid record and move to the next.
;
; 8) if no argument was entered, display help text. If an argument was entered that doesn't end
;    with ".hex", error out with faulty filename. For other inputs not leading to a hex file read,
;    display an invalid error message.
;
; 9) once all records are read, display total number of data bytes and total number of records
;    validated by the program. If EOF was encountered prior to reading the EOF record, notify the
;    user. Above all, determine whether the HEX file is valid or not. 
;
; There are several tallies that will be taken during the validation process. These figures will
; be displayed as results before closing the program, and they will also be used to ensure the
; file is valid (or not). These are the conditions the file must meet to be considered valid:
;
; a) filename must end in ".hex"
;
; b) file must contain at least one data record (begins with ':', follows hex format)
;
; c) all data records must have an LL field that matches the number of bytes
;
; d) all data records must have a CC field that checks with respect to the rest of the record
;
; e) the last record must be the EOF record 
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
  byteqty:	resb	1				; number of bytes in the current quantity
  bytesread:	resw	1				; number of data bytes that were read from the input file
  recordsread:	resw	1				; number of records counted as valid
  invrecsread:	resw	1				; number of records that do not pass all checks

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
	mov	word [rel bytesread], ax
	mov	word [rel recordsread], ax
	mov	word [rel invrecsread], ax
	
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
	xor	rbx, rbx
	xor	rcx, rcx
	xor	rdx, rdx
	xor	r8, r8
	xor	r9, r9
	xor	r10, r10
	
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

.readingloop:
	; the first record has been located. Now we input real data and start checking it
	; for accuracy.	
.readingbyteqty_1:
	; the first two ASCII characters are the number of data bytes in the record
	; we get them, convert them to a 1-byte value, and store that in memory. This will
	; be used later when we count the data bytes in the record.
	mov	rdx, 0x01
	mov	edi, [rel fd1]
	lea	rsi, [rel inbuf]
	add	rsi, rcx
	call	readfile
	test	rax, rax
	jnz	.readingbyteqty_2
	js	.readerror
	inc	r9
.readingbyteqty_2:
	xor	rax, rax
	mov	al, byte [rsi]
	; handle conversion of al from an ASCII character to a value from 0-15
	; store it in memory at byteqty
	; increment rcx and see if it is over 255. If so, make it 0 and return
	; RSI to the beginning of the input buffer.
	inc	rcx
	inc	rsi
	cmp	rcx, 0x100
	jb	.readingbyteqty_3
	xor	rcx, rcx
	lea	rsi, [rel inbuf]
.readingbyteqty_3:
	call	readfile
	test	rax, rax
	jnz	.readingbyteqty_4
	js	.readerror
	inc	r9
	jmp	; go to the part where we process an early EOF character
.readingbyteqty_4:
	xor	rax, rax
	mov	al, byte [rsi]
	; handle conversion of al from an ASCII character to a value from 0-15
	; shift byteqty left four times and 
	; increment rcx and see if it is over 255. If so, make it 0 and return
	; RSI to the beginning of the input buffer.
	inc	rcx
	inc	rsi
	cmp	rcx, 0x100
	jb	.readingbyteqty_5
	xor	rcx, rcx
	lea	rsi, [rel inbuf]
.readingbyteqty_5:
	; clean up data accountability for this section.
	add	invrecordsread, r9
	
.usageonly:
	; with no input, the program displays a message
	; explaining how to use the program
	mov	rdx, usage1len	
	lea	rsi, [rel usage1]
	call	printtext
	mov	rdx, usage2len
	lea	rsi, [rel usage2]
	call	printtext
	mov	rdx, usage3len	
	lea	rsi, [rel usage3]
	call	printtext
	mov	rdx, usage4len
	lea	rsi, [rel usage4]
	call	printtext
	mov	rdx, usage5len
	lea	rsi, [rel usage5]
	call	printtext
	jmp	.exitprogram

.inputerror:
	mov	rdx, error5len
	lea	rsi, [rel error5]
	call	printtext
	jmp	.exitprogram

.filenameerror:
	mov	rdx, error1len
	lea	rsi, [rel error1]
	call	printtext
	jmp	.exitprogram

.fileerror:
	mov	rdx, error6len
	lea	rsi, [rel error6]
	call	printtext
	jmp	.exitprogram
	
.eoferror:
	mov	rdx, error7len
	lea	rsi, [rel error7]
	call	printtext
	jmp	.closefile

.readerror:
	mov	rdx, error2len
	lea	rsi, [rel error2]
	call	printtext
	jmp	.closefile

.closefile:
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
; Subroutine: texttohex
; 
; Converts two ASCII characters into a hexadecimal qty 
; 
; Inputs: AX - high:low characters that will become a single byte quantity
; Destroys: 
; Outputs:
;--------------------------------------------------------------------	
texttohex:
		ret
