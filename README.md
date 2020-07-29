## tcpoverudp2: Forward TCP connections using UDP over two network interfaces in parallel (without root)

Does your link suffer from a high packet loss? Do you have a account in public Internet with perl scripting support? This tool can provide you a reliable fast TCP (web proxy + SSH) connectivity while constantly retrying transmissions on link of any quality.

The algorithm sends packets over two network interfaces concurrently in order to ensure that connection works as reliably as possible regardless of intermittent packet loss in either of them (assuming that the packet loss on either of the interfaces usually happen at unrelated moments).

### Usage:

Local script:

	./tcpoverudp2  --timeout=0.05 
                     --tcp-listen-port=8128 8122 \
                     --udp-server-addr=your.public.server.com --udp-server-port=8120 \
                     --udp-send-local-addr1=192.168.1.20 --udp-send-local-addr2=192.168.2.15

Remote script:

	./tcpoverudp2 --udp-listen-port=8120 \
                    --tcp-forward-addr=public.web.proxy --tcp-forward-port=3128 \
                    --tcp-forward-addr=127.0.0.1 --tcp-forward-port=22


### Additional info:

Developed by extending the tcpoverudp.pl "Forward TCP connections over UDP without root" by Jan Kratochvil

**Summary:**	    Forward TCP connections using UDP over two network interfaces in parallel (without root)
<br>**License:**	GNU General Public License
<br>**State:**	    Ready to use. Maintained.
<br>**Source:**	    https://github.com/levitation/tcpoverudp2
<br>**See also:**   Tcpoverudp     https://www.jankratochvil.net/project/tcpoverudp/
<br>**See also:**   Duat	       http://code.google.com/p/duat/
<br>**Language:**	Perl
 

