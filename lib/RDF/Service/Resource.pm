#  $Id: Resource.pm,v 1.15 2000/10/20 07:49:15 aigan Exp $  -*-perl-*-

package RDF::Service::Resource;

#=====================================================================
#
# DESCRIPTION
#   The main Resource class. Implement actions accessable by all
#   resources
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
use RDF::Service::Dispatcher;
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( interfaces uri2id list_prefixes
			    get_unique_id id2uri debug );
use Data::Dumper;
use Carp qw( cluck confess croak carp );


sub new_by_id
{
    my( $class, $parent, $id ) = @_;

    # This constructor shouls only be called from get_node, which
    # could be called from find_node or create_node.  get_node will
    # first look in the cache for this resource.

    my $self = bless [], $class;

    if( $parent and (ref($parent) ne 'RDF::Service::Resource'))
    {
#	print "**",ref($parent),"**";
	confess "Called Resource->new($class, $parent, $id)\n";
    }

    $self->[IDS] = $parent ? $parent->[IDS] : '';
    $self->[URISTR] = id2uri($id) or die "No URI for $self";
    $self->[ID] = $id;
    $self->[JTK] = "--no value--";

    return $self;
}

sub new
{
    my( $class, $parent, $uri ) = @_;

    # This constructor shouls only be called from get_node, which
    # could be called from find_node or create_node.  get_node will
    # first look in the cache for this resource.

    my $self = bless [], $class;

    if( $parent and (ref($parent) ne 'RDF::Service::Context'))
    {
#	print "**",ref($parent),"**";
	confess "Called Resource->new($class, $parent, $uri)\n";
    }

    $self->[IDS] = $parent ? $parent->[NODE][IDS] : '';
    $self->[URISTR] = $uri or die "No URI for $self";
    $self->[ID] = uri2id( $self->[URISTR] );
    $self->[JTK] = "--no value--";

    return $self;
}



sub find_prefix_id
{
    my( $self ) = @_;
    #
    # Return the longest prefix in the interface jumptables matching
    # the URI.

#    cluck " *** find_prefix_id *** \n";

    debug "Finding prefix_id for $self->[URISTR]\n", 2;
    foreach my $prefix ( &list_prefixes($self->[IDS]) )
    {
	debug "..Checking $prefix\n", 2;
	if( $self->[URISTR] =~ /^\Q$prefix/ )
	{
	    debug "....Done!\n", 2;
	    return uri2id($prefix);
	}
    }

    die "Prefixlist failed to return at least ''\n";
}

sub init_private
{
    my( $self ) = @_;
    #
    # Set up the private space for all the used interfaces

    # This could be called multipple times

#    cluck " *** init_private *** \n";

    foreach my $interface ( @{interfaces( $self->[IDS] )} )
    {
	$self->[PRIVATE]{$interface->[ID]} ||= {};
    }
}

1;


__END__
