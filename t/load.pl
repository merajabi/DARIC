#!/usr/bin/perl -w
use strict;
use warnings;
use lib "../lib";
use Data::Dumper;

my $dataHash ={};
while(my $line = <STDIN>) {
	chomp($line);
	$line =~ s/^\s+//;
	next if( ! length $line or $line =~ m/^#/);
	if($line =~ m/^(\d+)\s*:\s*(.+)?/){
		$$dataHash{$1} = $2||"";
	}
}

print $$dataHash{39}."\n";
if($$dataHash{39}=="000") {
	print substr(2,$$dataHash{54})."\n";
}

