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
my $isoFormat = shift;
my $isoLen = shift;

my %hwData;
$hwData{"K002T992770A"} ="10014794";
$hwData{"5000000428"}	="21009517";
$hwData{"70165292"}		="04833256";
$hwData{"5000000427"}	="02061888";

my $terminalData = {};
$$terminalData{"21009517"}={serial=> "5000000428", ss=>"0080002638206001847100407fbc5f9f",
							caic=>"000000000353138", name=>"Raha Rajabi", merchant=>"25000,30",
							pspinfo=>"088820031413- bpmellat  -026613021-2273-83100", 
							pin =>"D38FADAD31EA54C7", mac=>"EA97CD3BEAD53780", data=>"7b038db44b31843e", mmk=>"a3f1cc6d9afd4ab471d15c275cca5f9cf2eb41dc722caec8"};

$$terminalData{"02061888"}={serial=> "5000000427", ss=>"0180002638206003847100c077b45f9f",
							caic=>"000000000352974", name=>"Raha Rajabi", merchant=>"25000,30", 
							pspinfo=>"086103406213- bpmellat  -026613021-2273-83100", 
							pin =>"8689f7984386ad43", mac=>"76e59bb97ca11c91", data=>"5358c0f38daf6bf3", mmk=>"344a6068e40d3e8d38641ddefa827939b53b6d28b1c48831"};

$$terminalData{"10014794"}={serial=> "K002T992770A", ss=>"0080002638206001847100407fbc5f9f",
							caic=>"", name=>"Raha Rajabi", merchant=>"", 
							pspinfo=>"088820031413- bpmellat  -026613021-2273-83100", 
							pin =>"8CEE3C8B012D8B39", mac=>"AC422D5AE27EDA22", data=>"", mmk=>""};


$$terminalData{"04833256"}={serial=> "70165292", ss=>"0080002638206001847100407fbc5f9f",
							caic=>"", name=>"Raha Rajabi", merchant=>"", 
							pspinfo=>"088820031413- bpmellat  -026613021-2273-83100", 
							pin =>"2c23f4d52abedb8d", mac=>"cb5d5f233a78b58b", data=>"", mmk=>""};


my $cardHolderData = {};
$$cardHolderData{"6104337809607011"} = {track2=>"6104337809607011=18041008475842437356", sheba=>"IR830120000000000088200314", pin=>"1234", balance=>"150000"};
$$cardHolderData{"6362143005521148"} = {track2=>"6362143005521148=95101016994000000000", sheba=>"IR830120000000000088200314", pin=>"1234", balance=>"150000"};
$$cardHolderData{"6037691610000770"} = {track2=>"6037691610000770=99011014295000000000", sheba=>"IR470120000000000012404580", pin=>"1234", balance=>"150000"};

my $IRID = 127956104779; # Internal Reference ID # 31	Acquirer Reference Data


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
	}
}; if($@){
	print $@,"\n";
	exit;
}	

sub ValidateRequest {
	my ($server,$typeHash, $dataHash) = @_;

		$$typeHash{'MTI'} = $$typeHash{'MTI'} + 10;
		my $MTIPROCESS = $$typeHash{'MTI'}.((exists $$dataHash{3})?substr($$dataHash{3},0,2):"");
		print Dumper $dataHash;
		print Dumper $MTIPROCESS;

		my $Date	= strftime "%Y%m%d", localtime time;
		my $date	= strftime "%y%m%d", localtime time;
		my $time	= strftime "%H%M%S", localtime time;

		my $amount;
		my $pan;
		my $terminalId;

		if(exists($$dataHash{4})){
			$amount = $$dataHash{4};
			$amount =~ s/^0+//;
		}

		if(exists($$dataHash{35})){
			$pan = $$dataHash{35};
			$pan =~ s/=\d+//;
		}
		
		$$dataHash{7} = $Date.$time;
		$$dataHash{12} = $date.$time;
		$$dataHash{31} = $IRID++;

		if($MTIPROCESS eq "121031"){
			$$dataHash{30} = $$cardHolderData{$pan}{balance} if($pan);
			$$dataHash{39} = "000";
			$$dataHash{54} = $$cardHolderData{$pan}{balance} if($pan);
			$$dataHash{59} = $$cardHolderData{$pan}{sheba}.",".$amount.";" if($pan && $amount);
		}
		elsif($MTIPROCESS eq "121001"){
			$$dataHash{30} = $$cardHolderData{$pan}{balance} if($pan);
			$$dataHash{39} = "000";
			$$dataHash{54} = $$cardHolderData{$pan}{balance} if($pan);
			$$dataHash{59} = $$cardHolderData{$pan}{sheba}.",".$amount.";" if($pan && $amount);
		}
		elsif($MTIPROCESS eq "181000"){
		}

		{
			my $file;
			if( -f "../bpm/$MTIPROCESS.txt"){
				$file = "../bpm/$MTIPROCESS.txt";
			}elsif( -f "../bpm/".substr($MTIPROCESS,0,4).".txt" ){
				$file = "../bpm/".substr($MTIPROCESS,0,4).".txt";
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
	print Dumper $dataHash;
	return ($typeHash, $dataHash);
}

