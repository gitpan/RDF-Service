#  $Id: Service.pm,v 1.6 2000/09/24 16:53:32 aigan Exp $  -*-perl-*-

package RDF::Service;

#=====================================================================
#
# DESCRIPTION
#   Creates the Service resource
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2000 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use 5.006;
use RDF::Service::Constants qw( :rdf :namespace );
use RDF::Service::Cache qw( get_unique_id uri2id );
use RDF::Service::Resource;
use Data::Dumper;

our $VERSION = 0.01;

our $DEBUG = 0;


sub new
{
    my( $class, $uristr ) = @_;

    # This will (then implemented) create a session context resource.
    # This resource will hold a orderd list of connected interfaces.
    # A signature will be generated from this order.  Every created
    # object will be marked with this signature.  The object will be
    # cached and can be used again if a object with the same signature
    # is creating the same object.

    # This means that all the objects functions and information is
    # only dependent on the order of the connected interfaces. This
    # also means that for each resource there could be one object for
    # each signature. They are the same resource, but viewed from
    # diffrent contexts, they appear diffrent in regard to the result
    # of queries, etc.

    # Many queries will probably give the same answer for diffrent
    # signatures, but that could not be guaranteed.  This construction
    # is based on the asumption that there will be many agents using
    # the same signature. That is: the same object will be reused more
    # times than not.  For futher optimization, some data could be
    # shared between diffrent objects for the same resource. Data
    # could be marked as static or dynamic and new objects could point
    # to the data for the previous object, if its marked as static.

    # Interfaces connected after the creation of an object will not
    # change the objects signature. The objects signature is a read
    # only value.  The first interface connection parameter is taken
    # to be the URI of the source accessed by the interface. This URI
    # is a part of the signature. (That is, the connection string to a
    # database, or similar.)

    # All context/client-dependent functions should use the session
    # object methods or send it in as a parameter. This construction
    # is a compromise to shorten the method calls in most cases, so
    # that we doesn't have to tag along the context varaible evrywhere
    # and so that we still can reuse the cached resource objects
    # between more than one session.

    if( $uristr )
    {
	# Must have a Service URI as recognized by the Base find_node

	my $pattern = "^".NS_L."/service/[^/#]+\$";
	unless( $uristr =~  /$pattern/ )
	{
	    die "Invalid namespace for Service";
	}
    }
    else
    {
	# Every service object is unique
	#
	$uristr = NS_L."/service/".&get_unique_id;
    }

    my $s = RDF::Service::Resource->new('', $uristr);

    $s->[INTERFACES] = [];
    # We would have called $s->init_private(), if there would be
    # anything to init.

    # The service object is not stored in any interface.  The base
    # interface init_types function states that all resources matching
    # a specific pattern are Service objects.  That is needed since
    # the resources acts as models for other models stored in other
    # interfaces.  But here we state the types for the newly created
    # Service object.

    # Declare the types for the service
    #
    my $c_Resource = $s->get_node(NS_RDFS.'Resource');
    my $c_Model = $s->get_node(NS_L.'Model');
    my $c_Service = $s->get_node(NS_L.'Service');
    my $types = [$c_Service, $c_Model, $c_Resource];
    $s->declare_self( $s, $types );


    &_bootstrap( $s );

    return $s;
}

sub _bootstrap
{
    my( $s ) = @_;
    #
    # Connect the base interface.

    warn "Bootstrap\n" if $DEBUG;


    my $module = "RDF::Service::Interface::Base::V01";

    my $file = $module;
    $file =~ s!::!/!g;
    $file .= ".pm";
    require "$file";

    {   no strict 'refs';
	&{$module."::connect"}( $s, undef, $module );
    }

}

1;

