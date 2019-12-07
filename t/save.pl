#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";
use Data::Dumper;

use DARIC;

my $rrn = shift;
my $pan = shift;
my $track2 = shift;
my $fp;
open $fp, "<","1200.txt";
my $client = new DARIC();
my ($typeHash, $dataHash) = $client->LoadData($fp);
close $fp;

my $newHash ={};
while(my $line = <STDIN>) {
	chomp($line);
	$line =~ s/^\s+//;
	next if( ! length $line or $line =~ m/^#/);
	if($line =~ m/^(\d+)\s*:\s*(.+)?/){
		$$newHash{$1} = $2||"";
	}
}

$$dataHash{2}=$$newHash{2};
$$dataHash{35}=$$newHash{35};
$$dataHash{11}=$$newHash{11};
$$dataHash{37}=$$newHash{11};

foreach my $key(keys %$typeHash){
	print $key.":".$$typeHash{$key}."\n";
}

foreach my $key(keys %$dataHash){
	print $key.":".$$dataHash{$key}."\n";
}
