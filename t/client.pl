#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";
use lib qw(../ISO8583/lib);
use POSIX;
use IO::Socket::INET;
$| = 1;

use DataPackager::LV;
use Data::Dumper;
use DARIC;

if(@ARGV < 2){
	print "usage:\n";
	print "./server IP PORT < path-to-data-file \n";
	print "./server 172.20.122.160 9999 < ../bpm/atm/120031.txt \n";
	exit;
}

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

	($typeHash, $dataHash) = PreProcess($typeHash, $dataHash);

	my $request = $client->GenerateMessage($typeHash, $dataHash);

	my $hexreq = pack "H*", $request;
	print "# ",$socket->send($hexreq)," bytes send\n";

	my $hexres;
	$socket->recv($hexres,1024);
	$socket->close(); 
	die "No Message recieved \n" if(length($hexres) <= 0 );

	my ($response) = unpack "H*", $hexres;
	chomp($response);
	print "# ","res: ", $response,"\n";

	$client->ProcessMessage($typeHash, $response);

}; if($@){
	print $@,"\n";
	exit;
}	

sub PreProcess {
	my ($typeHash, $dataHash) = @_;
	my $MTIPROCESS;
	my $f = new DataPackager::LV();

	if(length($$typeHash{'MTI'})==2){
		#$$typeHash{'MTI'} = $$typeHash{'MTI'} + 10;
		$MTIPROCESS = $$typeHash{'MTI'}."Q";
	}else{
		$$typeHash{'MTI'} = $$typeHash{'MTI'};
		$MTIPROCESS = $$typeHash{'MTI'}.((exists $$dataHash{3})?substr($$dataHash{3},0,2):"");
	}
	$$typeHash{'MTIPROCESS'} = $MTIPROCESS;

	if($$typeHash{"MTI"} eq "1200" or $$typeHash{"MTI"} eq "04" or $$typeHash{"MTI"} eq "01")
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
	if($$typeHash{"MTI"} eq "1100" and $$dataHash{'3'} eq "890000")
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
		my $pin = $$dataHash{'60'};
		my $pinKey = $$typeHash{'PINKEY'};
		my $pinBlock=`perl crypt.pl "PIN" $pinKey $pin $pan`;
		chomp($pinBlock);
		$$dataHash{'60'} = $pinBlock;
	}
	if($$typeHash{"MTI"} eq "1800" and $$dataHash{'3'} eq "000000")
	{
		my $pin = $$dataHash{'52'};
		my $pinKey = $$typeHash{'PINKEY'};
		my $pinStr = $f->Set('ASC', 'ASC', 'FIX', 8)->Pack($pin);
		my $pinBlock= `perl crypt.pl DES encrypt $pinStr $pinKey`;
		chomp($pinBlock);
		$$dataHash{'52'} = $pinBlock;
	}

	return ($typeHash, $dataHash);
}


