; hextobin.asm - Linux x86-64 bit assembly code
; entered as a command line instruction with arguments
; converts Intel Hex to raw binary
;
;--------------------------------------------------------------
; format: hextobin infile.hex outfile.bin
; 
; Intel Hex: 	a file containing packets of binary data
;		represented as ascii characters. Each byte
;		is represented by two ascii characters meant
;		to be readable by a human operator. Designed
;		to be opened by a text editor.
;
; raw binary:	a file with binary values as a list of bytes
;		containing program, image, or file data.
;		Must be read with a hex editor
;
; Program flow:
;
;	1)	check the number of command line arguments
;
;	2)	if less than two, display usage information
;
;	3)	if at least two, treat the first two as filenames
;		and open then for input and output. Error out
;		if this doesn't succeed.
;
;	4)	input a byte from the file and check it. If it
;		is 2Fh ('/'), see if the next character is also
;		2Fh. Double forward slashes indicate a comment,
;		so keep reading until the byte we input is a new
;		line character, 0x0A. Then return to 4 and read
;		it again.
;
;		if the byte is 0x3A, we have a valid record. Read
;		the following bytes into an input buffer for
;		processing. Do this until we read a byte 0x0A.
;
;	5)	get the first two bytes in the buffer, translate
;		them into a value. This is the number of data
;		bytes in the record. Save this in memory for use.
;
;	6)	get the next four bytes in the buffer, translate
;		into a value. This is the address field. For now
;		we will do nothing with it, but a later iteration
;		of this program is going to be used with transferring
;		data into ROM. The address values will be important
;		then.
;
;	7)	the next two bytes will be data type. For this version
;		we process the record if it is "01". If it is "00" we
;		know that the record is finished and we stop reading
;		records with that line.
;
;	8)	the following will be a string of byte pairs that
;		total the amound read in step 5. These are translated to
;		values and written to the output buffer one by one.
;
;	9)	a tally is kept of all values read. Not bytes, but
;		translated values. The final two bytes in the record
;		are read and translated. The tally is converted to
;		two's complement and compared to the final read value.
;		The checksum should match, indicating a valid file. If
;		all of this checks, add one to the counter for a valid
;		record read.
;
;	10)	if the record type was 01, go back and look for another
;		record. If 00, finish up. Close the input and output
;		files and display the number of records read and number
;		of bytes written to the output file.
;
;	11)	if a record is read that is found invalid, error out by
;		displaying how many valid records were read before
;		finding the problem one.


global _start

section .data

  ; messages to display if no arguments are entered, describes usage

  usage1:	db	"Format: hextobin <inputfile.bin> <outputfile.hex>", 0x0A, 0x0A
  u1len:	equ	$ - usage1
  usage2:	db	"Translates Intel Hex files to raw binary. Currently", 0x0A
  u2len:	equ	$ - usage2
  usage3:	db	"processes only field types 00 and 01. Stores address data for", 0x0A
  u3len:	equ	$ - usage3
  usage4:	db	"later use, as with a programmer, but does nothing with it for now.", 0x0A
  u4len:	equ	$ - usage4
  usage5:	db	"Output file contains only raw data.", 0x0A
  u5len:	equ	$ - usage5
  
  error1:	db	"File error - invalid file name.", 0x0A
  error1len:	equ	$ - error1
  error2:	db	"File error - read failed.", 0x0A
  error2len:	equ	$ - error2
  error3:	db	"File error - write failed.", 0x0A
  error3len:	equ	$ - error3
  error4:	db	"Data error - invalid data.", 0x0A
  error4len:	equ	$ - error4
  
  success1:	db	"File conversion completed successfully.", 0x0A, 0x0A
  success1len:	equ	$ - success1
  success2:	db	" records read.", 0x0A
  success2len:	equ	$ - success2
  success3:	db	" bytes written.", 0x0A
  success3len:	equ	$ - success3

section .bss

  argc:		resq	1				; number of arguments on the command line
  arg1p:	resq	1				; pointer to first filename
  arg2p:	resq	1				; pointer to second filename
  arg3p:	resq	1				; pointer to third argument
  arg4p:	resq	1				; pointer to fourth argument
  address:	resw	1				; memory address to write to (16-bit for 6502 type addressing)

  fd1:		resd	1				; to store the first file descriptor
  fd2:		resd	1				; think really hard about this one...
  
  inbuf:	resb	522				; empty bytes to be used for input data
  inputptr:	resw	1				; used to track position in the input buffer
  
  outbuf:	resb	256				; output buffer to be filled up with data
  outputptr:	resb	1				; used to track position in the output buffer
  
  recordsread:	resd	1				; number of bytes that were read from the input file
  byteswritten:	resd	1				; number of bytes written to the output file
  bytesinrec:	resb	1				; number of bytes in current record

section .text
_start:
		xor	rax, rax			; clear A register
		mov	dword [rel recordsread], 0	; clear memory spots
		mov	dword [rel byteswritten], 0
		mov	rbx, [rsp]			; load the number of arguments into rbx
		mov	qword [rel argc], rbx		; store it in memory
		cmp	rbx, 3				; minimum number of arguments is 3
		jne	.usageonly			; if arguments insufficient, display usage messages as error
		mov	rsi, [rsp + 16]			; get the first argument otherwise
		mov	qword [rel arg1p], rsi		; save it in memory
		mov	rsi, [rsp + 24]			; get the second argument pointer
		mov	qword [rel arg2p], rsi		; save it in memory

.mainroutine:	; open the input file as read-only and output file as write only. Save the
		; file descriptors for later use.
		mov	rdi, [rel arg1p]		; load the address for the input file name
		mov	rsi, 0				; set rsi = 0 (read-only file)
		xor	rdx, rdx			; clear rdx to avoid interference
		call	openfile			; open the first file as the input
		test	rax, rax
		js	.fileerror
		mov	dword [rel fd1], eax		; save the file descriptor
		
		mov	rdi, [rel arg2p]		; load the address for the output file name
		mov	rsi, 577			; (write only file, create file, truncate)
		mov	rdx, 0o644			; set permissions rw-r--r--
		call	openfile			; open the second file as the output
		test	rax, rax
		js	.fileerror
		mov	dword [rel fd2], eax		; save the file descriptor

.loop01:	; read bytes from input file one at a time, check for key characters to steer
		; operation of program. Error out if we read anything that isn't allowed.
		movzx	edx, 1				; set quantity of bytes to read to one
		call	readfile			; read one byte from input file
		test	rax, rax			; check to see if file read succeeded
		js	.readerror			; error out if not
		jz	.donewithfiles			; shouldn't get here, but if we hit the end then exit
		cmp	al, 0x2F			; check if byte read was '/'
		je	.comment01			; handle a comment if so
		cmp	al, 0x3A			; check if byte was ':'
		je	.record01			; process the following text as a record
		cmp	al, 0x0A			; check if byte was endline
		je	.loop01				; if it is, ignore it and keep going
		cmp	al, 0x0D			; check if byte was carriage return
		je	.loop01				; if so, ignore and keep going
		jmp	.dataerror			; if it reads anything else, error out

.comment01:	; determine if we have two '/' characters
		movzx	edx, 1				; if the program reads a byte '/'
		call	readfile			; check if next one is '/' as well
		test	rax, rax
		js	.readerror
		jz	.donewithfiles
		cmp	al, 0x2F			; if second char is not '/' then go
		jne	.dataerror			; to error handler and quit
.comment02:	; if we do, keep reading bytes until end of line.
		call	readfile			; otherwise, we are reading a comment
		test	rax, rax			; so keep reading until we read an
		js	.readerror			; endline character and skip everything
		jz	.donewithfiles			; else.
		cmp	al, 0x0D			; check if byte read is CR or LF
		je	.loop01				; if so, go back and keep reading
		cmp	al, 0x0A			; otherwise ignore bytes until we
		je	.loop01				; get to one of the two endline chars
		jmp	.comment02

.record01:	; initialize data for reading a record
		xor	rbx, rbx			; use rbx as a buffer index
		lea	rdi, [rel inbuf]		; point rdi at input buffer
.record02:	; read bytes and store in buffer until we get to end of line
		movzx	edx, 1				; withdraw one byte
		call	readfile
		test	rax, rax			; standard error handler
		js	.readerror
		jz	.donewithfiles
		cmp	al, 0x0A			; endline character?
		je	.record03			; if so, go down to process the record
		cmp	al, 0x0D			; same check for CR character used in
		je	.record 03			; some data conventions
		mov	byte [rdi + rbx], al		; store the byte in the input buffer
		inc	bx				; increase input buffer index
		jmp	.record02			; go back and record another byte
.record03:	; reinitialize data to convert ASCII data to binary data and
		; store it in the output buffer
		mov	word [rel inputptr], bx		; save the value of bx
		xor	rbx, rbx			; clear the buffer index again
		xor	rcx, rcx			; clear the output buffer index
		xor	rdx, rdx			; clear input data register
		xor	r8, r8				; clear tally counter for checksum
		lea	rsi, [rel inbuf]		; rearrange buffer pointers
		lea	rdi, [rel outbuf]
.record04:	; read ASCII pairs from the input buffer and write the numerical
		; data in the output buffer.
		call	readbyte			; load dx with two ASCII chars
		call	TexttoDB			; transform dx into a number value
		test	rax, rax			; check validity
		js	.dataerror			; and error out if invalid
		mov	byte [rel bytesinrec], al	; save number of bytes in record
		add	r8d, eax			; add to tally
		call	readbyte			; address data is next
		call	TexttoDB
		test	rax, rax
		js	.dataerror
		mov	word [rel address], ax		; save al in memory
		add	r8d, eax			; add to tally
		call	readbyte
		call	TexttoDB
		test	rax, rax
		js	.dataerror
		shl	ax, 8				; move al to ah
		add	word [rel address], ax		; save low byte of address into memory
		add	r8d, eax			; add to tally
		call	readbyte			; field type is next
		call	TexttoDB			
		test	rax, rax
		js	.dataerror
		add	r8d, eax			; add to tally
		cmp	al, 1				; is this an EOF data field?
		je	.record07			; if not, write bytes to the file
.record05:	; go through the data field and read the number of bytes indicated
		; on the record. Store them in the output buffer
		call	readbyte			; look at a data byte
		call	TexttoDB
		test	rax, rax
		js	.dataerror
		mov	byte [rdi + rcx], al		; if it is valid, place it in output buffer
		add	r8d, eax			; add to tally
		inc	cl				; increase the counter
		cmp	cl, byte [rel bytesinrec]	; see if we have read all the bytes
		jne	.record05
.record06:	; read the final byte, the checksum. Use the tally collected
		; during all of the other reads to compare to the checksum
		; and determine if the read was valid.
		and	r8, 255				; clear top seven bytes of r8
		neg	r8b				; two's complement of r8b
		call	readbyte			; grab the checksum chars
		call	TexttoDB
		test	rax, rax
		js	.dataerror
		cmp	r8b, al				; see if file checksum matches calculated checksum
		jne	.dataerror			; 
		inc	dword [rel recordsread], 1	; if we've made it this far we add to the number
		jmp	.write01			; add to the number of successful records read	
.record07:	; if we have encountered the end-of-file data record (type 01), add to the number of
		; successfully written records and finish with program.
		inc	dword [rel recordsread], 1
		jmp	.donewithfiles

.write01:	mov	rdx, rcx			; load number of bytes to write in rdx
		call	writefile			; and write them
		test	rax, rax			; if write was unsuccessful then error out
		js	.writeerror
		jmp	.loop01				; otherwise, go back to beginning of function

.exitprogram:	mov	eax, 60				; set up the function to exit
  		xor	edi, edi			; and go back to the command line
  		syscall

.fileerror:	lea	rsi, [rel error1]		; if there was a problem opening a
		mov	edx, error1len			; file, or the file doesn't exist,
		call	printtext			; display a message and error out
		jmp	.exitprogram

.readerror:	lea	rsi, [rel error2]		; if a read operation failed
		mov	edx, error2len			; display a different message and
		call	printtext			; error out
		jmp	.exitprogram
		
.writeerror:	lea	rsi, [rel error3]		; if a write operation failed
		mov	edx, error3len			; display a different message and
		call	printtext			; error out
		jmp	.exitprogram

.dataerror:	lea	rsi, [rel error4]		; if invalid data is read, display
		mov	edx, error4len			; a different message and error out
		call	printtext
		jmp	.exitprogram

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
; Subroutine: readfile
; 
; Reads bytes from the input file 
; 
; Inputs: rdx - number of bytes
; Destroys: RAX
; Outputs: RAX - > 0: number of bytes read
;	         = 0: end of file reached
;	         < 0: error
;--------------------------------------------------------------------
readfile:	
		mov	edi, [rel fd1]
		lea	rsi, [rel inbuf]
		xor	rax, rax			; rax = 0 sys_read
		syscall
		ret

;--------------------------------------------------------------------
; Subroutine: writefile
; 
; Writes bytes to the output file 
; 
; Inputs: rdx - number of bytes
; Destroys: RAX
; Outputs: RAX - > 0: number of bytes written
;	         < 0: error
;--------------------------------------------------------------------
writefile:	
		mov	edi, [rel fd2]
		lea	rsi, [rel outbuf]
		mov	rax, 1				; rax = 1 sys_write
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
closefile:	
		mov	rax, 3				; rax = 3 sys_close
		syscall
		ret

;--------------------------------------------------------------------
; Subroutine: readbyte
; 
; Reads two ASCII characters from the input buffer and stores them in DH:DL
; 
; Inputs: 	rsi - pointer to the input buffer
;		rbx - buffer index
; Destroys: 	rdx
; Outputs: 	rbx - updated index pointer
;		rdx - contains two bytes of ASCII data (dh:dl)
;--------------------------------------------------------------------
readbyte:
		mov	dh, byte [rsi + rbx]		; take a byte from the input buffer
		inc	rbx				; and store it in dh
		mov	dl, byte [rsi + rbx]		; take another one in dl
		inc	rbx
		ret

;--------------------------------------------------------------------
; Subroutine: TexttoDB
; 
; Turns two ASCII characters into one byte
; 
; Inputs: RDX - two ASCII characters representing one byte 
;		(high byte = dh, low byte = dl)
; Destroys: RAX, RDX
; Outputs: RAX - number value of the ASCII characters in al
;		 rax = -1 if error
;	         
;--------------------------------------------------------------------
TexttoDB:
		xor	rax, rax			; clear rax
		mov	al, dh				; first time - handle high character
.TTDBscreen:	cmp	al, 0x30			; check if character < '0'
		jb	.TTDBerror			; error out
		cmp	al, 0x66			; check if character > 'f'
		ja	.TTDBerror			; error out
		cmp	al, 0x39			; check if character >= '9'
		jae	.TTDBnumber			; handle numeral
		cmp	al, 0x61			; check if character >= 'a'
		jae	.TTDBlower			; handle lower case
		cmp	al, 0x41			; check if character < 'A'
		jb	.TTDBerror			; error out
		cmp	al, 0x46			; check if character > 'F'
		ja	.TTDBerror			; error out
		jmp	.TTDBupper			; handle upper case
.TTDBnumber:	sub	al, 0x30			; convert ASCII '0' to 0x00
		jmp	.TTDBloopchk
.TTDBlower:	sub	al, 0x57			; convert ASCII 'a' to 0x0A
		jmp	.TTDBloopchk
.TTDBupper:	sub	al, 0x37			; convert ASCII 'A' to 0x0A
.TTDBloopchk:	cmp	dh, 0x7F			; is dh 'DEL'?
		je	.TTDBnoloop			; if it already is, don't loop again
		mov	dh, 0x7F			; make dh 'DEL' because we already used it
		shl	al, 4				; multiply al by 16
		mov	ah, al				; copy al into ah
		mov	al, dl				; get the lower byte
		jmp	.TTDBscreen			; go again one more time
.TTDBnoloop:	add	al, ah
		and	rax, 0x00000000000000FF		; ensure rax only contains data in al
		ret					; if we got here, return with al = byte
.TTDBerror:	mov	rax, -1				; return 0xFFFFFFFFFFFFFFFF if failed
		ret
