#!/usr/bin/perl -w

use Data::Dumper;
use Crypt::DES;

if(@ARGV < 2){
	print "usage:\n";
	print "\t./crypt PIN key pin pan\n";
	print "\t./crypt MAC key str len\n";
	print "\t./crypt DES [encrypt|decrypt] str key\n";
	print "\t./crypt 3DES [encrypt|decrypt] str key1 key2 key3\n";
	exit;
}

my $crypto = "Crypt::DES"; # "Crypt::DES" Crypt::Blowfish
my $blocksize = 8;

my $method =  shift;

if ($method eq "MAC"){
	my $keyStr = shift;
	my $str = shift;
	my $outlen = shift;
	my $macBlock = MACBlock($crypto, $keyStr, $blocksize, $str);
	print substr($macBlock,0,$outlen),"\n";
}elsif ($method eq "PIN") {
	my $keyStr = shift;
	my $pin = shift;
	my $pan = shift;
	my $pinBlock = PINBlock($crypto, $keyStr, $pin, $pan );
	print $pinBlock,"\n";
}elsif ($method eq "DES") {
	my $process = shift;
	my $str = shift;
	my $keyStr = shift;
	my $out;
	if($process eq "decrypt"){
		$out = ECB (\&Decrypt, $crypto, 2*$blocksize, $str, $keyStr);
	}elsif($process eq "encrypt"){
		$out = ECB (\&Encrypt, $crypto, 2*$blocksize, $str, $keyStr);
	}
	print $out,"\n";
}elsif ($method eq "3DES") {
	my $process = shift;
	my $str = shift;
	my $key1Str = shift;
	my $key2Str = shift;
	my $key3Str = shift;
	my $out;
	if($process eq "decrypt"){
		$out = ECB (\&Decrypt3, $crypto, 2*$blocksize, $str, $key1Str, $key2Str, $key3Str);
	}elsif($process eq "encrypt"){
		$out = ECB (\&Encrypt3, $crypto, 2*$blocksize, $str, $key1Str, $key2Str, $key3Str);
	}
	print $out,"\n";
}

sub Encrypt {
	my ($crypto,$str, $keyStr) = @_;
	my $key = pack "H*", $keyStr;
	my $hex = pack "H*", $str;
	my $cipher = $crypto->new($key);
	my $out = $cipher->encrypt($hex);
	my ($outStr) = unpack "H*", $out;
	return $outStr
}

sub Decrypt {
	my ($crypto,$str,$keyStr) = @_;
	my $key = pack "H*", $keyStr;
	my $hex = pack "H*", $str;
	my $cipher = $crypto->new($key);
	my $out = $cipher->decrypt($hex);
	my ($outStr) = unpack "H*", $out;
	return $outStr
}
sub Encrypt3 {
	my ($crypto,$str,$key1Str,$key2Str,$key3Str) = @_;
	
	my $out1 = Encrypt($crypto,$str, $key1Str);
	my $out2 = Decrypt($crypto,$out1,$key2Str);
	my $out3 = Encrypt($crypto,$out2,$key3Str);
	return $out3;
}

sub Decrypt3 {
	my ($crypto,$str,$key1Str,$key2Str,$key3Str) = @_;

	my $out1 = Decrypt($crypto,$str, $key3Str);
	my $out2 = Encrypt($crypto,$out1,$key2Str);
	my $out3 = Decrypt($crypto,$out2,$key1Str);
	return $out3;
}

sub ECB {
	my ($func, $crypto, $blocksize, $text, @keylist) = @_;
	my $out;
	for(my $i=0; $i < length($text); $i += $blocksize ) {
		my $substr = substr($text,$i,$blocksize);
		$out .= $func->( $crypto, $substr, @keylist );
	}
	return $out;
}

sub CBCENCMAC {
	my ($crypto,$blocksize,$key,$text) = @_;

	my $cipher = $crypto->new($key);
	my $iv= pack "H*", "0000000000000000";
	my $mid;
	my $encText;
	for(my $i=0; $i < length($text); $i += $blocksize ) {
		my $temp = substr($text,$i,$blocksize);
		#$mid = $temp; ECB 
		$mid = $iv ^ $temp; # CBC
		#print "temp: ", unpack( "H*", $temp), "\n";
		#print "mid: ",unpack( "H*", $mid), "\n";
		#print "iv: ",unpack( "H*", $iv), "\n";
		$iv = $cipher->encrypt($mid);
		$encText.=$iv;
	}
	return ($iv,$encText);
}

sub ECBENCMAC {
	my ($crypto,$blocksize,$key,$text) = @_;

	my $cipher = $crypto->new($key);
	my $iv= pack "H*", "0000000000000000";
	my $mid;
	my $encText;
	for(my $i=0; $i < length($text); $i += $blocksize ) {
		my $temp = substr($text,$i,$blocksize);
		$mid = $temp; # ECB 
		#$mid = $iv ^ $temp; # CBC
		#print "temp: ", unpack( "H*", $temp), "\n";
		#print "mid: ",unpack( "H*", $mid), "\n";
		#print "iv: ",unpack( "H*", $iv), "\n";
		$iv = $cipher->encrypt($mid);
		$encText.=$iv;
	}
	return ($iv,$encText);
}

sub MACBlock {
	my ($crypto, $keyStr, $blocksize, $str) = @_;

	my $len = length($str);
	my $pad = ( $len % 16 > 0 )? 16 - $len % 16 : 0 ;
	$str .= '30' x ($pad/2);

	my $text = pack "H*", $str;
	my $key = pack "H*", $keyStr;

	my ($mac,$encText) = CBCENCMAC($crypto,$blocksize,$key,$text);

	my ($out) = unpack "H*", $mac;

	return $out;
}

sub PINBlock {
	my ($crypto, $keyStr, $pin, $pan)= @_;

	my $panStr = "0000".substr($pan,3,12);
	my $pinStr = sprintf("%02d",length($pin)).$pin.('F'x(16-2-length($pin)));

	my $pinKey = pack "H*", $keyStr;
	my $panBin = pack "H*", $panStr;
	my $pinBin = pack "H*", $pinStr;

	my $plainPinBlock = $panBin ^ $pinBin;

	my $cipher = $crypto->new($pinKey);
	my $pinBlock = $cipher->encrypt($plainPinBlock);

	my $pinBlockStr = unpack "H*", $pinBlock;
	return $pinBlockStr;
}



=pod
my $mac = emac($key, $cipher, $text);
my $digest = hexdigest($mac), "\n";
#print base64digest($mac), "\n";
=cut

=pod
my $omac1 = Digest::CMAC->new($key, $cipher);
$omac1->add($text);
my $mac = $omac1->digest;
my $digest = $omac1->hexdigest;
=cut

