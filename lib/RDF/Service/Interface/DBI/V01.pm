#  $Id: V01.pm,v 1.22 2000/11/10 18:41:37 aigan Exp $  -*-cperl-*-

package RDF::Service::Interface::DBI::V01;

#=====================================================================
#
# DESCRIPTION
#   Interface to storage and retrieval of statements in a general purpouse DB
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
use DBI;
#use POSIX;
#use Time::HiRes qw( time );
use Time::Object;
use Date::Parse;
use vars qw( $prefix $interface_uri @node_fields );
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( get_unique_id uri2id id2uri debug $DEBUG );
use RDF::Service::Resource;
use Data::Dumper;
use Carp;


$prefix = [ ];

# Todo: Decide on a standard way to name functions
# # Will not use the long names in this version...
$interface_uri = "org.cpan.RDF.Interface.DBI.V01";

@node_fields = qw( id uri iscontainer isprefix
	     label aliasfor
	     pred distr subj obj fact model
	     member
	     updated readonly agent source
	     isliteral lang value );


sub register
{
    my( $i, $args ) = @_;

    my $connect = $args->{'connect'} or croak "Connection string missing";
    my $name    = $args->{'name'} || "";
    my $passwd  = $args->{'passwd'} || "";

    my $dbi_options =
    {
	RaiseError => 0,
    };

    my $dbh = ( DBI->connect( $connect, $name, $passwd, $dbi_options ) );


    die "Connect to $connect failed\n" unless $dbh;

    # Maby we should store interface data in a special hash instead,
    # like interface($interface->[ID])->{'dbh'}... But that seams to
    # be just as long.  Another alternative would be to reserve a
    # range especially for interfaces.
    #
    #
    # This interface module can be used for connection to several
    # diffrent DBs.  Every such connection will have the same methods
    # but the method calls will give diffrent results.  It is diffrent
    # interface objects but the same interface module.
    #
    debug "Store DBH for $i->[URISTR] in ".
	"[PRIVATE]{$i->[ID]}{'dbh'}\n", 3;

    $i->[PRIVATE]{$i->[ID]}{'dbh'} = $dbh;

    return
    {
	'' =>
	{
	    NS_LS.'#Service' =>
	    {
	    },
	    NS_LS.'#interface' =>
	    {
		#'list_arcs' => [\&list_arcs],
	    },
	    NS_LS.'#Model' =>
	    {
		'create_model'    => [\&create_model],
		'add_arc'        => [\&add_arc],
		'find_arcs_list' => [\&find_arcs_list],
	    },
	    NS_RDFS.'Resource'   =>
	    {
		'init_types'     => [\&init_types],
		'init_rev_subjs' => [\&init_rev_subjs],
		'init_rev_objs'  => [\&init_rev_objs],
		'name'           => [\&name],
		'find_node'      => [\&find_node],
		'create_literal' => [\&create_literal],
		'store_types'    => [\&store_types],
		'store_props'    => [\&store_props],
		'update_node'    => [\&update_node],
		'remove'         => [\&remove],
		'remove_types'   => [\&remove_types],
		'remove_props'   => [\&remove_props],
	    },
	    NS_RDFS.'Class' =>
	    {
		'objects_list' => [\&objects_list],
		'init_rev_types' => [\&init_rev_types],
	    },
	},
    };
}



sub find_node
{
    my( $self, $i, $uristr ) = @_;
    #
    # Is the node contained in the model?

    my $p = {}; # Interface private data
    my $obj;

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select id, refid, refpart, hasalias from uri
              where string=?
              ");
    $sth->execute( $uristr );

    my( $r_id, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_id, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$p->{'uri'} = $r_id;

	$obj = $self->get( $uristr );
	$obj->[NODE][PRIVATE]{$i->[ID]} = $p;
    }
    $sth->finish; # Release the handler

    return( $obj, 1 ) if defined $obj;
    return undef;
}

sub find_arcs_list
{
    my( $self, $i, $pred, $subj, $obj ) = @_;
    #
    # TODO: This will primarly return explicit arcs. But should also
    # return many implicit arcs.  Fo not return type arcs.

    die "Not implemented";
}

sub objects_list   ### DEPRECATED
{
    my( $self, $i ) = @_;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select node
              from type
              where type = ?
              ");

    # TODO: expand the type list to all subtypes that explicitly is
    # the type. Also make special exceptions for types stored implicit
    # or are specially handled.
    #
    my $types = [ $self ];

    my $objects = [];

    foreach my $type ( @$types )
    {
	my $r_type = &_get_id( $type, $i );
	$sth->execute( $r_type );
	while( my($r_node) = $sth->fetchrow_array )
	{
	    # TODO: Inline the _get_node() functionality in order to
	    # eliminate all the DBI queries for the individual
	    # resources.

	    push @$objects, &_get_node( $r_node, $self, $i );
	}
	$sth->finish;
    }

    return( $objects, 2 );
}

sub name
{
    # Will give the part of the URI following the 'namespace'
    die "not implemented";
}

sub add_arc
{
    my( $self, $i, $uristr, $pred, $subj, $obj ) = @_;

    # Assuems that the arc does not exist

    my $arc = $self->declare_arc($pred,
				 $subj,
				 $obj,
				 $uristr,
				);


    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", @node_fields;
    my $place_str = join ", ", ('?')x @node_fields;

    my $sth = $dbh->prepare_cached("  insert into node
				      ($field_str)
				      values ($place_str)
				      ");


    # TODO: Handle if arc already exist
    #    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    my %p = ();
    $p{'id'}     ||= &_nextval($dbh);

    $p{'uri'}         = &_create_uri( $arc->uri, $i);
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'label'}       = undef;
    $p{'aliasfor'}    = undef;
    $p{'pred'}        = &_get_id( $arc->pred, $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        = &_get_id( $arc->subj, $i);
    $p{'obj'}         = &_get_id( $arc->obj, $i);
    $p{'fact'}        = 'true';
    $p{'model'}       = &_get_id( $arc->model, $i);
    $p{'member'}      = undef;
    $p{'updated'}     = undef;
    $p{'readonly'}    = undef;
    $p{'agent'}       = undef;
    $p{'source'}      = undef;
    $p{'isliteral'}   = 'false';
    $p{'lang'}        = undef;
    $p{'value'}       = undef;


    $sth->execute( map $p{$_}, @node_fields )
	or confess( $sth->errstr );

    return( 1, 1 );
}

sub init_rev_subjs
{
    my( $self, $i, $constraint ) = @_;

    # This should initiate all props from this interface


    # TODO: Use the constraint

    $self->[NODE][TYPE_ALL] or $self->init_types;

    # TODO: Should props be undef if type changes?

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    # TODO: Also read all the other node data

    my $sth = $dbh->prepare_cached("
              select auri.string as arc,
                     puri.string as pred,
                     suri.string as subj,
                     ouri.string as obj,
                     muri.string as model
              from node,
                   uri auri,
                   uri puri,
                   uri suri,
                   uri ouri,
                   uri muri
              where node.pred  = puri.id and
                    node.subj  = suri.id and
                    node.obj   = ouri.id and
                    node.model = muri.id and
                    node.uri   = auri.id and
                    suri.string = ?
              ");

    $sth->execute( $self->[NODE][URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    debug "Fetching props\n", 1;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self->get( $r->{'pred'} );
	my $subj   = $self;
	my $obj    = $self->get( $r->{'obj'} );
	my $model  = $self->get( $r->{'model'} );
	debug "..Found a $pred->[NODE][URISTR]\n", 1;

	$subj->declare_add_prop( $pred, $obj, $r->{'arc'}, $model );
    }

    $self->[NODE][REV_SUBJ_ALL] = 1;

    return( 1, 3 );
}

sub init_rev_objs
{
    my( $self, $i, $constraint ) = @_;

    # This should get all rev_props from this interface


    # TODO: Use the constraint


    $self->[NODE][TYPE_ALL] or $self->init_types;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    # TODO: Also read all the other node data

    my $sth = $dbh->prepare_cached("
              select auri.string as arc,
                     puri.string as pred,
                     suri.string as subj,
                     ouri.string as obj,
                     muri.string as model
              from node,
                   uri auri,
                   uri puri,
                   uri suri,
                   uri ouri,
                   uri muri
              where node.pred  = puri.id and
                    node.subj  = suri.id and
                    node.obj   = ouri.id and
                    node.model = muri.id and
                    node.uri   = auri.id and
                    ouri.string = ?
              ");

#    warn "*** $self->[NODE][URISTR]\n";

    $sth->execute( $self->[NODE][URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    debug "Fetching rev_props\n", 1;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self->get( $r->{'pred'} );
	my $subj   = $self->get( $r->{'subj'} );
	my $obj    = $self;
	my $model  = $self->get( $r->{'model'} );
	debug "..Found a $pred->[NODE][URISTR]\n", 1;

	$subj->declare_add_prop( $pred, $obj, $r->{'arc'} );
    }

    $self->[NODE][REV_OBJ_ALL] = 1;

    return( 1, 3 );
}

sub init_types
{
    my( $self, $i ) = @_;
    #
    # Read the types from the DBI.  Get all info from the node
    # record

    # TODO: Get the implicite types from subClassOf (Handled by
    # RDFS_200001)


    debug "Init types for $self->[NODE][URISTR]\n", 2;

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};
    $p{'uri'} ||= &_get_id($self, $i);

    my $types = [];

  Node:
    {
	# TODO: Reuse cols variable and sth
	my @cols = qw( id iscontainer isprefix label aliasfor
		       model pred distr subj obj fact member updated
		       readonly agent source isliteral lang value blob
		       );
	my $fields = join ", ", @cols;

	my $sth_node = $dbh->prepare_cached("
              select $fields
              from node
              where uri=?
              ");

	my $true = '1';
	my  $false = '0';

	$sth_node->execute( $p{'uri'} );
	my $tbl = $sth_node->fetchall_arrayref({});
	$sth_node->finish; # The fetchall should finish the sth implicitly
	foreach my $r ( @$tbl )
	{
	    # TODO: Go through all the varables

	    # iscontainer

	    # isprefix

	    # label  (there can be only one!)
	    if( $r->{'label'} )
	    {
		if( $self->[NODE][LABEL] )
		{
		    $self->[NODE][LABEL] .= " /  $r->{'label'}";
		}
		else
		{
		    $self->[NODE][LABEL] = $r->{'label'};
		}
	    }

	    # aliasfor

	    # model
	    my $model= &_get_node($r->{'model'}, $self, $i);
	    $self->[NODE][MODEL]{$model->[NODE][ID]} = $model;

	    # pred distr subj obj fact
	    if( my $r_pred = $r->{'pred'} )
	    {
		push @$types, NS_RDF.'Statement';
	    }

	    # member

	    # updated readonly agent source
	    if( my $r_updated = $r->{'updated'} )
	    {
		push @$types, NS_LS.'#Model';

		my $lit_uristr = $self->[NODE][URISTR]."#updated";
		$self->declare_add_dynamic_literal(NS_LS.'updated',
						   \$r_updated,
						   $lit_uristr,
						   undef,
						   $model,
						   );


	    # TODO: Change this to be more RDF style!
		if(0) #if( defined $r->{'readonly'} )
		{
		    my $p_readonly = $self->get(NS_LS.'readonly');
		    if( ($r->{'readonly'} eq $true) or ($r->{'readonly'} eq $false) )
		    {
			my $bool = $r->{'readonly'}; # Copy the value

			# TODO: Change this
			$self->declare_add_static_literal($p_readonly,
							  \$bool,
							  );
		    }
		    else
		    {
			die "Malformed value ($r->{'readonly'})";
		    }
		}

		# agent
		# source
	    }

	    # isliteral, lang, value, blob
	    if( $r->{'isliteral'} eq $true )
	    {
		debug "..Literal: $self->[NODE][URISTR]\n", 2;
		if( $r->{'value'} )
		{
		    $self->[NODE][VALUE] = \ ($r->{'value'});
		    push @$types, NS_RDFS.'Literal';
		}
		else
		{
		    die "not implemented";
		}
	    }
	    $self->declare_add_types( $types );
	}
    }


  Types:
    {
	my $sth_types = $dbh->prepare_cached("
              select type.id, string, type, model
              from type, uri
              where node=? and uri.id=type and fact=TRUE
              ");

	$sth_types->execute( $p{'uri'} );
	my $tbl = $sth_types->fetchall_arrayref({});
	$sth_types->finish;
	foreach my $r ( @$tbl )
	{
	    my $type = $self->get($r->{'string'});
	    my $model = &_get_node( $r->{'model'}, $self, $i );

	    # Remember the record ID
	    $type->[NODE][PRIVATE]{$i->[ID]}{'uri'} = $r->{'type'};

	    # TODO: Maby group the types before creating them
	    $self->declare_add_types( [$type] );
	}
    }

    debug "Types for $self->[NODE][URISTR]\n", 1;
    debug $self->types_as_string, 1;

    $self->[NODE][TYPE_ALL] = 1;

    return( 1, 3 );
}

sub init_rev_types
{
    my( $self, $i ) = @_;
    #
    # Read the types from the DBI.

    # TODO: Get the implicite types from subClassOf. ( Should be
    # handled by declare_add_rev_types )

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};
    $p{'uri'} ||= &_get_id($self, $i);

    my $rev_types = [];

    my $sth_rev_types = $dbh->prepare_cached("
              select type.id, string, node, model
              from type, uri
              where type=? and uri.id=node and fact=TRUE
              ");

    $sth_rev_types->execute( $p{'uri'} );
    my $tbl = $sth_rev_types->fetchall_arrayref({});
    $sth_rev_types->finish;
    foreach my $r ( @$tbl )
    {
	my $rev_type = $self->get($r->{'string'});
	my $model = &_get_node( $r->{'model'}, $self, $i );

	# Remember the record ID
	$rev_type->[NODE][PRIVATE]{$i->[ID]}{'uri'} = $r->{'node'};

	# TODO: Group the rev_types (by model) before creating them
	$self->declare_add_rev_types( [$rev_type] );
    }

    $self->[NODE][REV_TYPE_ALL] = 1;

    return( 1, 3 );
}

sub create_literal
{
    my( $self, $i, $uristr, $lit_str_ref ) = @_;

    if( $uristr )
    {
	# NOTE: Copied from create_model

	# This should validate the uri.  If this interface can't
	# create the URI, it will either return "try next interface"
	# or "failed", depending on why.

	# For now: Just allow models in the local namespace
	unless( $uristr =~ /@{[NS_LD]}/o )
	{
	    die "Invalid namespace for literal";
	}
    }

    # TODO: Make sure that $self is a model
    #
    my $model = $self->[WMODEL];
    my $literal = $self->declare_literal( $lit_str_ref, $uristr );


    # NOTE from create_model: _create_node() assumes that the resource
    # is not yet present in the database . This could be done later.
    # It would suffice to just get a new record id and put this object
    # on a stack of objects to be flushed to the DB once we don't have
    # to wory about the response time.
    #
    &_create_node($literal, $i, $model);

    # Return the literal object
    #
    return( $literal, 1 );
}

sub create_model
{
    my( $self, $interface, $uri ) = @_;
    #
    # We are asked to create a new resource and a new object
    # representing that resource and a context for the resource
    # object.  The new resource must have an URI.  The creator must
    # own the $uri namespace, as statements will be placed in it..

    # If no URI is supplied, one will be generated by the method
    # create_resource().  In case the URI is supplied, it will
    # be validated by the appropriate interface.

    if( $uri )
    {

	# This should validate the uri.  If this interface can't
	# create the URI, it will either return "try next interface"
	# or "failed", depending on why.

	# For now: Just allow models in the local namespace
	my $ns_l = NS_LD;
	unless( $uri =~ /^$ns_l/ )
	{
	    die "Invalid namespace for model";
	}
    }

    # The working model of the model will be the model itself.  But
    # the model of the model will be the working model of it's parent.

    # What is the model of the model?  Is it the parent model
    # ($self->[MODEL]) or itself ($model) or some default
    # (NS_LD."/model/system") or maby the interface?  Answer: Its the
    # parent model.  Commonly the Service object.
    #
    my $model = $self->declare_model( $uri );
    $model->[WMODEL] = $model;


    # _create_node() assumes that the resource is not yet present in
    # the database . This could be done later.  It would suffice to
    # just get a new record id and put this object on a stack of
    # objects to be flushed to the DB once we don't have to wory about
    # the response time.
    #
    &_create_node($model, $interface, $model);

    # Return the model object
    #
    return( $model, 1);
}

sub remove
{
    my( $self, $i ) = @_;

    # Remove node from interface. But not from the cahce.  This is
    # called from Base delete before it removes the node from cache.

    # TODO: Check that the node (with the model) actually exist in
    # this interface


    # Remove types and node

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth_type = $dbh->prepare_cached("
                    delete from type
                    where node = ? and model = ?");
    my $sth_node = $dbh->prepare_cached("
                    delete from node
                    where uri = ? and model = ?");

    my $r_model = &_get_id( $self->[WMODEL], $i );
    my $r_node  = &_get_id( $self,  $i );
    my %node_p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    $sth_type->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );
    $sth_node->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );

    debug "Deleted $self->[NODE][URISTR] for model ".
      $self->[WMODEL][NODE][URISTR]."\n", 1;

    # Remove the private information.  This removes info for all
    # models.  Not just the deleted one.

    # TODO: Check that there is no mixup between diffrent models
    # interface private data in the same node.

    delete $self->[NODE][PRIVATE]{$i->[ID]};

    return( 1, 3 );
}

sub store_types
{
    my( $self, $i, $types ) = @_;
    #
    # TODO: Could store duplicate type statements. But only from
    # diffrent models. Should not store implicit types.  The calling
    # function should only include the explicit classes.

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    my $sth = $dbh->prepare_cached("
                   insert into type
                   (node, type, model, fact)
                   values (?, ?, ?, true)
    ");

    my $r_node  = &_get_id($self, $i);
    my $r_model = &_get_id($self->[WMODEL], $i);

    foreach my $type ( @$types )
    {
	my $r_type = &_get_id($type, $i);
	$sth->execute( $r_node, $r_type, $r_model )
	    or confess( $sth->errstr );
    }

    # This interface store all the types. Do not continue
    return( 1, 1 );
}

sub remove_types
{
    my( $self, $i, $types ) = @_;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
                   delete from type
                   where node=? and type=? and model=?
    ");

    my $r_node  = &_get_id($self, $i);
    my $r_model = &_get_id($self->[WMODEL], $i);

    foreach my $type ( @$types )
    {
	debug "  t $type->[NODE][URISTR]\n";

	my $r_type = &_get_id($type, $i);
	$sth->execute( $r_node, $r_type, $r_model )
	    or confess( $sth->errstr );
    }

    return( 1, 3 );
}

sub store_props
{
    my( $self, $i, $preds ) = @_;
    #
    # The supplied preds are a list of pred_uri.  They specify the
    # preds to store.  The arcs are already declared.  Store the arcs
    # matching the WMODEL.  Implicit preds should not be included in
    # the $preds list.  Preds already stored should not be included.

    debug "You are now in $self\n", 1;
    debug "..Will store ".($#$preds+1)." preds\n", 1;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    my $sth = $dbh->prepare_cached("
                   insert into node
                   (id, uri, iscontainer, isprefix, model,
                   pred, subj, obj, fact, isliteral)
                   values (?, ?, false, false, ?, ?, ?, ?, true, false)
    ");

    my $r_subj = $p{'uri'} ||= &_get_id($self, $i);
    my $r_model = &_get_id($self->[WMODEL], $i);
    my $model_id = $self->[WMODEL][NODE][ID];

    if( $DEBUG )
    {
	my $pred_cnt = keys %{$self->[NODE][REV_SUBJ]};
	debug "..Resource has $pred_cnt predicates\n", 1;
    }

    foreach my $pred_uri ( @$preds )
    {
	my $r_pred = &_get_id($self->get($pred_uri), $i);
	my $pred_id = &uri2id( $pred_uri );

	if( $DEBUG )
	{
	    debug "..Storing $pred_uri ($pred_id)\n", 1;
	    debug "....".@{$self->[NODE][REV_SUBJ]{$pred_id}}." entries\n", 1;
	}

	foreach my $arc_node ( @{$self->[NODE][REV_SUBJ]{$pred_id}} )
	{
	    # Is this arc defined for the WMODEL?
	    unless( $arc_node->[MODEL]{$model_id} )
	    {
		debug "The arc $arc_node->[URISTR] is not ".
		  "defined in $self->[WMODEL][NODE][URISTR]", 1;
		next;
	    }

	    my %pa = %{$arc_node->[PRIVATE]{$i->[ID]}};

	    $pa{'id'} ||= &_nextval($dbh);
	    $pa{'pred'} = $r_pred;
	    $pa{'subj'} = $r_subj;
	    $pa{'obj'} ||= &_get_id( $arc_node->[OBJ], $i );
	    $pa{'uri'} ||= &_get_id( $self->new($arc_node), $i );

	    $sth->execute( $pa{'id'}, $pa{'uri'}, $r_model,
			   $r_pred, $r_subj, $pa{'obj'} )
	      or confess( $sth->errstr );

	    debug "..Stored arc $arc_node->[URISTR]\n", 1;
	}
    }

    # This interface store all the props. Do not continue
    return( 1, 1 );
}


sub update_node
{
    my( $self, $i ) = @_;
    #
    # See _create_node for comments

    # This only updates the node; not the types or properties.  Mainly
    # used to update literals

    debug "Updateing node $self->[NODE][URISTR]\n", 2;

    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", map "$_=?",
      @node_fields[1..$#node_fields];

    my $sth = $dbh->prepare_cached(" update node
                                    set $field_str
                                    where uri = ?
                                    and model = ?
                                   ");

    $p{'uri'}         ||= &_get_id( $self, $i) or die;
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'label'}       = $self->[NODE][LABEL];
    $p{'aliasfor'}    ||= &_get_id( $self->[NODE][ALIASFOR], $i);
    $p{'pred'}        ||= &_get_id( $self->[NODE][PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $self->[NODE][SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $self->[NODE][OBJ], $i);
    $p{'fact'}        = $self->[NODE][FACT]? 'true':'false';
    $p{'model'}       ||= &_get_id( $self->[WMODEL], $i) or die;
    $p{'member'}      ||= &_get_id( $self->[NODE][MEMBER], $i);
    if( $self->is_a(NS_LS.'#Model') )
    {
	$p{'updated'}     = localtime->strftime('%Y-%m-%d %H:%M:%S');
	$p{'readonly'}    = 'f';
	$p{'agent'}       ||= &_get_id( $self->[NODE][AGENT], $i);
	$p{'source'}      ||= &_get_id( $self->[NODE][SOURCE], $i);
    }
    if( $self->[NODE][VALUE] )
    {
	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$self->[NODE][VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$self->[NODE][VALUE]};
	}
	else
	{
	    die "not implemented";
	}
    }
    else
    {
	$p{'isliteral'}   = 'false';
    }


    debug "Updating value to ($p{'value'})\n", 2;
    debug ".. where uri=$p{'uri'} and model=$p{'model'}\n", 2;


    $sth->execute( map $p{$_}, @node_fields[1..$#node_fields],
		   'uri', 'model' )
	or confess( $sth->errstr );

    return( 1, 3 );
}

sub _create_node
{
    my( $self, $i, $model ) = @_;
    #
    # Stores the object in the database.  The object does not exist
    # before this. All data gets stored in the supplied $model.

    # TODO: remove $model parameter and use $self->[MODEL]

    debug "_create_node $self->[NODE][URISTR]\n", 2;

    # Interface PRIVATE data. These has to be updated then the
    # corresponding official data change. The dependencies could be
    # handled as they are (will be) in RDF::Cache
    #
    my %p = %{$self->[NODE][PRIVATE]{$i->[ID]}};

    debug "Getting DBH for $i->[URISTR] from ".
	"[PRIVATE]{$i->[ID]}{'dbh'}\n", 3;
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", @node_fields;
    my $place_str = join ", ", ('?')x @node_fields;

    my $sth = $dbh->prepare_cached("  insert into node
				      ($field_str)
				      values ($place_str)
				      ");

    # This is a new node. We know that it doesn't exist yet. Create a
    # new record in the db
    #
    $p{'id'}     ||= &_nextval($dbh) or die;

    # TODO: method calls should be used, i case the attribute hasn't
    # been initialized. $self->pred->private($i, 'id')?  It's possible
    # that the attribute object is stored in several interfaces. We
    # are only intrested in the private id for this interface. We
    # can't make a special method for getting that id, because we
    # can't guarantee that another interface doesn't have the same
    # method.  The private() method could be constructed to access a
    # specific attribute, but that doesn't seem to be much better than
    # just using the _get_id() function.
    #
    # I don't like this repetivity there we get the
    # sth and execute it once for each resource.  How much can we save
    # by group the lookups together?
    #
    # The list below could be shortend if we knew the type of node to
    # create.
    #
    $p{'uri'}         ||= &_create_uri( $self->[NODE][URISTR], $i) or die;
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'label'}       = $self->[NODE][LABEL];
    $p{'aliasfor'}    ||= &_get_id( $self->[NODE][ALIASFOR], $i);
    $p{'pred'}        ||= &_get_id( $self->[NODE][PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $self->[NODE][SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $self->[NODE][OBJ], $i);
    $p{'fact'}        = $self->[NODE][FACT]? 'true':'false';
    $p{'model'}       ||= &_get_id( $model, $i) or die;
    $p{'member'}      ||= &_get_id( $self->[NODE][MEMBER], $i);
    if( $self->is_a(NS_LS.'#Model') )
    {
	$p{'updated'}     = localtime->strftime('%Y-%m-%d %H:%M:%S');
	$p{'readonly'}    = 'f';
	$p{'agent'}       ||= &_get_id( $self->[NODE][AGENT], $i);
	$p{'source'}      ||= &_get_id( $self->[NODE][SOURCE], $i);
    }
    if( $self->[NODE][VALUE] )
    {
	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$self->[NODE][VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$self->[NODE][VALUE]};
	}
	else
	{
	    die "not implemented";
	}
    }
    else
    {
	$p{'isliteral'}   = 'false';
    }

    debug ".. id: $p{'id'}\n", 1;
    debug "..uri: $p{'uri'}\n", 1;

#    confess "SQL insert node $self->[NODE][URISTR]\n" if $DEBUG;

    $sth->execute( map $p{$_}, @node_fields )
	or confess( $sth->errstr );
}

sub _get_node
{
    my( $r_id, $caller, $i ) = @_;
    #
    # find_node_by_interface_node_id


    # TODO: Optimize with a interface id cache

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my $p = {}; # Interface private data
    my $obj;
    $p->{'id'} = $r_id;

    my $sth = $dbh->prepare_cached("
              select string, refid, refpart, hasalias from uri
              where id=?
              ");
    $sth->execute( $r_id );

    my( $r_uristr, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_uristr, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$obj = $caller->get( $r_uristr );
	$obj->[NODE][PRIVATE]{$i->[ID]} = $p;
    }
    $sth->finish; # Release the handler

    die "couldn't find the resource with record id $r_id" unless $obj;

    return $obj;
}

sub _get_id
{
    return undef unless defined $_[0]; # Common case
    my( $obj, $interface ) = @_;
    #
    # The object already exist.  Here we just want to know what id it
    # has in the DB. NB!!! field URI in NODE table.

    debug "_get_id( $obj->[NODE][URISTR]\n", 2;

    # Has the object a known connection to the DB?
    #
    my $p = $obj->[NODE][PRIVATE]{$interface->[ID]} || {};
    if( defined( my $id = $p->{'uri'}) )
    {
	return $id;
    }


    $obj->[NODE][URISTR] or die "No URI supplied ".$obj->to_string;

    # Look for the URI in the DB.
    #
    my $dbh = $interface->[PRIVATE]{$interface->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select id, refid, refpart, hasalias from uri
              where string=?
              ");
    $sth->execute( $obj->[NODE][URISTR] );

    my( $r_id, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_id, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$p->{'uri'} = $r_id;
	$sth->finish; # Release the handler

	# TODO: Maby update other data with the result?
	return $r_id;
    }
    else
    {
	$sth->finish; # Release the handler

	# If URI not found in DB:
	#
	# Insert the uri in the DB. The object itself doesn't have to be
	# inserted since it would already be in the DB if this interface
	# handles its storage.

	return &_create_uri( $obj->[NODE][URISTR], $interface );
    }
}

sub _create_uri
{
    my( $uri, $interface ) = @_;
    #
    # Insert a new URI in the DB.

    debug "_create_uri( $uri )\n", 2;

    # Same as _get_id(), except that we know that the uri doesn't
    # exist in the db. No error checking.

    my $dbh = $interface->[PRIVATE]{$interface->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
                  insert into uri
                  (string, id, hasalias)
                  values (?,?,false)
                  ");
    my $id = &_nextval($dbh, 'uri_id_seq');
    $sth->execute($uri, $id);
    die unless defined $id;

    return $id;
}

sub _nextval
{
    my( $dbh, $seq ) = @_;

    # Values could be collected before they are needed, as to save the
    # lookup time.

    $seq ||= 'node_id_seq';
    my $sth = $dbh->prepare_cached( "select nextval(?)" );
    $sth->execute( $seq );
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;

    $id or die "Failed to get nextval";
}

1;
