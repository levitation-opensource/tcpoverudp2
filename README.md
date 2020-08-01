## tcpoverudp2 - TCP over dual UDP: Forward TCP connections using UDP over two network interfaces in parallel

The use case for this software is when you can use two network connections (for example, mobile or wifi), but both of them are unstable and have packet loss issues, and you still want to have a stable and fast internet.

Do both of your available network links suffer from a high packet loss? Do you have a server account in public internet with perl scripting support? Then this tool can provide you a reliable fast TCP (for example, for web proxy + SSH) connectivity - by constantly duplicating all the packets over two interfaces and retrying slow transmissions on links of any quality.

The algorithm sends clones of all packets over two network interfaces concurrently in order to ensure that the forwarded connection works as reliably as possible regardless of intermittent packet loss in either of the interfaces - assuming that the packet loss on either of the interfaces usually happens at unrelated moments.

### Usage:

Client script for Linux (Windows client example can be found in client.bat):

	./tcpoverudp2 --timeout=0.05 \
                     --tcp-listen-port=8128 8122 \
                     --udp-server-addr=your.public.server.com --udp-server-port=8120 \
                     --udp-send-local-addr1=192.168.1.20 --udp-send-local-addr2=192.168.2.15

Server script (Windows client example can be found in server.bat):

	./tcpoverudp2 --udp-listen-port=8120 \
                    --tcp-forward-addr=public.web.proxy --tcp-forward-port=3128 \
                    --tcp-forward-addr=127.0.0.1 --tcp-forward-port=22

Firewall configuration at server side (tcpoverudp2 needs to use <ins>two consecutive</ins> UDP port numbers):

    Open / forward the following __two__ UDP ports:
	1. udp-listen-port
	2. udp-listen-port + 1


### Additional info:

Developed by extending the tcpoverudp.pl *"Forward TCP connections over UDP without root" by Jan Kratochvil* by adding packet duplication over two network interfaces.

**Summary:**        Forward TCP connections using UDP over two network interfaces in parallel (without root).
<br>**License:**    GNU General Public License ver 2
<br>**State:**      Ready to use. Maintained and in active use.
<br>**Source:**     https://github.com/levitation/tcpoverudp2
<br>**See also:**   Tcpoverudp     https://www.jankratochvil.net/project/tcpoverudp/
<br>**See also:**   Duat	       http://code.google.com/p/duat/
<br>**Language:**   Perl


[![Analytics](https://ga-beacon.appspot.com/UA-351728-28/tcpoverudp2/README.md?pixel)](https://github.com/igrigorik/ga-beacon)
