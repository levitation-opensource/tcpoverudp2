@echo off


title TCP over UDP server



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

C:\Perl64\bin\perl.exe -w tcpoverudp2.pl --udp-listen-port=8120 ^
--tcp-forward-addr=public.web.proxy --tcp-forward-port=3128 ^
--tcp-forward-addr=127.0.0.1 --tcp-forward-port=22 > log.txt 2>&1


REM ping -n 2 127.0.0.1
sleep 1


goto loop

