#!/usr/bin/perl -w
use 5.006;
use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use RDF::Service;
use RDF::Service::Constants qw( :all );
use Data::Dumper;

#our $DEBUG = 1;

$|=1;
warn "Starting test program\n";

# Create the service object. It's a type of #model
#
my $s = new RDF::Service( NS_L."/service/R1" );

print "IDS: $s->[IDS]\n";

# Most operations requires that some interface exist to handle the
# RDFS The connection should store the interface in the $rdf object
#
my $rdfs = $s->connect("RDF::Service::Interface::Schema::RDFS_200001");

print "IDS: $s->[IDS]\n";

#print "***".$rdfs->uri."\n";


# Connect to a general purpose interface. The connect string is part
# of the uri
#
my $i_dbi = $s->connect("RDF::Service::Interface::DBI::V01",
			{
			    connect => "dbi:Pg:dbname=wraf_v01a",
			    name =>    "wwwdata",
			});

print "IDS: $s->[IDS]\n";

# Create a new model
my $model = $s->get_model(NS_L.'#M1');


#exit;
#die Dumper( $model );


my $subj = $s->get_node(NS_L.'#S1');

#my $pred = $s->get_node(NS_L.'#P1');
#my $obj = $s->get_node(NS_L.'#O1');
#$model->add_arc(NS_L.'#A1', $pred, $subj, $obj);

print "\n\nAnd here comes the properties of $subj->[URISTR]:\n";
foreach my $prop ( @{$subj->get_props_list} )
{
    my $objs = $subj->get_objects_list($prop);
    print "\t$prop->[URISTR]:\n";
    foreach my $obj ( @$objs )
    {
	print "\t\t", $obj->desig, "\n";
    }
}


print "\n";

