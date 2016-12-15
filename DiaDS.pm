#!/usr/bin/env perl

###################################################################################
##           DIA DS1 Router information parsing through RED CLI 
##           Author : Ravi Kondala
###################################################################################
##           Version : 2.0
##           TCA Errors for Accedian/TELCO NIDS and ESP devices
###################################################################################
##           Version : 3.0
##           CIIT SOAP Service Carrier, Customer Name info parsing.
###################################################################################
##           Version : 4.0
##           "terse" request for the Router posted on the Router Information Tab.
###################################################################################

package Coherence::DiaDS;

use strict;
use warnings;
use Data::Dumper;
use Data::Dumper::HTML qw(dumper_html);
use POSIX qw(strftime);
use LWP::UserAgent;
use HTTP::Request;
use XML::Simple;
use 5.010;

BEGIN {
    push (@INC, "/opt/dev/TAC/trunk/libs");
    push (@INC, "/opt/dev/TAC/trunk/libs/TAC");
    push (@INC, "/opt/dev/TAC/trunk/libs/TAC/conf");
    push (@INC, "/opt/dev/TAC/trunk/libs/Coherence");
}

use Util::Performance;
use Util::Error;
use Helpers;

our @ISA = qw(Exporter);
our @EXPORT = qw(diads1 tca_error_disp fro_response);

#Restful API urls
use Uri;
use vars qw(%uris);
*uris = \%Uri::uris;

our $common;
eval { $common = Helpers->new();};

our $device_intf_info;
our @intf_errors;

##### DIA DS1 Routines

sub diads1 {

    my $request = shift;

    my $device = $request->{'device'};
    my $interface = $request->{'interface'};

    $interface = lc($interface);

    if (!defined($device)) {
        set_error(7, "Module DIA-DS1 is missing required 'device'. Exiting module.");
        return undef;
    }
    
    my $cli;

    if( $device !~ /^(edge|mar|hr|pr)/i) {
	set_error(7, "Module DIA-DS1 recieved Invalid device '$device'. Exiting module.");
        return undef;
    } elsif($device =~ /(edge|mar)/i) {
	$cli = "red";
    } elsif($device =~ /(pr|hr)/i) {
	## Blue device case
	## http://svthdlv12/tacservices/diads1?device=pr1.bos1&interface=t1-2/0/0:1:2

	$cli = "blue";
    }

    $device_intf_info = undef;    

    $interface = lc($interface);
    my $cmd = "tid=$device&cmd=show interfaces $interface extensive";
    my $show_intf_uri = $uris{"cli_${cli}"} . $cmd;
    my $show_intf = $common->json_from_uri($show_intf_uri,"CLI:$cmd");

    if($show_intf !~ /json decode error/i && exists($show_intf->{result}->{response})) {    

	if (grep { /error: device $interface not found/ } @{$show_intf->{result}->{response}}) {
	    push @intf_errors, "device:$device interface:$interface not found";
	} else {	    
	    parse_intf($show_intf->{result}->{response});
	    parse_statistics($show_intf->{result}->{response});
	}

    } else {
	return "No response from CLI Service";
    }
    
    $cmd = "tid=$device&cmd=show interfaces interval $interface";
    my $show_intf_intr_uri = $uris{"cli_${cli}"} . $cmd;
    my $show_intf_intr = $common->json_from_uri($show_intf_intr_uri,"CLI:$cmd");

    if($show_intf_intr !~ /json decode error/i && exists($show_intf_intr->{result}->{response})) {
	if(grep { /interval table not available on this interface: $interface/ } 
	   @{$show_intf_intr->{result}->{response}}) {
	    push @intf_errors, "interval table not available on this interface: $interface";
	} else {
	    parse_intf_interval($show_intf_intr->{result}->{response});
	}
    }
        
    $cmd = "tid=$device&cmd=show interfaces $interface terse";
    my $show_intf_terse_uri =  $uris{"cli_${cli}"} . $cmd;
    my $show_intf_terse = $common->json_from_uri($show_intf_terse_uri,"CLI:$cmd");
    
    if($show_intf_terse!~ /json decode error/i && exists($show_intf_terse->{result}->{response})) {
	if(grep { /error: device $interface not found/ } 
	   @{$show_intf_terse->{result}->{response}}) {	    
	    push @intf_errors, "terse Information not available for interface $interface";
	} else {
	   parse_terse($show_intf_terse->{result}->{response},$interface);
	
	   ## Leaving as it is at the moment as Space issues on parsing
	   #@{$device_intf_info->{terse}} = 
	   #    grep {!(/show interfaces|orancid|^$/) } @{$show_intf_terse->{result}->{response}};
	}
    }
    
    if(@intf_errors) {
	set_error(4, join(", ", @intf_errors),'Processing Error');
    }

    return $device_intf_info;
}

##### Parsing Functions ######
sub parse_terse {
    my ($resp, $interface) = @_;
    
    my (@headers, $index);
     my @fields;
    foreach my $line (@$resp) {
        my $tmp;
	if($line=~/Interface\s+Admin\s+Link\s+Proto\s+Local\s+Remote/){
	    @headers = split('\s+', $line);
	}
	
	if($line =~/^$interface/) {
	    @fields = split('\s+', $line);
	    foreach my $i (0..5){
		next if(!$headers[$i] && !$fields[$i]);
		$tmp->{$headers[$i]} = $fields[$i];
	    }	
	}
        push @{$device_intf_info->{terse}}, $tmp if $tmp;
    }    

}

sub parse_statistics {
    my $resp = shift;

    my @fields = @$resp;

    # Traffic statistics:
    my( $traff_index ) = grep { $fields[$_] =~ /Traffic statistics:/i } 0..$#fields;

    if($traff_index) {
        foreach my $line (@fields[$traff_index + 1 .. $traff_index + 4]) {
            $line =~ s/^\s+//;
            my @tr_st_col = split(':', $line);
            map { $_ =~ s/(^\s+|\s+$)//g} @tr_st_col;
            my @tr_st_sp = split('\s+', $tr_st_col[1]);
            $tr_st_col[0] =~ s/\s+/ /;

            $device_intf_info->{statistics}->{traffic}->{$tr_st_col[0]}->{val} = $tr_st_sp[0];
            $device_intf_info->{statistics}->{traffic}->{$tr_st_col[0]}->{rate} =
                "$tr_st_sp[1] $tr_st_sp[2]";
        }
    }

    # Encapsulation statistics:
    my( $keepalive_index )= grep { $fields[$_] =~ /Keepalive statistics:/i } 0..$#fields;

    if($keepalive_index) {
        foreach my $line (@fields[$keepalive_index + 1 .. $keepalive_index + 2]) {
            $line =~ s/^\s+//;
            my @kp_al_col = split(':\s', $line);
            map { $_ =~ s/(^\s+|\s+$)//g} @kp_al_col;

            my ($val, $last_seen);
            if($kp_al_col[1] =~ /(\d+)\s+\((.*)\)/i){
                $val = $1;
                $last_seen = $2;
            }

            $device_intf_info->{statistics}->{keepalive}->{$kp_al_col[0]}->{val} = $val;
            $device_intf_info->{statistics}->{keepalive}->{$kp_al_col[0]}->{last_seen} = $last_seen;
        }
    }

    #Error statistics: Input and Output
    my( $in_err_index )  = grep { $fields[$_] =~ /Input errors:/i } 0..$#fields;
    my( $out_err_index ) = grep { $fields[$_] =~ /Output errors:/i } 0..$#fields;
    my( $egress_index )  = grep { $fields[$_] =~ /Egress queues:/i } 0..$#fields;

    my $index_counter = $in_err_index + 1;

    if($in_err_index || $out_err_index){
        foreach my $line (@fields[$in_err_index + 1 .. $egress_index - 1]) {
            my $input_output_type;

            if($index_counter > $in_err_index && $index_counter < $out_err_index) {
                $input_output_type = 'Input';
            } elsif($index_counter > $out_err_index && $index_counter < $egress_index ) {
                $input_output_type = 'Output';
            }

            my @Err_fields = split ',' , $line;
            map { $_ =~ s/(^\s+|\s+$)//g} @Err_fields;

            foreach my $field (@Err_fields) {
                my @items = split(':\s',  $field);

                my $err_key;
                if($items[0] =~ /^errors/i){
                    $err_key = "$input_output_type errors";
                } elsif($items[0] =~ /^Drops/i) {
                    $err_key = "$input_output_type drops";
                } elsif($items[0] =~ /^Framing errors/i) {
                    $err_key = "$input_output_type framing errors";
                } elsif($items[0] =~ /^Resource errors/i) {
                    $err_key = "$input_output_type Resource errors";
                } else {
                    next if( $items[0] =~ /:/);
                    $err_key = $items[0];
                }

                $device_intf_info->{statistics}->{errors}->{$err_key} = $items[1];
            }

            $index_counter++;
        }
    }

    #T1 statistics:
    my( $T1_media_index )  = grep { $fields[$_] =~ /T1  media:/i } 0..$#fields;
    my( $HDLC_conf_index ) = grep { $fields[$_] =~ /HDLC configuration:/i } 0..$#fields;

    ##T1  media:            Seconds        Count  State << Headers
    if($T1_media_index){
        foreach my $line (@fields[$T1_media_index + 1 .. $HDLC_conf_index - 1]) {
            $line =~ s/^\s+//;
            my @T1_fields = split '\s+' , $line;
            map { $_ =~ s/(^\s+|\s+$)//g} @T1_fields;

            if($T1_fields[0] =~ /^(BPV|EXZ|LCV|PCV|CS|CRC)$/i){
                $device_intf_info->{statistics}->{T1_media}->{$T1_fields[0]}->{Seconds}
                = $T1_fields[1];
                $device_intf_info->{statistics}->{T1_media}->{$T1_fields[0]}->{Count}
                = $T1_fields[2];
            }
        }
    }

    ## Active Alarms/Defects
    $device_intf_info->{statistics}->{'Active alarms'} =
        $device_intf_info->{interface}->{'DS1   alarms'};
    $device_intf_info->{statistics}->{'Active defects'} =
        $device_intf_info->{interface}->{'DS1   defects'};
}

sub parse_intf_interval {
    my $resp = shift;

    my @fields = @$resp;

    my( $curr_index )= grep { $fields[$_] =~ /-current:/i } 0..$#fields;
    my( $curr_day_index )= grep { $fields[$_] =~ /Current Day Interval Total:/i } 0..$#fields;
    @fields = grep(s/^\s*//g, @fields);
    
    my @intervals = @fields[$curr_index .. $curr_day_index + 1];    
    for(my $i = 0; $i < $#intervals; $i+= 2) {
	push @{$device_intf_info->{interval}}, "$intervals[$i]; $intervals[$i+1]";
    }
}

sub parse_intf {
    my $resp = shift;
    my ($log_intf, $protocol) = 0;

    foreach my $line(@$resp){
        if($line =~ /Physical interface:\s(.*)/i) {
            $device_intf_info->{interface}->{'Physical interface'} = $1;
        }

        if($line =~ /^\s*Interface index/i) {
            my @fields = split(': |,', $line);
            set_field('Interface index', \@fields);
            set_field('SNMP ifIndex', \@fields);
        }

        if($line =~ /(Link-level type|MTU|Clocking|Speed|Loopback|FCS|Framing)/i) {
            my @fields = split(': |,', $line);
            foreach my $key ('Link-level type', 'MTU', 'Clocking', 'Speed',
                             'Loopback', 'FCS', 'Framing') {
                next if($line !~ /$key/i);
                set_field($key, \@fields);
            }
        }

        if($line =~ /Parent:(.*)\sInterface index\s(\d+)/i) {
            $device_intf_info->{interface}->{parent}->{intf} = $1;
            $device_intf_info->{interface}->{parent}->{index} = $2;
        }

        my $regex = 'Device flags|Link flags|Input rate|Output rate|DS1   alarms|' .
            'DS1   defects|Last flapped';

        if($line =~ /($regex)\s*:\s*(.*)/i) {
            $device_intf_info->{interface}->{$1} = $2;
        }

        if($line =~ /Interface flags:(.*)\sSNMP/i) {
            $device_intf_info->{interface}->{'Interface flags'} = $1;
            $device_intf_info->{interface}->{'Interface flags'} =~ s/^\s+//;
        }

        if($line =~ /(Keepalive settings|Keepalive):\s(.*)/i) {
            $device_intf_info->{interface}->{$1} = $2;
        }

        if($line =~ / Logical interface(.*)/i) {
            $log_intf = 1;
            my $info = $1;

            if($info =~ /\s(.*?)\s\(/i){
                $device_intf_info->{interface}->{'Logical interface'}->{intf} = $1;
            }

            if($info =~ /(SNMP ifIndex)\s(\d+)/i){
                $device_intf_info->{interface}->{'Logical interface'}->{$1} = $2;
            }

            if($info =~ /(Index)\s(\d+)/i){
                $device_intf_info->{interface}->{'Logical interface'}->{$1} = $2;
            }
        }

        if($line =~ /Description:\s(.*)/i && $log_intf) {
            $device_intf_info->{interface}->{'Logical interface'}->{Description} = $1;
        }

        if($line =~ /^\s*Flags:\s(.*)\sSNMP/i && $log_intf &&!$protocol) {
            $device_intf_info->{interface}->{'Logical interface'}->{Flags} = $1;
        } elsif($protocol && $line =~ /^\s*Flags:\s(.*)/) {
            $device_intf_info->{interface}->{'Protocol'}->{Flags} = $1;
        }

        if($line =~ /Protocol/i && $log_intf) {
            $protocol++;
            $line =~ s/^\s+//;
            my @fields = split(' |: ', $line);
            set_field('Protocol', \@fields, 'Protocol');
            set_field('MTU', \@fields, 'Protocol');
        }

        if($line =~ /Destination:\s(.*)/i && $log_intf && $protocol) {
            $device_intf_info->{interface}->{'Protocol'}->{Destination} = $1;
        }
    }
}

sub set_field {

    my ($key,$fields,$layer) = @_;

    my @fields = @$fields;
    my( $index )= grep { $fields[$_] =~ /$key/i } 0..$#fields;
    
    unless($layer){
        $device_intf_info->{interface}->{$key} = $fields[$index + 1];
    } else {
        $device_intf_info->{interface}->{$layer}->{$key} = $fields[$index + 1];
    }
}

##### Hiper TCA Errors for RED Network Routines
### http://svthdlv12/tacservices/tca_error_disp?device=ESP1.MIA1&interface=4/2/7
sub tca_error_disp {
    
    my $request = shift;
    my $device = $request->{'device'};
    my $interface = $request->{'interface'};

    my $result;
    if (!defined($device)) {
        set_error(7, "Module TCA Error is missing required 'device'. Exiting module.");
        return undef;
    }

    if( $device !~ /^(nid|esp)/i) {
        set_error(7, "Module TCA Error recieved Invalid device '$device'. Exiting module.");
        return undef;
    }

    if ( $device =~ /^esp/i && !defined($interface)) {
        set_error(7, "Module TCA Error is missing required 'Interface'. Exiting module.");
        return undef;
    }

    if( $interface && $interface !~ /^(client|network|^\d)/i) {
        set_error(7, "Module TCA Error recieved Invalid Interface '$interface'. Exiting module.");
        return undef;
    }

    my ($device_status, $nid_type) = check_interf_device($device);

    unless($device_status) {
	$result->{$device} = '';
	return $result;
    }
    
    my $count = 0;
    if ($device =~ /^nid/i ){	

      REEXECUTE:
	if($count == 0){
	    if($nid_type =~ /accedian/i) {	
		$interface = 'client'; 
	    } elsif($nid_type =~ /telco/) {
		unless($interface) {
		    set_error(4, "No Interface for TELCO, provide Client Interface. Exiting module.");
		    $result->{$device} = '';
		    return $result;
		}		
	    }
	} elsif($count == 1) {
	    if($nid_type =~ /accedian/i) {
		$interface = 'network';
	    } else {
		$interface = '1/3/1';
	    }
	    
	} else {
	    goto DONE;
	}
    } else {
	$count = 2;
    }

    $result = hiper_TCA_15_24_device_intf($device, $interface, $result);
    $count++;
    goto REEXECUTE if($count < 2);
  DONE:
    return $result;
}

sub hiper_TCA_15_24_device_intf {

    my ($device, $interface, $result) = @_;

    $device =~ s/.mgmt.level3.net//g;

    my $hiper_end = time();
    my $hiper_start = $hiper_end - 15;

    my $parms = "?domain=red%20networks&device=$device&interface=$interface";
    my $uri = $uris{hiper_tca_error} . $parms;
    my $json = $common->json_from_uri($uri,"Hiper TCA error stats for $device & $interface");
 
    if($json !~ /json decode error/i && @{$json->{data}} && exists($json->{data}->[0]->{value})) {
	$result->{$device}->{ucfirst($interface)}->{disposition}->{'24hrs'} =
	    disp_code_txt($json->{data}->[0]->{value});	
    } else {
	set_error(4, "Response error for call $uri", "Processing Error");
    }

    my $uri_15mins = $uri . "&minimum=$hiper_start&maximum=$hiper_end";
    $json = $common->json_from_uri($uri_15mins,
				   "Hiper TCA error stats for $device & $interface for 15 mins");

    if($json !~ /json decode error/i && @{$json->{data}} && exists($json->{data}->[0]->{value})) {
	$result->{$device}->{ucfirst($interface)}->{disposition}->{'15mins'} =
	    disp_code_txt($json->{data}->[0]->{value});	
    } else {
	set_error(4, "Response error for call $uri_15mins", "Processing Error");
    }

    return $result;
}

sub check_interf_device {
    my $device = shift;

    $device =~ s/.mgmt.level3.net//g;

    my $uri = "http://insutildlv11.twtelecom.com/hiper/v3/domains/network/view/devices/" . 
	"interfaces_by_device?device=$device&domain=red%20networks";

    my $json = $common->json_from_uri($uri,"Hiper Check Device for error stats on $device", 10);

    my ($status, $Type);

    if($json !~ /json decode error/i && scalar(@{$json->{data}}) > 0) {	
	$status = 1;
	if($device =~ /^nid/i) {
	    foreach my $interfHash (@{$json->{data}}) {
		if($interfHash->{port} =~ /(Client|Network)/i) {
		    $Type = 'accedian';
		} else {
		    $Type = 'telco';
		}
	    }	    
	}	
    }    

    return  ($status, $Type);
}

sub disp_code_txt {
    my $val = shift;

    my $rtext;
    if ($val < 6) {$rtext = "PASS";}
    elsif ($val < 26) {$rtext = "MINOR FAIL";}
    elsif ($val < 73) {$rtext = "MAJOR FAIL";}
    elsif ($val < 145) {$rtext = "CRITICAL FAIL";}
    else {$rtext = "EPIC FAIL";}

    return $rtext;
}

##### FRO
sub fro_response {

    my $request = shift;
    my $froID = $request->{froid};

    if (!defined($froID)) {
        set_error(7, "Module FRO Response is missing required 'fro ID'. Exiting module.");
        return undef;
    }

    my $message = frorequest($froID);

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);

    my $WSDL = 'http://ciit-prod-new:9090/ciit-services/services/circuitSearch?wsdl';
    my $req = HTTP::Request->new(POST => $WSDL);

    $req->content($message);
    $req->content_type("text/xml; charset=utf-8");
    my $resp = $ua->request($req);

    my $xml_hash;
    if($resp->code == 200) {
        $xml_hash = XMLin($resp->decoded_content);
    }else {
        set_error(7, "SOAP XML Error on $WSDL: $resp->message");
        return undef;
    }

    my ($result, @ipRoots, $filteredHash);

    if($xml_hash->{'soap:Body'}->{'ns2:getCircuitsRelatedToCircuitResponse'}->
       {'circuitRelatedToCircuit'}->{'ipRoots'}){

        my $ipRootsFromXML = $xml_hash->{'soap:Body'}->{'ns2:getCircuitsRelatedToCircuitResponse'}->
        {'circuitRelatedToCircuit'}->{'ipRoots'};

        if(ref($ipRootsFromXML) eq "ARRAY") {
	    @ipRoots = @$ipRootsFromXML;
        } else {
            push @ipRoots, $ipRootsFromXML;
        }
	
	if(scalar(@ipRoots) == 1 ) {	    
	    $filteredHash->{$ipRoots[0]->{ipDevice}}->{device} = $ipRoots[0]->{ipDevice};
	    $filteredHash->{$ipRoots[0]->{ipDevice}}->{interface} = $ipRoots[0]->{ipInterface};
	    $filteredHash->{$ipRoots[0]->{ipDevice}}->{carrier} = $ipRoots[0]->{carrier};
	    $filteredHash->{$ipRoots[0]->{ipDevice}}->{customerName} = 
		$ipRoots[0]->{customerName};
	} else {
	    foreach my $set (@ipRoots) {
		
		next if(ref($set->{ipDevice}) eq "HASH");
		next if($set->{ipDevice} =~ /GM/i);

		## Check here if the device is same on data sets. 
		#$filteredHash->{$set->{ipDevice}}->{label}  = 'interfaces';
		$filteredHash->{$set->{ipDevice}}->{$set->{ipInterface}}->{device} = 
		    $set->{ipDevice};
		$filteredHash->{$set->{ipDevice}}->{$set->{ipInterface}}->{interface} = 
		    $set->{ipInterface};
		$filteredHash->{$set->{ipDevice}}->{$set->{ipInterface}}->{carrier} = 
		    $set->{carrier};
		$filteredHash->{$set->{ipDevice}}->{$set->{ipInterface}}->{customerName}
		    = $set->{customerName};
	    }
	}

	##$result->{ipRoots} = $ipRootsFromXML;
    }

    foreach my $device (keys %$filteredHash) {
	my $tmp->{device} = $device;			
	foreach my $interface (keys %{$filteredHash->{$device}}){
	    push @{$tmp->{interfaces}}, $filteredHash->{$device}->{$interface};
	}
	
	push @{$result->{data}}, $tmp;
    }    

    return $result;
}

sub frorequest {

    my $FROId = shift;

    my $message = '<soapenv:Envelope
          xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:ser="http://level3.com/noctools/ciit/service">
    <soapenv:Header/>
    <soapenv:Body>
      <ser:getCircuitsRelatedToCircuit>
         <!--Zero or more repetitions:-->
         <circuit>' . $FROId  . '</circuit>
         <!--Zero or more repetitions:-->
         <networkSourceId>5</networkSourceId>
         <networkSourceId>8</networkSourceId>
         <networkSourceId>9</networkSourceId>
         <networkSourceId>10</networkSourceId>
         <networkSourceId>12</networkSourceId>
         <!--Zero or more repetitions:-->
         <serviceSourceId>1</serviceSourceId>
         <serviceSourceId>2</serviceSourceId>
         <serviceSourceId>3</serviceSourceId>
         <serviceSourceId>4</serviceSourceId>
         <serviceSourceId>5</serviceSourceId>
         <serviceSourceId>6</serviceSourceId>
         <serviceSourceId>7</serviceSourceId>
         <serviceSourceId>8</serviceSourceId>
         <serviceSourceId>9</serviceSourceId>
         <serviceSourceId>10</serviceSourceId>
         <serviceSourceId>11</serviceSourceId>
         <serviceSourceId>12</serviceSourceId>
         <serviceSourceId>13</serviceSourceId>
         <serviceSourceId>14</serviceSourceId>
         <serviceSourceId>15</serviceSourceId>
         <!--Zero or more repetitions:-->
           <ipSourceId>1</ipSourceId>
         <ipSourceId>2</ipSourceId>
         <ipSourceId>3</ipSourceId>
         <ipSourceId>4</ipSourceId>
         <ipSourceId>5</ipSourceId>
         <ipSourceId>6</ipSourceId>
         <ipSourceId>7</ipSourceId>
         <ipSourceId>8</ipSourceId>
         <ipSourceId>9</ipSourceId>
      </ser:getCircuitsRelatedToCircuit>
   </soapenv:Body>
</soapenv:Envelope>';

    return $message;
}


1;
