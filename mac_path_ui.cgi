#!/usr/bin/env perl

###############################################################################################
##
## CGI page for Mac path Validation(MPV). Circuit decomposition on MPV between 
## Edge to Aggregation,  find legs and compare legs on Edge to Edge.
## 
## Author : Ravi Kondala
##
###############################################################################################

use warnings;
use strict;
use CGI qw/:standard/;
use CGI::Carp qw/warningsToBrowser fatalsToBrowser/; ### Useful for Debugging, Turn off when not in use
use Data::Dumper;
use Data::Dumper::HTML qw(dumper_html);
use LWP::Simple qw(!head);;
use JSON;

BEGIN {
    push (@INC, "/opt/dev/TAC/trunk/libs" , "/opt/dev/TAC/trunk/libs/TAC/conf");
    push (@INC, "/var/www/cgi-bin/libs/Util");
}

use Util::CGIUtils;
use Uri;

use vars qw(%uris);
*uris = \%Uri::uris;

## $| = 1;

#Globals
our $cgi = CGI->new;
our $host =  $cgi->url(-base =>1) ;
our $circuit = $cgi->param('circuit');
our $utils =  Util::CGIUtils->new();
our $coh_host = $uris{coh_host};

print $cgi->header;

my $jScript=<<jEND;
function logChecked(){
    var d=document.getElementById('Debug_');
    var cb=document.getElementById("log_cb");
    if (d != null){
        d.style.display=(cb.checked)?(d.style.display == "none")?"":"none":"none";
    }
}
jEND
    
print $cgi->start_html(
    -title=>"Metro Ethernet Path Validation", 
    -style => { -src => '/TAC_style.css'},
    -script=>$jScript,
    -onload=>"logChecked()"
    );

print $cgi->start_table({-align => 'center',-class => 'noborder' });
print $cgi->Tr(
    $cgi->td({-align => 'center'},
	     $cgi->img({-src => '/Level3Logo.jpg', -alt => 'Level(3)'}))
    );
print $cgi->end_table;
print $cgi->h1({-align => 'center', -style=>'color:  Green ; font-family: Arial ;'},"Metro Path Validation/Find Legs");

$circuit =~ s/^\s+//g if($circuit);
$circuit =~ s/\s+$//g if($circuit);

if ($circuit  &&  $circuit !~ /^\w{2}\/\w{4}\/\d{6}\/\w{4}$/){
    print $cgi->h3({-align => 'center', -style=>'font-family: Arial', },"Path Validation Invalid Circuit : '$circuit'");
    exit;
}

if(scalar $cgi->param('circuit') && $cgi->param('pathval') eq 'FindLeg') {
    findlegs();
} elsif ( $cgi->param('pathval') && scalar $cgi->param('pathval') eq 'Edge2Agg') {    
    edge2agg();
} elsif(scalar $cgi->param('compare_submit')){    
    compare_legs();
} else {
    show_main_form();
}

sub compare_legs {

    print $cgi->h1({-align => 'center', -style=>'color:  Green ; font-family: Arial ;'},"Layer 2 Path Continuity Edge to Edge Legs");

    if(scalar($cgi->param()) != 3) {	
	print $cgi->h4({-align => 'center', -style=>'color: Red'}, "Selected " .  eval(scalar($cgi->param()) - 1) . " Sites, Please select 2 sites to compare");
	exit;
    }

    print $cgi->br;

    print "<CENTER>",  checkbox (
        -name=>'log',
        -id=>'log_cb',
        -value=>'ON',
        -label=>'log',
        -onclick=>'logChecked()'
        ) ;

    print $cgi->br;     print $cgi->br;
        
    my @compare_ids = grep(!/compare_submit/, $cgi->param());    
    my $compare_ids = join("," , @compare_ids);
    
    my @siteAinfo = split(/\|/, $compare_ids[0]);
    my @siteBinfo =  split(/\|/, $compare_ids[1]);

    my $siteA = $siteAinfo[0]; my $siteB = $siteBinfo[0];

    my $uri =  $coh_host . "comparelegs?circuits=$compare_ids";

    #To debug JSON Errors : flip the commenting on the next two lines.
    my $cmp_data = $utils->json_from_uri($uri, "Metro Path Validation - Compare legs for Circuits $compare_ids");
    #my $cmp_data = 'json decode error';

    if( $cmp_data !~ /json decode error/i && $cmp_data->{result}->{data} && $cmp_data->{result}->{error}->{detail} !~ /No response from coherenced/i){
	
	create_table("MAC Path Validation - Edge to Edge Comparision");
	
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Site A"), $cgi->td($siteA));
        print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Site B"), $cgi->td($siteB));
        
	my $style;

	if($cmp_data->{result}->{data}->{SiteA2B}->{result} =~ /pass/i){
	    $style = 'color: ForestGreen';
	} else {
	    $style = 'color: red';
	}

        print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "SiteA2B Result"), $cgi->td({-align => 'center', -style => $style}, $cmp_data->{result}->{data}->{SiteA2B}->{result}));

	$style = undef;

	if($cmp_data->{result}->{data}->{SiteB2A}->{result} =~ /pass/i){
	    $style = 'color: ForestGreen';
	} else {
	    $style = 'color: red';
	}

	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "SiteB2A Result"), $cgi->td({-align => 'center', -style => $style}, $cmp_data->{result}->{data}->{SiteB2A}->{result}));

	my (@dispositionMessage) = split(/\,/, $cmp_data->{result}->{data}->{dispositionMessage});
	my $dispositionMessage = join("<br>",@dispositionMessage);
    
        print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Disposition"), $cgi->td( $dispositionMessage));
	print $cgi->end_table;
        print $cgi->br;


	print $cgi->start_div({id=>'Debug_', style=>'display:none'});
	print $cgi->br;
	print"<P><HR><P><P>";

	print "<CENTER><BR><b>Log info</b>";
	print $cgi->br;
	print $cgi->br;

	$Data::Dumper::Indent = 1;

	print $cgi->start_form({-id => 'log_output', -method => 'GET'});
	print $cgi->textarea( {-name => 'LOG_OUTPUT' , -readonly => "readonly", -default => Dumper($cmp_data), -rows => 70, -columns => 120}) ;
	print $cgi->end_form();

	print $cgi->end_div;
    } else { #if there was an error
       my @msg = ('Mac Path Validation -> mac_path_ui ->' );
       CASE:{
          if ($cmp_data=~/json decode error/i){
              push(@msg, "JSON Decode Error."); last CASE;
          } 
          if (! exists $cmp_data->{result}->{data}){                                           
            push(@msg, "No data returned for this comparison.");
          }
          if ($cmp_data->{result}{error}{detail}=~/No response.*coherenced/i){
             push(@msg, "No response from coherenced.")
          }; 
       } 
               
       printf STDOUT "\n<script> try {\npostMessage('" . join(" ", @msg) . "',".
            "'red');\n}catch(err){\nconsole.log('Could not find postMessage to ".
            "report the following error:" .join(" ",@msg). "');\n }</script>\n";
    }
}

sub findlegs {

    print $cgi->h1({-align => 'center', -style=>'color:  Green ; font-family: Arial ;'},"Layer 2 Path Continuity Edge to Edge Legs");

    show_main_form();

    my $uri = $coh_host . "findlegs?circuit=$circuit";
    my $json = $utils->json_from_uri($uri, "Metro Path Validation Find legs for Circuit +$circuit");

    if( $json !~ /json decode error/i && $json->{result}->{data} && $json->{result}->{error}->{detail} !~ /No response from coherenced/i){

	print $cgi->h2({-align => 'center', -style=>'color: #CD853F ; font-family: Arial ;'},"$circuit has following site list");	
	print $cgi->h3({-align => 'center', -style=>'color: #4169E1 ; font-family: Arial ;'},"Select any two Sites to compare Edge to Edge");	

	print $cgi->start_form({-name => 'site_compare'});

	create_table("Leg Summary for circuit : $circuit", 'fullwid');
	print $cgi->Tr(

	    $cgi->td( {-class => 'col-hd'}, "Site Number"),
	    $cgi->td( {-class => 'col-hd'}, "Circuit"),
	    $cgi->td( {-class => 'col-hd'}, "Hostname"),
	    $cgi->td( {-class => 'col-hd'}, "Interface"),
	    $cgi->td( {-class => 'col-hd'}, "Vlan"),
	    $cgi->td( {-class => 'col-hd'}, "Description"),
	    $cgi->td( {-class => 'col-hd'}, "Service Address"),
	    $cgi->td( {-class => 'col-hd'}, "Status"),
	    );

	print "<CENTER>";
	my $i = 1;
	
	foreach my $site (@{$json->{result}->{data}->{vlanslist}}) {
	    
	    my @site_rows;
	    
	    my $colour=(($i%2) != 0)?'plain':'alt';
	    
	    push @site_rows, $cgi->Tr({-class=>$colour, -valign=>'TOP'});
	    
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px;'},"Site $i");

	    my $check_box_value = "$site->{circuit}|$site->{hostname}|$site->{interface}";
	    if($site->{status} =~ /up/i ) {		
		push @site_rows, $cgi->td( {  -class=>$colour, -style=> 'font-size:13px; color: Green; min-width:180px;'}, 
					   $cgi->checkbox(-name =>  $check_box_value, -label => $site->{circuit}));
	    } else {
		push @site_rows,  $cgi->td( { -class=>$colour, -style=> 'font-size:13px; color: red; min-width:180px;'},  
					    $cgi->checkbox(-name => $check_box_value, -label => $site->{circuit}, -checked => 0, -disabled => 'disabled'));
	    }
	    
	    #replace commas with a comma-space when between vlan numbers.  This is 
	    #so that is will look nicer on the screen.
	    (my $formatted_vlans = $site->{vlan})=~s/,(\d)/, $1/g;
	    
	    #format Service address to look a little nicer.
	    my (@servAddress)=split(/\,/, $site->{ServiceAddress});         
	    if ($#servAddress > 2){
		my ($cityStateZip)=join(", ", splice(@servAddress,-3,3));
		push(@servAddress,$cityStateZip);
	    }         
	    my $prettyServiceAddress=join("<br>",@servAddress);
	    
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px;'}, $site->{hostname});
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px;'}, $site->{interface});
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px; min-width:60px; max-width:80px'},$formatted_vlans);
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px; min-width:500px'},$site->{description});
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px; min-width:200px'},$prettyServiceAddress);	   
	    push @site_rows, $cgi->td( { -class=>$colour, -style=> 'font-size:13px;'},$site->{status});	    
	    print @site_rows;
	    $i++
	}	    
	
	print $cgi->end_table;
	print $cgi->param('site_compare');
	print $cgi->p({-align=>'center'}, $cgi->submit({-name=>'compare_submit', -value => 'Compare Edge to Edge'}, ) , $cgi->reset());
	print $cgi->end_form();	
	
	print $cgi->param('site_compare');
	
    } else {
	print $cgi->h3({-align => 'center', -style=>'font-family: Arial', },"No Response from Find Legs service");
    }
}

sub edge2agg {

    print $cgi->h1({-align => 'center', -style=>'color:  Green ; font-family: Arial ;'},"Customer MAC at MetroEdgePI to MetroAgg");

    if($ENV{HTTP_REFERER} && $ENV{HTTP_REFERER} =~ /tac-analyzer.cgi/i){  ## check if Caller service is TACA, If so dont display the Input field
	show_main_form(1);
    } else {
	show_main_form();
    }
    
    my $uri =  $coh_host . "metropathval?circuit=$circuit&allAgg=1&nomgmt=1";

    #foreach (@check_on){
	#$uri .= "&$_=1";
    #}

    my $json = $utils->json_from_uri($uri, "Metro Path Validation for Circuit +$circuit");
    
    if( $json !~ /json decode error/i ||
	ref($json) eq "HASH" &&
	defined($json->{result}->{error}->{detail}) &&  
	$json->{result}->{error}->{detail} !~ /No response from coherenced/i 
	) {
	
	create_table("MAC Path Validation Summary for circuit : $circuit");
	
	my ($style, $disposition_summary) = get_style($json->{result}->{data}->{dispositionSummary});
	
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Circuit ID"), $cgi->td($json->{result}->{data}->{circuit}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Customer"), $cgi->td($json->{result}->{data}->{customerName}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Account Number"), $cgi->td($json->{result}->{data}->{acctno}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Service Type"), $cgi->td($json->{result}->{data}->{serviceType}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Service Address"), $cgi->td($json->{result}->{data}->{ServiceAddress}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Metro Edge"), $cgi->td($json->{result}->{data}->{metroEdge}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Metro Edge Interface"), $cgi->td($json->{result}->{data}->{metroEdgePI}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Metro Aggregate(s)"), $cgi->td($json->{result}->{data}->{metroAggs}));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Vlan(s)"), $cgi->td($json->{result}->{data}->{VlansValidated}));

	if($json->{result}->{data}->{dispositionMessage} && 
	   $json->{result}->{data}->{dispositionMessage} =~ /^no/i){
            $style = 'text-align:center; color: #FF0000; font-weight:bold;';
        } else {
            $style = 'text-align:center; color: #009900; font-weight:bold;';
        }

        ## print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Disposition Code"), $cgi->td({-style =>$style},$json->{result}->{data}->{dispositionCode}));
        print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Disposition"), $cgi->td({-style =>$style}, $json->{result}->{data}->{dispositionMessage}));

	my ($sum_style), $disposition_summary = get_style($json->{result}->{data}->{dispositionSummary});
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Disposition Summary"), $cgi->td({-style =>$sum_style}, $disposition_summary));
	print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Runtime"), $cgi->td($json->{result}->{data}->{"Run time"}));

	my $comments = "For highest confidence please run again if mac not seen in Aggregates, Mac tables may have been out of sync.";
        if($disposition_summary && $disposition_summary =~ /Paths for none of the vlans validated/i &&  $json->{result}->{data}->{metroAggs} =~ /\w{8}9K\d{3}/){
            print $cgi->Tr( $cgi->td({-class => 'col-hd'}, "Additional Comments"), $cgi->td($comments));
        }

	print $cgi->end_table;
	print $cgi->br;

	print $cgi->start_div({id=>'Debug_', style=>'display:none'});
	print $cgi->br;
	print"<P><HR><P><P>";
	
	print "<CENTER><BR><b>Log info</b>";
	print $cgi->br;
	print $cgi->br;
	
	$Data::Dumper::Indent = 1;
	
	print $cgi->start_form({-id => 'log_output', -method => 'GET'});
	print $cgi->textarea( {-name => 'LOG_OUTPUT' , -readonly => "readonly", -default => Dumper($json), -rows => 70, -columns => 120}) ;
	print $cgi->end_form();

	print $cgi->end_div;
    } else {
	print $cgi->h3({-align => 'center', -style=>'font-family: Arial', },"No Response for Circuit : '$circuit'");
        exit;
    }
}

sub get_style {
    
    my $disposition_summary = shift;    
    my $style;

    if( $disposition_summary && $disposition_summary =~ /Paths for all vlans validated/i) {	    
	$style = 'text-align:center; color: #009900; font-weight:bold;';
    } elsif($disposition_summary && $disposition_summary =~ /Paths for none of the vlans validated/i){
	$style = 'text-align:center; color: #FF0000; font-weight:bold;';	 	    
    } elsif($disposition_summary && $disposition_summary =~ /Some but not all vlan paths validated/i){
	$style = 'text-align:center; color: #A0522D; font-weight:bold;';
    } elsif($disposition_summary && $disposition_summary =~ /overture/i ) { 
	$style = 'text-align:center; color: #686868 ; font-weight:bold;'; 	    
	$disposition_summary =~ s/Exiting module\.//i;
    }
    
    return ($style, $disposition_summary);
}

sub create_table {

    my ($header, $class) = @_;

    print $cgi->start_table( {-align => 'center', -class => $class });
    print $cgi->th({ -colspan => 20, -style=> 'font-size:20px;'}, "$header") if($header);
}

sub show_main_form {

    my $limit = shift;
    
    print $cgi->start_form({-id => 'main_form', -style=>'font-family: Arial', -method => 'POST'});

    unless($limit) {

	print $cgi->h4({-align => 'center', -style => 'color: #A0522D'}, 
		       "Select FindLeg to find all the Edge Site information, Select Edge2Agg for Metro path validation from Edge to Aggregate.");	
	
	print "<CENTER><BR><b>CIRCUIT ID :&nbsp&nbsp</b>";
	print $cgi->textfield( -name => 'circuit' , -size => 20, -maxlength => 20);
	print "&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp&nbsp";
	
	my $select_ref = {
	    'FindLeg' => 'FindLeg',
	    'Edge2Agg' => 'Edge2Agg',
	};

	print "<b>Path Validate : &nbsp&nbsp</b>";
	print $cgi->Tr(
	    $cgi->td({-align => 'center', -style=>'font-family: Arial' },
		     popup_menu(
			 -name    => 'pathval',
			 -values => ['FindLeg','Edge2Agg'],
			 -default=>['Edge2Agg',],
			 -labels  => $select_ref,
		     )
	    )
	    );       
	
	print $cgi->br ;	print $cgi->br ;
	
	my %labels = (
	    'nomgmt' => 'nomgmt',
	    'allAgg' => 'allAgg',
	    );
	
=pod
	print checkbox_group(-name=>'check_parms',
			     -values => ['allAgg', 'nomgmt'],
			     -linebreak=>'true',
			     -default=>['nomgmt','allAgg'],
			     -labels => \%labels,	
	    ) ;	
=cut	
    }
    
    print "<CENTER>",  checkbox (
	-name=>'log',
	-id=>'log_cb',
	-value=>'ON',
	-label=>'log',
	-onclick=>'logChecked()'
        ) ;
    
    unless($limit){
	print $cgi->br , $cgi->br;	
	print $cgi->submit({-name=>'param_sub', -value => 'Submit' } ),  "&nbsp&nbsp" , $cgi->reset();
	print $cgi->end_form();
    }	

    print $cgi->br;
    print $cgi->br;    
}
