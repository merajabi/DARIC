package DARIC;

use strict;
use warnings;

use lib qw(../ISO8583/lib);

use Data::Dumper;

use Tools;
use Packet;
use Bitmap;
use DataPackager::LV;
use DataFormat::ISO8583v87;
use DataFormat::ISO8583vbpmATM;
use DataFormat::ISO8583vbpmPOS;

sub new {
	my ($class, $bits) = @_;
	my $self = {};
    bless $self, $class;
    return $self;
};

sub LoadData {
	my ($self, $fp) = @_;
	my $dataHash={};
	my $typeHash={};

	local $@;
	eval {
		while(my $line = <$fp>) {
			chomp($line);
			$line =~ s/^\s+//;
			next if( ! length $line or $line =~ m/^#/);
			if($line =~ m/^(\d+)\s*:\s*(.+)?/){
				$$dataHash{$1} = $2//"";
			}elsif ($line =~ m/^(ISO|MTI|TPDU|MACKEY|PINKEY|LEN)\s*:\s*(.+)/i){
				$$typeHash{uc $1} = $2;
			}else{
				die "Invalid input format: $line\n"
			}
		}

		die "No MTI code provided" if( ! exists $$typeHash{"MTI"});
		die "No MACKEY code provided" if( ! exists $$typeHash{"MACKEY"});
		die "No PINKEY code provided" if( ! exists $$typeHash{"PINKEY"});
		die "No LEN code provided" if( ! exists $$typeHash{"LEN"});
	}; if($@){
		print "# ",$@,"\n";
	}	

	return ($typeHash, $dataHash);
}

sub ProcessMessage {
	my ($self, $typeHash, $response) = @_;

	my $ISOCLASS = "DataFormat::".$$typeHash{'ISO'};

	my $iso = $ISOCLASS->new();
	my $f = new DataPackager::LV();

	my $dataHash = {};

	local $@;
	eval {
		my ($out,$len,$str);
		my $bitmap = new Bitmap($$typeHash{'LEN'});
		$str = $response;

		($out,$len,$str) = $f->Set('BIN', 'BIN', 'FIX', 16)->UnPack($str);
		($$typeHash{"TPDU"},$len,$str) = $f->Set($iso->GetFieldFormat('TPDU'))->UnPack($str) if ( exists($$typeHash{"TPDU"}) );
		print "TPDU:".$$typeHash{"TPDU"}."\n";
		($$typeHash{"MTI"},$len,$str) = $f->Set($iso->GetFieldFormat('MTI'))->UnPack($str);		# MTI
		print "MTI:".$$typeHash{"MTI"}."\n";
		($out,$len,$str) = $f->Set($iso->GetFieldFormat('BITMAP'))->UnPack($str);		# bitmap

		$bitmap->SetHexStr($out);
		my $fieldList = $bitmap->GetBits();
		print "# ","bitmap fields: ",join(' ',@$fieldList),"\n";

		foreach my $key (@$fieldList) {
			next if ($key == 1 );
			($$dataHash{$key},$len,$str) = $f->Set($iso->GetFieldFormat($key))->UnPack($str);
			print "$key:".$$dataHash{$key}."\n";
		}
		print "# ",$str,"\n";
	}; if($@){
		print "# ",$@,"\n";
		die $@;
	}	
	return ($typeHash,$dataHash);
}

sub GenerateMessage {
	my ($self, $typeHash, $dataHash) = @_;

	my $ISOCLASS = "DataFormat::".$$typeHash{'ISO'};
	my $iso = $ISOCLASS->new();

	my $f = new DataPackager::LV();
	my @commonfields =();

	my $p1 = new Packet;
	my $p2 = new Packet;
	my $p3 = new Packet;
	my $p4 = new Packet;

	local $@;
	eval {

		{
			my $fieldType = $iso->GetFields($$typeHash{'MTIPROCESS'});
			my $fieldList = [ sort { $a <=> $b } keys %$fieldType ];

			foreach my $key (@$fieldList) {
				if ($key == 1 or $key == 64 or $key == 128 ){
					push @commonfields, $key;
					next;
				}
				die "Mandatory field $key must be present in message" if( $$fieldType{$key} eq "M" and ! exists($$dataHash{$key}) );
				if ( exists($$dataHash{$key}) ){
					print "# ","field: $key data: ".$$dataHash{$key}."\n";
					$p1 .= $f->Set($iso->GetFieldFormat($key))->Pack($$dataHash{$key}) ;
					push @commonfields, $key;
				}
			}
		}
		{
			my $bitmap = new Bitmap($$typeHash{"LEN"});
			$bitmap->SetBits(@commonfields);
			print "# ","bitmap fields: ",join(' ',@{$bitmap->GetBits()}),"\n";
			print "# ","bitmap: ",$bitmap->GetHexStr(),"\n";

			$p2 .= $f->Set($iso->GetFieldFormat('MTI'))->Pack($$typeHash{'MTI'});		# MTI code
			$p2 .= $f->Set($iso->GetFieldFormat('BITMAP'))->Pack($bitmap->GetHexStr());	# BITMAP
			$p2 .= $p1;

			print "# ","ISO Message without MAC: ", $p2->Data(),"\n";
		}
		{
			my $data = $p2->Data();
			my $macKey = $$typeHash{"MACKEY"};
			my $mac;
			if(length $$typeHash{'MTI'} == 2){
				$mac=`./crypt.pl "MAC" $macKey $data 8`;				# assume the MAC Key is = 0123456789ABCDEF
			}else{
				$mac=`./crypt.pl "MAC" $macKey $data 16`;				# assume the MAC Key is = 0123456789ABCDEF
			}
			chomp($mac);

			# ISO8583 messaging has no routing information, so is sometimes used with a TPDU header. 
			$p3 .= $f->Set($iso->GetFieldFormat('TPDU'))->Pack($$typeHash{"TPDU"}) if ( exists($$typeHash{"TPDU"}) );
			$p3 .= $p2;
			$p3 .= $f->Set($iso->GetFieldFormat($$typeHash{"LEN"}))->Pack($mac);				# 64 or 128 Message Authentication Code (MAC)
		}

		{
			my $hexlen = sprintf( "%04x",length($p3->Data())/2 );
			$p4 .= $f->Set('BIN', 'BIN', 'FIX', 16)->Pack($hexlen);
			$p4 .= $p3;
			print "# ","ISO Message: ", $p4->Data(), "\n";
		}
	}; if($@){
		print "# ",$@,"\n";
		die $@;
	}	

	return $p4->Data();
}

1;

