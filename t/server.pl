#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";

use POSIX;
use IO::Socket::INET;
$| = 1;

use Data::Dumper;
use DARIC;

if(@ARGV < 5){
	print "usage:\n";
	print "./server IP PORT ISO length path-to-data-files \n";
	print "./server 172.20.122.160 9999 ISO8583vbpmATM 128 ../bpm/atm \n";
	exit;
}

my $server	= shift || '127.0.0.1';	
my $port	= shift || '9999';
my $isoFormat = shift;
my $isoLen = shift;
my $path = shift;

my $IRID = 111111111111; # Internal Reference ID # 31	Acquirer Reference Data

local $@;
eval {

	# creating a listening socket
	my $socket = new IO::Socket::INET (
		LocalHost => $server ,
		LocalPort => $port,
		Proto => 'tcp',
		Listen => 5,
		Reuse => 1
	);
	die "Cannot create a socket $! \n" unless $socket;

	print "server waiting for client connection on port $port\n";

	while(1) {
		local $@;
		eval {
			# waiting for a new client connection
			my $client_socket = $socket->accept();

			# get information about a newly connected client
			my $client_address = $client_socket->peerhost();
			my $client_port = $client_socket->peerport();
			print "connection from $client_address:$client_port\n";

			my $request;
			$client_socket->recv($request,1024);
			my ($requestStr) = unpack "H*", $request;
			print "recv: ",length($request)," bytes\n";
			print "$requestStr\n";

			my $server = new DARIC();
			my $typeHash = {"ISO"=>$isoFormat,"LEN"=>$isoLen,"TPDU"=>""};
			my $dataHash = {};

			($typeHash, $dataHash) = $server->ProcessMessage($typeHash,$requestStr);
			($typeHash, $dataHash) = ValidateRequest($server,$typeHash, $dataHash);
			my $responseStr = $server->GenerateMessage($typeHash, $dataHash);

			my $response = pack "H*", $responseStr;
			print "send: ",$client_socket->send($response)," bytes\n";
			print "$responseStr\n";

			$client_socket->close(); 
		}; if($@){
			print $@,"\n";
		}	

	}
}; if($@){
	print $@,"\n";
	exit;
}	

sub ValidateRequest {
	my ($server,$typeHash, $dataHash) = @_;
		my $MTIPROCESS;
		if(length($$typeHash{'MTI'})==2){
			#$$typeHash{'MTI'} = $$typeHash{'MTI'} + 10;
			$MTIPROCESS = $$typeHash{'MTI'}."A";
		}else{
			$$typeHash{'MTI'} = $$typeHash{'MTI'} + 10;
			$MTIPROCESS = $$typeHash{'MTI'}.((exists $$dataHash{3})?substr($$dataHash{3},0,2):"");
		}
		$$typeHash{'MTIPROCESS'} = $MTIPROCESS;

		my $Date	= strftime "%Y%m%d", localtime time;
		my $date	= strftime "%y%m%d", localtime time;
		my $time	= strftime "%H%M%S", localtime time;

		$$dataHash{7} = $Date.$time;
		$$dataHash{12} = $date.$time;
		$$dataHash{31} = $IRID++;

		if($MTIPROCESS eq "121031"){
		}
		elsif($MTIPROCESS eq "121001"){
		}
		elsif($MTIPROCESS eq "181000"){
		}

		{
			my $file;
			if( -f "$path/$MTIPROCESS.txt"){
				$file = "$path/$MTIPROCESS.txt";
			}elsif( -f "$path/".substr($MTIPROCESS,0,4).".txt" ){
				$file = "$path/".substr($MTIPROCESS,0,4).".txt";
			}
			
			if( defined($file) ) {
				my $fp;
				open $fp,"<",$file;
				my ($localTypeHash, $localDataHash) = $server->LoadData($fp);
				close($fp);

				foreach my $key (keys %$localTypeHash){
					if($$localTypeHash{$key} ne "" || ! exists $$typeHash{$key} ){
						$$typeHash{$key} = $$localTypeHash{$key};
					}
				}
				foreach my $key (keys %$localDataHash){
					if($$localDataHash{$key} ne "" || ! exists $$dataHash{$key} ){
						$$dataHash{$key} = $$localDataHash{$key};
					}
				}
			}
		}
	return ($typeHash, $dataHash);
}

