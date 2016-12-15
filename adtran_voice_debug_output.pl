#!/usr/bin/env perl

###############################################################################################
##
## Perl script to capture Adtran voice debug output for a specific time period. 
## If no time period specified then default is 60 sec.
## After starting to capture the data, enter 'stop' to stop capturing the output
## 
## Author : Ravi Kondala
##
###############################################################################################

use warnings;
use strict;
use Data::Dumper;
use File::HomeDir;
use Net::SSH::Expect; ## wrapper version that allows you to use passwords
use Getopt::Long;
use IO::Select;

## Passed parameters for Hosts, Type and Timeout
my %options;
if(! GetOptions(\%options,
                "h|host=s" ,
                'type=s',
                'timeout=i',
		'label=s',
		'nodebug=s',
                "help" )) {
    exit 1;
}

if ($options{help}) {
    help();
    exit 0;
}

my $host = $options{h} || $ARGV[0];
if (!$host) {
    print "\t\t\tHost is missing\n";
    help();
    exit 1;
}

if($host !~ /\w{8}(AJ)\d{3}/){
    print "\t\t\tDevice $host is Invalid, Please pass only Adtrans.\n\n";
    help();
    exit 1;
}

$options{type} = 'all' unless ($options{type});
my $cmd_type;
$cmd_type->{pri} = ["debug isdn l2-formatted"];
$cmd_type->{sip} = ["debug sip stack messages"];
$cmd_type->{cas} = ["debug voice summary"];
$cmd_type->{analog} = ["debug voice summary",
                       "debug voice tone",
                       "debug interface fxs",
                       "debug voice switchboard"]
;
my $timeout = 5;

my @now = localtime();
my $timeStamp = sprintf("%02d-%02d-%04d-%02d:%02d:%02d", 
                        $now[4]+1,    $now[3],   $now[5]+1900,
                        $now[2],      $now[1],   $now[0]);
my $date =  sprintf("%02d-%02d-%02d", $now[4]+1, $now[3], $now[5]+1900);

unless($cmd_type->{$options{type}} || $options{type} =~ /all/i){
    print "\t\t\tInvalid Type argument\n\n";
    exit 1;
}

my ($user, $pass) = user_password();

## Connection
my $ssh = Net::SSH::Expect->new(
    host => $host,
    password => $pass,
    user => $user,
    raw_pty => 1,
    timeout => $timeout,
    );

my $login_output;
eval { $login_output = $ssh->login(); };

if ($@) {
    print " -> Login has failed\n" unless($options{nodebug});
    print " -> Login output: $login_output\n" unless($options{nodebug} || !$login_output);
    $ssh->close();
    exit 2;
} else {
    if( $login_output !~ /#/) {
        print " -> Login has failed. Didn't see device prompt as expected.\n" unless($options{nodebug});
        print " -> Login output: $login_output\n" unless($options{nodebug});
        $ssh->close();
        exit 2;
    }

    print " -> Logged in to $host!\n" unless($options{nodebug}); 
}

## set terminal length 0
$ssh->send("terminal length 0");
$ssh->waitfor("#", $timeout) or die "Timeout after setting terminal length on $host\n";

## set No Event
$ssh->send("no event");
$ssh->waitfor("#", $timeout) or die "Timeout after turning off event logging on $host\n";

my ($line, $cmd_output );

## Send command based on user type sent

my @run = (@{$cmd_type->{sip}});
push(@run, ($options{type} eq 'all')?
       (@{$cmd_type->{pri}},@{$cmd_type->{analog}}):
       @{$options{type}}
    );
foreach my $cmd (@run){
    $ssh->send($cmd);
    $ssh->waitfor("#", $timeout) or die "Timeout after turning on customer side debugging on $host\n";
}

#unless($options{type} eq 'all'){
#    {
#   
#    $ssh->send($cmd_type->{$options{type}});
# else {
#    $ssh->send($cmd_type->{pri});
#    $ssh->waitfor("#", $timeout) or die "Timeout after turning on customer side debugging on $host\n";
#    $ssh->send($cmd_type->{analog});
#}

#$ssh->waitfor("#", $timeout) or die "Timeout after turning on customer side debugging on $host\n";

print " -> ISDN Debug '$options{type}' mode enabled for $host\n" unless($options{nodebug});

my $stop_at = '';
my $count = 1;
my $s = IO::Select->new();
$s->add(\*STDIN);

my $debug_timeout;
$debug_timeout = $options{timeout};
$debug_timeout = 60 unless($debug_timeout);
my $end_time = time() + $debug_timeout;

print " -> Capturing Debug output for next $debug_timeout secs, enter 'stop' if needed to stop capturing the output'\n" unless($options{nodebug});

while(time() <= $end_time && $stop_at !~ /stop/i){
    #print Dumper($count);
    
    if ($s->can_read(.5)) { 
	chomp( $stop_at = <STDIN>);
	#print "Got '$stop_at' from STDIN\n";
    }
    
    if (($line = $ssh->eat($ssh->peek(1))) ne '' ) {  ## grab chunks of data each sec and eat from input stream
	chomp($line);
	$line =~ s/^\n//;
	## Debug lines , see what's coming from input stream at this sec
	#my $debug_line =  scalar(localtime(time())) . " : $line";
	#print Dumper($debug_line);
	push @$cmd_output, $line;
    }
    
    $count++;
}

if($stop_at =~ /stop/i || $stop_at eq '') {
    print " -> Stopping to capture the debug output\n" unless($options{nodebug});
}
   
if( !defined($cmd_output) || @$cmd_output <= 0 ){
    print " -> No data retrieved.\n" unless($options{nodebug});
    $ssh->send("undebug all");
    $ssh->close();
    exit 3;
}

print " -> Removing debug options\n" unless($options{nodebug});
$ssh->send("undebug all");
$ssh->close();

my $outputfile = '/var/tmp/adtran_output/';
$outputfile .= "${user}_${host}_${timeStamp}";
$outputfile .= '_' . $options{label} if( $options{label} );
$outputfile .=  "_$options{type}.txt";

print " -> Copying the debug output to file : $outputfile\n" unless($options{nodebug});

open (DOUT, ">$outputfile") || die "Cannot write file $outputfile: $!\n";
print DOUT "#Username    : $user\n";
print DOUT "#Device      : $host\n";
print DOUT "#Timestamp   : $timeStamp\n";
print DOUT "#Label       : $options{label}\n" if( $options{label} );
print DOUT "\n\n";
print DOUT join("\n", @$cmd_output);
close(DOUT);

print " -> Output to file completed \n" unless($options{nodebug});

## Chmod world Readable output file
`chmod 666 $outputfile`;
print " -> Output file changed to Readable mode. \n" unless($options{nodebug});

## Create File for adtran password
umask 0077;
my $AdPass = unpack(chr(ord("a") + 19 + print ""),'&861T<F%N');
my $pass_file = "/var/tmp/${user}-adtran.pass";
open (PASS, ">$pass_file") || die "Cannot write file $pass_file: $!\n";
print PASS "$AdPass";
close(PASS);

## Rsync on to the /Opt/Smarts_Shared so that it can be viewed on Unix servers. 
#`rsync -qr --delete /var/tmp/adtran_output svthplv32.twtelecom.com:/opt/smarts_shared/TAC_data/Adtran/production`;
`rsync -qr --delete /var/tmp/adtran_output adtran\@svthplv32.twtelecom.com::adtran-voice --password-file $pass_file`;
print " -> Output file synched to /opt/smarts_shared/TAC_data/Adtran/production on svthplv32. \n" unless($options{nodebug});

unlink $pass_file or warn "Could not unlink $pass_file: $!";;
exit 0;

sub user_password {

    my $user = getpwuid( $< );
    my $home = home();
    my $cloginrc_fn=$home."/\.cloginrc";

    system("/usr/local/bin/cloginmkr");
    open(CLOGINRC, "< $cloginrc_fn") or die "\n: Can't open cloginrc_fn : $cloginrc_fn\n";
    chomp(my @clog = <CLOGINRC>);
    close CLOGINRC;

    my ($pass) = grep { /add password/ } @clog;
    if($pass  =~ /.*add password\s*\*\s*{(.*?)}/i){
        $pass = $1;
    }

    return ($user, $pass);
}

sub help {
    print <<"EOF";
    
    $0 : script to start and stop Adtran voice debug
	
        Syntax : $0 [-help]
        $0 <Adtran Device name> 
	--[type] <in pri, cas, analog or all> 
	--[timeout] <Timeout in secs to capture the debug log, Enter 'Stop' to stop capturing after the debug mode is enabled> 
	--[label] <Label on output file from USER>  
	--[nodebug] <print no debug statments>
	
        --h|host          : Adtran Device name.
        --help            : Print this help message
        --type            : Type of Debug
        --timeout         : Timeout in secs which the debug log times out, Default is 60, Enter 'Stop' to stop capturing after the debug mode is enabled
	--label           : Label on output file from USER
	--nodebug         : Turn off Debug statements 
EOF
    print "\n";
}
