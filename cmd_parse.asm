; cmd_parse.asm - Linux x86-64 bit assembly code
; accept an input from the terminal, format and parse it
; and output the appropriate response

; Flow chart

; 1) print a prompt for input (currently '>')
;
; 2) input up to 64 bytes from the keyboard buffer and store in memory
;
; 3) scan the memory array. Convert all non-alphanumeric characters to null (0x00),
;    convert all lower-case letters to upper-case, and note the position of the
;    first letter/number in every word, store in memory, and count the number
;    of arguments in the string. Returns RAX = 1 for a successful read, else 0.
;
; 4) compare the first argument in the string to a list of known command words and
;    direct the program to a handler for each one.
;    If the handler finds a valid command, it returns 1 in RAX to print the message
;    If not, it returns a zero and the output is "?". Return to beginning.
;    If the command is "QUIT", it returns 2 to RAX, prints a message and exits.
;
; 5) valid commands:
;    QUIT - exits the program
;    HELP - displays a list of commands. If a command is listed as an argument,
;           prints the purpose of that command
;    ADD - adds all numbers entered as arguments. Can discern hexadecimal and
;          binary inputs through use of "0x" and "0b" prefixes. Maximum result
;          is four bytes (4,294,967,295). Returns error if overflow exists.
;    SUB - loads the first number argument into a tally counter and subtracts
;          all following arguments from it. Returns error if result is less than
;          zero. No negative support at this time
;    HEX - translates all arguments into hexadecimal format
;    DEC - translates all arguments into decimal format
;    BIN - translates all arguments into binary format

global _start

section .data
  prompt:	db	'>'
  plen:		equ	$ - prompt
  fail:		db	'?', 10
  flen:		equ	$ - fail
  
  cmd_quit:	db	"QUIT"		; Commands that the user can enter
  cmd_help:	db	"HELP"		; Commands are three or four chars
  cmd_add:	db	"ADD", 0x00	; For three-char commands, the fourth
  cmd_sub:	db	"SUB", 0x00	; char is 0x00
  cmd_hex:	db	"HEX", 0x00
  cmd_dec:	db	"DEC", 0x00
  cmd_bin:	db	"BIN", 0x00
  
  err_addovflw	db	"Error: addition over maximum value.", 0x0A
  err_aoflen	equ	$ - err_addovflw
  err_subunflw	db	"Error: subtraction less than zero.", 0x0A
  err_suflen	equ	$ - err_subunflw
  
  txt_help:	db	"Commands: QUIT HELP ADD SUB HEX DEC BIN", 0x0A
  helplen:	equ	$ - txt_help
  txt_helpquit:	db	"QUIT: exits the program and returns to the terminal.", 0x0A
  helpquitlen:	equ	$ - txt_helpquit
  txt_helpadd:	db	"ADD: adds up to 15 positive integers and displays the result.", 0x0A
  helpaddlen:	equ	$ - txt_helpadd
  txt_helpsub:	db	"SUB: subtracts a string of numbers from the first entered.", 0x0A
  helpsublen:	equ	$ - txt_helpsub
  txt_helphex:	db	"HEX: gives hexadecimal value of binary/decimal numbers.", 0x0A
  helphexlen:	equ	$ - txt_helphex
  txt_helpdec:	db	"DEC: gives decimal values of binary/hexadecimal numbers.", 0x0A
  helpdeclen	equ	$ - txt_helpdec
  txt_helpbin:	db	"BIN: gives binary values of hexadecimal/decimal numbers.", 0x0A
  helpbinlen	equ	$ - txt_helpbin

section .bss
  inbuf:	resb	64		; Memory to store command instructions (up to 64B)
  inlen:	resb	1		; Memory to store number of bytes in input buffer
  outbuf:	resb	64		; Memory to store output test (up to 64B)
  outlen:	resb	1		; Memory to store length of output buffer
  argcount:	resb	1		; Memory to store number of commands and arguments (maximum 16 arguments, including command)
  argptrs:	resb	16		; Memory to store argument pointers (the space in inbuf where each argument sits)

section .text
_start:

.beginloop:
  lea	rsi, [rel prompt]		; put address of prompt in rsi
  mov	edx, plen			; length of message to display
  call	Print
  
  ; read(0, inbuf, 64)
  ; not carried out to a subroutine because this happens one time in the program
  mov	eax, 0				; sys_read
  xor	edi, edi			; stdin
  lea	rsi, [rel inbuf]		; put address of input buffer in rsi
  mov	edx, 64				; read up to 64 bytes
  syscall
  test	rax, rax			; did function return EOF or error?
  jle	.exit				; exit if it did
  
  ; parse the command and identify argument locations
  lea rsi, [rel inbuf]			; point rsi to input buffer[0]
  call Parse_command

  test	ax, ax				; if subroutine returned zero, print '?'
  jz	.invalidout
  
  ; scan the command and decide what to do about it
  ; rsi should still be pointing at [rel inbuf]
  call Exec_command
  
  test	ax, ax				; if subroutine returned zero, print '?'
  jz	.invalidout
  push	rax				; temporarily save rax

.printoutput:				; print whatever is in the outbuf
  lea	rsi, [rel outbuf]		; as programmed by the exec function
  movzx	edx, byte [rel outlen]
  call	Print
  pop	rax				; restore rax after calling print
  cmp	rax, 2				; if rax was 2 after Exec_command, exit the program
  je	.exit
  call	ClearData			; wipe all memory for next go-around
  jmp	.beginloop

.exit:
  mov	eax, 60				; set up the function to exit
  xor	edi, edi			; and go back to the command line
  syscall

.invalidout:
  mov	ax, word [rel fail]		; load the fail message to ax ('?', 10)
  mov	word [rel outbuf], ax		; copy it to the output buffer
  mov	byte [rel outlen], flen
  jmp	.printoutput

; --------------------------------------------------------------------------
; Print
; Inputs: RSI - beginning of string buffer, EDX - number of bytes to output (0-255)
; Returns: output of string to the screen. (last character of stream must be 0x0A, or \n)
; Clobbers: EAX, EDI

Print:
  mov	eax, 1
  mov	edi, 1
  syscall
  ret

; --------------------------------------------------------------------------
; Parse_Command
; Inputs: RSI - beginning of buffer with ASCII command and arguments
; Returns: RAX = 0 if invalid command, = 1 if valid. Changes space characters and 0x0A character to null (0x00).
;          Stores number of arguments (starting with command) in memory, and stores byte location of each argument
;	   relative to inbuf[0]
; Clobbers: RAX, RCX, RDI

Parse_command:
  xor	rcx, rcx				; Clear counter
  xor	rax, rax				; Clear byte grabber
  mov	[rel argcount], al			; Clear number of args
  mov	qword [rel argptrs], rax		; Clear first half of argptrs (8 bytes)
  mov	qword [rel argptrs + 8], rax		; Clear second half of argptrs (8 bytes)
  
.parseloop:
  cmp	cl, 0x40				; Is the counter over the max input?
  jae	.quitparse				; If so, don't read anymore
  mov	al, [rsi + rcx]				; Grab a byte from the input buffer at inbuf(0 + counter)
  cmp	al, 0x0A				; Check for newline character
  je	.quitparse				; We're done here
  cmp	al, 0x0D				; Check for carriage return
  je	.quitparse				; Also done
  cmp	al, 0x20				; Is the byte equal to ' '?
  je	.spacechar				; If so, handle as an argument (assumes first character is the first letter of a command)
  cmp	al, 0x30				; Is the byte lower than '0'?
  jb	.invalidchar				; If so, then process invalid character
  cmp	al, 0x39				; Is the byte '9' or lower?
  jbe	.recordargument				; If so, record it as an argument
  cmp	al, 0x41				; Is the character lower than 'A'?
  jb	.invalidchar				; If so, process invalid character
  cmp	al, 0x5A				; Is the byte higher than 'Z'?
  ja	.lowercaseparse				; If so, check for lower case letter
  
  jmp .recordargument				; If it passes all the checks, then see if it is the beginning of an argument.
  
.lowercaseparse:
  cmp	al, 0x61				; Is the byte lower than 'a'?
  jb	.invalidchar				; Invalid character, quit loop
  cmp	al, 0x7A				; Is the byte higher than 'z'?
  ja	.invalidchar				; Same thing
  
  ; The byte is a lower case character. Convert it to upper case and move on.
  sub	al, 0x20				; Subtract 32 from value to convert it
  mov	byte [rsi + rcx], al			; Write over the character with the capitalized one

  jmp   .recordargument				; Record it as an argument for the next phase

.spacechar:
  ; Spaces become null characters, then pass to the next character without any further checks.
  mov	byte [rsi + rcx], 0x00			; Make it a zero
  inc	rcx					; Move to the next character
  jmp	.parseloop				; Go back and do it again
  
.recordargument:
  ;Check if the first character in a statement (e.g, the "Q" in "QUIT").
  cmp	rcx, 0					; Is this the first character?
  je	.argumentfound				; If it is, record it as an argument
  cmp	byte [rsi + rcx - 1], 0x00		; Is the previous character a null?
  je	.argumentfound				; If it is, record it as an argument
  
  ; If neither of the above are true, move on to the next character
  inc	rcx					; Advance counter to next character
  jmp	.parseloop				; Perform process on next character
  
.argumentfound:
  ;Since it does qualify as an argument, designate the location as an argument first character, and increment the number of detected args
  mov	al, [rel argcount]			; Get the current number of arguments
  cmp	al, 0x10				; Is it 16 or higher?
  jae	.argoverflow				; If so, stop accepting new arguments
  
  lea	rdi, [rel argptrs]
  mov	byte [rdi + rax], cl			; Store offset (0..63)
  
  inc	al					; Add one to the number of arguments
  mov	[rel argcount], al			; Store it back in memory
  
  inc	rcx					; Advance the counter
  jmp	.parseloop  				; Next cycle

.invalidchar:
  ; For now, just turn it to a null character and ignore it. Maybe do something else with it later.
  mov	byte [rsi + rcx], 0x00			; Kill it with fire!!
  
  inc	rcx
  jmp	.parseloop

.argoverflow:
  ; If, somehow, we have more than 16 arguments in a 64 byte string, cut it off at the 16th and ignore the rest
  mov	byte [rsi + rcx], 0x0A			; Make current character null
  jmp	.parseloop				; Go back to loop, it'll catch it as the end.

.quitparse:
  cmp	byte [rel argcount], 0			; Did we get a garbage input?
  jnz	.validparse				; If not, rax = 1
  mov	rax, 0
  jmp	.endparse				; If so, rax = 0
  
.validparse:
  ; Input wasn't null, maybe later parse to ensure at least one character was valid
  mov	[rel inlen], cl
  mov	rax, 1

.endparse:
  mov	byte [rsi + rcx], 0x00			; Convert line end character to null
  ret						; Back to regularly scheduled program

; --------------------------------------------------------------------------
; Exec_Command
; Inputs: RSI - beginning of buffer with ASCII command and arguments; argcount - number of args recognized in input string; argptrs - array 
;          of locations where commands/args exist in string
; Returns: Stores output string in outbuf, adds 0x0A to end string. RAX = 0 for invalid input, 1 for valid command, and 2 for terminate  
;          program
; Clobbers: RAX, RCX, RSI, RDI, R8, R9

Exec_command:
  mov	al, [rel argcount]			; Check if the arg count was zero
  test	al, al
  jz	.execbadinput				; If so, go to the end
  
  movzx	ecx, byte [rel argptrs]			; Check the location of the first argument pointer. This should be reading the value in the byte, not the address of the byte
  cmp	ecx, 0x40				; Is ecx >= 64?
  jae	.execbadinput				; If so, go to the end
  
  lea	rsi, [rel inbuf]			; Ensure rsi points at the input string in case it was moved  
  lea	rdi, [rsi + rcx]			; Use rcx to point to the location where the first argument sits
  mov	eax, dword [rdi]			; draw four bytes from the input buffer, starting at argptrs(0)
  
  cmp	eax, dword [rel cmd_quit]		; Is our command quit?
  jne	.notquit				; If so, go to the quit command
  cmp	byte [rdi + 4], 0			; Check if the next character after "QUIT" is a null
  je 	.execquit				; If so, valid command. Execute "QUIT"
.notquit:
  cmp	eax, dword [rel cmd_help]		; Is the command help?
  jne	.nothelp
  cmp	byte [rdi + 4], 0
  je	.exechelp
.nothelp:
  cmp	eax, dword [rel cmd_add]		; Is the command add?
  jne	.notadd
  jmp	.execadd
.notadd:
  cmp	eax, dword [rel cmd_sub]		; Is the command subtract?
  jne	.notsub
  jmp	.execsub
.notsub:
  cmp	eax, dword [rel cmd_hex]		; Is the command hexadecimal?
  jne	.nothex
  jmp	.exechex
.nothex:
  cmp	eax, dword [rel cmd_dec]		; Is the command decimal?
  jne	.notdec
  jmp	.execdec
.notdec:
  cmp	eax, dword [rel cmd_bin]		; Is the command binary?
  jne	.notbin
  jmp	.execbin
.notbin:

.execbadinput:
  xor	rax, rax				; Clear rax to indicate failed input

.endexec:
  ret

.execquit:
  mov	dword [rel outbuf], 0x0A2E6B4F		; Store the string "Ok.\n" in the output buffer
  mov	byte [rel outlen], 4			; Set the length of the string to 4
  mov	eax, 2					; Mark the operation with the unique operator for exiting the program
  ret
  
.exechelp:
  cmp	byte [rel argcount], 1			; Check if we have one or more arguments
  je	.exechelp_no_argument			; If only one, display the list of commands
  mov	r8d, 1					; If more than one, select the second one
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  mov	eax, dword [rdi]			; grab four bytes from the second argument
  
  cmp	eax, [rel cmd_quit]			; check if argument 2 is "QUIT"
  jne	.help_notquit				; if not, check for the next argument
  cmp	byte [rdi + 4], 0			; check if the byte after "QUIT" is a null character
  jne	.help_notquit				; if not, don't treat this as "QUIT"
  cld
  lea	rsi, [rel txt_helpquit]			; load outbuf with the help message for QUIT
  lea	rdi, [rel outbuf]
  mov	ecx, helpquitlen
  rep	movsb
  mov	byte [rel outlen], helpquitlen
  mov	eax, 1
  ret
  
.help_notquit:
  cmp	eax, [rel cmd_add]			; check if argument 2 is "ADD"
  jne	.help_notadd
  cld
  lea	rsi, [rel txt_helpadd]			; load outbuf with the help message for ADD
  lea	rdi, [rel outbuf]
  mov	ecx, helpaddlen
  rep	movsb
  mov	byte [rel outlen], helpaddlen
  mov	eax, 1
  ret
  
.help_notadd:
  cmp	eax, [rel cmd_sub]			; check if argument 2 is "SUB"
  jne	.help_notsub
  cld
  lea	rsi, [rel txt_helpsub]			; load outbuf with the help message for SUB
  lea	rdi, [rel outbuf]
  mov	ecx, helpsublen
  rep	movsb
  mov	byte [rel outlen], helpsublen
  mov	eax, 1
  ret

.help_notsub:
  cmp	eax, [rel cmd_hex]			; check if argument 2 is "HEX"
  jne	.help_nothex
  cld
  lea	rsi, [rel txt_helphex]			; load outbuf with the help message for HEX
  lea	rdi, [rel outbuf]
  mov	ecx, helphexlen
  rep	movsb
  mov	byte [rel outlen], helphexlen
  mov	eax, 1
  ret
  
.help_nothex:
  cmp	eax, [rel cmd_dec]			; check if argument 2 is "DEC"
  jne	.help_notdec
  cld
  lea	rsi, [rel txt_helpdec]			; load outbuf with the help message for DEC
  lea	rdi, [rel outbuf]
  mov	ecx, helpdeclen
  rep	movsb
  mov	byte [rel outlen], helpdeclen
  mov	eax, 1
  ret  
  
.help_notdec:
  cmp	eax, [rel cmd_bin]			; check if argument 2 is "BIN"
  jne	.execbadinput
  cld
  lea	rsi, [rel txt_helpbin]			; load outbuf with the help message for BIN
  lea	rdi, [rel outbuf]
  mov	ecx, helpbinlen
  rep	movsb
  mov	byte [rel outlen], helpbinlen
  mov	eax, 1
  ret

.exechelp_no_argument:
  cld						; Clear direction flag
  lea	rsi, [rel txt_help]			; Source register (rsi) equals address of variable where text data is stored
  lea	rdi, [rel outbuf]			; Destination register (rdi) equals address of output buffer
  mov	ecx, helplen				; Counter register (ecx) equals number of bytes to transfer from source to destination
  rep	movsb					; Until counter is zero, move a byte from source to destination one byte at a time
  mov	byte [rel outlen], helplen		; Make the output length equal the length of the help string  
  mov	eax, 1					; Mark the operation with the indicator for a successful command
  ret
  
.execadd:
  cmp	byte [rel argcount], 3			; Check if there are less than three args ("ADD" needs at least three)
  jb	.execbadinput				; Reject the function if it is
  
  mov	r8d, 1					; i = 1 (an index to point to the second argument)
  xor	r9d, r9d				; Clear r9d (sum)

.execaddloop:
  cmp	r8b, byte [rel argcount]		; Is i >= argument count?
  jae	.execadddone				; If so, we are done
  cmp	r8d, 16					; Is i >= 16? Remember that valid arguments exist from 0-15
  ja	.execadddone				; If so, we are done
  
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  call	Txt_to_DW
  jc	.execbadinput
  
  add	r9d, eax				; Add eax to sum
  jc	.execaddoverflow			; Check if addition overflows a 4-byte word
  inc	r8d
  jmp	.execaddloop
    
.execaddoverflow:
  lea	rsi, [rel err_addovflw] 		; Point rsi to the error message string
  lea	rdi, [rel outbuf]			; Point rdi to the output buffer string
  mov	ecx, err_aoflen				; Set ecx to the length of the error message
  cld						; Direction flag = 0 (increment rsi,rdi after every copy)
  rep 	movsb					; Move a byte from [rsi] to [rdi] until ecx = 0
  mov	ecx, err_aoflen				; Grab the length again
  mov	byte [rel outlen], cl			; Lowest byte of C register into the output length
  mov	eax, 1
  ret

.execadddone:
  mov	ecx, 0x0A				; Set divisor to 10
  call	DW_to_Text				; Translate r9d into ascii text
  jmp	.execdone

.execsub:
  cmp	byte [rel argcount], 3			; Check if there are less than three args ("SUB" needs at least three)
  jb	.execbadinput				; Reject the function if it is
  
  mov	r8d, 1					; i = 1 (an index to point to the second argument)
  xor	r9d, r9d				; Clear r9d (sum)
  
.execsubloop:
  cmp	r8b, byte [rel argcount]		; Is i >= argument count?
  jae	.execsubdone				; If so, we are done
  cmp	r8d, 16					; Is i >= 16? Remember that valid arguments exist from 0-15
  ja	.execsubdone				; If so, we are done
  
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  call	Txt_to_DW
  jc	.execbadinput
  
  cmp	r8d, 1					; Is this the first number argument?
  jne	.execsubnotfirst			; If not, subtract it from r9d
  mov	r9d, eax				; If so, r9d becomes what is stored in eax
  jmp	.execsubendofloop
.execsubnotfirst:
  sub	r9d, eax				; Subtract eax from r9d
.execsubendofloop:
  jc	.execsuboverflow			; Check if subtraction goes below zero
  inc	r8d
  jmp	.execsubloop

.execsuboverflow:
  lea	rsi, [rel err_subunflw] 		; Point rsi to the error message string
  lea	rdi, [rel outbuf]			; Point rdi to the output buffer string
  mov	ecx, err_suflen				; Set ecx to the length of the error message
  cld						; Direction flag = 0 (increment rsi,rdi after every copy)
  rep 	movsb					; Move a byte from [rsi] to [rdi] until ecx = 0
  mov	ecx, err_suflen				; Grab the length again
  mov	byte [rel outlen], cl			; Lowest byte of C register into the output length
  mov	eax, 1
  ret
  
.execsubdone:
  mov	ecx, 0x0A				; Set divisor to 10
  call	DW_to_Text				; Translate r9d into ascii text
  jmp	.execdone
    
.exechex:
  cmp	byte [rel argcount], 2			; Check if there are less than two args ("HEX" needs at least two)
  jb	.execbadinput				; Reject the function if it is
  mov	r8d, 1					; i = 1 (an index to point to the second argument)
  xor	r9d, r9d				; clear the number to store the conversion value

.exechexloop:
  cmp	r8b, byte [rel argcount]		; Is i >= argument count?
  jae	.execdone				; If so, we are done
  cmp	r8d, 16					; Is i >= 16? Remember that valid arguments exist from 0-15
  ja	.execdone				; If so, we are done
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rsi, [rel inbuf]
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  call	Txt_to_DW				; Interpret the input as a number
  jc	.execbadinput				; If that failed, go to bad input
  mov	r9d, eax				; Shift the added number over to r9d
  mov	ecx, 0x10				; Set divisor to 16
  inc	r8d					; Increase the argument counter
  call	DW_to_Text				; Translate the value in r9d to a hexadecimal string
  cmp	r8b, byte [rel argcount]		; Check if we are on the last argument
  je	.exechexloop				; If we are, don't print here. Printing will happen when we exit the loop.
  lea	rsi, [rel outbuf]
  movzx	edx, byte [rel outlen]
  call	Print
  jmp	.exechexloop	

.execdec:
  cmp	byte [rel argcount], 2			; Check if there are less than two args ("DEC" needs at least two)
  jb	.execbadinput				; Reject the function if it is
  mov	r8d, 1					; i = 1 (an index to point to the second argument)
  xor	r9d, r9d				; clear the number to store the conversion value

.execdecloop:
  cmp	r8b, byte [rel argcount]		; Is i >= argument count?
  jae	.execdone				; If so, we are done
  cmp	r8d, 16					; Is i >= 16? Remember that valid arguments exist from 0-15
  ja	.execdone				; If so, we are done
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rsi, [rel inbuf]
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  call	Txt_to_DW				; Interpret the input as a number
  jc	.execbadinput				; If that failed, go to bad input
  mov	r9d, eax				; Shift the added number over to r9d
  mov	ecx, 0x0A				; Set divisor to 10
  inc	r8d					; Increase the argument counter
  call	DW_to_Text				; Translate the value in r9d to a hexadecimal string
  cmp	r8b, byte [rel argcount]		; Check if we are on the last argument
  je	.execdecloop
  lea	rsi, [rel outbuf]
  movzx	edx, byte [rel outlen]
  call	Print
  jmp	.execdecloop	
  
.execbin:
  cmp	byte [rel argcount], 2			; Check if there are less than two args ("BIN" needs at least two)
  jb	.execbadinput				; Reject the function if it is
  mov	r8d, 1					; i = 1 (an index to point to the second argument)
  xor	r9d, r9d				; clear the number to store the conversion value

.execbinloop:
  cmp	r8b, byte [rel argcount]		; Is i >= argument count?
  jae	.execdone				; If so, we are done
  cmp	r8d, 16					; Is i >= 16? Remember that valid arguments exist from 0-15
  ja	.execdone				; If so, we are done
  lea	rdi, [rel argptrs]			; load the address of argptrs[0] into rdi
  movzx	edx, byte [rdi + r8]			; load the value stored in argptrs[r8] into edx
  lea	rsi, [rel inbuf]
  lea	rdi, [rsi + rdx]			; load the address of the byte in inbuf[ argptrs[r8] ]
  call	Txt_to_DW				; Interpret the input as a number
  jc	.execbadinput				; If that failed, go to bad input
  mov	r9d, eax				; Shift the added number over to r9d
  mov	ecx, 0x02				; Set divisor to 2
  inc	r8d					; Increase the argument counter
  call	DW_to_Text				; Translate the value in r9d to a hexadecimal string
  cmp	r8b, byte [rel argcount]		; Check if we are on the last argument
  je	.execbinloop
  lea	rsi, [rel outbuf]
  movzx	edx, byte [rel outlen]
  call	Print
  jmp	.execbinloop	

.execdone:
  mov	eax, 1					; If you've made it this far, the handler has succeeded.
  ret
  
; --------------------------------------------------------------------------
; Txt_to_DW
; Converts an ascii number from 0-4,294,967,295 to a DWORD containing an unsigned value.
; Inputs: rsi points to input string, argptrs to locate arguments (remember that argptrs[0] is the command)
;         rdi points to the beginning of the argument
; Outputs: eax equals the numerical value of one argument // cf is set if there is an error
; Clobbers: EAX, EBX, ECX, EDX
Txt_to_DW:

  xor	eax, eax
  xor	ecx, ecx				; Set a counter to advance the offset one byte at a time, until we reach a 0x00 value
  mov	edx, 10					; Default base = 10

  cmp	word [rdi], 0x5830			; Check if hexadecimal
  je	.Txt_to_DW_Hexadecimal
  cmp	word [rdi], 0x4230			; Check if binary
  je	.Txt_to_DW_Binary
  jmp	.Txt_to_DW_Loop				; If not, go straight to decoding
  
.Txt_to_DW_Hexadecimal:
  mov	edx, 16					; Base = 16
  mov	ecx, 2					; Skip the first two characters
  jmp	.Txt_to_DW_Loop
  
.Txt_to_DW_Binary:
  mov	edx, 2					; Base = 2
  mov	ecx, 2					; Skip the first two characters
  jmp	.Txt_to_DW_Loop
  
.Txt_to_DW_Loop:	

  movzx	ebx, byte [rdi + rcx]			; Grab a byte
  cmp	bl, 0x00				; Check for null character
  je	.Txt_to_DW_Done
  cmp	bl, 0x30				; Check for character below '0'
  jb	.Txt_to_DW_Error
  cmp	bl, 0x46				; Check for character above 'F'
  ja	.Txt_to_DW_Error
  cmp	bl, 0x3A				; Check for character between '0' and '9'
  jb	.Txt_to_DW_BinDecChar
  cmp	bl, 0x40				; Check for character between 'A' and 'F'
  ja	.Txt_to_DW_HexChar
  jmp	.Txt_to_DW_Error

.Txt_to_DW_HexChar:
  sub	ebx, 0x37				; Subtract 55 so A = 10, B = 11, C = 12, etc...
  jmp	.Txt_to_DW_Calculate

.Txt_to_DW_BinDecChar:
  cmp	dl, 0x02				; Check if base = 2
  jne	.Txt_to_DW_DecChar			; If not, go straight to the decimal handler
  cmp	bl, 0x31				; If binary, check if character is above '1' to prevent garbage inputs
  ja	.Txt_to_DW_Error			; Return garbage input (example: 0B0010010102)
  jmp	.Txt_to_DW_BinDecAdjust			; If the character is '0' or '1', proceed
.Txt_to_DW_DecChar:  
  cmp	bl, 0x39				; Check if character is above '9' to prevent garbage inputs			
  ja	.Txt_to_DW_Error
.Txt_to_DW_BinDecAdjust:
  sub	ebx, 0x30				; Subtract 48 so number value equals ascii character
  jmp	.Txt_to_DW_Calculate

.Txt_to_DW_Calculate:
  ; Math here is total = total * base + digit
  ; EAX - total
  ; EBX - digit
  ; EDX - base
  
  imul	eax, edx				; Shift the existing value left by the base by multiplying
  add	eax, ebx				; Add the new value of the current byte
  inc	ecx					; Move the counter up one
  jmp	.Txt_to_DW_Loop

.Txt_to_DW_Error:				; signify the operation failed
  stc
  ret
  
.Txt_to_DW_Done:				; signify the operation succeeded
  clc  
  ret

; --------------------------------------------------------------------------
; DW_to_Text
; Translates a binary unsigned double-word (four bytes) into ASCII text. It loads into the end of the output
; buffer and counts back as the number grows
; Inputs: rdi points at the 64th byte of the output buffer (outbuf + 63), ecx as divisor (2, 10, 16)
; Outputs: a decimal ascii representation of r9d in the output buffer.
; Clobbers: EAX, EBX, ECX, EDX

DW_to_Text:
  lea	rdi, [rel outbuf + 63]			; Establish the base address at the end of Outbuf
  lea	rsi, [rel outbuf]			; Establish the address at the beginning of Outbuf
  mov	eax, r9d				; Move the arithmetic result into eax to work math on it
  xor	ebx, ebx				; Clear ebx to use as a length counter
  mov	byte [rdi], 0x0A			; Make the last character end line
  cmp	r8b, byte [rel argcount]		; Check if we are at the end of the argument string
  je	.DW_to_Text_LastArg			; If so, don't overwrite with a space
  mov	byte [rdi], 0x20			; If not, change ENDL character to SP to add on to output
.DW_to_Text_LastArg:
  dec	rdi					; Move left one character
  inc	ebx					; Bump the character count up by one
  cmp	eax, 0					; Check for zero
  jne	.DW_to_Text_loop			; If not, perform the procedure to translate number into text
  mov	byte [rdi], 0x30			; Write '0' to outbuf + 62
  inc	ebx					; Count one more character in the output string
  dec	rdi					; Move buffer pointer as we would in another operation
  jmp	.DW_to_Text_end				; Go to end of procedure
  
.DW_to_Text_loop:
  xor	edx, edx				; Clear edx
  div	ecx					; Eax = eax / ecx. Edx = eax % ecx
  cmp	dl, 0x09				; Is the remainder higher than 9?
  ja	.DW_to_Text_Hexchar
  add	dl, 0x30				; Add 48 to dl to make it an ascii digit
  jmp	.DW_to_Text_Writechar
.DW_to_Text_Hexchar:
  cmp	ecx, 16					; Are we sure we are writing in hexadecimal?
  jne	.DW_to_Text_end				; If not, go to the end of the routine
  add	dl, 0x37				; Otherwise, add 55 to it to make the value match 'A' - 'F'
.DW_to_Text_Writechar:
  mov	byte [rdi], dl				; Write to the output buffer in the next unwritten spot
  inc	ebx					; Increase the number of characters written
  dec	rdi					; Move back one from the end of outbuf
  cmp	eax, 0					; Are we out of base units to divide out of eax?
  je	.DW_to_Text_end				; If we are, go to the next part of the routine
  cmp	ebx, 61					; Are we out of room to write new characters?
  je	.DW_to_Text_end				; If so, stop the ride and get off
  jmp	.DW_to_Text_loop			; If not, return to beginning and divide again

.DW_to_Text_end:
  ; Check if we are in binary or hex mode. If so, write '0B' or '0X' in front of the result
  cmp	ecx, 2					; Is our divisor 2?
  jne	.DW_to_Text_end_notbinary		; If not, move on
  mov	byte [rdi], 0x42			; If so, add a 'B' to the front of the string
  inc	ebx					; Increase number of characters written
  dec	rdi					; Move back one in the string pointer
  mov	byte [rdi], 0x30			; Write '0' to the front of the string
  inc	ebx					; Increase number of characters written
  dec	rdi					; Move back one in the string pointer
  jmp	.DW_to_Text_end_nothex			; Jump over non-useful code
.DW_to_Text_end_notbinary:
  cmp	ecx, 16
  jne	.DW_to_Text_end_nothex  
  mov	byte [rdi], 0x58			; If so, add a 'X' to the front of the string
  inc	ebx					; Increase number of characters written
  dec	rdi					; Move back one in the string pointer
  mov	byte [rdi], 0x30			; Write '0' to the front of the string
  inc	ebx					; Increase number of charactHs written
  dec	rdi					; Move back one in the string pointer
.DW_to_Text_end_nothex:
  xor	eax, eax				; Clear eax
  xor	ecx, ecx				; Clear ecx
  mov	byte [rel outlen], bl			; Record the number of characters in memory
  mov	cl, bl					; Save bl into cl
  xor	ebx, ebx				; Clear ebx
  inc	rdi					; Move the output buffer pointer to the last character written
  
.DW_to_Text_write_loop:
  mov	al, byte [rdi]				; Save the character at the leftmost byte in the string
  mov	byte [rsi + rbx], al			; Store the character at the beginning of the string
  inc	rdi
  inc	ebx					; Move to the next character
  cmp	bl, cl					; Is bl up to the number of characters?
  jne	.DW_to_Text_write_loop			; If not, go around and do it again
  ret
  
; --------------------------------------------------------------------------
; ClearData
; Zeroizes program memory so it doesn't interfere with future loops
; Inputs: none
; Outputs: none
; Clobbers: rax used to quickly zeroize input buffers

ClearData:
  xor	rax, rax				; Rax = 0
  lea	rdi, [rel inbuf]			; Point rdi to input buffer\
  cld						; Clear direction flag (positive count)
  mov	ecx, 8					; For c = 1 to 64
  rep	stosq					; inbuf[rdi] = rax, rdi++
  
  lea	rdi, [rel outbuf]			; Perform the same operation to clear
  mov	ecx, 8					; the output buffer
  rep	stosq

  lea	rdi, [rel argptrs]			; Perform the same operation to clear
  mov	ecx, 2					; the argument pointer array
  rep	stosq
  
  mov	byte [rel inlen], 0x00			; Clear the input and output lengths
  mov	byte [rel outlen], 0x00			;
  mov	byte [rel argcount], 0x00		; Clear the argument counter
  ret