
#  $Id: V01.pm,v 1.10 2000/09/24 16:53:33 aigan Exp $  -*-cperl-*-

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
use RDF::Service::Cache qw( get_unique_id uri2id id2uri );
use RDF::Service::Resource;
use Data::Dumper;
use Carp;

our $DEBUG = 1;


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
    my( $interface, $args ) = @_;

    my $connect = $args->{'connect'} or croak "Connection string missing";
    my $name    = $args->{'name'} || "";
    my $passwd  = $args->{'passwd'} || "";

    my $dbi_options =
    {
	RaiseError => 1,
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
    warn "Store DBH for $interface->[URISTR] in ".
	"[PRIVATE]{$interface->[ID]}{'dbh'}\n" if $DEBUG;

    $interface->[PRIVATE]{$interface->[ID]}{'dbh'} = $dbh;

    return
    {
	'' =>
	{
	    NS_L.'Service' =>
	    {
	    },
	    NS_L.'interface' =>
	    {
		#'list_arcs' => [\&list_arcs],
	    },
	    NS_L.'Model' =>
	    {
		'create_model' => [\&create_model],
		'add_arc'      => [\&add_arc],
	    },
	    NS_RDFS.'Resource' =>
	    {
		'init_types' => [\&init_types],
		'init_props' => [\&init_props],
		'name' => [\&name],
		'find_node' => [\&find_node],
		'create_literal' => [\&create_literal],
		'set'            => [\&set],
		'set_literal'    => [\&set_literal],
		'find_arcs_list' => [\&find_arcs_list],
		'remove'         => [\&remove],
	    },
	    NS_RDFS.'Class' =>
	    {
		'objects_list' => [\&objects_list],
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
	$p->{'id'} = $r_id;

	$obj = $self->get_node( $uristr );
	$obj->[PRIVATE]{$i->[ID]} = $p;
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

sub objects_list
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

	    push @$objects, &_get_node( $r_node, $i );
	}
	$sth->finish;
    }

    return( $objects, 1 );
}

sub name
{
    # Will give the part of the URI following the 'namespace'
    die "not implemented";
}

sub set
{
    my( $self, $i, $model, $types, $props ) = @_;
    #
    # This could be one of many set functions called in many
    # interfaces.  Each of them can store any, all or none of the
    # statements from the set() call.  how do we know that each of the
    # statements has been saved in at least one of the interfaces?

    # This interface will allways save all the statements.

    # TODO: First see if this model already has stated some of the
    # types and/or props


    $self->declare_self( $model, $types, $props );

    &_store_types( $self, $i, $model, $types );
    &_store_props( $self, $i, $model, $props );

    return( 1, 1 );
}

sub set_literal
{
    my( $self, $i, $model, $lit_str_ref ) = @_;

    $self->declare_literal( $model, $self, $lit_str_ref );
    &_update_node( $self, $i, $model );

    return( 1, 1 );
}

sub add_arc
{
    my( $self, $i, $uristr, $pred, $subj, $obj ) = @_;

    if( $uristr )
    {
	die "Arc already exist" if $self->find_node( $uristr );
    }
    else
    {
	$uristr = $self->[URISTR].'#'.&get_unique_id;
    }
    my $arc_id = uri2id($uristr);
    push @{ $subj->[PROPS]{$pred->[ID]} }, [$obj->[ID], $arc_id, $self->[ID]];


    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", @node_fields;
    my $place_str = join ", ", ('?')x @node_fields;

    my $sth = $dbh->prepare_cached("  insert into node 
				      ($field_str)
				      values ($place_str)
				      ");

#    my %p = %{$self->[PRIVATE]{$i->[ID]}};
    my %p = ();
    $p{'id'}     ||= &_nextval($dbh);

    $p{'uri'}         = &_create_uri( $uristr, $i);
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'label'}       = undef;
    $p{'aliasfor'}    = undef;
    $p{'pred'}        = &_get_id( $pred, $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        = &_get_id( $subj, $i);
    $p{'obj'}         = &_get_id( $obj, $i);
    $p{'fact'}        = 'true';
    $p{'model'}       = &_get_id( $self, $i);
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

sub init_props
{
    my( $self, $i ) = @_;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my %p = %{$self->[PRIVATE]{$i->[ID]}};

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

    $sth->execute( $self->[URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    warn "Fetching props\n" if $DEBUG;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self->get_node( $r->{'pred'} );
	my $subj   = $self;
	my $obj    = $self->get_node( $r->{'obj'} );
	my $model  = $self->get_node( $r->{'model'} );
	warn "\tFound a $pred->[URISTR]\n" if $DEBUG;

	$subj->declare_add_prop( $pred, $obj, $model, $r->{'arc'} );
    }

    return undef;
}

sub init_types
{
    my( $self, $i ) = @_;
    #
    # Read the types from the DBI.  Get all info from the node
    # record

    # TODO: Get the implicite types from subClassOf

    warn "Init types for $self->[URISTR]\n" if $DEBUG;

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[PRIVATE]{$i->[ID]}};
    $p{'id'} ||= &_get_id($self, $i);


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

	$sth_node->execute( $p{'id'} );
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
		if( $self->[LABEL] )
		{
		    $self->[LABEL] .= " /  $r->{'label'}";
		}
		else
		{
		    $self->[LABEL] = $r->{'label'};
		}
	    }

	    # aliasfor

	    # model
	    my $model = &_get_node($r->{'model'}, $i);

	    # pred distr subj obj fact

	    # member

	    # updated readonly agent source
	    my $r_updated = $r->{'updated'};
	    if( $r_updated )
	    {
		my $c_Model = $self->get_node(NS_L.'Model');
		$self->declare_add_type($i, $c_Model);

		my $p_updated = $self->get_node(NS_L.'updated');
		my $lit_uristr = $self->[URISTR]."#updated";
		$self->declare_add_dynamic_literal($p_updated,
						   \$r_updated,
						   $model,
						   $lit_uristr,
						   );


	    # TODO: Change this to be more RDF style!
		if(0) #if( defined $r->{'readonly'} )
		{
		    my $p_readonly = $self->get_node(NS_L.'readonly');
		    if( ($r->{'readonly'} eq $true) or ($r->{'readonly'} eq $false) )
		    {
			my $bool = $r->{'readonly'}; # Copy the value

			$self->declare_add_static_literal($p_readonly,
							  \$bool,
							  $model,
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
		warn "\tLiteral: $self->[URISTR]\n" if $DEBUG;
		if( $r->{'value'} )
		{
		    $self->[VALUE] = $r->{'value'};
		    my $c_Literal = $self->get_node(NS_RDFS.'Literal');
		    $self->declare_add_type( $i, $c_Literal );
		}
		else
		{
		    die "not implemented";
		}
	    }

	}
    }

  Types:
    {
	my $sth_types = $dbh->prepare_cached("
              select type.id, string, type, model
              from type, uri
              where node=? and uri.id=type and fact=TRUE
              ");

	$sth_types->execute( $p{'id'} );

	my( $r_arcid, $r_uristr, $r_type, $r_model );
	$sth_types->bind_columns(\$r_arcid, \$r_uristr, \$r_type, \$r_model);
	while( $sth_types->fetch )
	{
	    my $type = $self->get_node($r_uristr);
	    $type->[PRIVATE]{$i->[ID]}{'id'} = $r_type; # Remember the record ID
	    $self->declare_add_type( $i, $type );
	}
	$sth_types->finish;
    }

# A special cache will infere indirect types from the direct
# types. They should be returned in heiarcy order


    return undef;
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
	my $ns_l = NS_L;
	unless( $uristr =~ /$ns_l/ )
	{
	    die "Invalid namespace for literal";
	}
    }
    else
    {
	$uristr = NS_L."/literal/". &get_unique_id;
    }

    # TODO: Make sure that $self is a model
    #
    my $literal = $self->declare_literal( $self, $uristr, $lit_str_ref );


    # NOTE from create_model: _create_node() assumes that the resource
    # is not yet present in the database . This could be done later.
    # It would suffice to just get a new record id and put this object
    # on a stack of objects to be flushed to the DB once we don't have
    # to wory about the response time.
    #
    &_create_node($literal, $i, $self);

    # Return the literal object
    #
    return( $literal, 1 );
}

sub create_model
{
    my( $self, $interface, $uri ) = @_;
    #
    # We are asked to create a new resource and a new object
    # representing that resource.  The new resource must have an URI.
    # There must be an interface with the authority to create the new
    # resource within the URI, as every URI has an owner.

    # If no URI is supplied, one will be generated by the method
    # create_resource(). Which interface executing this method is
    # dependent on the IDS.

    # The Interface may want to know the type of resource to create in
    # order to generate the URI. In case the URI is supplied, it will
    # be validated by the appropriate interface.

    # The return value should be a result object, that containt the
    # result as well as any error information.


    # Using this object, the model is created with the IDS of the RDF
    # object. This means that the object can use methods from all
    # connected interfaces.


    # Called from Interface or Service.  $self is the object
    # creating the model.

    if( $uri )
    {

	# This should validate the uri.  If this interface can't
	# create the URI, it will either return "try next interface"
	# or "failed", depending on why.

	# For now: Just allow models in the local namespace
	my $ns_l = NS_L;
	unless( $uri =~ /$ns_l/ )
	{
	    die "Invalid namespace for model";
	}
    }
    else
    {
	# Generate the default model URI
	my $ns_base = &default_model_ns_base;
	my $id = &get_unique_id;

	$uri = "$ns_base/$id#";
    }

    # What is the model of the model?  Is it the parent model
    # ($self->[MODEL]) or itself ($model) or some default
    # (NS_L."/model/system") or maby the interface?  Answer: Its the
    # parent model.  Commonly the Service object.
    #
    my $model = $self->declare_model( $self, $uri );


    # _create_node() assumes that the resource is not yet present in
    # the database . This could be done later.  It would suffice to
    # just get a new record id and put this object on a stack of
    # objects to be flushed to the DB once we don't have to wory about
    # the response time.
    #
    &_create_node($model, $interface, $self);

    # Return the model object
    #
    return( $model, 1);
}

sub remove
{
    my( $self, $i, $model ) = @_;

    # Remove node from interface. But not from the cahce.  This is
    # called from Base delete before it removes the node from cache.

    die "Model not specified" unless $model;

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

    my $r_model = &_get_id( $model, $i );
    my $r_node  = &_get_id( $self,  $i );
    my %node_p = %{$self->[PRIVATE]{$i->[ID]}};

    $sth_type->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );
    $sth_node->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );

    # Remove the private information.  This removes info for all
    # models.  Not just the deleted one.

    # TODO: Check that there is no mixup between diffrent models
    # interface private data in the same node.

    delete $self->[PRIVATE]{$i->[ID]};

    return( 1, 3 );
}

sub _store_types
{
    my( $self, $i, $model, $types ) = @_;
    #
    # TODO: Could store duplicate type statements. But only from
    # diffrent models. Should not store implicit types.  The calling
    # function should only include the explicit classes.

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[PRIVATE]{$i->[ID]}};

    my $sth = $dbh->prepare_cached("
                   insert into type
                   (node, type, model, fact)
                   values (?, ?, ?, true)
    ");

    my $r_node  = &_get_id($self, $i);
    my $r_model = &_get_id($model, $i);

    foreach my $type ( @$types )
    {
	my $r_type = &_get_id($type, $i);
	$sth->execute( $r_node, $r_type, $r_model )
	    or confess( $sth->errstr );
    }

    return( 1 );
}

sub _store_props
{
     my( $self, $i, $model, $props ) = @_;
    #
    # TODO: Could store duplicate type statements. But only from
    # diffrent models. Should not store implicit props.  The calling
    # function should only include the explicit props.

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my %p = %{$self->[PRIVATE]{$i->[ID]}};

    my $sth = $dbh->prepare_cached("
                   insert into node 
                   (id, uri, iscontainer, isprefix, model, 
                   pred, subj, obj, fact, isliteral)
                   values (?, ?, false, false, ?, ?, ?, ?, true, false)
    ");

    my $r_subj  = &_get_id($self, $i);
    my $r_model = &_get_id($model, $i);

    foreach my $pred ( keys %$props )
    {
	my $r_pred = &_get_id($self->get_node($pred), $i);
	foreach my $obj (@{$props->{$pred}})
	{
	    my $r_id  = &_nextval($dbh);
	    my $r_obj = &_get_id( $obj, $i );
	    my $r_uri = &_create_uri($self->[URISTR].
				     '#'.&get_unique_id, $i);

	    $sth->execute( $r_id, $r_uri, $r_model,
			   $r_pred, $r_subj, $r_obj )
		or confess( $sth->errstr );
	}
    }

    return( 1 );
}

sub _update_node
{
    my( $self, $i, $model ) = @_;
    #
    # See _create_node for comments

    # This only updates the node; not the types or properties.  Mainly
    # used to update literals

    warn "Updateing node $self->[URISTR]\n" if $DEBUG;

    my %p = %{$self->[PRIVATE]{$i->[ID]}};
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
    $p{'label'}       = $self->[LABEL];
    $p{'aliasfor'}    ||= &_get_id( $self->[ALIASFOR], $i);
    $p{'pred'}        ||= &_get_id( $self->[PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $self->[SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $self->[OBJ], $i);
    $p{'fact'}        = $self->[FACT]? 'true':'false';
    $p{'model'}       ||= &_get_id( $model, $i) or die;
    $p{'member'}      ||= &_get_id( $self->[MEMBER], $i);
    if( $self->is_a(NS_L.'Model') )
    {
	$p{'updated'}     = localtime->strftime('%Y-%m-%d %H:%M:%S');
	$p{'readonly'}    = 'f';
	$p{'agent'}       ||= &_get_id( $self->[AGENT], $i);
	$p{'source'}      ||= &_get_id( $self->[SOURCE], $i);
    }
    if( $self->[VALUE] )
    {
	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$self->[VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$self->[VALUE]};
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


    warn "Updating value to ($p{'value'})\n".
      "\twhere uri=$p{'uri'} and model=$p{'model'}\n";


    $sth->execute( map $p{$_}, @node_fields[1..$#node_fields],
		   'uri', 'model' )
	or confess( $sth->errstr );
}

sub _create_node
{
    my( $self, $i, $model ) = @_;
    #
    # Stores the object in the database.  The object does not exist
    # before this. All data gets stored in the supplied $model.

    # TODO: remove $model parameter and use $self->[MODEL]

    # There is presently no way to store what information that belongs
    # to which model. Then that has been implemented, the _create_node
    # will cycle through the models and create one record per model.

    warn "Creating node $self->[URISTR]\n" if $DEBUG;
#    warn $self->to_string;

    # Interface PRIVATE data. These has to be updated then the
    # corresponding official data change. The dependencies could be
    # handled as they are (will be) in RDF::Cache
    #
    my %p = %{$self->[PRIVATE]{$i->[ID]}};

    warn "Getting DBH for $i->[URISTR] from ".
	"[PRIVATE]{$i->[ID]}{'dbh'}\n" if $DEBUG;
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
    $p{'uri'}         ||= &_create_uri( $self->[URISTR], $i) or die;
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'label'}       = $self->[LABEL];
    $p{'aliasfor'}    ||= &_get_id( $self->[ALIASFOR], $i);
    $p{'pred'}        ||= &_get_id( $self->[PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $self->[SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $self->[OBJ], $i);
    $p{'fact'}        = $self->[FACT]? 'true':'false';
    $p{'model'}       ||= &_get_id( $model, $i) or die;
    $p{'member'}      ||= &_get_id( $self->[MEMBER], $i);
    if( $self->is_a(NS_L.'Model') )
    {
	$p{'updated'}     = localtime->strftime('%Y-%m-%d %H:%M:%S');
	$p{'readonly'}    = 'f';
	$p{'agent'}       ||= &_get_id( $self->[AGENT], $i);
	$p{'source'}      ||= &_get_id( $self->[SOURCE], $i);
    }
    if( $self->[VALUE] )
    {
	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$self->[VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$self->[VALUE]};
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

#    confess "SQL insert node $self->[URISTR]\n" if $DEBUG;

    $sth->execute( map $p{$_}, @node_fields )
	or confess( $sth->errstr );
}

sub _get_node
{
    my( $r_id, $i ) = @_;
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
	$p->{'id'} = $r_id;

	$obj = $i->get_node( $r_uristr );
	$obj->[PRIVATE]{$i->[ID]} = $p;
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
    # has in the DB

    # Has the object a known connection to the DB?
    #
    my $p = $obj->[PRIVATE]{$interface->[ID]} || {};
    if( defined( my $id = $p->{'id'}) )
    {
	return $id;
    }


    $obj->[URISTR] or die "No URI supplied ".$obj->to_string;

    # Look for the URI in the DB.
    #
    my $dbh = $interface->[PRIVATE]{$interface->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select id, refid, refpart, hasalias from uri
              where string=?
              ");
    $sth->execute( $obj->[URISTR] );

    my( $r_id, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_id, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$p->{'id'} = $r_id;
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

	my $sth = $dbh->prepare_cached("
                  insert into uri
                  (string, id, hasalias)
                  values (?,?,false)
                  ");
	$r_id = &_nextval($dbh, 'uri_id_seq');
	$sth->execute($obj->[URISTR], $r_id);
	$sth->finish;
	return $r_id;
    }
}

sub _create_uri
{
    my( $uri, $interface ) = @_;
    #
    # Insert a new URI in the DB.

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

sub default_model_ns_base
{
    return NS_L."/model";
}


1;
