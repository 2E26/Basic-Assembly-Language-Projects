# Basic-Assembly-Language-Projects
Exercises and basic tools in Linux x86-64 Assembly, compiled in NASM and run in Ubuntu

1 - cmd_parse.asm
An exercise in reading input text, parsing commands, and reacting to user input
Contains routines that will be useful in command line and terminal programs

2 - bintohex.asm
An exercise in file I/O. Reads a file and translates the data (as raw binary) into
the Intel Hex format. Record lengths are 32 bytes. A tool to be used in handling
programming data for later experiments with PIC, 6502, or other external computing
hardware. Will be of limited use until I increase my ASM skills and write improvements.

3 - hextobin.asm
Another exercise in file I/O. Strips the binary code from an Intex Hex file and spits
out raw binary. A useful tool for when I need such a thing.

4 - serial_01.asm
A link in my tool chain for the 6502 computer. I coded a major program in PIC16 assembly
to place programs in ROM (currently just an AT28C256 EEPROM) so the 6502 can run them.
This program pings the PIC16 with a single command, allowing me to confirm I am
sending and receiving data from the PIC. The next steps will be validating a Hex file
to ensure its validity, and then sending the right commands to the PIC so I can 
automatically move a large amount of data very quickly. Hand-typing in hundreds of bytes
of instructions was NOT fun.

5 - serial_02.asm
(coming soon) a program to run a validation program on a Hex file. This will be another
part of the eventual PIC programmer-handler which loads 6502 programs into the ROM
automatically.
