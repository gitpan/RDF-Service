#  $Id: Context.pm,v 1.5 2000/10/22 10:59:00 aigan Exp $  -*-perl-*-

package RDF::Service::Context;

#=====================================================================
#
# DESCRIPTION
#   All resources exists in a context. This is the context.
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
			    get_unique_id id2uri debug
			    debug_start debug_end
			    $DEBUG );
use Data::Dumper;
use Carp;

sub new
{
    my( $class, $node, $context, $wmodel ) = @_;

    # This constructor shouls only be called from get_node, which
    # could be called from find_node or create_node.

    my $self = bless [], $class;

    # TODO: Maby perform a deep copy of the context.  At least copy
    # each key-value pair.

    $self->[CONTEXT] = $context;
    $self->[NODE]    = $node;
    $self->[WMODEL]  = $wmodel;

    return $self;
}


sub AUTOLOAD
{
    # The substr depends on the package length
    #
    $AUTOLOAD = substr($AUTOLOAD, 23);
    return if $AUTOLOAD eq 'DESTROY';
    debug "AUTOLOAD $AUTOLOAD\n", 2;

    &RDF::Service::Dispatcher::go(shift, $AUTOLOAD, @_);
}


sub name
{
    my( $self ) = @_;
    return $self->[NODE][NAME]; # not guaranteed to be defined
}

sub uri
{
    # This is always defined
    $_[0]->[NODE][URISTR];
}


sub get
{
    $_[1] ||= NS_L."#".&get_unique_id;
    return get_node_by_id( $_[0], uri2id($_[1]) );
}

sub get_node_by_id
{
    my( $self, $id ) = @_;

    # TODO: First look for the object in the cache

    die "IDS undefined" unless defined $self->[NODE][IDS];
    my $obj = $RDF::Service::Cache::node->{$self->[NODE][IDS]}{ $id };

    unless( $obj )
    {
	# Create an uninitialized object. Any request for the objects
	# properties will initialize the object with the interfaces.

	$obj = RDF::Service::Resource->new_by_id($self->[NODE], $id);
	$obj->init_private();

	$RDF::Service::Cache::node->{$self->[NODE][IDS]}{ $id } = $obj;
    }
    else
    {
	debug "Got URI from cache!!!\n", 2;
    }

    debug "get_node( $obj->[URISTR] )\n", 2;

    return RDF::Service::Context->new( $obj,
				       $self->[CONTEXT],
				       $self->[WMODEL] );
}

sub get_model
{
    my( $self, $uri ) = @_;

    debug_start("get_model", ' ', $self);

    die "No uri specified" unless $uri;
    my $obj = $self->find_node( $uri );
    if( $obj )
    {
	debug "Model existing: $uri\n", 1;
	# Is this a model?
	unless( $obj->is_a(NS_L.'#Model') )
	{
	    debug "$obj->[URISTR] is not a model\n", 1;
	    debug $obj->types_as_string, 1;
	    exit;
	}
    }
    else
    {
	debug "Model not existing. Creating it: $uri\n", 1;
	$obj = $self->create_model( $uri );
    }

    debug_end("get_model");
    return $obj;
}

sub is_a
{
    my( $self, $class ) = @_;

    $class = $self->get( $class ) unless ref $class;

    $self->[NODE][TYPES] or $self->init_types;
    if( defined $self->[NODE][TYPE]{$class->[NODE][ID]} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


# The alternative selectors:
#
#   arc               subj arcs
#   arc_obj           subj arcs objs
#   select_arc        container subj arcs
#   select_arc_obj    container subj arcs objs
#   type              subj types
#   select_type       container subj types
#   rev_arc           obj arcs
#   arc_subj          obj arcs subjs
#   select_rev_arc    container obj arcs
#   select_arc_subj   container obj arcs subjs
#   rev_type          type objs
#   select_rev_type   container types objs
#   li                container res
#   rev_li            res container
#   select            container res
#   rev_select        res container

sub type
{
    my( $self, $point ) = @_;

    die "Not implemented" if $point;

    debug_start("type", ' ', $self);

    $self->[NODE][TYPE] or $self->init_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my $selection = $self->declare_selection( [$self->[NODE][TYPES]] );

    debug_end("rev_type");
    return( $selection );
}

sub rev_type
{
    my( $self, $point ) = @_;

    die "Not implemented" if $point;

    debug_start("rev_type", ' ', $self);

    $self->[NODE][REV_TYPE] or $self->init_rev_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my $subjs = [];
    foreach my $subj_id ( keys %{$self->[NODE][REV_TYPE]} )
    {
	# This includes types from all models
	foreach my $model_id ( keys %{$self->[NODE][REV_TYPE]{$subj_id}})
	{
	    if( $self->[NODE][REV_TYPE]{$subj_id}{$model_id} )
	    {
		my $subj = $self->get_node_by_id( $subj_id );
		push @$subjs, $subj;
	    }
	}
    }

    my $selection = $self->declare_selection( $subjs );

    debug_end("rev_type");
    return( $selection );
}


sub arc
{
    my( $self, $point ) = @_;

    debug_start( "arc", ' ', $self );

    if( not defined $point )
    {
	$self->init_props() unless defined $self->[NODE][PROPS];

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $arcs = [];
	foreach my $pred_id ( keys %{$self->[NODE][PROPS]} )
	{
	    push @$arcs, @{$self->[NODE][PROPS]{$pred_id}};
	}
	my $selection = $self->declare_selection( $arcs );

	debug_end("arc");
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}
sub arc_subj
{
    my( $self, $point ) = @_;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    die "Not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_subj", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	$self->init_rev_props( $point ) unless defined
	  $self->[NODE][REV_PROPS]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $subjs = [];
	foreach my $arc (
	      @{$self->[NODE][REV_PROPS]{$point->[NODE][ID]}}
	     )
	{
	    push @$subjs, $arc->subj;
	}
	my $selection = $self->declare_selection( $subjs );

	debug_end("arc_subj");
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_pred
{
    my( $self, $point ) = @_;

    debug_start( "arc_pred", ' ', $self );

    if( not defined $point )
    {
	$self->init_props() unless defined $self->[NODE][PROPS];

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $preds = [];
	foreach my $pred_id ( keys %{$self->[NODE][PROPS]} )
	{
	    push @$preds, $self->get_node_by_id($pred_id);
	}
	my $selection = $self->declare_selection( $preds );

	debug_end("arc_pred");
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_obj
{
    my( $self, $point ) = @_;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    die "Not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_obj", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	$self->init_props( $point ) unless defined
	  $self->[NODE][PROPS]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $objs = [];
	foreach my $arc (
	      @{$self->[NODE][PROPS]{$point->[NODE][ID]}}
	     )
	{
	    push @$objs, $arc->obj;
	}
	my $selection = $self->declare_selection( $objs );

	debug_end("arc_obj");
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub selector
{
    die "not imlemented";

    my $point;
    if( not defined $point ) # Return all arcs
    {
    }
    elsif( ref $point eq 'ARRAY' ) # Return ORed elements
    {
    }
    elsif( ref $point eq 'HASH' ) # Return ANDed elements
    {
    }
    elsif( ref $point eq 'RDF::Service::Context' )
    {
    }
    else
    {
	die "Malformed entry";
    }
}


sub set
{
    my( $self, $model, $types, $props ) = @_;

    # This is practicaly the same as declare_self, except that the
    # changes doesn't get stored

    debug_start("set", ' ', $self);

    die "No model supplied" unless $model->[NODE][URISTR];

    # Should each type and property only be saved in the first best
    # interface and not saved in the following interfaces?  Yes!
    #
    # The types and props taken by one interface must be marked so
    # that the next interface doesn't handle them. This could be done
    # by modifying the arguments $types and $props to exclude those
    # that has been taken care of.

  SET_TYPES:
  {
      $self->[NODE][TYPES] or $self->init_types;

      my @add_types;
      my %del_types;
      foreach my $type ( @{$self->[NODE][TYPES]} )
      {
	  if( $self->[NODE][TYPE]{$type->[NODE][ID]}{$model->[NODE][ID]} )
	  {
	      $del_types{$type->[NODE][ID]} = $type;
	  }
      }

      foreach my $type ( @$types )
      {
	  $type = $self->get( $type ) unless ref $type;
	  if( $del_types{ $type->[NODE][ID] } )
	  {
	      delete $del_types{ $type->[NODE][ID] };
	  }
	  else
	  {
	      push @add_types, $type;
	  }
      }

      if( @add_types )
      {
	  # Will only add each type in one interface
	  $self->declare_add_types( $model, [@add_types] );
	  $self->store_types( $model, [@add_types] );
      }
      if( %del_types )
      {
	  # Will delete types from all interfaces
	  $self->declare_del_types( $model, [values %del_types] );
	  $self->remove_types( $model, [values %del_types] );
      }
  }


  SET_PROPS:
  {
      $self->[NODE][PROPS] or $self->init_props;

      my %add_props;
      my %del_props;

      # This will hold present properties in the model
      # that does not exist in the new set of
      # properties.  Start by adding all present properties and remove
      # the ones that exist in the new property list.

      foreach my $arc ( @{$self->arc->list} )
      {
	  if( $arc->[NODE][MODEL]{$model->[NODE][ID]} )
	  {
	      $del_props{$arc->[NODE][PRED][ID]}{$arc->[NODE][OBJ][ID]} = $arc;
	  }
      }

      # Foreach pred and obj
      foreach my $pred_id ( keys %$props )
      {
	  foreach my $obj ( @{ $props->{$pred_id} } )
	  {
	      # Is the object a literal?
	      if( not ref $obj )
	      {
		  $obj = $self->create_literal(undef, \$obj);
	      }

	      # Does this resource already have the arc?
	      if( $del_props{$pred_id}{$obj->[NODE][ID]} )
	      {
		  delete $del_props{$pred_id}{$obj->[NODE][ID]};
	      }
	      else
	      {
		  push @{$add_props{$pred_id}}, $obj;
	      }
	  }
      }

      if( %add_props )
      {
	  # Will only add each prop in one interface
	  foreach my $pred ( keys %add_props )
	  {
	      foreach my $obj ( @{ $add_props{$pred} } )
	      {
		  $self->declare_add_prop( $pred, $obj, $model );
	      }
	  }
	  $self->store_props( $model, {%add_props} );
      }
      if( %del_props )
      {
	  # Will delete props from all interfaces
	  foreach my $pred_id ( keys %del_props )
	  {
	      foreach my $obj_id ( keys %{ $del_props{$pred_id} } )
	      {
		  $del_props{$pred_id}{$obj_id}->delete_node( $model );
	      }
	  }
      }
  }

    debug_end("set");
    return $self;
}

sub set_literal
{
    my( $self, $model, $lit_str_ref ) = @_;

    debug_start("set_literal", ' ', $self);
    debug "   ($$lit_str_ref)\n", 1;

    $self->declare_literal( $model, $self, $lit_str_ref );
    $self->update_node( $model );

    debug_end("set_literal");
}


sub types_as_string
{
    my( $self ) = @_;
    #
#   die $self->uri."--::".Dumper($self->[TYPES]);
    return join '', map "..".$_->[NODE][URISTR]."\n", @{$self->[NODE][TYPES]};
}


sub to_string
{
    my( $self ) = @_;

    my $str = "";
    no strict 'refs';

    {
	my @urilist = map( $_->[NODE][URISTR], @{ $self->[NODE][TYPES] });
	$str.="TYPES\t: @urilist\n";
    }


    foreach my $attrib (qw( IDS URISTR ID NAME LABEL VALUE FACT PREFIX MODULE_NAME ))
    {
	$self->[NODE][&{$attrib}] and $str.="$attrib\t:".
	    $self->[NODE][&{$attrib}] ."\n";
    }

    foreach my $attrib (qw( NS MODEL ALIASFOR LANG PRED SUBJ OBJ ))
    {
#	my $dd = Data::Dumper->new([$self->[&{$attrib}]]);
#	$str.=Dumper($dd->Values)."\n\n\n";
#	$self->[&{$attrib}] and $str.="$attrib\t:".Dumper($self->[&{$attrib}])."\n";
	$self->[NODE][&{$attrib}] and $str.="$attrib\t:".
	    ($self->[NODE][&{$attrib}][URISTR]||"no value")."\n";
    }

    return $str;
}

sub li
{
    my( $self ) = @_;

    # TODO: Add support for criterions

    my $cnt = @{$self->[NODE][CONTENT]};

    if( $cnt == 1 )
    {
	return $self->[NODE][CONTENT][0];
    }
    else
    {
	die "Selection has $cnt resources, while expecting one\n";
    }
}

sub list
{
    my( $self ) = @_;

    # TODO: Convert the contents to individual objects.  Maby tie the
    # list to a list object for iteration through the list.

    if( $DEBUG )
    {
	my $cnt = @{$self->[NODE][CONTENT]};
	debug "Returning a list of $cnt resources\n", 1;
    }

    return $self->[NODE][CONTENT];
}


######################################################################
#
# Declaration methods should only be called from interfaces.  Since
# they are 'low_level', they should not accept uri's in place of
# objects, etc.
#

sub declare_delete_arc
{
    my( $self, $i ) = @_;

    debug_start("declare_delete_arc", ' ', $self);

    # TODO: remove the dependent dynamic props

    if( my $pred = $self->[NODE][PRED] )
    {
	my $subj = $self->[NODE][SUBJ];
	my $props = $self->[NODE][PROPS]{$pred->[NODE][ID]};
	for( my $i=0; $i<= $#$props; $i++ )
	{
	    if( $props->[$i][NODE][URISTR] eq $self->[NODE][URISTR] )
	    {
		splice( @$props, $i, 1 );
		$i--; # A entry was removed. Compensate
	    }
	}
    }
    debug_end("declare_delete_arc");
}

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

    ref $model eq 'RDF::Service::Context'
      or croak "Bad model";

    # $lit can be node or uristr
    #
    unless( ref $lit )
    {
	unless( defined $lit )
	{
	    $lit = $self->[NODE][URISTR].'#'.&get_unique_id;
	}
	$lit = $self->get( $lit );
    }

    ref $lit_str_ref or die "value must be a reference";

    debug_start("declare_literal", ' ', $self );
    debug "   ( $$lit_str_ref )\n", 1;


    # TODO: Set value as property if value differ among models

    $lit->[NODE][VALUE]     = $lit_str_ref;
    $lit->[NODE][MODEL]{$model->[NODE][ID]} = $model;

    $types ||= [];
    push @$types, NS_RDFS.'Literal', NS_RDFS.'Resource';
    $lit->declare_add_types( $model, $types );

    debug_end("declare_literal");
    return $lit;
}

sub declare_selection
{
    my( $self, $content, $selection ) = @_;


    debug_start("declare_selection", ' ', $self);
    if( $DEBUG )
    {
	my @con_uristr = map $_->[NODE][URISTR], @$content;
	debug "   ( @con_uristr )\n";
    }

    $content ||= [];
    my $model = $self->[WMODEL] or
      die "$self->[NODE][URISTR] doesn't have a defined model";

    unless( ref $selection )
    {
	unless( defined $selection )
	{
	    $selection = $self->[NODE][URISTR].'/'.&get_unique_id;
	}
	$selection = $self->get( $selection );
    }
#    warn "*** Selection is $selection->[NODE][URISTR]\n";

    my $selnode = $selection->[NODE];

    $selnode->[MODEL]{$model->[NODE][ID]} = $model;
    $selnode->[CONTENT] = $content;

    $selection->declare_add_types( $model, [
	  NS_L.'#Selection',
	 ]);

    debug_end("declare_selection");
    return $selection;
}

sub declare_model
{
    my( $self, $model, $obj, $content ) = @_;

    $model or die "model must be defined";
    $content ||= [];

    unless( ref $obj )
    {
	unless( defined $obj )
	{
	    $obj = $self->[NODE][URISTR].'/'.&get_unique_id;
	}
	$obj = $self->get( $obj );
    }

    debug_start("declare_model", ' ', $self );

    my $objnode = $obj->[NODE];

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
    $objnode->[MODEL]{$model->[NODE][ID]} = $model;
    $objnode->[FACT]     = 1; # DEPRECATED
    $objnode->[NS]       = $objnode->[URISTR];
    $objnode->[CONTENT]  = $content;
    $objnode->[READONLY] = 0;
    $objnode->[UPDATED]  = time;

    $obj->declare_add_types( $model, [
	  NS_L.'#Model',
	  NS_RDFS.'Resource',
	 ]);


    debug_end("declare_model");
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

    # This is practicaly the same as set, except that the
    # changes is stored in the handling interface

    debug_start("declare_self", ' ', $self );

    die "No model supplied" unless $model->[NODE][URISTR];

    # Should each type and property only be saved in the first best
    # interface and not saved in the following interfaces?  Yes!
    #
    # The types and props taken by one interface must be marked so
    # that the next interface doesn't handle them. This could be done
    # by modifying the arguments $types and $props to exclude those
    # that has been taken care of.

  SET_TYPES:
  {
      $self->[NODE][TYPES] or $self->init_types;

      my @add_types;
      my %del_types;

      # Look up all types previous added by $model
      #
      foreach my $type ( @{$self->[NODE][TYPES]} )
      {
	  if( $self->[NODE][TYPE]{$type->[NODE][ID]}{$model->[NODE][ID]} )
	  {
	      $del_types{$type->[NODE][ID]} = $type;
	  }
      }

      # Find the diffrence between the new and the existing list of
      # types for $model
      #
      foreach my $type ( @$types )
      {
	  if( $del_types{ $type->[NODE][ID] } )
	  {
	      delete $del_types{ $type->[NODE][ID] };
	  }
	  else
	  {
	      push @add_types, $type;
	  }
      }

      # Add the new types
      #
      if( @add_types )
      {
	  # Will only add each type in one interface
	  $self->declare_add_types( $model, [@add_types] );
      }

      # Remove the old types
      #
      if( %del_types )
      {
	  # Will delete types from all interfaces
	  $self->declare_del_types( $model, [values %del_types] );
      }
  }


  SET_PROPS:
  {
      $self->[NODE][PROPS] or $self->init_props;

      my %add_props;
      my %del_props;

      # This will hold present properties in the model
      # that does not exist in the new set of
      # properties.  Start by adding all present properties and remove
      # the ones that exist in the new property list.

      foreach my $arc ( @{$self->arc->list} )
      {
	  if( $arc->[NODE][MODEL]{$model->[NODE][ID]} )
	  {
	      $del_props{$arc->[NODE][PRED][ID]}{$arc->[NODE][OBJ][ID]} = $arc;
	  }
      }

      # Foreach pred and obj
      foreach my $pred_id ( keys %$props )
      {
	  foreach my $obj ( @{ $props->{$pred_id} } )
	  {
	      # Does this resource already have the arc?
	      if( $del_props{$pred_id}{$obj->[NODE][ID]} )
	      {
		  delete $del_props{$pred_id}{$obj->[NODE][ID]};
	      }
	      else
	      {
		  push @{$add_props{$pred_id}}, $obj;
	      }
	  }
      }

      if( %add_props )
      {
	  # Will only add each prop in one interface
	  foreach my $pred ( keys %add_props )
	  {
	      foreach my $obj ( @{ $add_props{$pred} } )
	      {
		  $self->declare_add_prop( $pred, $obj, $model );
	      }
	  }
      }
      if( %del_props )
      {
	  # Will delete props from all interfaces
	  foreach my $pred_id ( keys %del_props )
	  {
	      foreach my $obj_id ( keys %{ $del_props{$pred_id} } )
	      {
		  $del_props{$pred_id}{$obj_id}->declare_delete_arc;
	      }
	  }
      }
  }

    debug_end("declare_self");
    return 1;
}

sub declare_add_types
{
    my( $self, $model, $types ) = @_;

    debug_start("declare_add_types", ' ', $self );

    # TODO: Should it be model instead of types?

    # TODO: type(Resource) should be added even if not specified

    # The types will be listed in order from the most specific to the
    # most general. rdfs:Resource will allways be last.  Insert
    # implicit items according to subClassOf.

    my $node = $self->[NODE];

    croak "types must be a list ref" unless ref $types;
    croak "Bad model" unless ref $model eq "RDF::Service::Context";

    $node->[TYPE] ||= {};
    $node->[TYPES] ||= [];

    my $subClassOf = $self->get(NS_RDFS.'subClassOf');

    foreach my $type ( @$types )
    {
	$type = $self->get( $type ) unless ref $type;
	my $type_node = $type->[NODE];

	debug "   T $type_node->[URISTR]\n", 1;

	# We wan't to remember what model says what.
	#
	$node->[TYPE]{$type_node->[ID]}{$model->[NODE][ID]} = 1;

	# NB!!! Special handling of some basic classes  in order to
	# avoid cyclic dependencies
	#
	next if $type_node->[URISTR] eq NS_RDFS.'Literal';
	next if $type_node->[URISTR] eq NS_RDFS.'Class';
	next if $type_node->[URISTR] eq NS_RDFS.'Resource';
	next if $type_node->[URISTR] eq NS_RDF.'Statement';
	next if $type_node->[URISTR] eq NS_L.'#Model';
	next if $type_node->[URISTR] eq NS_L.'#Selection';

	# The class init_props creates implicit subClassOf for
	# second and nth stage super classes.  We only have to iterate
	# through the class subClassOf.
	#
	foreach my $sc ( @{$type->arc_obj(NS_RDFS.'subClassOf')->list} )
	{
	    $node->[TYPE]{$sc->[NODE]->[ID]}{$model->[NODE][ID]} = 1;

	    # These types are dependent on the subClasOf statements

	    # TODO: Add dependency
	}
    }


    # Make sure to always return the types in the same
    # order.

    # Create the new complete list
    push @$types, @{$node->[TYPES]};
    $node->[TYPES] = [];
    my %included; # Keep track of included types
    foreach my $type ( @$types )
#    foreach my $type ( sort { $a->level <=> $b->level } @$types )
    {
	push @{$node->[TYPES]}, $type unless $included{$type->[NODE][ID]};
	$included{$type->[NODE][ID]}++;
    }

    # The jumptable must be redone now!
    if( $node->[JUMPTABLE] )
    {
	debug "Resetting the jumptable for ".
	  "$node->[URISTR]: $node->[JTK]\n", 1;
	$node->[JTK] = '--resetted--';
	undef $node->[JUMPTABLE];
    }

    debug_end("declare_add_types");
    return 1;
}

sub declare_add_rev_types
{
    my( $self, $model, $rev_types ) = @_;

    debug_start("declare_add_rev_types", ' ', $self );

    my $node = $self->[NODE];

    croak "rev_types must be a list ref" unless ref $rev_types;
    croak "Bad model" unless ref $model eq "RDF::Service::Context";

    $node->[TYPE] ||= {};

    my $subClassOf = $self->get(NS_RDFS.'subClassOf');

    # Each $rev_type is a resource of type $self
    #
    foreach my $rev_type ( @$rev_types )
    {
	$rev_type = $self->get( $rev_type ) unless ref $rev_type;
	my $rev_type_node = $rev_type->[NODE];
	debug "Adding $rev_type_node->[URISTR]\n",1;

	$node->[REV_TYPE]{$rev_type_node->[ID]}{$model->[NODE][ID]} = 1;

	# Special handling of some basic classes
	#
	die if $rev_type_node->[URISTR] eq NS_RDFS.'Literal';
	die if $rev_type_node->[URISTR] eq NS_RDFS.'Resource';
	die if $rev_type_node->[URISTR] eq NS_RDF.'Statement';

	# I addition to all resources with type $self, we have to
	# include the implicit types.  If a class is a subClasOf $self,
	# we have to add all resources of that type.  init_rev_props()
	# in the RDFS interface should have added the implicit
	# subClassOf for us. But those implicit subClassOf isn't
	# exactly necessary since the subClass rev_types willinclude
	# sub-sub classes.
	#
	debug "..Finding implicit rev_types\n", 1;
	foreach my $sc ( @{$self->arc_subj(NS_RDFS.'subClassOf')->list} )
	{
	    $sc->[NODE][REV_TYPE] or $sc->init_rev_types;

	    # $srt_id: sub_rev_type id
	    foreach my $srt_id ( keys %{$sc->[NODE][REV_TYPE]} )
	    {
		# TODO: What is the correct model for the type arc?
		# This includes types from all models
		foreach my $model_id ( keys %{$sc->[NODE][REV_TYPE]{$srt_id}})
		{
		    if( $sc->[NODE][REV_TYPE]{$srt_id}{$model_id} )
		    {
			my $srt = $self->get_node_by_id( $srt_id );

			$node->[REV_TYPE]{ $srt->[NODE][ID]
					  }{ $model->[NODE][ID]
					 } = 1;
		    }
		}
	    }

	    # These types are dependent on the subClasOf statements

	    # TODO: Add dependency
	}
	debug "..Finding done\n", 1;
    }

    debug_end("declare_add_rev_types");
    return 1;
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

    debug_start("declare_add_dynamic_literal", ' ', $subj );

    croak "Invalid subj" unless ref $subj;
    croak "No subj model" unless ref $subj->[MODEL];

    $pred = $subj->[MODEL]->get( $pred ) unless ref $pred;

    $arc_uristr ||= $model->[NODE][URISTR].'#'.get_unique_id();

    # TODO: This is a implicit object. It's URI should be based on the
    # subject URI
    #
    my $lit = $model->declare_literal( $model, $lit_uristr, $lit_str_ref );

    my $arc = $model->declare_arc( $model, $arc_uristr, $pred, $subj, $lit );

    debug_end("declare_add_dynamic_literal");
    return $arc;
}

sub declare_add_prop
{
    my( $subj, $pred, $obj, $model, $arc_uristr ) = @_;

    $arc_uristr ||= $model->[NODE][URISTR].'#'.get_unique_id();

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


    debug_start("declare_arc", ' ', $self);

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

    my $arc = $self->get( $uristr );

    $pred = $self->get($pred) unless ref $pred;
    $subj = $self->get($subj) unless ref $subj;
    $obj = $obj->get($obj) unless ref $obj;
    $model = $obj->get($model) unless ref $model;

    debug "   P $pred->[NODE][URISTR]\n", 1;
    debug "   S $subj->[NODE][URISTR]\n", 1;
    debug "   O $obj->[NODE][URISTR]\n", 1;

    $arc->[NODE][PRED] = $pred;
    $arc->[NODE][SUBJ] = $subj;
    $arc->[NODE][OBJ]  = $obj;
    $arc->[NODE][MODEL]{$model->[NODE][ID]} = $model;


    $arc->declare_add_types( $model, [NS_RDF.'Statement', NS_RDFS.'Resource'] );

    push @{ $subj->[NODE][PROPS]{$pred->[NODE][ID]} }, $arc;
    push @{ $obj->[NODE][REV_PROPS]{$pred->[NODE][ID]} }, $arc;


    debug_end("declare_arc");
    return $arc;
}





1;


__END__
