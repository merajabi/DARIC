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
				$$dataHash{$1} = $2||"";
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

sub GenerateRequest {
	my ($self, $typeHash, $dataHash) = @_;

	my $ISOCLASS = "DataFormat::".$$typeHash{'ISO'};

	my $iso = $ISOCLASS->new();
	my $f = new DataPackager::LV();
	my $p1 = new Packet;
	my $p2 = new Packet;
	my $p3 = new Packet;

	{
		my $bitmap = new Bitmap($$typeHash{"LEN"});
		$bitmap->SetBits(keys %$dataHash);
		print "# ","bitmap fields: ",join(' ',@{$bitmap->GetBits()}),"\n";
		print "# ","bitmap: ",$bitmap->GetHexStr(),"\n";

		my $fieldType = $iso->GetFields($$typeHash{'MTI'});
		my $fieldList = [ sort { $a <=> $b } keys %$fieldType ];

		$p1 .= $f->Set($iso->GetFieldFormat(1))->Pack($$typeHash{'MTI'});				# MTI code
		$p1 .= $f->Set($iso->GetFieldFormat(0))->Pack($bitmap->GetHexStr());# BITMAP

		foreach my $key (@$fieldList) {
			next if ($key == 1 or $key == 64 or $key == 128 );
			print "# ","field: $key\n";
			die "Mandatory field $key must be present in message" if( $$fieldType{$key} eq "M" and ! exists($$dataHash{$key}) );
			$p1 .= $f->Set($iso->GetFieldFormat($key))->Pack($$dataHash{$key}) if ( exists($$dataHash{$key}) );
		}
		print "# ","ISO Message without MAC: ", $p1->Data(),"\n";
	}
	{
		my $data = $p1->Data();
		my $macKey = $$typeHash{"MACKEY"};
		my $mac=`./crypt.pl "MAC" $macKey $data 16`;				# assume the MAC Key is = 0123456789ABCDEF
		chomp($mac);

		# ISO8583 messaging has no routing information, so is sometimes used with a TPDU header. 
		$p2 .= $f->Set('BIN', 'BIN', 'FIX', 40)->Pack($$typeHash{"TPDU"}) if ( exists($$typeHash{"TPDU"}) );
		$p2 .= $p1;
		$p2 .= $f->Set($iso->GetFieldFormat($$typeHash{"LEN"}))->Pack($mac);				# 64 or 128 Message Authentication Code (MAC)
	}

	{
		my $hexlen = sprintf( "%04x",length($p2->Data())/2 );
		$p3 .= $f->Set('BIN', 'BIN', 'FIX', 16)->Pack($hexlen);
		$p3 .= $p2;
		print "# ","ISO Message: ", $p3->Data(), "\n";
	}
	return $p3->Data();
}

=pod
sub GenerateResponse {
	my ($tpdu, $dataHash) = @_;

	my $f = new Filter();  # BINARY BCD ASCII // # FIXED LVAR
	my $iso = new ISO8583BPMOPT;

	my $p1 = new Packet;
	my $p2 = new Packet;
	my $p3 = new Packet;

	{
		my $fields = ${$iso->Fields($$dataHash{1})}{A};
		print "iso fields: ", join(',',@$fields),"\n";
		{
			my $key = 1;
			$p1 .= $f->Set($iso->FieldFormat($key))->Pack($$dataHash{$key});			# MTI code	1

			my $bitmap1 = new BitSet($bitmapLen);
			$bitmap1->SetBits(@$fields);
			print "bitmap: ",$bitmap1->GetHexStr(),"\n";

			$p1 .= $f->Set('BINARY','FIXED',8)->Pack($bitmap1->GetHexStr());		# BITMAP
		}
		foreach my $key (@$fields){
			if($key != 128){
				if(exists($$dataHash{$key})){
					print "field $key, ",($iso->FieldFormat($key))[3]," : ",$$dataHash{$key}," :\n";
					$p1 .= $f->Set($iso->FieldFormat($key))->Pack($$dataHash{$key});
				}
			}
		}

		print $p1->Data(),"\n";
	}
	{
		my $data = $p1->Data();
		my $terminalId = $$dataHash{41};
		my $macKey = $$terminalData{$terminalId}{mac};
		my $mac=`./crypt.pl "MAC" $macKey $data 8`;
		chomp($mac);
		$p2 .= $f->Set('BINARY','FIXED',5)->Pack($tpdu);					# TPDU
		$p2 .= $p1;
		$p2 .= $f->Set($iso->FieldFormat(64))->Pack($mac);					# 128 Message Authentication Code (MAC)
		print $p2->Data(),"\n";
	}
	{
		my $hexlen = sprintf( "%04x",length($p2->Data())/2 );
		$p3 .= $f->Set('BINARY','FIXED',2)->Pack($hexlen);
		$p3 .= $p2;
		print $p3->Data(),"\n";
	}

	return $p3->Data();
}
=cut

=pod
sub ProcessRequest {
	my ($requestStr) = @_;

	my $f = new Filter();  # BINARY BCD ASCII // # FIXED LVAR
	my $iso = new ISO8583BPMOPT;

	my $dataHash = {};
	my $tpdu;

	{
		my ($out,$len,$str);
		my $bitmap2 = new BitSet($bitmapLen);
		$str = $requestStr;

		($out,$len,$str) = $f->Set('BINARY','FIXED',2)->UnPack($str);		# len
		($tpdu,$len,$str) = $f->Set('BINARY','FIXED',5)->UnPack($str);		# tpdu
		($$dataHash{1},$len,$str) = $f->Set($iso->FieldFormat(1))->UnPack($str);	# MTI
		($out,$len,$str) = $f->Set('BINARY','FIXED',8)->UnPack($str);		# bitmap

		$bitmap2->SetHexStr($out);
		my $fields = $bitmap2->GetFields();
		print join(' ',@$fields),"\n";
		# my %Fields = map {$_ => 1} @$fields;
		foreach my $key (@$fields){
			if($key != 1) {
				print "feild: ",$key,"\n";
				($$dataHash{$key},$len,$str) = $f->Set($iso->FieldFormat($key))->UnPack($str);
			}
		}
		print $str,"\n";
	}
	return ($tpdu,$dataHash);	
}
=cut

sub ProcessResponse {
	my ($self, $typeHash, $response) = @_;

	my $ISOCLASS = "DataFormat::".$$typeHash{'ISO'};

	my $iso = $ISOCLASS->new();
	my $f = new DataPackager::LV();

	local $@;
	eval {
		my ($out,$len,$str);
		my $bitmap = new Bitmap($$typeHash{'LEN'});
		$str = $response;

		($out,$len,$str) = $f->Set('BIN', 'BIN', 'FIX', 16)->UnPack($str);
		($out,$len,$str) = $f->Set('BIN', 'BIN', 'FIX', 40)->UnPack($str) if ( exists($$typeHash{"TPDU"}) );
		print "TPDU:$out\n";
		($out,$len,$str) = $f->Set($iso->GetFieldFormat(1))->UnPack($str);		# MTI
		print "MTI:$out\n";
		($out,$len,$str) = $f->Set($iso->GetFieldFormat(0))->UnPack($str);		# bitmap

		$bitmap->SetHexStr($out);
		my $fieldList = $bitmap->GetBits();
		print "# ","bitmap fields: ",join(' ',@$fieldList),"\n";

		foreach my $key (@$fieldList) {
			next if ($key == 1 );
			($out,$len,$str) = $f->Set($iso->GetFieldFormat($key))->UnPack($str);
			print "$key:$out\n";
		}
		print "# ",$str,"\n";
	}; if($@){
		print "# ",$@,"\n";
		exit;
	}	
}

1;

