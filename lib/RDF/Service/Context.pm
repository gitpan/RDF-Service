#  $Id: Context.pm,v 1.12 2000/11/12 23:25:34 aigan Exp $  -*-perl-*-

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
			    $DEBUG expire );
use Data::Dumper;
use Carp qw( confess cluck croak);

sub new
{
    my( $proto, $node, $context, $wmodel ) = @_;

    # This constructor shouls only be called from get_node, which
    # could be called from find_node or create_node.

    my $class = ref($proto) || $proto;
    my $self = bless [], $class;

    if( ref($proto) )
    {
	$context ||= $proto->[CONTEXT];
	$node    ||= $proto->[NODE]; # The same node in another context?
	$wmodel  ||= $proto->[WMODEL];
    }

    # TODO: Maby perform a deep copy of the context.  At least copy
    # each key-value pair.

    $self->[NODE]    = $node or die;
    $self->[CONTEXT] = $context or die "No context supplied";
    $self->[WMODEL]  = $wmodel or debug "No WMODEL supplied by $proto\n";

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

sub model
{
    my( $self ) = @_;
    die "not implemented";

    # TODO: Should return a selection of models

}


sub get
{
    $_[1] ||= NS_LD."#".&get_unique_id;
    return get_node_by_id( $_[0], uri2id($_[1]) );
}

sub get_node_by_id
{
    my( $self, $id ) = @_;

    # TODO: First look for the object in the cache

    confess "IDS undefined" unless defined $self->[NODE][IDS];
    my $obj = $RDF::Service::Cache::node->{$self->[NODE][IDS]}{ $id };

    unless( $obj )
    {
	# Create an uninitialized object. Any request for the objects
	# properties will initialize the object with the interfaces.

	$obj = $self->[NODE]->new_by_id($id);
	$obj->init_private();

	$RDF::Service::Cache::node->{$self->[NODE][IDS]}{ $id } = $obj;
    }
    else
    {
	debug "Got URI from cache!!!\n", 3;
    }

    debug "get_node( $obj->[URISTR] )\n", 3;

    if( $DEBUG )
    {
	unless( $self->[WMODEL] or
		  $obj->[URISTR] eq NS_LD.'#The_Base_Model' )
	{
	    confess "No WMODEL found for $self->[NODE][URISTR] ";
	}
    }

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
	unless( $obj->is_a(NS_LS.'#Model') )
	{
	    debug "$obj->[NODE][URISTR] is not a model\n", 1;
	    debug $obj->types_as_string, 1;
	    die;
	}
	# setting WMODEL
	$obj->[WMODEL] = $obj;
    }
    else
    {
	debug "Model not existing. Creating it: $uri\n", 1;
	# create_model sets WMODEL
	$obj = $self->create_model( $uri );
    }

    debug_end("get_model");
    return $obj;
}

sub is_a
{
    my( $self, $class ) = @_;

    $class = $self->get( $class ) unless ref $class;

    $self->[NODE][TYPE_ALL] or $self->init_types;
    if( defined $self->[NODE][TYPE]{$class->[NODE][ID]} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub type_orderd_list
{
    my( $self, $i, $point ) = @_;

    # TODO:  This should (as all the other methods) be cached and
    # dpendencies registred.

    die "Not implemented" if $point;
    my $node = $self->[NODE];


    # We can't call level() for the resources used to define level()
    #
    if( $node->[URISTR] =~ /^(@{[NS_RDF]}|@{[NS_RDFS]}|@{[NS_LS]})/o )
    {
	my $type_uri_ref = $Schema->{$self->[NODE][URISTR]}{NS_RDF.'type'};

	return( [$self->get( $$type_uri_ref ),
		 $self->get(NS_RDFS.'Resource')] );
    }

    debug_start("type_orderd_list", ' ', $self);


#  Do we have to have all types to list the *present* defined types?
#    $node->[TYPE_ALL] or $self->init_types;

    my @types = ();
    my %included; # Keep track of included types
    foreach my $type ( sort { $b->level <=> $a->level }
			 map $self->get_node_by_id($_),
		       keys %{$node->[TYPE]}
		      )
    {
	# Check that at least one model defines the type.  Can we
	# assume that the existence of the type (in the hash tree)
	# implies the existence of at least one model (in the hash
	# treee) and that the existence of a model implies that that
	# model has the value 1, meaning that the model states the
	# type?  Yes. Assume that.

	push @types, $type unless $included{$type->[NODE][ID]};
	$included{$type->[NODE][ID]}++;
    }

    debug_end("type_orderd_list");
    return( \@types );
}



# The alternative selectors:
#
#   arc               subj arcs
#   arc_obj           subj arcs objs
#   arc_obj_list      subj arcs objs list
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

    $self->[NODE][TYPE_ALL] or $self->init_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my $selection = $self->declare_selection( $self->type_orderd_list );

    debug_end("rev_type");
    return( $selection );
}


sub rev_type
{
    my( $self, $point ) = @_;

    die "Not implemented" if $point;

    debug_start("rev_type", ' ', $self);

    $self->[NODE][REV_TYPE_ALL] or $self->init_rev_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my %subjs = ();
    foreach my $subj_id ( keys %{$self->[NODE][REV_TYPE]} )
    {
	# This includes types from all models
	foreach my $model_id ( keys %{$self->[NODE][REV_TYPE]{$subj_id}})
	{
	    if( $self->[NODE][REV_TYPE]{$subj_id}{$model_id} )
	    {
		$subjs{$subj_id} = $self->get_node_by_id( $subj_id );
	    }
	}
    }

    my $selection = $self->declare_selection( [values %subjs] );

    debug_end("rev_type");
    return( $selection );
}


sub arc
{
    my( $self, $point ) = @_;

    debug_start( "arc", ' ', $self );

    if( not defined $point )
    {
	# TODO: allow partially initialized props

	$self->init_rev_subjs() unless defined $self->[NODE][REV_SUBJ_ALL];

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $arcs = [];
	foreach my $pred_id ( keys %{$self->[NODE][REV_SUBJ]} )
	{
	    foreach my $arc_node ( @{$self->[NODE][REV_SUBJ]{$pred_id}} )
	    {
		push @$arcs, $self->new($arc_node);
	    }
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
	$self->init_rev_objs( $point ) unless defined
	  $self->[NODE][REV_OBJ]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $subjs = [];
	foreach my $arc_node (
	      @{$self->[NODE][REV_OBJ]{$point->[NODE][ID]}}
	     )
	{
	    push @$subjs, $self->new( $arc_node )->subj;
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
	$self->init_rev_subjs() unless defined $self->[NODE][REV_SUBJ_ALL];

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $preds = [];
	foreach my $pred_id ( keys %{$self->[NODE][REV_SUBJ]} )
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
	$self->init_rev_subjs( $point ) unless defined
	  $self->[NODE][REV_SUBJ]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $objs = [];
	foreach my $arc_node (
	      @{$self->[NODE][REV_SUBJ]{$point->[NODE][ID]}}
	     )
	{
	    push @$objs, $self->new( $arc_node )->obj;
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

sub arc_obj_list
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
	$self->init_rev_subjs( $point ) unless defined
	  $self->[NODE][REV_SUBJ]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $objs = [];
	foreach my $arc_node (
	      @{$self->[NODE][REV_SUBJ]{$point->[NODE][ID]}}
	     )
	{
	    push @$objs, $self->new( $arc_node )->obj;
	}

	debug_end("arc_obj");
	return $objs;
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
    my( $self, $types, $props ) = @_;

    # This is practicaly the same as declare_self.  set() updates the
    # data in the interfaces.

    debug_start("set", ' ', $self);

    my $node = $self->[NODE];
    my $model = $self->[WMODEL];

    # Should each type and property only be saved in the first best
    # interface and not saved in the following interfaces?  Yes!
    #
    # The types and props taken by one interface must be marked so
    # that the next interface doesn't handle them. This could be done
    # by modifying the arguments $types and $props to exclude those
    # that has been taken care of.

  SET_TYPES:
  {
      $node->[TYPE_ALL] or $self->init_types;

      my @add_types;
      my %del_types;
      foreach my $type ( @{$self->type_orderd_list} )
      {
	  if( $node->[TYPE]{$type->[NODE][ID]}{$model->[NODE][ID]} )
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
	  $self->declare_add_types( [@add_types] );
	  $self->store_types( [@add_types] );
      }
      if( %del_types )
      {
	  # Will delete types from all interfaces
	  $self->declare_del_types( [values %del_types] );
	  $self->remove_types( [values %del_types] );
      }
  }


  SET_PROPS:
  {
      $node->[REV_SUBJ_ALL] or $self->init_rev_subjs;

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
		  $self->declare_add_prop( $pred, $obj );
	      }
	  }
	  $self->store_props( [ keys %add_props ] );
      }
      if( %del_props )
      {
	  # Will delete props from all interfaces
	  foreach my $pred_id ( keys %del_props )
	  {
	      foreach my $obj_id ( keys %{ $del_props{$pred_id} } )
	      {
		  $del_props{$pred_id}{$obj_id}->delete_node();
	      }
	  }
      }
  }

    debug_end("set");
    return $self;
}

sub set_literal
{
    my( $self, $lit_str_ref ) = @_;

    debug_start("set_literal", ' ', $self);
    debug "   ($$lit_str_ref)\n", 1;

    $self->declare_literal( $lit_str_ref, $self,  );
    warn "***** ${$self->[NODE][VALUE]} *****\n";
    $self->update_node();

    debug_end("set_literal");
}


sub types_as_string
{
    my( $self ) = @_;
    #
#   die $self->uri."--::".Dumper($self->[TYPES]);
    return join '', map "t ".$_->[NODE][URISTR]."\n",
      map $self->get_node_by_id($_),
	keys %{$self->[NODE][TYPE]};
}


sub to_string
{
    my( $self ) = @_;

    # Old!

    my $str = "";
    no strict 'refs';

    $str.="TYPES\t: ". $self->types_as_string ."\n";

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
# Declaration methods should only be called from interfaces.
#

sub declare_del_node
{
    my( $self ) = @_;

    debug_start("declare_del_node", ' ', $self);

    # Only deletes the part of the node associated with the WMODEL

    if( $DEBUG )
    {
	unless( ref $self eq 'RDF::Service::Context' )
	{
	    confess "Self $self not Context";
	}
    }


    my $node = $self->[NODE];
    my $wmodel = $self->[WMODEL];
    my $wmodel_id = $wmodel->[NODE][ID];

    delete $self->[MODEL]{$wmodel_id};

    $self->declare_del_types;
    $self->declare_del_rev_types;

    for(my $j=0; $j<= $#{$node->[REV_PRED]}; $j++)
    {
	# This model does not longer define the arc.  Remove the
	# property unless another model also defines the arc.

	my $arc_node = $node->[REV_PRED][$j];
	next unless delete $arc_node->[MODEL]{$wmodel_id};
	splice @{$node->[REV_PRED]}, $j--, 1
	  unless keys %{$arc_node->[MODEL]};

	$self->new($arc_node)->declare_del_node;
    }

    foreach my $subj_id ( keys %{$node->[REV_SUBJ]} )
    {
	for(my $j=0; $j<= $#{$node->[REV_SUBJ]{$subj_id}}; $j++ )
	{
	    # This model does not longer define the arc.  Remove the
	    # property unless another model also defines the arc.

	    my $arc_node = $node->[REV_SUBJ]{$subj_id}[$j];
	    next unless delete $arc_node->[MODEL]{$wmodel_id};
	    splice @{$node->[REV_SUBJ]{$subj_id}}, $j--, 1
	      unless keys %{$arc_node->[MODEL]};

	    $self->new($arc_node)->declare_del_node;
	}
	delete $node->[REV_SUBJ]{$subj_id}
	  unless @{$node->[REV_SUBJ]{$subj_id}};
    }

    foreach my $obj_id ( keys %{$node->[REV_OBJ]} )
    {
	for(my $j=0; $j<= $#{$node->[REV_OBJ]{$obj_id}}; $j++ )
	{
	    # This model does not longer define the arc.  Remove the
	    # property unless another model also defines the arc.

	    my $arc_node = $node->[REV_OBJ]{$obj_id}[$j];
	    next unless delete $arc_node->[MODEL]{$wmodel_id};
	    splice @{$node->[REV_OBJ]{$obj_id}}, $j--, 1
	      unless keys %{$arc_node->[MODEL]};

	    $self->new($arc_node)->declare_del_node;
	}
	delete $node->[REV_OBJ]{$obj_id}
	  unless @{$node->[REV_OBJ]{$obj_id}};
    }

    # Should we delete the whole node?
    #
    if( keys %{$self->[MODEL]} ) # Has another model defined this node?
    {
	# TODO: Something to do here?
    }
    else
    {
	# Is this a statement?
	if( $node->[PRED] )
	{
	    # Expire all dependent lists
	    $node->[PRED][NODE][REV_PRED] = undef;
	    $node->[PRED][NODE][REV_PRED_ALL] = undef;
	    $node->[SUBJ][NODE][REV_SUBJ] = undef;
	    $node->[SUBJ][NODE][REV_SUBJ_ALL] = undef;
	    $node->[OBJ][NODE][REV_OBJ] = undef;
	    $node->[OBJ][NODE][REV_OBJ_ALL] = undef;
	}

	$node = undef;
    }

    debug_end("declare_del_node");
}

sub declare_del_types
{
    my( $self, $types ) = @_;

    debug_start("declare_del_types", ' ', $self);

    my $node_type = $self->[NODE][TYPE];
    my $model_id = $self->[WMODEL][NODE][ID];
    my $id = $self->[NODE][ID];

    my @ids = ();
    if( defined $types )
    {
	@ids = map $_->[NODE][ID], @$types;
    }
    else
    {
	@ids = keys %$node_type;
    }

    foreach my $type_id ( @ids )
    {
	next unless delete $node_type->{$type_id}{$model_id};

	my $class_rev_type =
	  $self->get_node_by_id($type_id)->[NODE][REV_TYPE];

	delete $class_rev_type->{$id}{$model_id};

	unless( keys %{$node_type->{$type_id}} )
	{
	    delete $node_type->{$type_id};
	    delete $class_rev_type->{$id};
	}
    }

    debug_end("declare_del_types");
}

sub declare_del_rev_types
{
    my( $self, $res ) = @_;

    debug_start("declare_del_rev_types", ' ', $self);

    my $class_rev_type = $self->[NODE][REV_TYPE];
    my $model_id = $self->[WMODEL][NODE][ID];
    my $id = $self->[NODE][ID];

    my @ids = ();
    if( defined $res )
    {
	@ids = map $_->[NODE][ID], @$res;
    }
    else
    {
	@ids = keys %$class_rev_type;
    }

    foreach my $res_id ( @ids )
    {
	next unless delete $class_rev_type->{$res_id}{$model_id};

	my $type = $self->get_node_by_id($res_id)->[NODE][TYPE];

	delete $type->{$id}{$model_id};

	unless( keys %{$class_rev_type->{$res_id}} )
	{
	    delete $class_rev_type->{$res_id};
	    delete $type->{$id};
	}
    }

    debug_end("declare_del_rev_types");
}

sub declare_literal
{
    my( $self, $lit_str_ref, $lit, $types, $props, $model ) = @_;
    #
    # - $model is a resource object
    # - $lit (uri or node or undef)
    # - $lref will be a scalar ref
    # - $types is ref to array of type objects or undef
    # - $props is hash ref with remaining properties or undef

    # $types and $props is not done yet

    # $lit can be node or uristr
    #
    unless( ref $lit )
    {
	unless( defined $lit )
	{
	    $lit = NS_LD."/literal/". &get_unique_id;
	}
	$lit = $self->get( $lit );
    }

    ref $lit_str_ref or die "value must be a reference";

    debug_start("declare_literal", ' ', $self );
    debug "   ( $$lit_str_ref )\n", 1;


    # TODO: Set value as property if value differ among models

    $model ||= $self->[WMODEL];
    $lit->[NODE][VALUE]     = $lit_str_ref;
    $lit->[NODE][MODEL]{$model->[NODE][ID]} = $model;


    $lit->declare_self( [NS_RDFS.'Literal', NS_RDFS.'Resource']);

    debug_end("declare_literal");
    return $lit;
}

sub declare_selection
{
    my( $self, $content, $selection ) = @_;


    debug_start("declare_selection", ' ', $self);
    if( $DEBUG )
    {
	confess unless ref $content;
	my @con_uristr = ();
	foreach my $res ( @$content )
	{
	    confess "$res no Resource" unless ref $res and ref $res->[NODE];
	    push @con_uristr, $res->[NODE][URISTR];
	}
	debug "   ( @con_uristr )\n";
    }

    $content ||= [];
    my $model = $self->[WMODEL] or
      die "$self->[NODE][URISTR] doesn't have a defined model";

    unless( ref $selection )
    {
	unless( defined $selection )
	{
	    $selection = NS_LD.'/selection/'.&get_unique_id;
	}
	$selection = $self->get( $selection );
    }
#    warn "*** Selection is $selection->[NODE][URISTR]\n";

    my $selnode = $selection->[NODE];

    $selnode->[MODEL]{$model->[NODE][ID]} = $model;
    $selnode->[CONTENT] = $content;

    $selection->declare_add_types( [NS_LS.'#Selection'] );

    debug_end("declare_selection");
    return $selection;
}

sub declare_model
{
    my( $self, $obj, $content ) = @_;

    $content ||= [];

    unless( ref $obj )
    {
	unless( defined $obj )
	{
	    $obj = NS_LD."/model/".&get_unique_id;
	}
	$obj = $self->get( $obj );
    }

    debug_start("declare_model", ' ', $self );

    my $obj_node = $obj->[NODE];

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
    $obj_node->[MODEL]{$obj->[WMODEL][NODE][ID]} = $self->[WMODEL];
    $obj_node->[FACT]     = 1; # DEPRECATED
    $obj_node->[NS]       = $obj_node->[URISTR];
    $obj_node->[CONTENT]  = $content;
    $obj_node->[READONLY] = 0;
    $obj_node->[UPDATED]  = time;
    $obj->[WMODEL] = $obj;

    $obj->declare_self( [
	  NS_LS.'#Model',
	  NS_RDFS.'Resource',
	 ]);

    debug_end("declare_model");
    return $obj;
}

sub declare_node
{
    my( $self, $uri, $types, $props );

    die "Not done";
}

sub declare_self
{
    my( $self, $types, $props ) = @_;

    # This is practicaly the same as set.  declare_self does not store
    # the changes in the interfaces

    debug_start("declare_self", ' ', $self );

    my $node = $self->[NODE];
    my $model = $self->[WMODEL];

    # Should each type and property only be saved in the first best
    # interface and not saved in the following interfaces?  Yes!
    #
    # The types and props taken by one interface must be marked so
    # that the next interface doesn't handle them. This could be done
    # by modifying the arguments $types and $props to exclude those
    # that has been taken care of.

  SET_TYPES:
  {
      $node->[TYPE_ALL] or $self->init_types;

      my @add_types;
      my %del_types;

      # Look up all types previous added by $model
      #
      foreach my $type ( @{$self->type_orderd_list} )
      {
	  if( $node->[TYPE]{$type->[NODE][ID]}{$model->[NODE][ID]} )
	  {
	      $del_types{$type->[NODE][ID]} = $type;
	  }
      }

      # Find the diffrence between the new and the existing list of
      # types for $model
      #
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

      # Add the new types
      #
      if( @add_types )
      {
	  # Will only add each type in one interface
	  $self->declare_add_types( [@add_types] );
      }

      # Remove the old types
      #
      if( %del_types )
      {
	  # Will delete types from all interfaces
	  $self->declare_del_types( [values %del_types] );
      }
  }

  SET_PROPS:
  {
      $node->[REV_SUBJ_ALL] or $self->init_rev_subjs;

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
		  $self->declare_add_prop( $pred, $obj );
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
		  $del_props{$pred_id}{$obj_id}->declare_del_node;
	      }
	  }
      }
  }

    debug_end("declare_self");
    return 1;
}

sub declare_add_types
{
    my( $self, $types ) = @_;

    debug_start("declare_add_types", ' ', $self );

    # TODO: Should it be model instead of types?

    # TODO: type(Resource) should be added by base init_types

    # The types will be listed in order from the most specific to the
    # most general. rdfs:Resource will allways be last.  Insert
    # implicit items according to subClassOf.

    my $node = $self->[NODE];
    my $model = $self->[WMODEL];

    if( $DEBUG )
    {
	croak "types must be a list ref" unless ref $types;
	croak "Bad model" unless
	  ref $model eq "RDF::Service::Context";
    }

    my $model_node_id = $model->[NODE][ID];
    foreach my $type ( @$types )
    {
	# This should update the $types listref
	#
	$type = $self->get( $type ) unless ref $type;
	debug("    T $type->[NODE][URISTR]\n", 2);

	# Duplicate types in the same model will merge
	#
	$node->[TYPE]{$type->[NODE][ID]}{$model_node_id} = 1;
	$type->[NODE][REV_TYPE]{$node->[ID]}{$model_node_id} = 1;
    }


    # TODO: Separate the dynamic types to a separate init_types



    # TODO: Maby place in separate method

    # Add the implicit types for $node.  This is done in a second loop
    # in order to resolv cyclic dependencies.
    # TODO: Check that this generates the right result.
    #
    my $subClassOf = $self->get(NS_RDFS.'subClassOf');
    foreach my $type ( @$types )
    {
 	# NB!!! Special handling of some basic classes  in order to
 	# avoid cyclic dependencies
 	#
	my $type_node = $type->[NODE];
 	next if $type_node->[URISTR] eq NS_RDFS.'Literal';
 	next if $type_node->[URISTR] eq NS_RDFS.'Class';
 	next if $type_node->[URISTR] eq NS_RDFS.'Resource';
 	next if $type_node->[URISTR] eq NS_RDF.'Statement';
 	next if $type_node->[URISTR] eq NS_LS.'#Selection';


 	# The class init_rev_subjs creates implicit subClassOf for
 	# second and nth stage super classes.  We only have to iterate
 	# through the subClassOf properties of the type.
 	#
 	foreach my $sc ( @{$type->arc_obj_list(NS_RDFS.'subClassOf')} )
 	{
 	    $node->[TYPE]{$sc->[NODE][ID]}{$model->[NODE][ID]} = 1;
 	    # These types are dependent on the subClasOf statements
 	    # TODO: Add dependency
 	}
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
    my( $self, $rev_types ) = @_;

    debug_start("declare_add_rev_types", ' ', $self );

    # NOTE:  We can't merge with declare_add_types().  Since we want
    # to have a complete list of types, we would have to initialize in
    # both directions. If you declare somthing to be of type Person,
    # you would have to initialize rev_type for Person.

    my $node = $self->[NODE];
    my $model = $self->[WMODEL];

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
	# we have to add all resources of that type.  init_rev_objs()
	# in the RDFS interface should have added the implicit
	# subClassOf for us. But those implicit subClassOf isn't
	# exactly necessary since the subClass rev_types will include
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
    my( $subj, $pred, $lit_str, $arc_uristr ) = @_;
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
    my( $subj, $pred, $lit_str_ref, $lit_uristr, $arc_uristr, $model ) = @_;
    #
    # $lit_str is a scalar ref
    #
    # The URI of a dynamic literal represents the property for the
    # specific subject.  The literal changes content as the subjects
    # property changes.  (The literal static/dynamic type info is not
    # stored)

    debug_start("declare_add_dynamic_literal", ' ', $subj );

    croak "Invalid subj" unless ref $subj;
    croak "No subj model" unless ref $subj->[NODE][MODEL];

    $pred = $subj->get( $pred ) unless ref $pred;
    $model ||= $subj->[WMODEL];

    $arc_uristr ||= NS_LD."/literal/".get_unique_id();

    # TODO: This is a implicit object. It's URI should be based on the
    # subject URI
    #
    my $lit = $subj->declare_literal( $lit_str_ref,
				      $lit_uristr,
				      undef,
				      undef,
				      $model,
				     );

    my $arc = $subj->declare_add_prop( $pred, $lit, $arc_uristr, $model );

    debug_end("declare_add_dynamic_literal");
    return $arc;
}

sub declare_add_prop
{
    my( $subj, $pred, $obj, $arc_uristr, $model ) = @_;

    $model ||= $subj->[WMODEL];

    my $arc = $subj->declare_arc( $pred,
				  $subj,
				  $obj,
				  $arc_uristr,
				  $model,
				 );

    return $arc;
}

sub declare_arc
{
    my( $self, $pred, $subj, $obj, $uristr, $model ) = @_;

    # It *could* be that we have two diffrent arcs with the same URI,
    # if they comes from diffrent models.  The common case is that the
    # arcs with the same URI are identical.  The PRED, SUBJ, OBJ slots
    # are used for the common case.
    #
    # TODO: Use explicit properties if the models differs.
    #
    # All models says the same thing unless the properties are
    # explicit.

    # A defined [REV_SUBJ] only means that some props has been
    # defined. It doesn't mean that ALL props has been defined.

    # A existing prop key with an undef value means that we know that
    # the prop doesn't exist.  But a look for a nonexisting prop sould
    # (for now) trigger a complete initialization and set the complete
    # key.

    # The concept of "complete list" depends on other selection.
    # Diffrent selections will have diffrent lists.  Every such
    # selection will be saved separately from the [REV_SUBJ] list.
    # It's existence guarantee that the list is complete.

    debug_start("declare_arc", ' ', $self);

    if( $uristr )  # arc could be changed
    {
	# TODO: Check that tha agent owns the namespace
	# For now: Just allow models in the local namespace
	my $ns_l = NS_LD;
	unless( $uristr =~ /$ns_l/ )
	{
	    confess "Invalid namespace for literal: $uristr";
	}
    }
    else  # The arc is created
    {
	# Who will know anything about this arc?  There could be
	# statements about it later, but not now.

	$uristr = NS_LD."/arc/". &get_unique_id;

	# TODO: Call a miniversion of add_types that knows that no other
	# types has been added.  We should not require the setting of
	# types and props to initialize itself. The initialization
	# should be done here.
    }

    # Prioritize submitted $model
    #
    $model ||= $self->[WMODEL];


    my $arc = $self->get( $uristr );
    my $arc_node = $arc->[NODE];

    $model or die "*** No WMODEL for arc $arc_node->[URISTR]\n";
    $arc_node->[IDS] or die "*** No IDS for arc $arc_node->[URISTR]\n";



    $pred = $self->get($pred) unless ref $pred;
    $subj = $self->get($subj) unless ref $subj;
    $obj = $obj->get($obj) unless ref $obj;

    debug "   P $pred->[NODE][URISTR]\n", 1;
    debug "   S $subj->[NODE][URISTR]\n", 1;
    debug "   O $obj->[NODE][URISTR]\n", 1;
    debug "   M $model->[NODE][URISTR]\n", 1;
    debug "   A $arc->[NODE][URISTR]\n", 1;

    $arc_node->[PRED] = $pred;
    $arc_node->[SUBJ] = $subj;
    $arc_node->[OBJ]  = $obj;
    $arc_node->[MODEL]{$model->[NODE][ID]} = $model;

    push @{ $subj->[NODE][REV_SUBJ]{$pred->[NODE][ID]} }, $arc_node;
    push @{ $obj->[NODE][REV_OBJ]{$pred->[NODE][ID]} }, $arc_node;


    # TODO: declare_self should only be used if a existing arc is
    # changed. New arc should not call declare_self since that forces
    # an deep initialization of itself.

    $arc->declare_self( [NS_RDF.'Statement', NS_RDFS.'Resource'] );

    debug_end("declare_arc");
    return $arc;
}





1;


__END__
