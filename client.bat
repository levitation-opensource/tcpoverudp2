@echo off


title TCP over UDP client



REM change active dir to current location
%~d0
cd /d "%~dp0"



REM if not defined iammaximized (
REM     set iammaximized=1
REM     start "" /max /wait "%~0"
REM     exit
REM )



REM change screen dimensions
mode con: cols=200 lines=9999



:loop


REM depending on the Perl installation you can use either
REM - C:\Strawberry\perl\bin\perl.exe
REM - C:\Perl64\bin\perl.exe

REM no indendation is allowed in batch files after line break using caret

C:\Perl64\bin\perl.exe -w tcpoverudp2.pl --timeout=0.05 ^
--tcp-listen-port=8128 8122 ^
--udp-server-addr=your.public.server.com --udp-server-port=8120 ^
--udp-send-local-addr1=192.168.1.20 --udp-send-local-addr2=192.168.2.15 > log.txt 2>&1


REM ping -n 2 127.0.0.1
sleep 1


goto loop

