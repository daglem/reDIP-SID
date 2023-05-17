#!/usr/bin/perl

# Verification of LFSR envelope counter values, see
# https://github.com/libsidplayfp/SID_schematics/wiki/Envelope-Overview

print "LFSR15\n";
my $bits = 0b111111111111111;
my $lfsr = $bits;
for (my $i = 0; $i < (1 << 15); $i++) {
    if (grep {$i == $_} (8, 31, 62, 94, 148, 219, 266, 312, 391, 976, 1953, 3125, 3906, 11719, 19531, 31250)) {
        print sprintf("count: %5i, lfsr: \$%04x = %015b\n", $i, $lfsr, $lfsr);
    }
    $lfsr = (($lfsr << 1) & $bits) | ((($lfsr >> 14) ^ ($lfsr >> 13)) & 0b1);
}

print "\n";

print "LFSR5\n";
$bits = 0b11111;
$lfsr = $bits;
for (my $i = 0; $i < (1 << 5) + 2; $i++) {
    if (grep {$i == $_} (2, 4, 8, 16, 30)) {
        print sprintf("count: %3i, lfsr: \$%02x = %05b\n", $i, $lfsr, $lfsr);
    }
    $lfsr = (($lfsr << 1) & $bits) | ((($lfsr >> 4) ^ ($lfsr >> 2)) & 0b1);
}
