#  $Id: V01.pm,v 1.9 2000/09/24 16:53:33 aigan Exp $  -*-perl-*-

package RDF::Service::Interface::Base::V01;

#=====================================================================
#
# DESCRIPTION
#   Interface to the basic Resource actions 
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
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( generate_ids uri2id );
use URI;
use Data::Dumper;

our $DEBUG = 0;


sub register
{
    my( $interface ) = @_;

    return
    {
	'' =>
	{
	    NS_L.'Service' =>
	    {
		'connect' => [\&connect],
		'find_node' => [\&find_node],
	    },
	    NS_L.'Model' =>
	    {
		'list_arcs' => [\&list_model_arcs],
	    },
	    NS_RDFS.'Literal' =>
	    {
		'desig' => [\&desig_literal],
	    },
	    NS_RDFS.'Resource' =>
	    {
		'desig' => [\&desig_resource],
#          'init_types' => [\&init_types],
		'delete' => [\&delete_node],
	    },
	},
	NS_L."/service/" =>
	{
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&service_init_types],
	    },
	},
    };
}


sub connect
{
    my( $self, $i, $module, $args ) = @_;

    # Create the interface object. The IDS will be the same for the
    # RDF object and the new interface object.  Old interfaces doesn't
    # get their IDS changed.

    # A Interface is a source of statements. The interface also has
    # special metadata, as the type of interface, its range, etc.  The
    # main property of the interface is its model that represents all
    # the statements.  The interface can also have a collection of
    # literals, namespaces, resource names and other things.


    my $uri = _construct_interface_uri( $module, $args );

    # Create the new interface resource
    #
    my $ni = RDF::Service::Resource->new($self, $uri);

    $ni->[MODULE_NAME] = $module; # Should we also save the args?
    $RDF::Service::Cache::node->{$self->[IDS]} = {};
    push @{$self->[INTERFACES]}, $ni;
    $self->[IDS] = $ni->[IDS] = generate_ids($self->[INTERFACES]);

    $self->init_private;

    # Purge the existing Service jumptable, because of the changed IDS
    #
    $self->[JUMPTABLE] = undef;

    # Initialize  with the updated IDS
    #
    $ni->init_private();

    # OBS: The TYPE creation must wait. The type object depends on the
    # RDFS interface object in the creation. So it can't be set until
    # the RDFS interface has been created. The TYPE value will be set
    # then needed.

    # This is the functions offered by the interface. Pass on the
    # interface initialization arguments.
    #
    my $file = $module;
    $file =~ s!::!/!g;
    $file .= ".pm";
    require "$file" or die $!;

    warn "Registring $file\n" if $DEBUG;
    {   no strict 'refs';
	$ni->[MODULE_REG] = &{$module."::register"}( $ni, $args );
    }
    return( $ni, 1 );
}

sub _construct_interface_uri
{
    my( $module, $args ) = @_;

    # Generate the URI of interface object. This will have to
    # change. The URI should be known or availible by request. Not
    # guessed.  Make a clear distinction between the interface module
    # resource and the interface resource returned from a connection.
    #
    my $uri = URI->new("http://cpan.org/rdf/module/"
		       . join('/',split /::/, $module));

    if( ref $args eq 'HASH' )
    {
	my @query = ();
	foreach my $key ( sort keys %$args )
	{
	    next if $key eq 'passwd';
	    push @query, $key, $args->{$key};
	}
	$uri->query_form(@query);
    }
    return $uri->as_string;
}

sub delete_node
{
    my( $self, $i, $model ) = @_;
    #
    # TODO:
    #  1. The agent must be authenticated
    #  2. Is the target model open?
    #  3. Does the agent owns the target model?
    #
    #  Special handling of implicit nodes
    #
    # Delete the node and all statements refering to the node.  How
    # will we handle dangling nodes, like the properties of the node
    # mainly in the form of literals?  We will not delete them if they
    # belong to another model or if they are referenced in another
    # statement (that itself is not among the statements to be
    # deleted).  But there could be references to the node from other
    # interfaces that arn't even connected in this session.
    #
    # We could collect the dangling nodes and return them to the
    # caller for decision.  This could be made to an option.

    # This version will delete from left to right.  A deleted subject
    # will delete all prperty statements and all objects. This will
    # obviously have to change!

    # Procedure:
    #  Foreach statement
    #    - call obj->delete
    #    - call statement->delete
    #  Remove self

    die "Model not specified" unless $model;

    foreach my $arc ( @{ $self->get_arcs_list} )
    {
	my $obj = $arc->obj;
#	warn "Would delete Obj $obj->[URISTR]\n";
#	warn "Would delete Sta $arc->[URISTR]\n";
	$obj->delete( $model );
	$arc->delete( $model );
    }
    warn "Delete Node $self->[URISTR]\n" if $DEBUG;

    # Removes the node from the interfaces
    $self->remove( $model ); # TODO: maby check return value?


    # TODO: Do not remove the node if it's defined by other
    # models.  Only remove the node if this is the last model.  Only
    # remove the connections to the node if this is the last model.

    # Remove all connections to this node

    # TODO: Use the right channels to find all nodes that uses this
    # node; ie the subscription cache

    # Is this an arc?
    if( my $pred = $self->[PRED] )
    {
	my $subj = $self->[SUBJ];
	my $props = $self->[PROPS]{$pred->[ID]};
	for( my $i=0; $i<= $#$props; $i++ )
	{
	    if( $props->[$i][URISTR] eq $self->[URISTR] )
	    {
		splice( @$props, $i, 1 );
		$i--; # A entry was removed. Compensate
	    }
	}
    }

    return( 1, 1 );
}

sub find_node
{
    my( $self, $i, $uri ) = @_;

    my $obj = $RDF::Service::Cache::node->{$self->[IDS]}{ uri2id($uri) };
    return $obj;
}

sub service_init_types
{
    my( $self, $i ) = @_;
    #
    # We currently doesn't store the service objects in any
    # interface. The Base interface states that all URIs matching a
    # specific pattern are Service objects.

    warn "Initiating types for $self->[URISTR]\n";

    my $pattern = "^".NS_L."/service/[^/#]+\$";
    if( $self->[URISTR] =~ /$pattern/ )
    {
	# Declare the types for the service
	#
	my $c_Resource = $self->get_node(NS_RDFS.'Resource');
	my $c_Model = $self->get_node(NS_L.'Model');
	my $c_Service = $self->get_node(NS_L.'Service');
	my $types = [$c_Service, $c_Model, $c_Resource];
	$self->declare_self( $self, $types );
	return( undef, 1 );
    }
    return undef;
}

sub init_types
{
    my( $self, $i ) = @_;
    #
    # Set the types for this URI

    # TODO: Set the implicit types (should be done last maby...)
    return undef;

    die "deprecated";

    # Only set Resource for now.
    warn "Setting type for $self->[URISTR] to Resource\n" if $DEBUG;

    my $c_Resource = $self->get_node(NS_RDFS.'Resource');
    $self->declare_add_type($i, $c_Resource);

    return( undef );
}

sub desig_literal
{
    if( $_[0]->[VALUE] )
    {
	return( "'$_[0]->[VALUE]'", 1);
    }
    else
    {
	return( "''", 1);
#	return( desig($_[0]) );
    }
}

sub desig_resource
{
    # Change to make method calls
    #
    return( $_[0]->[LABEL] || 
	    $_[0]->[NAME] || 
	    $_[0]->[URISTR] || 
	    '(anonymous resource)'
	    , 1);
}




# All methods with the prefix 'list_' will return a list of objects
# rather than a collection. (Model or collection of resources or
# literals.)  But teh method will still return a ref to the list to
# the Dispatcher.

sub list_model_arcs
{
    my( $self ) = @_;

    die "Not implemented";

    my $arcs = [];
    # Each $part is a Interface object
    foreach my $part ( @{$self->[CONTENT]} )
    {
	# Only handle interfaces for now.
	die unless  ref $part eq 'RDF_023::Resource::Interface';

#	warn "Getting arcs for $part->[URI]\n";
	# TODO: use wantarray()
	push @$arcs, @{$part->list_arcs};
    }

    return @$arcs;
}



1;
