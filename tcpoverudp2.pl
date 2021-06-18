#! /usr/bin/perl
#
# $Id$
# Copyright (C) 2019-2021 Roland Pihlakas <roland@simplify.ee>
#
# Developed by extending the code by
#
# $Id$
# Copyright (C) 2004-2007 Jan Kratochvil <project-tcpoverudp@jankratochvil.net>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; exactly version 2 of June 1991 is required
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use warnings;
use Getopt::Long 2.35;	# >=2.35 for: {,}
require IO::Socket::INET;
require IO::Select;
use Time::HiRes ('sleep');
use Fcntl;
use Carp qw(cluck confess);
use Socket;
use Time::HiRes qw(time sleep usleep);


# my $READ_SIZE=1492; # 256;	# 96kbit = 47 x 256B
my $READ_SIZE=4000;	# 96kbit = 47 x 256B
# my $READ_SIZE=64;	# 96kbit = 47 x 256B
my $MAX_UNACKED=128;

my $V=1;
$|=1;
for (qw(PIPE)) {
	$SIG{$_}=eval "sub { cluck 'INFO: Got signal SIG$_'; };";
}

my $D;
my $opt_udp_send_local_addr1;
my $opt_udp_send_local_addr2;
my $opt_udp_listen_port;
my $opt_udp_server_addr;
my $opt_udp_server_port;
my @opt_tcp_listen_port;
my @opt_tcp_forward_addr;
my @opt_tcp_forward_port;

# my $opt_timeout=0.1;
my $opt_timeout=0.25; 	# roland
my $aggregation_timeout=0.05; # roland

my $opt_recvloss=0;
die if !GetOptions(
		  "udp-send-local-addr1=s",\$opt_udp_send_local_addr1,
		  "udp-send-local-addr2=s",\$opt_udp_send_local_addr2,
		  "udp-listen-port=s",\$opt_udp_listen_port,
		  "udp-server-addr=s",\$opt_udp_server_addr,
		  "udp-server-port=s",\$opt_udp_server_port,
		  "tcp-listen-port=s{,}",\@opt_tcp_listen_port,
		  "tcp-forward-addr=s{,}",\@opt_tcp_forward_addr,
		  "tcp-forward-port=s{,}",\@opt_tcp_forward_port,
		"t|timeout=s",\$opt_timeout,
		  "recvloss=s",\$opt_recvloss,
		"d|debug+",\$D,
		);

die "udp-server- addr/port inconsistency" if !$opt_udp_server_addr != !$opt_udp_server_port;
die "udp- listen/sever port inconsistency" if !$opt_udp_listen_port == !$opt_udp_server_port;
die "tcp-forward- addr/port inconsistency" if !@opt_tcp_forward_addr != !@opt_tcp_forward_port;
die "tcp- listen/forward port inconsistency" if !@opt_tcp_listen_port == !@opt_tcp_forward_port;
die "udp vs. tcp inconsistency" if !$opt_udp_listen_port == !@opt_tcp_listen_port;

my @sock_tcp;
for my $tcp_listen_port (@opt_tcp_listen_port) {
	my $sock_tcp=IO::Socket::INET->new(
		LocalPort=>$tcp_listen_port,
		Proto=>"tcp",
		Listen=>5,
		ReuseAddr=>1,
	) or die "socket(): $!";
	push @sock_tcp,$sock_tcp;
}

my $sock_udp1;
my $sock_udp2;	# roland

if ($opt_udp_listen_port) {

	$sock_udp1=IO::Socket::INET->new(
		Proto=>"udp",
		LocalPort=>"" . (int($opt_udp_listen_port) + 0),
	) or die "socket(): $!";

	$sock_udp2=IO::Socket::INET->new(
		Proto=>"udp",
		LocalPort=>"" . (int($opt_udp_listen_port) + 1),
	) or die "socket(): $!";
	
} else {

	# print "\n" . (int($opt_udp_server_port) + 0) . "\n";
	# print "\n" . (int($opt_udp_server_port) + 1) . "\n";

	$sock_udp1=IO::Socket::INET->new(
		Proto=>"udp",
		PeerAddr=>$opt_udp_server_addr,
		PeerPort=>"" . (int($opt_udp_server_port) + 0),
		LocalAddr=>$opt_udp_send_local_addr1
	) or die "socket(): $!";
	
	$sock_udp2=IO::Socket::INET->new(
		Proto=>"udp",
		PeerAddr=>$opt_udp_server_addr,
		PeerPort=>"" . (int($opt_udp_server_port) + 1),
		LocalAddr=>$opt_udp_send_local_addr2
	) or die "socket(): $!";
}
	
my $select = new IO::Select();
$select->add($sock_udp1);		
$select->add($sock_udp2);

sub id_new()
{
	our $id;
	
	# $id||=0;
	$id||=int(time()); 	# roland
	
	return $id++;
}

my %stats;
sub stats($)
{
	my($name)=@_;

	$stats{$name}++;
	
	our $last;
	my $now=time();
	$last||=$now;
	
	return if $now<$last+1 && !$D;
	$last=$now;
	
	print join(" ", "", map(("$_=".$stats{$_}), sort keys(%stats))) . ($D ? "\r" : "\r");
}

sub filter_stats($)
{
	my($name)=@_;
	if (length $name == 2) {
		$name = undef();
	}
	
	return $name;
}


my $peer_addr1;
my $peer_addr2;

my $MAGIC=0x97AEBFDD;

sub sendpkt($;$)
{
	my($data,$stats)=@_;

	if (!$peer_addr1 && !$peer_addr2) {
		cluck "Still no peer to send";
		stats("sentearly");
		return;
	}
	$data=pack "Na*",$MAGIC,$data;
	
	my $i;
	my $send1a=1;
	my $send1b=1;
	my $send2a=1;
	my $send2b=1;
	
	if (!$stats) {
		$stats = "";
	}
	
	for ($i = 0; $i < 10; $i++) {
		if ($peer_addr1) {

			if ($send1a==1) {
				$send1a=0;
				if (!send $sock_udp1,$data,0,$peer_addr1) {
					# cluck "Error sending packet: $!";
					stats(filter_stats($stats . "1a") || "senterr1a");
					$send1a=1;
				}
				else {
					stats(filter_stats($stats . "1a") || "senok1a");
				}
			}

			if (1==0 && $send1b==1) {
				$send1b=0;
				if (!send $sock_udp1,$data,0,$peer_addr1) {
					# cluck "Error sending packet: $!";
					stats(filter_stats($stats . "1b") || "senterr1b");
					$send1b=1;
				}
				else {
					stats(filter_stats($stats . "1b") || "senok1b");
				}
			}
		}

		if ($peer_addr2) {
		
			if ($send2a==1) {
				$send2a=0;
				if (!send $sock_udp2,$data,0,$peer_addr2) {
					# cluck "Error sending packet: $!";
					stats(filter_stats($stats . "2a") || "senterr2a");
					$send2a=1;
				} 
				else {
					stats(filter_stats($stats . "2a") || "senok2a");
				}
			}

			if (1==0 && $send2b==1) {
				$send2b=0;
				if (!send $sock_udp2,$data,0,$peer_addr2) {
					# cluck "Error sending packet: $!";
					stats(filter_stats($stats . "2b") || "senterr2b");
					$send2b=1;
				} 
				else {
					stats(filter_stats($stats . "2b") || "senok2b");
				}
			}
		}
	}
	
	# stats($stats||"senok");
}

sub printable($)
{
	local $_=$_[0];
	s/\W/./gs;
	return $_;
}

sub seq_new($)
{
	my($data)=@_;

	return {
		"data"=>$data,
		"timeout"=>time()+$opt_timeout,
	};
}

my %sock;
my %active;

sub sock_new($$$)
{
	my($id,$which,$stream)=@_;

	confess if $sock{$id};
	$active{$id}=$sock{$id}={
		"id"=>$id,
		"stream"=>$stream,
		"which"=>$which,	# for OPEN retransmits
		"sent_to_udp"=>0,
		"sent_queue"=>{
				0=>seq_new(undef()),
			},
		"acked_to_udp"=>0,
		"incoming"=>{
				# 5=>$udp_data,
			},
	};
}

my $TYPE_OPEN=0;	# new_id,which
my $TYPE_SEND=1;	# id,seq,data
my $TYPE_ACK=2;		# id,seq
my $TYPE_CLOSE=3;	# id,seq


$V and print localtime()." START\n";
if ($opt_udp_server_port) {
	my $host=gethostbyname($opt_udp_server_addr) or die "resolving $opt_udp_server_addr: $!";
	my ($opt_udp_server_port1, $opt_udp_server_port2);
	
	$opt_udp_server_port1 = "" . (int($opt_udp_server_port) + 0);
	$opt_udp_server_port2 = "" . (int($opt_udp_server_port) + 1);
	
	$peer_addr1=sockaddr_in($opt_udp_server_port1,$host) or die "assembling $opt_udp_server_addr:$opt_udp_server_port";
	my($back_port1,$back_host1)=sockaddr_in $peer_addr1;
	$back_host1=inet_ntoa $back_host1;
	print "Peer server: $back_host1:$back_port1\n";
	
	$peer_addr2=sockaddr_in($opt_udp_server_port2,$host) or die "assembling $opt_udp_server_addr:$opt_udp_server_port";
	my($back_port2,$back_host2)=sockaddr_in $peer_addr2;
	$back_host2=inet_ntoa $back_host2;
	print "Peer server: $back_host2:$back_port2\n";
}

my $earliest;
my $sockets_were_ready=0;
my $time1=0;
my $time2=0;
my $last_recv=0;

for (;;) {
	my $rfds="";
	for my $sock_tcp (@sock_tcp) {
		vec($rfds,fileno($sock_tcp),1)=1;
	}
	
	vec($rfds,fileno($sock_udp1),1)=1;
	vec($rfds,fileno($sock_udp2),1)=1;
	
	for my $hashref (values(%active)) {
		next if !$hashref->{"stream"};
		next if keys(%{$hashref->{"sent_queue"}})>=$MAX_UNACKED;
		vec($rfds,fileno($hashref->{"stream"}),1)=1;
	}
	###warn "select(2)..." if $D;
	my $periodic_remaining;
	my $now=time();
	$periodic_remaining=($earliest>$now ? $earliest-$now : 0) if $earliest;
	my $got=select($rfds,undef(),undef(),$periodic_remaining);
	###warn "got from select." if $D;
	die "Invalid select(2): ".Dumper($got) if !defined $got || $got<0;

	for my $which (0..$#sock_tcp) {
		my $sock_tcp=$sock_tcp[$which];
		next if !vec($rfds,fileno($sock_tcp),1);
		my $sock_tcp_new;
		accept($sock_tcp_new,$sock_tcp) or confess "Error accepting new TCP socket: $!";
		my $id=id_new();
		print "New id: " . $id . "\n";
		warn "Accepted new TCP (id=$id)" if $D;
		my $old=select($sock_tcp_new);
		$|=1;
		select($old);
		sock_new($id,$which,$sock_tcp_new);
		sendpkt(pack("CNN",$TYPE_OPEN,$id,$which));
		warn "Sent OPEN (id=$id)" if $D;
	}
	
	
	for my $hashref (values(%active)) {
	
		next if !$hashref->{"stream"};
		my $id=$hashref->{"id"};
		next if !vec($rfds,fileno($hashref->{"stream"}),1);
		
		my $buf=undef();
		my $combined_buf=undef();
		my $remaining_read_size = $READ_SIZE;
		
		my $read_time;
		my $read_start_time = time();
		my $remaining_read_time = $aggregation_timeout;
		
		my @tcp_sockets_ready;
		# my $tcp_socket;
		
		my $got = 0;
		
	read_more:
		# fcntl($hashref->{"stream"},F_SETFL,O_NONBLOCK) or die "fnctl(,F_SETFL,O_NONBLOCK)";
		
		my $tcp_socket1 = $hashref->{"stream"};
		my $tcp_select = new IO::Select();
		$tcp_select->add($tcp_socket1);
		
		# @tcp_sockets_ready = $tcp_select->can_read($remaining_read_time);
		my ($tcp_sockets_ready, $udp_sockets_ready) = IO::Select->select($tcp_select, $select, undef, $remaining_read_time);
		
		# if (!defined $tcp_sockets_ready || ! scalar(@tcp_sockets_ready)) {
		if (!defined $tcp_sockets_ready || ! scalar(@$tcp_sockets_ready)) {
			# print "TCP timeout\n";
			# goto send_tcp;
			
			
			if ($combined_buf && length $combined_buf > 0) {
				
				$got = length $combined_buf;
				
				stats("tcpout");

				warn "Got TCP data (id=$id,got=$got)" if $D;
				my $seq=++$hashref->{"sent_to_udp"};
				$hashref->{"sent_queue"}{$seq}=seq_new($combined_buf);
				sendpkt(pack("CNNa*",$TYPE_SEND,$id,$seq,$combined_buf));
				warn "Sent SEND (id=$id,seq=$seq,data=".printable($combined_buf).")" if $D;

				$last_recv = time();
				
			}  	# if (length $combined_buf > 0) {
			
		} else {

        	# foreach my $tcp_socket (@tcp_sockets_ready) {
        	foreach my $tcp_socket (@$tcp_sockets_ready) {
		
				# $tcp_socket->setsockopt( SOL_SOCKET, SO_RCVTIMEO, $remaining_read_time );
				# my $got=sysread $tcp_socket,$buf,$remaining_read_size;
				my $got_addr=recv($tcp_socket, $buf, $remaining_read_size, 0);
				
				$got = length $buf;

				# fcntl($hashref->{"stream"},F_SETFL,0)          or die "fnctl(,F_SETFL,0)";
				#defined($got) or confess "Error reading TCP socket: $!";

				# send_tcp:
				# if (!$got && length $combined_buf == 0) {
				# 	print "Got TCP EOF/error (id=$id)"; # if $D;
				# 	my $seq=++$hashref->{"sent_to_udp"};
				# 	$hashref->{"sent_queue"}{$seq}=seq_new(undef());
				# 	sendpkt(pack("CNN",$TYPE_CLOSE,$id,$seq));
				# 	close $hashref->{"stream"} or confess "Error closing local socket: $!";
				# 	delete $hashref->{"stream"};
				# 	warn "Sent CLOSE (id=$id,seq=$seq)" if $D;
				# } else { 	# if ($got==length $buf) {

					my $now2 = time();

					if (!$combined_buf) {
					
						$combined_buf = $buf;
						if (length $buf > 0) {
							stats("tcpin");
							$last_recv = $now2;
						}
					}
					elsif (!$got) {
						# do not append
					}
					else {
						$combined_buf = $combined_buf . $buf;
						if (length $buf > 0) {
							stats("tcpin");
							$last_recv = $now2;
						}
					}
					
					$got = length $combined_buf;
					

					$read_time = $now2 - $read_start_time;			
					if ($got < $READ_SIZE && $read_time < $aggregation_timeout) {
					
						if ( !scalar(@$udp_sockets_ready)) {
						
							$remaining_read_size = $READ_SIZE - $got;
							$remaining_read_time = $aggregation_timeout - $read_time;
							# print "Got " . $got . " remaining time: " . $remaining_read_time . "\n";
							goto read_more;	
						}
						elsif ($got == 0 && $now2 - $last_recv > $aggregation_timeout * 2) {   # NB! avoid busy-looping when TCP client connection is dropped
							IO::Select->select(undef, undef, undef, $aggregation_timeout);
						}
					}

					if ($got > 0) {
					
						stats("tcpout");
					
						warn "Got TCP data (id=$id,got=$got)" if $D;
						my $seq=++$hashref->{"sent_to_udp"};
						$hashref->{"sent_queue"}{$seq}=seq_new($combined_buf);
						sendpkt(pack("CNNa*",$TYPE_SEND,$id,$seq,$combined_buf));
						warn "Sent SEND (id=$id,seq=$seq,data=".printable($combined_buf).")" if $D;
					}
				# } 
				
				# else {
				# 	confess "Invalid socket read return value: $got";
				# }
				
			}	#/ foreach $socket (@sockets_ready) {
		}	#/ if (! scalar(@sockets_ready)) {
	}
	
	if (vec($rfds,fileno($sock_udp1),1) || vec($rfds,fileno($sock_udp2),1)) {
	
		my $udp_data;
		
		
		$time2 = time();
		
		
		# if (!$opt_udp_listen_port && ($sockets_were_ready==0 || $time2 - $time1 >= $aggregation_timeout / 2)) {
		# if ($sockets_were_ready==0 || $time2 - $time1 >= 0.01) {
		
			# print "Time: " . ($time2 - $time1) . "\n";
			# print "Sleeping: " . time() . "\n";
			
			# my $pause = $time2 - $time1;
			# if ($pause > $aggregation_timeout) {
			# 	$pause = $aggregation_timeout;
			# }
			
			# sleep($pause);
			
			# $time2 = time();
		# }
		
		$time1 = $time2;
				
				
		# @sockets_ready = $select->can_read(0);	# causes 100% CPU usage
		# my @sockets_ready = $select->can_read(0); 	
		my ($sockets_ready) = IO::Select->select($select, undef, undef, 0);
		
		
		
		$sockets_were_ready = 0;
			
		# if (!defined $sockets_ready || ! scalar(@sockets_ready)) {
		if (!defined $sockets_ready || ! scalar(@$sockets_ready)) {
			# print "Timeout\n";
			
		} else {
			# foreach my $socket (@sockets_ready) {
			foreach my $socket (@$sockets_ready) {
			
				$sockets_were_ready = 1;

				my $got_addr=recv($socket, $udp_data, 0x10000, 0);
				
				if (!$got_addr) {
					# cluck "Error receiving UDP data: $!";
					if ($socket == $sock_udp1) {
						stats("recverr1");
					} elsif ($socket == $sock_udp2) {
						stats("recverr2");
					}
					# last;

					# $got_addr = "";		# comparison to undefined string would cause error in below code
				}

				# $peer_addr||=$got_addr;
				
				if ($socket == $sock_udp1 && $got_addr && (!$peer_addr1 || $peer_addr1 ne $got_addr)) {
					$peer_addr1=$got_addr;
					# print "Peer_addr1: " . $peer_addr1 . "\n";
					
					my($back_port1,$back_host1)=sockaddr_in $peer_addr1;
					$back_host1=inet_ntoa $back_host1;
					print "\nPeer server: $back_host1:$back_port1\n";
				}
				elsif ($socket == $sock_udp2 && $got_addr && (!$peer_addr2 || $peer_addr2 ne $got_addr)) {
					$peer_addr2=$got_addr;
					# print "Peer_addr2: " . $peer_addr2 . "\n";
					
					my($back_port2,$back_host2)=sockaddr_in $peer_addr2;
					$back_host2=inet_ntoa $back_host2;
					print "\nPeer server: $back_host2:$back_port2\n";
				}
				
				# if ($got_addr ne $peer_addr1 && $got_addr ne $peer_addr2) {
				#
				#	my($port,$host)=sockaddr_in $got_addr;
				#	$host=inet_ntoa $host;
				#	print "Ignoring packet as from unidentified address: $host:$port";
				#	
				#	if ($socket == $sock_udp1) {
				#		stats("ufoaddr1");
				#	} elsif ($socket == $sock_udp2) {
				#		stats("ufoaddr2");
				#	}
				#	
				#	# last;
				# }

				# if ($got_addr ne $peer_addr) {
				# 	my($port,$host)=sockaddr_in $got_addr;
				# 	$host=inet_ntoa $host;
				# 	cluck "Ignoring packet as from unidentified address: $host:$port";
				# 	stats("ufoaddr");
				# 	last;
				# }
				
				my $try_retry;
			retry:
				if ($try_retry) {
					$udp_data=$try_retry;
					$try_retry=undef();
				}
				
				my $udp_data_orig=$udp_data;
				my($magic,$type,$id);
				($magic,$type,$id,$udp_data)=unpack "NCNa*",$udp_data;
				
				if (!$magic || $magic!=$MAGIC) {
				
					# stats("badcrc");
					
					if ($socket == $sock_udp1) {
						stats("badcrc1");
					} elsif ($socket == $sock_udp2) {
						stats("badcrc2");
					}
					
				# } elsif (rand() < $opt_recvloss) {
				# 
				# 	warn "Got type=$type (id=$id) but it got lost" if $D;
					
				} elsif ($type==$TYPE_OPEN) {
				
					my($which);
					($which,$udp_data)=unpack "Na*",$udp_data;
					warn "Got OPEN (id=$id,which=$which)" if $D;
					die if $udp_data;
					
					if (!$sock{$id}) {
					
						my $sock_tcp_new=IO::Socket::INET->new(
							PeerAddr=>$opt_tcp_forward_addr[$which],
							PeerPort=>$opt_tcp_forward_port[$which],
							Proto=>"tcp",
						);
						
						if (!$sock_tcp_new) {
							sendpkt(pack("CNN",$TYPE_CLOSE,$id,1));
							warn "Refused back OPEN by CLOSE (id=$id,seq=1)" if $D;
						} else {
							my $old=select($sock_tcp_new);
							$|=1;
							select($old);
							sock_new($id,$which,$sock_tcp_new);
							
							# stats("openok");
							
							if ($socket == $sock_udp1) {
								stats("openok1");
							} elsif ($socket == $sock_udp2) {
								stats("openok2");
							}
						}
					}	#/ if (!$sock{$id}) {
					
					sendpkt(pack("CNN",$TYPE_ACK,$id,0));
					
					if ($socket == $sock_udp1) {
						stats("oackout1");
					} elsif ($socket == $sock_udp2) {
						stats("oackout2");
					}
					
				} elsif ($type==$TYPE_SEND) {
				
					my($seq);
					($seq,$udp_data)=unpack "Na*",$udp_data;
					my $hashref=$sock{$id};
					
					if (!$hashref) {
					
						# cluck "Got SEND but for nonexisting sock $id";
						# stats("ufosock");

						if ($socket == $sock_udp1) {
							stats("uforecv1");
						} elsif ($socket == $sock_udp2) {
							stats("uforecv2");
						}

					} else {
					
						warn "Got SEND(id=$id,seq=$seq (acked_to_udp=".$hashref->{"acked_to_udp"}."),data=".printable($udp_data).")" if $D;
						
						if ($hashref->{"acked_to_udp"}+1>$seq) {
						
							if ($socket == $sock_udp1) {
								stats("recvdup1");
							} elsif ($socket == $sock_udp2) {
								stats("recvdup2");
							}
						}
						
						if ($hashref->{"acked_to_udp"}+1==$seq) {
						
							if ($hashref->{"stream"}) {
							
								if (length($udp_data)==((syswrite $hashref->{"stream"},$udp_data,length($udp_data)) || 0)) {
									warn "Wrote TCP data (id=$id,acked_to_udp=seq=$seq,data=".printable($udp_data).")" if $D;
									
								} else {
									my $seqclose=++$hashref->{"sent_to_udp"};
									$hashref->{"sent_queue"}{$seqclose}=seq_new(undef());
									warn "Refusing back OPEN by CLOSE (id=$id,seqclose=$seqclose)" if $D;
									sendpkt(pack("CNN",$TYPE_CLOSE,$id,$seqclose));
								}
							}
							
							$hashref->{"acked_to_udp"}=$seq;
						
							if ($socket == $sock_udp1) {
								stats("recok1");
							} elsif ($socket == $sock_udp2) {
								stats("recok2");
							}
							
							warn "In order - got SEND (id=$id,seq=$seq (acked_to_udp=".$hashref->{"acked_to_udp"}.")" if $D && $D>=2;
							
							if (($try_retry=$hashref->{"incoming"}{$seq+1})) {
							
								delete $hashref->{"incoming"}{$seq+1};
								warn "Reinserted, retrying" if $D && $D>=2;
							}
						}
						
						if ($hashref->{"acked_to_udp"}+1<$seq) {
						
							warn "Out of order - got SEND (id=$id,seq=$seq (acked_to_udp=".$hashref->{"acked_to_udp"}.")" if $D && $D>=2;
							$hashref->{"incoming"}{$seq}=$udp_data_orig;
						}
					}
					
					if (!$hashref || $hashref->{"acked_to_udp"}+1>=$seq) {
					
						# TODO!!! aggregate with next send packet
						
						sendpkt(pack("CNN",$TYPE_ACK,$id,$seq));
						warn "Sent ACK (id=$id,seq=$seq)" if $D;
					
						if ($socket == $sock_udp1) {
							stats("ackout1");
						} elsif ($socket == $sock_udp2) {
							stats("ackout2");
						}
					}

					if ($try_retry) {

						goto retry;
					}
					
				} elsif ($type==$TYPE_ACK) {
				
					my $hashref=$sock{$id};
					if (!$hashref) {
						# cluck "Got ACK but for nonexisting sock $id";
						# stats("ufosock");
						
						if ($socket == $sock_udp1) {
							stats("ufoack1");
						} elsif ($socket == $sock_udp2) {
							stats("ufoack2");
						}
								
						# last;
					}
					
					my($seq);
					($seq,$udp_data)=unpack "Na*",$udp_data;
					warn "Got ACK (id=$id,seq=$seq)" if $D;
					
					die if $udp_data;
					###exists $hashref->{"sent_queue"}{$seq} or confess "Nonexisting queue of $id: $seq";
					
					if (exists $hashref->{"sent_queue"}{$seq}) {
					
						my $data=$hashref->{"sent_queue"}{$seq}{"data"};
						die if !$seq && defined $data;
						die if $seq && defined $data && $data eq "";
						
						delete $hashref->{"sent_queue"}{$seq};
						if ($seq && !defined $data) {
							delete $active{$id};
							warn "Deleted active id $id (processed ACK on close)" if $D;
						}
						warn "Processed ACK (id=$id,seq=$seq); remaining:".scalar(keys(%{$hashref->{"sent_queue"}})) if $D;
					
						if ($socket == $sock_udp1) {
							stats("ackin1");
						} elsif ($socket == $sock_udp2) {
							stats("ackin2");
						}
					}
					
				} elsif ($type==$TYPE_CLOSE) {
				
					my($seq);
					($seq,$udp_data)=unpack "Na*",$udp_data;
					my $hashref=$sock{$id};
					
					if (!$hashref) {
						# cluck "Got CLOSE but for nonexisting sock $id";
						# stats("ufosock");
						
						if ($socket == $sock_udp1) {
							stats("ufoclose1");
						} elsif ($socket == $sock_udp2) {
							stats("ufoclose2");
						}
							
					} else {
					
						warn "Got CLOSE (id=$id,seq=$seq)" if $D;
						die if $udp_data;
						
						if ($hashref->{"acked_to_udp"}+1>$seq) {
						
							# stats("recvdup");
						
							if ($socket == $sock_udp1) {
								stats("recvdup1");
							} elsif ($socket == $sock_udp2) {
								stats("recvdup2");
							}
						}
						
						if ($hashref->{"acked_to_udp"}+1==$seq && $hashref->{"stream"}) {
						
							close $hashref->{"stream"} or confess "Cannot close socket of $id";
							delete $hashref->{"stream"};
							$hashref->{"acked_to_udp"}=$seq;
							confess if !$active{$id};
							delete $active{$id};
							warn "Closed the local stream, deleted it from active (id=$id,seq=$seq)" if $D;
						}
					
						if ($socket == $sock_udp1) {
							stats("closein1");
						} elsif ($socket == $sock_udp2) {
							stats("closein2");
						}
					}
					
					if (!$hashref || $hashref->{"acked_to_udp"}+1>=$seq) {
					
						sendpkt(pack("CNN",$TYPE_ACK,$id,$seq));
						warn "Sent ACK of close (id=$id,seq=$seq)" if $D;
					
						if ($socket == $sock_udp1) {
							stats("cackout1");
						} elsif ($socket == $sock_udp2) {
							stats("cackout2");
						}
					}
					
				} else {
					# confess "Invalid packet type $type";
					print "Invalid packet type $type \n";
				}
				
			} #/ foreach $socket (@sockets_ready) {
			
		}	#/ if (! scalar(@sockets_ready)) {
		
	}	#/ if (vec($rfds,fileno($sock_udp1),1) || vec($rfds,fileno($sock_udp2),1)) {
	
	$earliest=undef();
	
	for my $hashref (values(%active)) {
	
		my $id=$hashref->{"id"};
		for my $seq (sort {$a <=> $b} keys(%{$hashref->{"sent_queue"}})) {
		
			my $seqhashref=$hashref->{"sent_queue"}{$seq};
			my $data=$seqhashref->{"data"};
			my $when=$seqhashref->{"timeout"};
			
			if (time()>=$when) {
			
				if ($seq==0) {
					die if defined $data;
					warn "Resent OPEN (id=$id)" if $D;
					sendpkt(pack("CNN",$TYPE_OPEN,$id,$hashref->{"which"}), "sendup");
					
				} elsif (defined $data) {
					die if $data eq "";
					# print "ERR: data eq ''" if $data eq "";
					warn "Resent SEND (id=$id,seq=$seq)" if $D;
					sendpkt(pack("CNNa*",$TYPE_SEND,$id,$seq,$data), "sendup");
					
				} else {	# pending CLOSE
					warn "Resent CLOSE (id=$id,seq=$seq)" if $D;
					sendpkt(pack("CNN",$TYPE_CLOSE,$id,$seq), "sendup");
				}
				
				$when=$seqhashref->{"timeout"}=time()+$opt_timeout;
			}
			
			$earliest=$when if !$earliest || $when<$earliest;
			
			last if time()<$seqhashref->{"timeout"};
		}
	}
}
