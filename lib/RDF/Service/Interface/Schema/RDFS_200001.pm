#  $Id: RDFS_200001.pm,v 1.10 2000/10/22 10:59:00 aigan Exp $  -*-perl-*-

package RDF::Service::Interface::Schema::RDFS_200001;

#=====================================================================
#
# DESCRIPTION
#   Interface to the RDF and RDFS Schema
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
use vars qw( $node );
use RDF::Service::Constants qw( :all );
use RDF::Service::Resource;
use RDF::Service::Cache qw( debug );
use Data::Dumper;
use Carp qw( confess carp cluck croak );

my $xml = "xml:"; ### TODO: Fix this
# ??? Create literal URIs by apending '#val' to the statement URI


sub register
{
    my( $interface ) = @_;

    # TODO: Decide on a standard way to name functions
    # # Will not use the long names in this version...
    my $module_uri = "org.cpan.RDF.Interface.Schema.RDFS_200001";

    # TODO: add init_rev_types and init_rev_props

    return
    {
	&NS_RDF =>
	{
	    NS_L.'#Interface' =>
	    {
		'list_arcs' => [\&list_arcs],
	    },
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
	    },
	},
	&NS_RDFS =>
	{
	    NS_L.'#Interface' =>
	    {
		'list_arcs' => [\&list_arcs],
	    },
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
	    },
	},
	'' =>
	{
	    NS_RDFS.'Class' =>
	    {
		'init_props' => [\&init_props_class],
	    },
	},
    };
}




$node =
{
    NS_RDFS.'Resource' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'Resource',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'label' => \ '___some_uri___',
	NS_RDFS.'comment' => 'The most general class',
    },
    '___some_uri___' =>
    {
	NS_RDF.'value' => 'Resource',
	$xml.'lang' => 'en',
    },

    NS_RDF.'type' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'type',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'range' => \(NS_RDFS.'Class'),
    },
    NS_RDFS.'comment' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'comment',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_RDFS.'Literal'),
    },
    NS_RDFS.'label' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'label',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_RDFS.'Literal'),
    },
    NS_RDFS.'Class' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'Class',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Resource'),
    },
    NS_RDFS.'subClassOf' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'subClassOf',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Class'),
	NS_RDFS.'range' => \(NS_RDFS.'Class'),
    },
    NS_RDFS.'subPropertyOf' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'subPropertyOf',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDF.'Property'),
	NS_RDFS.'range' => \(NS_RDF.'Property'),
    },
    NS_RDFS.'seeAlso' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'seeAlso',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_RDFS.'Resource'),
    },
    NS_RDFS.'isDefinedBy' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'isDefinedBy',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_RDFS.'Resource'),
    },
    NS_RDFS.'ConstraintResource' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'ConstraintResource',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_RDFS.'ConstraintProperty' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'ConstraintProperty',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => [ \(NS_RDF.'Property'),
				\(NS_RDFS.'ConstraintResource'),
				],
    },
    NS_RDFS.'domain' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'domain',
	NS_RDF.'type' => \(NS_RDF.'ConstraintProperty'),
	NS_RDFS.'domain' => \(NS_RDF.'Property'),
	NS_RDFS.'range' => \(NS_RDFS.'Class'),
    },
    NS_RDFS.'range' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'range',
	NS_RDF.'type' => \(NS_RDF.'ConstraintProperty'),
	NS_RDFS.'domain' => \(NS_RDF.'Property'),
	NS_RDFS.'range' => \(NS_RDFS.'Class'),
    },
    NS_RDF.'Property' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'Property',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_RDFS.'Literal' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'Literal',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_RDF.'Statement' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'Statement',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_RDF.'subject' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'subject',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDF.'Statement'),
	NS_RDFS.'range' => \(NS_RDFS.'Resource'),
    },
    NS_RDF.'predicate' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'predicate',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDF.'Statement'),
	NS_RDFS.'range' => \(NS_RDF.'Property'),
    },
    NS_RDF.'object' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'object',
	NS_RDF.'type' => \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDF.'Statement'),
    },
    NS_RDFS.'Container' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'Container',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_RDF.'Bag' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'Bag',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Container'),
    },
    NS_RDF.'Seq' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'Seq',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Container'),
    },
    NS_RDF.'Alt' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'Alt',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Container'),
    },
    NS_RDFS.'ContainerMembershipProperty' =>
    {
	NS_L.'ns' => NS_RDFS,
	NS_L.'name' => 'ContainerMembershipProperty',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDF.'Property'),
    },
    NS_RDF.'value' =>
    {
	NS_L.'ns' => NS_RDF,
	NS_L.'name' => 'value',
	NS_RDF.'type' => \(NS_RDF.'Property'),
    },
    NS_L.'#Interface' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'Interface',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
    },
    NS_L.'#interface' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'interface',
	NS_RDF.'type' =>  \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_L.'Interface'),
    },
    NS_L.'#Selection' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'Selection',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Container'),
    },
    NS_L.'#Model' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'Model',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_RDFS.'Container'),
    },
    NS_L.'#model' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'model',
	NS_RDF.'type' =>  \(NS_RDF.'Property'),
	NS_RDFS.'domain' => \(NS_RDFS.'Resource'),
	NS_RDFS.'range' => \(NS_L.'Model'),
    },
    NS_L.'#Service' =>
    {
	NS_L.'ns' => NS_L,
	NS_L.'name' => 'Service',
	NS_RDF.'type' => \(NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \(NS_L.'Selection'),
    },
};

sub init_props_class
{
    my( $self, $i ) = @_;
    #
    # A class inherits it's super-class subClassOf properties

    debug "RDFS init_props_class $self->[URISTR]\n", 1;

    my $subClassOf = $self->get(NS_RDFS.'subClassOf');

    # Could be optimized?
    my $subj_uristr = $self->[NODE][URISTR];
    foreach my $pred_uristr ( keys %{$node->{$subj_uristr}} )
    {
	my $lref = $node->{$subj_uristr}{$pred_uristr} or
	  die "\$node->{$subj_uristr}{$pred_uristr} not defined\n";
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
					     $multisuperclass,
					     $self->[NODE][MODEL]);
		}
	    }
	}

	# TODO: Set create dependency on the subject and remove
	# dependency on each added statement and change dependency on
	# object literlas.
    }

    return( 1, 3 );
}


sub init_types
{
    my( $self, $i ) = @_;

#    warn "***The model of $i is $i->[MODEL]\n";
    croak "Bad interface( $i )" unless ref $i eq "RDF::Service::Resource";

    if( my $entry = $node->{$self->[NODE][URISTR]}{NS_RDF.'type'} )
    {
	$self->[NODE]->declare_add_types( $i->[MODEL],
					  &_obj_list($self, $i, $entry) );
	return( 1, 3);
    }
    return undef;
}


sub list_arcs
{
    my( $self, $i ) = @_;
    #
    # Only returns arcs from the top level

    my $arcs = [];
    foreach my $subj_uri ( keys %$node )
    {
	# Could be optimized?
	foreach my $pred_uri ( keys %{$node->{$subj_uri}} )
	{
	    my $lref = $node->{$subj_uri}{$pred_uri} or
		die "\$node->{$subj_uri}{$pred_uri} not defined\n";
	    my $subj = $self->get($subj_uri);
	    my $pred = $self->get($pred_uri);
	    push @$arcs, _arcs_branch($self, $i, $subj, $pred, $lref);
	}
    }
    # TODO: use wantarray()
    return $arcs;
}

sub _arcs_branch
{
    my( $self, $i, $subj, $pred, $lref ) = @_;

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
	# or NS_L, rather than $i
	#
	debug "_arcs_branch adds literal $lref\n", 1;
#	debug  "*|* The node $self with URI $self->[NODE][URISTR]\n";
#	warn "*|* has a model $self->[NODE][MODEL] with".
#	  "URI $self->[NODE][MODEL][NODE][URISTR]\n";
	$obj = $self->declare_literal( $self->[NODE][MODEL],
				       undef, \$lref );
    }
    debug "_arcs_branch adds arc $pred->[NODE][URISTR]( ".
      "$subj->[NODE][URISTR], # $obj->[NODE][URISTR])\n", 1;

    return @$arcs, $self->declare_arc( $self->[NODE][MODEL],
				       undef, $pred, $subj, $obj );
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
	push @objs, $self->[NODE]->declare_literal($i, undef, $ref);
    }

    return \@objs;
}

1;
