#  $Id: V01.pm,v 1.17 2000/10/22 10:59:00 aigan Exp $  -*-perl-*-

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
use RDF::Service::Cache qw( generate_ids uri2id debug $DEBUG);
use URI;
use Data::Dumper;

sub register
{
    my( $interface ) = @_;

    return
    {
	'' =>
	{
	    NS_L.'#Service' =>
	    {
		'connect' => [\&connect],
		'find_node' => [\&find_node],
	    },
	    NS_L.'#Model' =>
	    {
		'arcs_list' => [\&arcs_list],
		'is_empty'  => [\&not_implemented],
		'size'      => [\&not_implemented],
		'validate'  => [\&not_implemented],

		# The NS. The base for added things...
		'source_uri'=> [\&not_implemented],

		# is the model open or closed?
		'is_mutable'=> [\&not_implemented],

	    },
	    NS_RDFS.'Literal' =>
	    {
		'desig' => [\&desig_literal],
		'value' => [\&value],
	    },
	    NS_RDF.'Statement' =>
	    {
		'pred' => [\&pred],
		'subj' => [\&subj],
		'obj'  => [\&obj],
	    },
	    NS_RDFS.'Resource' =>
	    {
		'desig' => [\&desig_resource],
		'delete' => [\&delete_node],
	    },
	    NS_RDFS.'Class' =>
	    {
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

sub not_implemented { die "not implemented" }

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


    # Create the new interface resource object
    #
    my $uri = _construct_interface_uri( $module, $args );
    my $nio = RDF::Service::Resource->new($self, $uri);


    # Update the Service object IDS
    #
    push @{$self->[NODE][INTERFACES]}, $nio;
    $self->[NODE][IDS] = $nio->[IDS] =
      generate_ids($self->[NODE][INTERFACES]);

    # Initialize the cache for this IDS.  Each IDS has it's own cache
    # of node objects
    #
    $RDF::Service::Cache::node->{$self->[NODE][IDS]} ||= {};

    # Set up the new object, based on the IDS
    #
    $nio->[MODEL] = $self->[NODE][MODEL];
    $nio->[MODULE_NAME] = $module; # This is not used
    $nio->init_private();


    # Purge the existing Service jumptable, because of the changed IDS
    #
    $self->[NODE][JUMPTABLE] = undef;
    $self->[NODE]->init_private;


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


    debug "Registring $file\n", 1;

  {   no strict 'refs';
      $nio->[MODULE_REG] = &{$module."::register"}( $nio, $args );
  }

    my $ni = RDF::Service::Context->new($nio, $self->[CONTEXT], $self->[WMODEL]);
    return( $ni, 1 );
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

    foreach my $arc ( @{ $self->arc->list} )
    {
	my $obj = $arc->obj;
#	warn "Would delete Obj $obj->[URISTR]\n";
#	warn "Would delete Sta $arc->[URISTR]\n";
	$obj->delete( $model );
	$arc->delete( $model );
    }
    debug "Delete Node $self->[URISTR]\n", 1;

    # Removes the node from the interfaces
    $self->remove( $model ); # TODO: maby check return value?


    # TODO: Do not remove the node if it's defined by other
    # models.  Only remove the node if this is the last model.  Only
    # remove the connections to the node if this is the last model.

    # Remove all connections to this node

    # TODO: Use the right channels to find all nodes that uses this
    # node; ie the subscription cache

    # Is this an arc?
    $self->declare_delete_arc;

    return( 1, 1 );
}


sub find_node
{
    my( $self, $i, $uri ) = @_;

    my $obj = $RDF::Service::Cache::node->{$self->[NODE][IDS]}{ uri2id($uri) };
    return( RDF::Service::Context->new($obj,
				       $self->[CONTEXT],
				       $self->[WMODEL]),
	    1) if $obj;
    return( undef );
}

sub service_init_types
{
    my( $self, $i ) = @_;
    #
    # We currently doesn't store the service objects in any
    # interface. The Base interface states that all URIs matching a
    # specific pattern are Service objects.

    debug "Initiating types for $self->[NODE][URISTR]\n", 1;

    my $pattern = "^".NS_L."/service/[^/#]+\$";
    if( $self->[NODE][URISTR] =~ /$pattern/ )
    {
	# Declare the types for the service
	#
	$self->[NODE]->declare_add_types( $self, [
	      NS_L.'#Service',
	      NS_L.'#Model',
	      NS_L.'#Selection',
	      NS_RDFS.'Container',
	      NS_RDFS.'Resource',
	      ]);
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
    debug "Setting type for $self->[URISTR] to Resource\n", 1;

    $self->[NODE]->declare_add_types($i, [NS_RDFS.'Resource']);

    return( undef );
}

sub desig_literal
{
    if( $_[0]->[NODE][VALUE] )
    {
	return( "'$_[0]->[NODE][VALUE]'", 1);
    }
    else
    {
	return( "''", 1);
#	return( desig($_[0]) );
    }
}

sub desig_resource
{
    debug "T ".$_[0]->types_as_string, 1;

    # Change to make method calls
    #
    return( $_[0]->[NODE][LABEL] || 
	    $_[0]->[NODE][NAME] || 
	    $_[0]->[NODE][URISTR] || 
	    '(anonymous resource)'
	    , 1);
}




# All methods with the prefix 'list_' will return a list of objects
# rather than a collection. (Model or collection of resources or
# literals.)  But teh method will still return a ref to the list to
# the Dispatcher.

sub arcs_list
{
    my( $self ) = @_;

    die "Not implemented";

    my $arcs = [];
    # Each $part is a Interface object
    foreach my $part ( @{$self->[NODE][CONTENT]} )
    {
	# Only handle interfaces for now.
	die unless  ref $part eq 'RDF_023::Resource::Interface';

#	warn "Getting arcs for $part->[NODE][URI]\n";
	# TODO: use wantarray()
	push @$arcs, @{$part->list_arcs};
    }

    return @$arcs;
}

sub value
{
    my( $self ) = @_;
    $self->init_props unless $self->[NODE][PROPS];

    # TODO: Should return 2
    return( $_[0]->[NODE][VALUE], 1);
}


sub pred
{
    # TODO. Should return 2;
    return( $_[0]->[NODE][PRED], 1);
}

sub subj
{
    # TODO. Should return 2;
    return( $_[0]->[NODE][SUBJ], 1);
}

sub obj
{
    # TODO. Should return 2;
    return( $_[0]->[NODE][OBJ], 1);
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



1;
