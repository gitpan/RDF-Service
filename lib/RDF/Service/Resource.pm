#  $Id: Resource.pm,v 1.10 2000/09/24 16:53:33 aigan Exp $  -*-perl-*-

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
use vars qw( $AUTOLOAD );
use RDF::Service::Dispatcher;
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( interfaces uri2id list_prefixes
			    get_unique_id id2uri );
use Data::Dumper;
use Carp;

our $DEBUG = 0;


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

    return $self;
}

sub new
{
    my( $class, $parent, $uri ) = @_;

    # This constructor shouls only be called from get_node, which
    # could be called from find_node or create_node.  get_node will
    # first look in the cache for this resource.

    my $self = bless [], $class;

    if( $parent and (ref($parent) ne 'RDF::Service::Resource'))
    {
#	print "**",ref($parent),"**";
	confess "Called Resource->new($class, $parent, $uri)\n";
    }

    $self->[IDS] = $parent ? $parent->[IDS] : '';
    $self->[URISTR] = $uri or die "No URI for $self";
    $self->[ID] = uri2id( $self->[URISTR] );

    return $self;
}


sub AUTOLOAD
{
    # The substr depends on the package length
    #
    $AUTOLOAD = substr($AUTOLOAD, 24);
    return if $AUTOLOAD eq 'DESTROY';
    warn "\nAUTOLOAD $AUTOLOAD\n" if $DEBUG;

    &RDF::Service::Dispatcher::go(shift, $AUTOLOAD, @_);
}




# Call as either: 
# node( $ns, $name );
# node( $uri );


sub name
{
    my( $self ) = @_;
    return $self->[NAME]; # not guaranteed to be defined
}

sub uri
{
    # This is always defined
    $_[0]->[URISTR];
}

sub value
{
    my( $self ) = @_;
    $self->init_props unless $self->[PROPS];

#    warn "T @{$self->[TYPES]}\n";

    $_[0]->[VALUE];
}


sub pred
{
    $_[0]->[PRED];
}

sub subj
{
    $_[0]->[SUBJ];
}

sub obj
{
    $_[0]->[OBJ];
}

sub find_prefix_id
{
    my( $self ) = @_;
    #
    # Return the longest prefix in the interface jumptables matching
    # the URI.

    foreach my $prefix ( &list_prefixes($self->[IDS]) )
    {
	if( $self->[URISTR] =~ /^\Q$prefix/ )
	{
	    warn( "Finding the prefix for ".$self->[URISTR].
			 " to be '$prefix'\n") if $DEBUG;
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

    foreach my $interface ( @{interfaces( $self->[IDS] )} )
    {
	$self->[PRIVATE]{$interface->[ID]} ||= {};
    }
}

sub get_node
{
    $_[1] ||= NS_L."#".&get_unique_id;
    return get_node_by_id( $_[0], uri2id($_[1]) );
}

sub get_node_by_id
{
    my( $self, $id ) = @_;

    # TODO: First look for the object in the cache

    my $obj = $RDF::Service::Cache::node->{$self->[IDS]}{ $id };

    unless( $obj )
    {
	# Create an uninitialized object. Any request for the objects
	# properties will initialize the object with the interfaces.

	$obj = RDF::Service::Resource->new_by_id($self, $id);
	$obj->init_private();

	$RDF::Service::Cache::node->{$self->[IDS]}{ $id } = $obj;
    }
    else
    {
	warn "Got URI from cache!!!\n" if $DEBUG;
    }
#    die Dumper $obj;

    return $obj;
}

sub get_model
{
    my( $self, $uri ) = @_;

    die "No uri specified" unless $uri;
    my $obj = $self->find_node( $uri );
    if( $obj )
    {
	warn "Model existing: $uri\n" if $DEBUG;
	# Is this a model?
	$obj->[TYPES] or $obj->init_types;

	my $c_model = $self->get_node(NS_L.'Model');
	unless( $obj->is_a(NS_L.'Model') )
	{
	    warn "$obj->[URISTR] is not a model\n";
	    warn $obj->types_as_string;
	    exit;
	}
    }
    else
    {
	warn "Model not existing. Creating it: $uri\n" if $DEBUG;
	$obj = $self->create_model( $uri );
    }

    return $obj;
}

sub is_a
{
    my( $self, $uristr ) = @_;

    my $class = $self->get_node($uristr);
    $self->[TYPES] or $self->init_types;
    if( defined $self->[TYPE]{$class->[ID]} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub get_props_list
{
    my( $self ) = @_;
    warn "get_props_list for $self->[URISTR]\n" if $DEBUG;

    my $props = [];
    $self->init_props unless $self->[PROPS];
    foreach my $prop_id ( keys %{$self->[PROPS]} )
    {
	my $node = $self->get_node( id2uri($prop_id) );
	warn "Adding $node->[URISTR] to props_list\n" if $DEBUG;
	push @{$props}, $node;
    }
    return $props;
}

sub get_objects_list
{
    my( $self, $prop ) = @_;

    warn "get_objects_list for $self->[URISTR]\n" if $DEBUG;

    my $objs = [];
    $self->init_props unless $self->[PROPS];
#    die Dumper $self->[PROPS];
    return undef unless defined $self->[PROPS]{$prop->[ID]};
    foreach my $arc ( @{$self->[PROPS]{$prop->[ID]}} )
    {
	push @$objs, $arc->obj;
    }
    return $objs;
}

sub get_arcs_list
{
    my( $self ) = @_;

    my $arcs = [];
    $self->init_props unless $self->[PROPS];
    # TODO: Inline get_props_list for optimizations
    foreach my $prop ( @{$self->get_props_list} )
    {
	push @$arcs, @{$self->[PROPS]{$prop->[ID]}};
    }
    return $arcs;
}



######################################################################
#
# Declaration methods should only be called from interfaces.  Since
# they are 'low_level', they should not accept uri's in place of
# objects, etc.
#

sub declare_literal
{
    my( $self, $model, $lit, $lit_str_ref, $types, $props ) = @_;
    #
    # - $model is a resource object
    # - $lit (uri or node or undef)
    # - $lref will be a scalar ref
    # - $types is ref to array of type objects or undef
    # - $props is hash ref with remaining properties or undef

    # $types and $props is not done yet

    unless( ref $lit )
    {
	unless( defined $lit )
	{
	    $lit = $self->[URISTR].'#'.&get_unique_id;
	}
	$lit = $self->get_node( $lit );
    }

    ref $lit_str_ref or die "value must be a reference";

    # TODO: Set value as property if value differ among models

    $lit->[VALUE]     = $lit_str_ref;

    my $c_Literal = $self->get_node(NS_RDFS.'Literal');
    my $c_Resource = $self->get_node(NS_RDFS.'Resource');
    $types ||= [];
    push @$types, $c_Literal, $c_Resource;
    #
    $lit->declare_self( $model, $types );


    return $lit;
}

sub declare_model
{
    my( $self, $model, $uri, $content ) = @_;

    $model or die "model must be defined";
    $uri or die "URI must be defined";
    $content ||= [];

    my $obj = $self->get_node( $uri );

    # The model consists of triples. The [content] holds the access
    # points for the parts of the model. Each element can be either a
    # triple, model, ns, prefix or interface. Each of ns, prefix and
    # interface represents all the triples contained theirin.

    # the second parameter is the interface of the created object
    # That parameter will be removed and the interface list will be
    # created from the availible interfaces as pointed to by the
    # context signature.

    # Just handle one model ??
    #
#    $obj->[MODEL]    = $model; # TODO
    $obj->[FACT]     = 1;
    $obj->[NS]       = $obj->[URISTR];
    $obj->[CONTENT]  = $content;
    $obj->[READONLY] = 0;
    $obj->[UPDATED]  = time;

    my $c_Resource = $self->get_node(NS_RDFS.'Resource');
    my $c_Model = $self->get_node(NS_L.'Model');
    my $types = [$c_Model, $c_Resource];
    #
    $obj->declare_self( $model, $types );

    return $obj;
}

sub declare_node
{
    my( $self, $model, $uri, $types, $props );

    die "Not done";
}

sub declare_self
{
    my( $self, $model, $types, $props ) = @_;
    #
    # Replace all statements in $model with $types and $props

    # TODO: $props
    # TODO: remove previous $model statements

    my $cnt = @$types;
    warn "Preparing to add $cnt types to $self->[URISTR]\n" if $DEBUG;

    foreach my $type ( @$types )
    {
	unless( $self->[TYPE]{$type->[ID]} )
	{
	    # Make sure to always return the types in the same
	    # order.  It would be better to order the types in
	    # heiarcy order, so that Resource always comes
	    # last.
	    #
	    push @{$self->[TYPES]}, $type;
#	    warn "\ttype $type->[URISTR]\n";

	}

	# Remember what interface says what, in order to
	# enable updating of the type
	#
	# In this case. Remember the model
	#
	$self->[TYPE]{$type->[ID]}{$model->[ID]} = 1;
    }
}

sub declare_add_type
{
    my( $self, $i, $type ) = @_;

    unless( defined $self->[TYPE]{$type->[ID]} )
    {
	# Make sure to always return the types in the same
	# order.  It would be better to order the types in
	# heiarcy order, so that Resource always comes
	# last.
	#
	push @{$self->[TYPES]}, $type;
    }

    confess "No type id for $type->[URISTR]" unless $type->[ID];
    die "no interface id" unless $i->[ID];

    # Remember what interface says what, in order to
    # enable updating of the type
    #
    $self->[TYPE]{$type->[ID]}{$i->[ID]} = 1;
}

sub declare_add_static_literal
{
    my( $subj, $pred, $lit_str, $model, $arc_uristr ) = @_;
    #
    # $lit_str is a scalar ref
    #
    # The URI of a static literal represents what the value
    # represents.  That is; the abstract property.  It will never
    # change.  (The literal static/dynamic type info is not stored)

    # TODO: find the literal...

    die "Not implemented";

#    $arc_uristr ||= $model.'#'.get_unique_id();
#    my $arc_id = uri2id( $arc_uristr );
#    push @{ $subj->[PROPS]{$pred->[ID]} }, [$obj->[ID], 
#					    $arc_id, 
#					    $model->[ID],
#					    ];
#    return $arc_uristr;
}

sub declare_add_dynamic_literal
{
    my( $subj, $pred, $lit_str_ref, $model, $lit_uristr, $arc_uristr  ) = @_;
    #
    # $lit_str is a scalar ref
    #
    # The URI of a dynamic literal represents the property for the
    # specific subject.  The literal changes content as the subjects
    # property changes.  (The literal static/dynamic type info is not
    # stored)

    $arc_uristr ||= $model->[URISTR].'#'.get_unique_id();

    # TODO: This is a implicit object. It's URI should be based on the
    # subject URI
    #
    my $lit = $model->declare_literal( $model, $lit_uristr, $lit_str_ref );


    return $model->declare_arc( $model, $arc_uristr, $pred, $subj, $lit );
}

sub declare_add_prop
{
    my( $subj, $pred, $obj, $model, $arc_uristr ) = @_;

    $arc_uristr ||= $model->[URISTR].'#'.get_unique_id();

    my $arc = $model->declare_arc( $model,
				   $arc_uristr,
				   $pred,
				   $subj,
				   $obj);

    return $arc;
}

sub declare_arc
{
    my( $self, $model, $uristr, $pred, $subj, $obj ) = @_;

    # It *could* be that we have two diffrent arcs with the same URI,
    # if they comes from diffrent models.  The common case is that the
    # arcs with the same URI are identical.  The PRED, SUBJ, OBJ slots
    # are used for the common case.
    #
    # TODO: Use explicit properties if the models differs.
    #
    # All models says the same thing unless the properties are
    # explicit.

    if( $uristr )
    {
	# TODO: Check that tha agent owns the namespace
	# For now: Just allow models in the local namespace
	my $ns_l = NS_L;
	unless( $uristr =~ /$ns_l/ )
	{
	    confess "Invalid namespace for literal: $uristr";
	}
    }
    else
    {
	$uristr = NS_L."/arc/". &get_unique_id;
    }

    my $arc = $self->get_node( $uristr );

    $arc->[PRED] = $pred;
    $arc->[SUBJ] = $subj;
    $arc->[OBJ]  = $obj;


    push @{ $subj->[PROPS]{$pred->[ID]} }, $arc;

    return $arc;
}


sub types_as_string
{
    my( $self ) = @_;
    #
#   die $self->uri."--::".Dumper($self->[TYPES]);
    return join '', map "\t".$_->[URISTR]."\n", @{$self->[TYPES]};
}


1;


__END__
