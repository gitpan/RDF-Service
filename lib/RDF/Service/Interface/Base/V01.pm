#  $Id: V01.pm,v 1.22 2000/11/12 18:14:00 aigan Exp $  -*-perl-*-

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
use Carp qw( confess carp cluck croak );

sub register
{
    my( $interface ) = @_;

    return
    {
	'' =>
	{
	    NS_LS.'#Service' =>
	    {
		'connect' => [\&connect],
		'find_node' => [\&find_node],
	    },
	    NS_LS.'#Model' =>
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
		'level' => [\&level],
		'init_rev_subjs' => [\&init_rev_subjs_class],
	    },
	},
	NS_LS."/service/" =>
	{
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&service_init_types],
	    },
	},
	&NS_LS =>
	{
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
		'init_rev_subjs' => [\&init_rev_subjs],
		'level'      => [\&base_level],
	    },
	},
	&NS_RDF =>
	{
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
		'init_rev_subjs' => [\&init_rev_subjs],
		'level'      => [\&base_level],
	    },
	},
	&NS_RDFS =>
	{
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
		'init_rev_subjs' => [\&init_rev_subjs],
		'level'      => [\&base_level],
	    },
	},
    };
}



# ??? Create literal URIs by apending '#val' to the statement URI

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
    my $new_i_node = $self->[NODE]->new( $uri );


    # Update the Service object IDS
    #
    push @{$self->[NODE][INTERFACES]}, $new_i_node;
    $self->[NODE][IDS] = $new_i_node->[IDS] =
      generate_ids($self->[NODE][INTERFACES]);

    # Initialize the cache for this IDS.  Each IDS has it's own cache
    # of node objects
    #
    $RDF::Service::Cache::node->{$self->[NODE][IDS]} ||= {};

    # Set up the new object, based on the IDS
    #
    $new_i_node->[MODEL] = undef; # What is the model of this?
    $new_i_node->[MODULE_NAME] = $module; # This is not used
    $new_i_node->init_private();


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
      $new_i_node->[MODULE_REG] = &{$module."::register"}( $new_i_node, $args );
  }

    my $new_i = RDF::Service::Context->new($new_i_node,
					   $self->[CONTEXT],
					   $self->[WMODEL]);
    return( $new_i, 1 );
}


sub init_types
{
    my( $self, $i ) = @_;

#    warn "***The model of $i is $i->[MODEL]\n";
    croak "Bad interface( $i )" unless ref $i eq "RDF::Service::Resource";

    if( my $entry = $Schema->{$self->[NODE][URISTR]}{NS_RDF.'type'} )
    {
	$self->declare_add_types( &_obj_list($self, $i, $entry) );
	return( 1, 3);
    }
    $self->[NODE][TYPE_ALL] = 1;
    return undef;
}

sub init_rev_subjs
{
    my( $self, $i) = @_;

    my $subj_uri = $self->[NODE][URISTR];
    my $subj = $self;
    foreach my $pred_uri (keys %{$Schema->{$subj_uri}})
    {
	# Make an exception for type
	#
	next if $pred_uri eq NS_RDF.'type';

	my $lref = $Schema->{$subj_uri}{$pred_uri} or
	  die "\$Schema->{$subj_uri}{$pred_uri} not defined\n";
	my $pred = $self->get($pred_uri);

	# Just define the arcs.
	#
	_arcs_branch($self, $i, $subj, $pred, $lref);
    }
    $self->[NODE][REV_SUBJ_ALL] = 1;

    return(1, 3);
}


sub init_rev_subjs_class
{
    my( $self, $i ) = @_;
    #
    # A class inherits it's super-class subClassOf properties

    debug "RDFS init_rev_subjs_class $self->[URISTR]\n", 1;


    # Since init_rev_subjs_class() depends on that all the other
    # init_rev_subjs has been called, it will call init_rev_subjs()
    # from here.  That would cause an infinite recurse unless the
    # dispatcher would remember which interface subroutines it has
    # called, by storing that in a hash in the context.  The
    # dispatcher will not call the same interface subroutine twice (in
    # deapth) with the same arguments.
    #
    # TODO: But how do we know if the cyclic dependency was a mistake
    # or not?  In some cases, we should report it as an error.  ... I
    # will waite with this until we have the function/property
    # equality.
    #
    # $self->init_rev_subjs;


    my $subClassOf = $self->get(NS_RDFS.'subClassOf');

    # Could be optimized?
    my $subj_uristr = $self->[NODE][URISTR];
    foreach my $pred_uristr ( keys %{$Schema->{$subj_uristr}} )
    {
	my $lref = $Schema->{$subj_uristr}{$pred_uristr} or
	  die "\$Schema->{$subj_uristr}{$pred_uristr} not defined\n";
	my $pred = $self->get($pred_uristr);

	# This should recursively add all arcs
	&_arcs_branch($self, $i, $self, $pred, $lref);

	if( $pred_uristr eq NS_RDFS.'subClassOf' )
	{
	    foreach my $superclass (
		  @{ $self->arc_obj($subClassOf)->list }
		 )
	    {
		foreach my $multisuperclass (
		      @{ $superclass->arc_obj($subClassOf)->list }
		     )
		{

		    # TODO: Place this dynamic statement in a special
		    # namespace

		    $self->declare_add_prop( $subClassOf,
					     $multisuperclass );
		}
	    }
	}

	# TODO: Set create dependency on the subject and remove
	# dependency on each added statement and change dependency on
	# object literlas.
    }

    $self->[NODE][REV_SUBJ_ALL] = 1;

    return( 1, 3 );
}


sub list_arcs   ### DEPRECATED
{
    my( $self, $i ) = @_;
    #
    # Only returns arcs from the top level

    my $arcs = [];
    foreach my $subj_uri ( keys %$Schema )
    {
	# Could be optimized?
	foreach my $pred_uri ( keys %{$Schema->{$subj_uri}} )
	{
	    my $lref = $Schema->{$subj_uri}{$pred_uri} or
		die "\$node->{$subj_uri}{$pred_uri} not defined\n";
	    my $subj = $self->get($subj_uri);
	    my $pred = $self->get($pred_uri);
	    push @$arcs, _arcs_branch($self, $i, $subj, $pred, $lref);
	}
    }
    # TODO: use wantarray()
    return $arcs;
}

sub base_level
{
    my( $self, $point ) = @_;

    my $level = $Schema->{$self->[NODE][URISTR]}{NS_LS.'#level'};
    defined $level or die "No level for $self->[NODE][URISTR]\n";
    return( $level, 1);
}

sub level
{
    my( $self, $point ) = @_;

    # The level of a node is a measure of it's place in the class
    # heiarchy.  The Resouce class is level 0.  The level of a class
    # is the level of the heighest superclass plus one.  Used for
    # sorting in type_orderd_list().

    # TODO: Store the level as a property

    my $level = 0;
    foreach my $sc ( @{$self->arc_obj(NS_RDFS.'subClassOf')->list} )
    {
	my $sc_level = $sc->level;
	$level = $sc_level if $sc_level > $level;
    }
    $level++;

    return( $level, 1);
}


sub delete_node
{
    my( $self, $i ) = @_;
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

    foreach my $arc ( @{ $self->arc->list} )
    {
	my $obj = $arc->obj;
#	warn "Would delete Obj $obj->[URISTR]\n";
#	warn "Would delete Sta $arc->[URISTR]\n";
	$obj->delete();
	$arc->delete();
    }
    debug "Delete Node $self->[URISTR]\n", 1;

    # Removes the node from the interfaces
    $self->remove(); # TODO: maby check return value?


    # TODO: Do not remove the node if it's defined by other
    # models.  Only remove the node if this is the last model.  Only
    # remove the connections to the node if this is the last model.

    # Remove all connections to this node

    # TODO: Use the right channels to find all nodes that uses this
    # node; ie the subscription cache

    $self->declare_del_node;

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

    my $pattern = "^".NS_LD."/service/[^/#]+\$";
    if( $self->[NODE][URISTR] =~ /$pattern/ )
    {
	# Declare the types for the service
	#
	$self->[NODE]->declare_add_types( $self, [
	      NS_LS.'#Service',
	      NS_LS.'#Model',
	      NS_LS.'#Selection',
	      NS_RDFS.'Container',
	      NS_RDFS.'Resource',
	      ]);
	return( undef, 1 );
    }
    return undef;
}

sub desig_literal
{
    if( $_[0]->[NODE][VALUE] )
    {
	return( "'${$_[0]->[NODE][VALUE]}'", 1);
    }
    else
    {
	return( "''", 1);
#	return( desig($_[0]) );
    }
}

### <<<--- HERE !!!

sub desig_resource
{
    debug $_[0]->types_as_string, 1;

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
    $self->init_rev_subjs unless $self->[NODE][REV_SUBJ_ALL];

#    warn "**** ".($self->types_as_string)."****\n";

    # TODO: Should return 2
    return( ${$_[0]->[NODE][VALUE]}, 1);
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


sub _obj_list
{
    my( $self, $i, $ref ) = @_;
    my @objs = ();

    if( ref $ref eq 'SCALAR' )
    {
	push @objs, $self->get($$ref);
    }
    elsif( ref $ref eq 'ARRAY' )
    {
	foreach my $obj ( @$ref )
	{
	    push @objs, _obj_list( $self, $i, $obj );
	}
    }
    else
    {
	push @objs, $self->declare_literal($i, undef, $ref);
    }

    return \@objs;
}

sub _arcs_branch
{
    my( $self, $i, $subj, $pred, $lref ) = @_;

    my $model = $self->get($Schema->{$subj->[NODE][URISTR]}{NS_LS.'#ns'});
    my $arcs = [];
    my $obj;
    if( ref $lref and ref $lref eq 'SCALAR' )
    {
	my $obj_uri = $$lref;
	$obj = $self->get($obj_uri);
    }
    elsif( ref $lref and ref $lref eq 'HASH' )
    {
	# Anonymous resource
	# (Sublevels is not returned)

	die "Anonymous resources not supported";
#	$obj = RDF::Service::Resource->new($ids, undef);
    }
    elsif(  ref $lref and ref $lref eq 'ARRAY' )
    {
	foreach my $item ( @$lref )
	{
#	    warn "Ignored recurse\n"; # not any more?
	    push @$arcs, _arcs_branch($self, $i, $subj, $pred, $item);
	}
	return @$arcs;
    }
    else
    {
	confess("_arcs_branch called with undef obj: ".Dumper(\@_))
	    unless defined $lref;

	# TODO: The model of the statement should be NS_RDFS or NS_RDF
	# or NS_LS, rather than $i
	#
	debug "_arcs_branch adds literal $lref\n", 1;
	$obj = $self->declare_literal( \$lref );
    }
    debug "_arcs_branch adds arc $pred->[NODE][URISTR]( ".
      "$subj->[NODE][URISTR], # $obj->[NODE][URISTR])\n", 3;

    return @$arcs, $self->declare_arc( $pred, $subj, $obj );
}


1;
