#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";

use POSIX;
use IO::Socket::INET;
$| = 1;

use Data::Dumper;
use DARIC;

my $server	= shift || '127.0.0.1';	
my $port	= shift || '9999';

local $@;
eval {

	my $socket = new IO::Socket::INET (
			PeerHost => $server,
			PeerPort => $port,
			Proto => 'tcp'
		);
	die "Cannot create a socket $! \n" unless $socket;

	my $client = new DARIC();
	my ($typeHash, $dataHash) = $client->LoadData(\*STDIN);
	{
		my $pan;
		if( exists($$dataHash{'2'}) ){
			$pan = $$dataHash{'2'};
		}elsif( exists($$dataHash{'35'}) ){
			if( $$dataHash{'35'} =~ m/^(\d+)=/ ){
				$pan = $1;
			}
		}

		die "NO PAN" if(!$pan);
		my $pin = $$dataHash{'52'};
		my $pinKey = $$typeHash{'PINKEY'};
		my $pinBlock=`./crypt.pl "PIN" $pinKey $pin $pan`;
		chomp($pinBlock);
		$$dataHash{'52'} = $pinBlock;
	}
	my $request = $client->GenerateRequest($typeHash, $dataHash);

	my $hexreq = pack "H*", $request;
	print $socket->send($hexreq)," bytes send\n";

	my $hexres;
	$socket->recv($hexres,1024);
	$socket->close(); 

	my ($response) = unpack "H*", $hexres;
	chomp($response);
	print "res: ", $response,"\n";

	$client->ProcessResponse($typeHash, $response);

}; if($@){
	print $@,"\n";
	exit;
}	



