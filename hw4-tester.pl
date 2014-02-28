#! /usr/bin/perl -w

open(FOO, "osprd.c") || die "Did you delete osprd.c?";
$lines = 0;
$lines++ while defined($_ = <FOO>);
close FOO;

@tests = (
# single write
    # 1
    [ '(echo test1 | ./osprdaccess -w) && ' .
      '(./osprdaccess -r 16 | hexdump -C)',
      "00000000 74 65 73 74 31 0a 00 00 00 00 00 00 00 00 00 00 |test1...........| " .
      "00000010" ],

# write with offset
    # 2
    [ '(echo test1 | ./osprdaccess -w -o 5) && ' .
      '(./osprdaccess -r 16 | hexdump -C)',
      "00000000 00 00 00 00 00 74 65 73 74 31 0a 00 00 00 00 00 |.....test1......| " .
      "00000010" ],

# write to an offset in next sector
    # 3
    [ '(echo sector2 | ./osprdaccess -w -o 512) && ' .
      '(./osprdaccess -r 1024| hexdump -C)',
      "00000000 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................| " .
      "* " .
      "00000200 73 65 63 74 6f 72 32 0a 00 00 00 00 00 00 00 00 |sector2.........| " .
      "00000210 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................| " .
      "* " .
      "00000400" ],


# multiple writes
    # 4
    [ '(echo test1 | ./osprdaccess -w) && ' .
      '(echo test2 | ./osprdaccess -w) && ' .
      '(./osprdaccess -r 16 | hexdump -C)',
      "00000000 74 65 73 74 32 0a 00 00 00 00 00 00 00 00 00 00 |test2...........| " .
      "00000010" ],

    # 5
    [ '(echo test1 | ./osprdaccess -w) && ' .
      '(echo test2 | ./osprdaccess -w -o 5) && ' .
      '(./osprdaccess -r 16 | hexdump -C)',
      "00000000 74 65 73 74 31 74 65 73 74 32 0a 00 00 00 00 00 |test1test2......| " .
      "00000010" ],

# delay cases
    # 6
    [ '(echo overwrite | ./osprdaccess -w -d 5) & ' .
      '(echo hidden | ./osprdaccess -w) && ' .
      'sleep 8 &&' .
      '(./osprdaccess -r 16 | hexdump -C)',
      "00000000 6f 76 65 72 77 72 69 74 65 0a 00 00 00 00 00 00 |overwrite.......| " .
      "00000010" ],

    # 7
    [ '(echo overwrite | ./osprdaccess -w -d 5) & ' .
      '(./osprdaccess -r 16 | hexdump -C) ' ,
      "00000000 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................| " .
      "00000010" ],

    # 8
    [ '(echo foo | ./osprdaccess -w 3) && sleep 1 && ' .
      '(./osprdaccess -r 3 && ./osprdaccess -r 3) && sleep 4 ',
      "foofoo"
    ],

# locking
    # 9
    [ '(echo aa | ./osprdaccess -w 2 -l -d 2) & ' .
      'sleep 1 ; (echo b | ./osprdaccess -w 1 -o 1 -l) ; ' .
      './osprdaccess -r 2',
      "ab"
    ],

    # 10
    [ 'echo a | ./osprdaccess -w 1 ; ' .
      '(./osprdaccess -r -l -d 3 >/dev/null &) ; ' .
      '(echo b | ./osprdaccess -w -l 1 &) ; ' .
      'sleep 1 ; ./osprdaccess -r 1',
      "a"
    ],    

    # 11
    [ '(./osprdaccess -r 6 -l 1) &' .
      '(echo foobar | ./osprdaccess -w -l) ',
      "foobar"
    ],    

    # 12
    [ 'echo foobar | ./osprdaccess -w 6 ; ' .
      '(./osprdaccess -r 6 -l -d 1) &' .
      '(./osprdaccess -r 6 -L 1 -d 1) &' .
      '(echo xxxxxx | ./osprdaccess -w -L) ; ' .
      'sleep 3',
      "ioctl OSPRDIOCTRYACQUIRE: Device or resource busy foobarfoobar"
    ],

# more complex locking cases
    # 13
    [ '(echo aaa | ./osprdaccess -w 3 -l -d 2) & ' .
      '(sleep 1 ; echo bb | ./osprdaccess -w 2 -o 1 -l -d 1) & ' .
      'sleep 2 ; (echo c | ./osprdaccess -w 1 -o 2 -l) ; ' .
      './osprdaccess -r 3',
      "abc"
    ],

    # 14
    [ '(echo aaa | ./osprdaccess -w 3 -l -d 3) & ' .
      '(sleep 1 ; ./osprdaccess -r 3 -l) & ' .
      'sleep 2 ; echo ccc | ./osprdaccess -w 3 -l',
      "aaa"
    ],

    # 15
    [ '(echo aaa | ./osprdaccess -w 3 -l -d 5) & ' .
      '(sleep 1 ; ./osprdaccess -r 1 -l ; echo -n X) & ' .
      '(sleep 2 ; ./osprdaccess -r 1 -l -d 1 ; echo -n Y) & ' .
      '(sleep 3 ; echo bbb | ./osprdaccess -w 3 -l) & ' .
      '(sleep 4 ; ./osprdaccess -r 1 -l ; echo -n Z)',
      "aXaYbZ"
    ],

    );

my($ntest) = 0;

my($sh) = "bash";
my($tempfile) = "hw4test.txt";
my($ntestfailed) = 0;
my($ntestdone) = 0;
my($zerodiskcmd) = "./osprdaccess -w -z";
my(@disks) = ("/dev/osprda", "/dev/osprdb", "/dev/osprdc", "/dev/osprdd");

my(@testarr, $anytests);
foreach $arg (@ARGV) {
    if ($arg =~ /^\d+$/) {
	$anytests = 1;
	$testarr[$arg] = 1;
    }
}

foreach $test (@tests) {

    $ntest++;
    next if $anytests && !$testarr[$ntest];

    # clean up the disk for the next test
    foreach $disk (@disks) {
	`$sh <<< "$zerodiskcmd $disk"`
    }

    $ntestdone++;
    print STDOUT "Starting test $ntest\n";
    my($in, $want) = @$test;
    open(F, ">$tempfile") || die;
    print F $in, "\n";
    print STDERR $in, "\n";
    close(F);
    $result = `$sh < $tempfile 2>&1`;
    $result =~ s|\[\d+\]||g;
    $result =~ s|^\s+||g;
    $result =~ s|\s+| |g;
    $result =~ s|\s+$||;

    next if $result eq $want;
    next if $want eq 'Syntax error [NULL]' && $result eq '[NULL]';
    next if $result eq $want;
    print STDOUT "Test $ntest FAILED!\n  input was \"$in\"\n  expected output like \"$want\"\n  got \"$result\"\n";
    $ntestfailed++;
}

unlink($tempfile);
my($ntestpassed) = $ntestdone - $ntestfailed;
print "$ntestpassed of $ntestdone tests passed\n";
exit(0);
