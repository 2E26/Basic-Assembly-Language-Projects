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
  
  error1:	db	"File error - invalid file name.", 0x0A
  error1len:	equ	$ - error1
  error2:	db	"File error - read failed.", 0x0A
  error2len:	equ	$ - error2
  error3:	db	"File error - write failed.", 0x0A
  error3len:	equ	$ - error3
  error4:	db	"Error - HEX file not valid", 0x0A
  error4len:	equ	$ - error4
  error5:	db	"Error - input invalid.", 0x0A
  error5len:	equ	$ - error5
  
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
  bytesread:	resw	1				; number of bytes that were read from the input file
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
	mov	rdi, [rel filename]
	
.filenamereadloop:
	; read the argument filename one character at a time until we read
	; a null character. Store each byte in memory and increment rcx
	; or if we exceed 64 characters
	mov	al, [rbx + rcx]
	cmp	al, 0x00
	jz	.filenamereaddone
	mov	byte [rdi + rcx], al
	inc	rcx
	cmp	rcx, 0x40
	je	.filenamereaddone
	jmp	.filenamereadloop
	
.filenamereaddone:
	; store the length of the filename in memory
	mov	byte [rel filenamelen], cl
	
.loop:

.usageonly:
	; with no input, the program displays a message
	; explaining how to use the program
	mov	rdx, usage1	
	lea	rsi, [rel usage1len]
	call	printtext
	mov	rdx, usage2
	lea	rsi, [rel usage2len]
	call	printtext
	mov	rdx, usage3	
	lea	rsi, [rel usage3len]
	call	printtext
	mov	rdx, usage4
	lea	rsi, [rel usage4len]
	call	printtext
	mov	rdx, usage5
	lea	rsi, [rel usage5len]
	call	printtext
	jmp	.exitprogram

.inputerror:
	mov	rdx, error5	
	lea	rsi, [rel error5len]
	call	printtext

.closefile:

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
