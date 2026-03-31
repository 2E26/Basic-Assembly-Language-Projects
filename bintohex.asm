; bintohex.asm - Linux x86-64 bit assembly code
; entered as a command line instruction with arguments
; converts raw binary to Intel Hex
;
;--------------------------------------------------------------------
; format: bintohex infile.bin outfile.hex
;
; raw binary: a file with values byte-by-byte sequentially.
; 	      can represent program code or any other file
;
; Intel Hex: a file containing binary data in packets, using
;            ascii characters to represent values. Each byte
;	     is represented with two ascii characters in a
;	     hexadecimal format.
;
; Intel Hex Format: ":LLAAAATTDDDD...DDDDCC"
;
; Each instance of "//" denotes a comment. The program ignores all text
; that occurs following this until the next line.
;
; Each line containing data starts with ":" (hex value 0x3A)
; LL: the first byte contains the number of data bytes on the line (max 256)
; AAAA: addressing information to be used for storing the data
; TT: type of record. Several conventional values exist.
;	-00 for data (most records)
;	-01 for end of file (occurs at end of file, strangely enough)
;	-02 for extended segment address (not used in this program)
;	-03 for start segment address (not used in this program)
;	-04 for extended linear address (not used in this program)
;	-05 for start linear address (not used in this program)
; DD: data bytes. The number of character pairs equals the value
;	in the LL field.
; CC: checksum. This figure is the 2's complement of the lower byte
;	of all values in the line added together. The lower byte of
;	the sum shoud all add to 0x00. 
;
; Program flow:
;
;   1) check the number of command line arguments
;
;   2) if less than two, display usage help message
;
;   3) if two or more, create pointers of first two args
;
;   4) third and fourth arg are optional address info
;
;   5) open input and output files. Error out if this fails
;
;   6) read 256 bytes from input file
;
;   7) 32 bytes at a time, create Intel Hex records with data
;
;   8) write IH records to output file until all data is read
;
;   9) close files and print success message with number of bytes read
;
;--------------------------------------------------------------------

global _start

section .data

  ; messages to display if no arguments are entered, describes usage

  usage1:	db	"Format: bintohex <inputfile.bin> <outputfile.hex>", 0x0A, 0x0A
  u1len:	equ	$ - usage1
  usage2:	db	"Translates raw binary files to Intel Hex format. Currently", 0x0A
  u2len:	equ	$ - usage2
  usage3:	db	"uses only data field types 00 and 01. Addressing can be", 0x0A
  u3len:	equ	$ - usage3
  usage4:	db	"adjusted by adding the arguments '-a ####' to the command.", 0x0A
  u4len:	equ	$ - usage4
  usage5:	db	"#### is the hex value for the starting address.", 0x0A
  u5len:	equ	$ - usage5
  
  error1:	db	"File error - invalid file name.", 0x0A
  error1len:	equ	$ - error1
  error2:	db	"File error - read failed.", 0x0A
  error2len:	equ	$ - error2
  error3:	db	"File error - write failed.", 0x0A
  error3len:	equ	$ - error3
  error4:	db	"Address error - invalid input", 0x0A
  error4len:	equ	$ - error4
  
  success1:	db	"File conversion completed successfully.", 0x0A, 0x0A
  success1len:	equ	$ - success1
  success2:	db	" bytes read.", 0x0A
  success2len:	equ	$ - success2
  success3:	db	" bytes written.", 0x0A
  success3len:	equ	$ - success3

  eofline:	db	":00000001FF", 0x0A
  eoflinelen:	equ	$ - eofline

section .bss

  argc:		resq	1				; number of arguments on the command line
  arg1p:	resq	1				; pointer to first filename
  arg2p:	resq	1				; pointer to second filename
  arg3p:	resq	1				; pointer to third argument
  arg4p:	resq	1				; pointer to fourth argument
  address:	resw	1				; memory address to write to (16-bit for 6502 type addressing)
  
  fd1:		resd	1				; to store the first file descriptor
  fd2:		resd	1				; think really hard about this one...
  
  infilebuf:	resb	256				; empty bytes to be used for input data
  inputptr:	resb	1				; used to track position in the input buffer
  
  outbuf:	resb	96				; output buffer to be filled up with data
  outputptr:	resb	1				; used to track position in the output buffer
  
  bytesread:	resd	1				; number of bytes that were read from the input file
  byteswritten:	resd	1				; number of bytes written to the output file  

section .text
_start:

		xor	rax, rax			; clear A register
		mov	dword [rel bytesread], 0	; clear memory spots
		mov	dword [rel byteswritten], 0	;
		mov	eax, 0x00000200			; set a default starting address of 200h for 6502 programming
		mov	word [rel address], ax		; write to the start address memory, default 0200h
		mov	rbx, [rsp]			; load the number of arguments into rbx
		mov	qword [rel argc], rbx		; store it in memory
		cmp	rbx, 3				; minimum number of arguments is 3
		jb	.usageonly			; if arguments insufficient, display usage messages as error
		
		mov	rsi, [rsp + 16]			; get the first argument otherwise
		mov	qword [rel arg1p], rsi		; save it in memory
		mov	rsi, [rsp + 24]			; get the second argument pointer
		mov	qword [rel arg2p], rsi		; save it in memory
		cmp	rbx, 5				; if there is address data, args = 5
		jne	.mainroutine			; if not, jump to the next step
		mov	rsi, [rsp + 32]			; get the third argument pointer
		mov	qword [rel arg3p], rsi		; save it in memory
		mov	rsi, [rsp + 40]			; get the fourth argument pointer
		mov	qword [rel arg4p], rsi		; save it in memory
		
		mov	rsi, [rel arg3p]		; save the third argument pointer in rsi
		mov	al, '-'				; make al character to compare
		mov	bl, byte [rsi]			; grab first character of arg 3
		cmp	al, bl				; see if they match
		jne	.addresserror			; if not then error out
		mov	al, 'a'				; repeat process to check if third argument is "-a", 0x00
		mov	bl, byte [rsi + 1]
		cmp	al, bl
		jne	.addresserror
		mov	al, 0
		mov	bl, byte [rsi + 2]
		cmp	al, bl
		jne	.addresserror
		
		mov	rsi, [rel arg4p]
		mov	eax, dword [rsi]		; otherwise, get four bytes from the command line
		call	TexttoDW			; convert ascii characters into a number value
		test	eax, eax
		js	.addresserror			; error out if address invalid
		mov	word [rel address], ax		; store this as the new address

		; the following four characters into the address variable and use it to designate
		; where the code is going in the Intel Hex format. For this we will need a routine
		; to translate ASCII to a number value in memory, something I'm going to have to
		; borrow from my other programs.
				
.mainroutine:
  ; translates raw binary data into the HEX format. Draws 256 bytes at a time from the input
  ; file and creates HEX records of 32 bytes at a time.
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
		
.loop_01:	mov	rdx, 256			; rdx = 256
		call	readfile			; pull 256 bytes from input file
		test	rax, rax			; check value of rax
		js	.readerror			; if value is negative, error out
		je	.donewithfiles			; exit loop if end of file
		add	dword [rel bytesread], eax	; total up number of read bytes
		xor	rbx, rbx			; rbx = 0 to clear some memory
		mov	byte [rel inputptr], bl		; reset the pointer for the input buffer
		
		; The write routine will work with the following steps
		;
		; establish pointers to the input buffer and output buffer
		; if (bytes read < 32) then rdx = bytes read, rax = 0
		; else if (bytes read >= 32) then rdx = 32, rax = rax - 32
		; call make record
		;    makerecord: take the input bytes and translate them into an Intel Hex string
		;    1 - first character of the output string is 0x3A, or ":"
		;    2 - then the number of data bytes in ASCII hexadecimal
		;    3 - the address in hexadecimal (default is 0x0200), can be changed in the command line
		;    4 - the record type, 01 for EOF and 00 for everything else
		;    5 - the data bytes
		;    6 - check sum is calculated using all bytes in the string
		;    7 - 0x0A is added as the last character
		; rax is saved before makerecord is called, and loaded afterward.
		; Once the record is written, send the entire record to the output file.
		;
		; Since we are reading 256 bytes at a time and writing 32 at a time, we will need pointers
		; to keep track of the position in the input buffer.
		; A single byte, inputptr, will save our place in the input buffer 
		
.loop_02:	lea	rsi, [rel infilebuf]
		lea	rdi, [rel outbuf]
		cmp	rax, 0x20			; compare the number of read bytes to 32
		jae	.32ormore			; if we have more than 32, process 32 at a time
		mov	rdx, rax			; save the number of bytes remaining in rdx
		xor	rax, rax			; clear rax
		jmp	.writetofile			; go to writing part of loop
.32ormore:	mov	rdx, 0x20			; rdx = 32
		sub	rax, 0x20			; rax = rax - 32
.writetofile:	push	rax				; save rax to the stack
		call	makerecord			; translate bytes into ASCII text
		mov	rdx, rcx			; set rdx to the number of bytes
		call	writefile
		test	rax, rax			; check if write succeeded
		js	.writeerror			; error out if it failed
		add	dword [rel byteswritten], edx	; save the number of bytes written
		pop	rax				; recover rax from the stack
		test	rax, rax			; if (rax = 0) then go back to read loop
		jne	.loop_02			; if (rax > 0) then keep writing
		jmp	.loop_01  			; if all is well, loop back and do it again
		
.donewithfiles:	
		call	endrecord
		mov	edi, dword [rel fd1]		; load file designator for input file
		call	closefile			; release control of it
		mov	edi, dword [rel fd2]		; do the same for the output file
		call	closefile

		lea	rsi, [rel success1]		; display a message of successful file conversion
		mov	edx, success1len		;
		call	printtext			;
		mov	eax, dword [rel bytesread]	; get the number of bytes read
		call	DWtoText			; convert it to ASCII
		lea	rsi, [rel outbuf]		; print it to the screen
		mov	edx, r9d
		call	printtext
		lea	rsi, [rel success2]		; print the accompanying text to the screen
		mov	edx, success2len		; "###,###,### bytes read."
		call	printtext			;
		mov	eax, dword [rel byteswritten]	; get the number of bytes written
		call	DWtoText			; convert it to ASCII
		lea	rsi, [rel outbuf]		; print it to the screen
		mov	edx, r9d
		call	printtext
		lea	rsi, [rel success3]		; print the accompanying text to the screen
		mov	edx, success3len		; "###,###,### bytes written."
		call	printtext		
		jmp	.exitprogram

.usageonly:
  ; If the program is entered without enough arguments to function, prints usage information
  ; instead of faulting out. This is the default response unless the arguments fit the expected
  ; format. All it does is display the usage text messages and then exits the program
  
		lea	rsi, [rel usage1]
		mov	edx, u1len
		call	printtext
		lea	rsi, [rel usage2]
		mov	edx, u2len
		call	printtext
		lea	rsi, [rel usage3]
		mov	edx, u3len
		call	printtext
		lea	rsi, [rel usage4]
		mov	edx, u4len
		call	printtext
		lea	rsi, [rel usage5]
		mov	edx, u5len
		call	printtext
		jmp	.exitprogram

.readerror:
		lea	rsi, [rel error2]		; if a read operation failed
		mov	edx, error2len			; display a different message and
		call	printtext			; error out
		jmp	.exitprogram
		
.writeerror:
		lea	rsi, [rel error3]		; if a write operation failed
		mov	edx, error3len			; display a different message and
		call	printtext			; error out
		jmp	.exitprogram
		
.fileerror:
		lea	rsi, [rel error1]		; if there was a problem opening a
		mov	edx, error1len			; file, or the file doesn't exist,
		call	printtext			; display a message and error out
		jmp	.exitprogram

.addresserror:	lea	rsi, [rel error4]		; if there was an issue with the address
		mov	edx, error4len			; specified by the user, display a
		call	printtext			; message and error out

.exitprogram:	mov	eax, 60				; set up the function to exit
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
; Destroys: RAX
; Outputs: RAX - > 0: number of bytes read
;	         = 0: end of file reached
;	         < 0: error
;--------------------------------------------------------------------
readfile:	mov	edi, [rel fd1]
		lea	rsi, [rel infilebuf]
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
writefile:	mov	edi, [rel fd2]
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
closefile:	mov	rax, 3				; rax = 3 sys_close
		syscall
		ret
		
;--------------------------------------------------------------------
; Subroutine: makerecord
; 
; translates a chunk of bytes into an Intel Hex string 
; 
; Inputs: 	rsi - input array address pointer
;	  	rdi - output string address pointer
;	  	rdx - number of bytes to translate
;
; Destroys: 	rbx - used to pass bytes to DBtoText
;		rcx - used to track position in the output buffer
;		r8 - tracks the input buffer position (256 bytes vs 80ish)
;		r9 - accumulates the total value of all bytes to write a checksum at the end
;
; Outputs: 	output buffer has an Intel Hex string in it.
;		rcx - number of bytes written to file
;--------------------------------------------------------------------
makerecord:	xor	rcx, rcx			; clear rcx
		xor	r8, r8				; clear r8
		xor	r9, r9
		mov	byte [rdi], 0x3A		; first character is ":"
		inc	ecx				; ecx += 1
		
		; now we convert the number of data bytes in the record
		; to the LL format. Range 0-255. Value is in rdx right now.
		
		mov	rbx, rdx			; copy byte number into rbx
		call	DBtoText			; ah, al, now contain ascii characters
		call	writerecord			; store them in the output buffer
		add	r9, rbx				; add the byte to r9 to establish a total
		
		; the next step is to print the address byte. Default location is
		; 0x0200 unless a command line argument changes it.
		
		mov	bx, word [rel address]		; get the address location
		and	bx, 0xFF00			; clear out the bottom 8 bits
		shr	bx, 8				; move the bytes over
		call	DBtoText			; translate the high byte of address into ASCII
		call	writerecord			; write it to the buffer
		add	r9, rbx				; add to the total
		mov	bx, word [rel address]		; grab the address location again
		and	bx, 0x00FF			; this time, clear off the top 8 bits
		call	DBtoText			; convert to ASCII
		call	writerecord			; store it in the output buffer
		add	r9, rbx				; add to the total
		
		; data field type is next. All fields will be 00 except for the last one, which is 01.
		; for now we are just writing the code to write data fields. There will be a subroutine
		; just to write the EOF record, which is the same in every file
		
		xor	bx, bx				; just make data field 00
		call	DBtoText			; and write it to the output buffer
		call	writerecord
		
		; at this point we are ready to read from the input buffer and translate it to text
		; for the output. 
		
		xor	r8, r8				; clear r8 to use as an input tracker
		xor	rbx, rbx			; clear bx again
.makerecord_01:	add	r8b, [rel inputptr]		; restore the offset in the input pointer
		mov	bl, byte [rsi + r8]		; grab the byte in the input buffer + pointer
		inc	r8b				; advance the counter by one
		call	DBtoText			; convert the byte
		call	writerecord			; write the characters
		add	r9, rbx				; add to the total
		sub	r8b, [rel inputptr]		; get the number of times we've done this
		cmp	r8b, dl				; see if we've written all the bytes
		jne	.makerecord_01			; if we haven't, go back and do it again
		add	r8b, [rel inputptr]		; restore the input pointer once the loop has exited
		add	dx, word [rel address]		; add the current address to rdx
		mov	word [rel address], dx		; and save it in memory, increasing the address for the next record
		mov	byte [rel inputptr], r8b	; save the new offset
		
		; now we calculate the checksum using all of the bytes written so far.
		; r9 has been totaling up the sum of the bytes in the record
		; and by now has added up all relevant bytes
		
		and	r9, 0x00000000000000FF		; clear out all information except for the bottom byte
		neg	r9b				; take the two's complement of r9b
		mov	bl, r9b				; move it to the end
		call	DBtoText
		call	writerecord
		mov	byte [rdi + rcx], 0x0A		; place a new line character on the end
		inc	ecx				; add one to counter of bytes
		ret
		
;--------------------------------------------------------------------
; Subroutine: writerecord
; 
; places ASCII characters stored in AX into output memory to be
; written to the output file. Typically called right after
; DBtoText
; 
; Inputs:   rdi - output record pointer
;	    rcx - output record offset
;	    ah - ascii character for top nibble of byte
;	    al - ascii character for bottom nibble of byte
; Destroys: 
; Outputs: ascii characters to the output buffer
;--------------------------------------------------------------------		
writerecord:	mov	byte [rdi + rcx], ah
		inc	ecx
		mov	byte [rdi + rcx], al
		inc	ecx
		ret
		
;--------------------------------------------------------------------
; Subroutine: endrecord
; 
; writes the EOF record to the output file (":00000001FF", 0x0A)
; 
; Inputs:   none, reads all inputs from memory
; Destroys: rcx, rdx, rsi, rdi
; Outputs: ASCII characters to the output buffer
;--------------------------------------------------------------------
endrecord:	mov	rcx, eoflinelen		
		lea	rsi, [rel eofline]
		lea	rdi, [rel outbuf]
		rep	movsb
		mov	rdx, eoflinelen
		call	writefile
		add	dword [rel byteswritten], 12
		ret

;--------------------------------------------------------------------
; Subroutine: TexttoDW
; 
; translates an ASCII string into a number value 
; 
; Inputs: 	eax - four bytes containing ascii characters
; Destroys: 	eax, ebx, ecx, edx
; Outputs:	ax = word with updated address in it
;		eax = -1 if invalid input
;--------------------------------------------------------------------

		; This process works by converting four ascii characters
		; into a single two-byte value for address dictation
		; 
		; Example: input is "ABCD"
		; 
		; 1 - eax = 0x44434241
		; 2 - bswap eax (eax = 0x41424344)
		; 3 - copy eax to ebx for later
		; 4 - make ecx = 4 to count down loops
		; 5 - mask off eax (eax = 0x41000000)
		; 6 - shift right by 24 (eax = 0x00000041)
		; 7 - convert 0x41 to 0x0A
		; 8 - shift edx left 8 bits, multiplying by 16 (edx = 0)
		; 9 - add eax to edx (edx = 0x0000000A)
		; A - copy ebx back to eax (eax = 0x41424344)
		; B - shift eax left 8 bits (eax = 0x424344xx)
		; C - subtract 1 from ecx (the shift counter)
		; D - if ecx isn't zero, go to 5 and do it again
		;
		; Second loop - eax = 0x00000042, ecx = 3, edx = 0x000000AB
		;
		; Third loop - eax = 0x00000043, ecx = 2, edx = 0x00000ABC
		; 
		; Fourth loop - eax = 0x00000044, ecx = 1, edx = 0x0000ABCD
		;
		; After the fourth loop, ecx = 0 and we don't do it again
		; 
		; At this point, we finish up
		;
		; 1 - eax = edx (eax = 0xxxxxABCD)
		; 2 - eax = eax && 0x0000FFFF (eax = 0x0000ABCD)
		; 3 - return from program

TexttoDW:	bswap	eax
		mov	ebx, eax			; save eax to ebx
		mov	ecx, 4				; count four bytes
		xor	edx, edx			; clear edx
.TexttoDW_loop:	and	eax, 0xFF000000			; mask off highest byte in eax
		shr	eax, 24				; shift right 24 times to place data in al
		cmp	al, 0x30			; check for characters less than '0'
		jb	.TexttoDW_err
		cmp	al, 0x66			; check for characters higher than 'f'
		ja	.TexttoDW_err
		cmp	al, 0x39			; check if character is '9' or lower
		jbe	.TexttoDW_num
		cmp	al, 0x61			; check if character is 'a' or higher
		jae	.TexttoDW_lwc
		cmp	al, 0x41			; check if character is lower than 'A'
		jb	.TexttoDW_err
		cmp	al, 0x46			; check if character is 'F' or lower
		jbe	.TexttoDW_upc
		jmp	.TexttoDW_err		
		
.TexttoDW_num:	sub	al, 0x30			; convert a numerical digit into a number value
		jmp	.TexttoDW_cnv
.TexttoDW_lwc:	sub	al, 0x57			; convert a lower case character into a number value
		jmp	.TexttoDW_cnv
.TexttoDW_upc:	sub	al, 0x37			; convert an upper case character into a number value
.TexttoDW_cnv:	shl	edx, 4				; multiply edx by 16
		add	edx, eax			; add the value in eax
		shl	ebx, 8				; move saved value left 8 bits to work on new byte
		mov	eax, ebx			; copy value back into working register
		dec	ecx				; count down by 1
		test	ecx, ecx			; is counter zero?
		jne	.TexttoDW_loop			; if not, do it again
		mov	eax, edx			; copy numerical value to eax
		and	eax, 0x0000FFFF			; clear any garbage data from high word
		ret		
		
.TexttoDW_err:	mov	eax, -1				; return error code	
		ret

;--------------------------------------------------------------------
; Subroutine: DBtoText
; 
; translates a number value into ASCII text in hexadecimal notation
; 
; Inputs: rbx - number value to translate into text
; Destroys: rax
; Outputs: ah, al - two ascii characters representing one byte
;          when writing to memory, these will need to be placed
;          individually and not as ax.
;--------------------------------------------------------------------
DBtoText:	; example of how this system works
		;  
		; rdx = 185 (0xB9)
		; al = bl = 185
		; ah = al = 185
		; ax = 0xB9B9
		; and al, 0b00001111 (al = 0b00001001, or 0x09)
		; carry flag equal zero for shifting
		; ah = ah / 16 (ah = 0b00001011, or 0x0B)
		; ax is now 0x0B09
		;
		; ah is higher than 9, so ah += 0x37. Ah now is 0x42 ('B')
		; al is not higher than 9, so al += 0x30. Al now 0x39 ('9')
		; ax now contains 0x4239 ('B', '9')
		
		mov	al, bl		; save the number value in al
		mov	ah, al		; copy the number to ah
		and	al, 0x0F	; mask off high bits of al
		shr	ah, 4		; mask off low bits of ah
		cmp	ah, 9
		ja	.DBtoText_01
		add	ah, 0x30
		jmp	.DBtoText_02
.DBtoText_01:	add	ah, 0x37
.DBtoText_02:	cmp	al, 9
		ja	.DBtoText_03
		add	al, 0x30
		jmp	.DBtoText_04
.DBtoText_03:	add	al, 0x37
.DBtoText_04:	ret

;--------------------------------------------------------------------
; Subroutine: DWtoText
; 
; translates a 32-bit number value into ASCII text in decimal notation
; 
; Inputs: 	rax - number value to translate into text
; Destroys: 	rax, rbx, rcx, rdx, rdi, r8d, r9d
; Outputs: 	output buffer memory with string of text
;--------------------------------------------------------------------
DWtoText:
		; the procedure here translates the bytes read and written to
		; ASCII text to be printed on the command line. Here are the steps...
		;
		; 1 - initialize variables and point to the output buffer
		; 2 - place a space character in the last byte of outbuf
		; 3 - check if number of bytes is zero
		; 4 - if it is, make the second-to-last byte '0' and go to end
		; 5 - if not, start the division sequence
		; 6 - divide EDX:EAX by 10
		; 7 - add 48 to the remainder value to convert to ASCII
		; 8 - store ASCII-shifted remainder value in output buffer and subtract one from counter
		; 9 - clear EDX in case we are going again
		; A - check if the quotient is zero, if it is, go to 6 and repeat
		;
		; Example:
		;
		; lets assume the input is 1,024
		; divide cycle one: eax = 102, edx = 4
		; add 0x30 to 4, edx = 0x34 ('4')
		; write dl to the output buffer, position rdi + 94
		; decrement ecx (ecx = 93) and ebx (ebx = 2)
		; eax is not zero so go again
		;
		; divide cycle two: eax = 10, edx = 2
		; edx + 0x30 = 0x32 ('2')
		; write dl rdi + 93
		; dec ecx (ecx = 92) and ebx (ebx = 1)
		; eax != 0
		;
		; divide cycle three: eax = 1, edx = 0
		; edx + 0x30 = 0x30 ('0')
		; write dl rdi + 92
		; dec ecx (ecx = 91) and ebx (ebx = 0)
		; since ebx = 0, write 0x2C (',') rdi + 91
		; dec ecx (ex = 90) and ebx = 3
		; eax != 0
		;
		; divide cycle four: eax = 0, edx = 1
		; edx + 0x30 = 0x31 ('1')
		; write dl rdi + 90
		; dec ecx (ecx = 89) and ebx (ebx = 2)
		; eax = 0, so exit loop
		;
		; r9b = 95; r9b = r9b - cl (95 - 89 = 6)
		;
		; now we move all of those bytes written to the
		; beginning of the output buffer
		; 
		; r9b = 6, r8b = 0, cl = 90
		; take a byte from the output buffer and write
		; to the beginning of the buffer
		;
		; take a byte from the output buffer at byte 90 ('1')
		; move it to byte 0
		; cl = 91, r8b = 1
		; r8b != r9b
		;
		; take byte at position 91 (',')
		; move it to byte 1
		; cl = 92, r8b = 2
		; r8b != r9b
		; 
		; take byte at position 92 ('0')
		; move it to byte 2
		; cl = 93, r8b = 3
		; r8b != r9b
		;
		; take byte at position 93 ('2')
		; move it to byte 3
		; cl = 94, r8b = 4
		; r8b != r9b
		;
		; take byte at position 94 ('4')
		; move it to byte 4
		; cl = 95, r8b = 5
		; r8b != r9b
		; 
		; take byte at position 95 (0x20)
		; move it to byte 5
		; cl = 96, r8b = 6
		; r8b = r9b
		; exit routine, r9b = r8b = bytes written

		lea	rdi, [rel outbuf]
		mov	ebx, 3
		mov	ecx, 95				; count down from end of buffer
		xor	edx, edx			; clear rdx for division
		xor	r8, r8				; clear r8 for division
		mov	r8b, 10				; set r8 for base 10 division
		test	rax, rax			; check for the unique case of zero bytes
		je	.DWtoText_zero			; if zero bytes, jump to zero handler
.DWtoText_loop:	div	r8d				; divide EDX:EAX by R8D, EAX = quotient, EDX = remainder
		add	dl, 0x30			; DL will be valued 0-9, adding 48 converts it to ASCII
		mov	byte [rdi + rcx], dl		; store the byte in the output string
		dec	ecx				; reduce offset counter by one
		dec	ebx				; reduce comma counter by one
		jne	.DWtoText_nocm			; if comma counter is not zero, skip ahead
		test	eax, eax			; are there more digits to be written?
		je	.DWtoText_move			; if not, jump to the end now
		mov	byte [rdi + rcx], 0x2C		; write a comma in the output buffer
		mov	ebx, 3				; reset comma counter
		dec	ecx				; subtract offset counter again
.DWtoText_nocm	xor	edx, edx			; clear EDX
		test	eax, eax			; is the quotient zero?
		jne	.DWtoText_loop			; if it isn't, go back and do it again
		jmp	.DWtoText_move			; once the last digit is done, go to the end
.DWtoText_zero:	mov	byte [rdi + rcx], 0x30		; put a single character in the string, '0'
		dec	ecx
.DWtoText_move: mov	r9b, 95				; get the difference between 95 and the
		sub	r9b, cl				; number of bytes written
		mov	r8b, 0				; use r8b as a counter to write bytes
		inc	cl				; point to the last byte written
.DWtoText_lp2:	mov	al, byte [rdi + rcx]		; take a byte written and rewrite it to
		mov	byte [rdi + r8], al		; the beginning of the buffer
		inc	cl
		inc	r8b				; count up one
		cmp	r8b, r9b			; if the bytes haven't all been writte, go back and
		jne	.DWtoText_lp2			; do it again
		ret
