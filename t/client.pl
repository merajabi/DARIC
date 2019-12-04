#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";

use POSIX;
use IO::Socket::INET;
$| = 1;

use Data::Dumper;
use DARIC;

my $server	= '85.10.1.131';	my $port	= '9999';

	local $@;
	eval {
=pod
		my $socket = new IO::Socket::INET (
				PeerHost => $server,
				PeerPort => $port,
				Proto => 'tcp'
			);
		die "Cannot create a socket $! \n" unless $socket;
=cut
		my $client = new DARIC();
		my ($typeHash, $dataHash) = $client->LoadData(\*STDIN);
		my $request = $client->GenerateRequest($typeHash, $dataHash);

		my $hexreq = pack "H*", $request;
#		print $socket->send($hexreq)," bytes send\n";

		my $hexres;
#		$socket->recv($hexres,1024);
#		$socket->close(); 

#		my ($response) = unpack "H*", $hexres;
#		chomp($response);
#		print "res: ", $response,"\n";

		$client->ProcessResponse($typeHash, $request);
	}; if($@){
		print $@,"\n";
		exit;
	}	



