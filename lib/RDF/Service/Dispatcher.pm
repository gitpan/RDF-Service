#  $Id: Dispatcher.pm,v 1.19 2000/11/10 18:41:37 aigan Exp $  -*-perl-*-

package RDF::Service::Dispatcher;

#=====================================================================
#
# DESCRIPTION
#   Forwards Resource actions to the appropriate interface
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
use vars qw( %JumpJumpTable );
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( interfaces uri2id debug $DEBUG
			  debug_start debug_end );
use Data::Dumper;
use Carp;

# Every resource can only belong to one dispatcher. This should change
# in a future version.

sub go
{
    my( $self, $call, @args ) = @_;

    my $node = $self->[NODE];

#    ref $node->[MODEL] eq 'RDF::Service::Context'
#      or confess "Bad model ($node->[MODEL])";
    my $uri = $node->[URISTR] or
      confess "Call to $call from anonymous obj";

    # Todo: optimize for common case
    #
    if( not defined $node->[JUMPTABLE] )
    {
	debug_start( "select_jumptable", ' ', $self );

	my $prefix_key = $node->[IDS].'/'.$node->find_prefix_id;

	unless( $node->[TYPE_ALL] )
	{
	    # Create a temporary JUMPTABLE in order to call the
	    # init_types() function in the correct interfaces

	    # Set the first type: Resource
	    # TODO: Determine the model for this type statement
	    #
	    my $c_resource = $self->get( NS_RDFS.'Resource' )
	      or die "Oh no!!!";
	    my $model_node_id = $self->[WMODEL][NODE][ID]
	      or do
	      {
		  warn "Oh no!!\n";
		  warn "While dispatching $call\n";
		  warn "  for $self->[NODE][URISTR]\n";
		  warn "WMODEL: $self->[WMODEL]\n";
		  warn "Mnode: $self->[WMODEL][NODE]\n";
		  warn "$self->[WMODEL][NODE][ID]\n";
		  confess;
	      };
	    $node->[TYPE]{$c_resource->[NODE][ID]}{$model_node_id}=1;
#	    $self->[NODE][TYPES][0] = $self->get( NS_RDFS.'Resource' );

	    if(not defined $JumpJumpTable{$prefix_key})
	    {
		# Create the jumptable
		&create_jumptable($self, $prefix_key);
	    }
	    $node->[JUMPTABLE] = $JumpJumpTable{$prefix_key};

	    # This will call go() the second time.  This time with the
	    # temporary JUMPTABLE.  Since JUMPTABLE is defined, this
	    # part will not be called a second time.  The interfaces
	    # init_types functions will be called.  After this, the
	    # real JUMPTABLE will be defined and the original function
	    # called.


	    &go($self, 'init_types');

	    # There will allways be at least one type for a node
#	    die "No types found for $node->[URISTR]\n "
#		unless defined $node->[TYPE][0];
	}

	if( $DEBUG > 1 )
	{
	    debug "D Types for $uri:\n";
	    # This lists all types not thinking about what their
	    # models are
	    foreach my $type_id ( keys %{$node->[TYPE]} )
	    {
		my $type = $self->get_node_by_id( $type_id );
		# TODO: Check that at least one node declared this
		# type
		debug "..$type->[NODE][ID] : $type->[NODE][URISTR]\n";
	    }
	    debug "\n";
	}

	# Defines the TYPES list
	#
	my $key = $prefix_key.'/'.join('-', map $_->[NODE][ID],
				       @{$self->type_orderd_list});
	debug "Jumptable for $uri is defined to $key\n", 2;

	if(not defined $JumpJumpTable{$key})
	{
	    # Create the jumptable
	    &create_jumptable($self, $key);
	}

	$node->[JUMPTABLE] = $JumpJumpTable{$key};
	$node->[JTK] = $key;

	debug_end("select_jumptable");
    }



    ### Dispatch to the handling interfaces
    ###

    if( defined(my $coderef = $node->[JUMPTABLE]{$call}) )
    {
	# TODO: If call not found: treat this as a property and maby
	# as an dynamic property

	debug "Dispatching $call...\n", 2;

	# Return a object or a list ref.
	#  Arg 1: the return value
	#  Arg 2: Action
	#         undef = Ignore this result; call next
	#         1     = Final; Return result
	#         2     = Part; Append and call next
	#         3     = Successful. Call next

	my $success = 0;
	my $result = [];
	my $result_type = 0;

	for( my $i=0; $i<= $#$coderef; $i++ )
	{
	    debug_start( $call, $i, $self );
	    debug "..Calling $coderef->[$i][1][URISTR]\n", 2;

	    # The second parameter is the interface object
	    my( $res, $action ) = &{$coderef->[$i][0]}($self,
						       $coderef->[$i][1],
						       @args);


	    if( not defined $action )
	    {
		die "Malformed return value from $call ".
		    "in $coderef->[$i][1][URISTR]\n" if defined $res;
	    }
	    elsif( $action == 1 )
	    {
		debug_end( $call, $i );
		return $res;
	    }
	    elsif( $action == 2 )
	    {
		if( not defined $result_type)
		{
		    # This is the first pat. No copying needed
		    $result = $res;
		}
		else
		{
		    # The first iterface decides the result type
		    $result_type ||= 2;
		    push @$result, @$res;
		}
	    }
	    elsif( $action == 3)
	    {
		$success += 1;
	    }
	    else
	    {
		confess "Action ($action) not implemented";
	    }
	    debug_end( $call, $i );
	}

#	if( $call eq 'init_types' )
#	{
#	    my @types = map "\t$_->[NODE][URISTR]\n",
#	      @{$self->[NODE][TYPES]};
#	    warn("\nTypes for $uri\n@types\n");
#	}

	if( $result_type == 2 )
	{
	    return $result;
	}
	else
	{
	    return $success;
	}
    }

#    warn " Dumping info for $self\n";
#    warn $self->to_string;

    my $types_str = $self->types_as_string;
    $node->[JTK] ||= "--no JTK--";
    die("\nNo function named '$call' defined for $uri ".
	  "($node->[JTK])\n$types_str\n");
}

sub create_jumptable
{
    my( $self, $key ) = @_;

    my $node = $self->[NODE];
    my $entry = {};

    # TODO: Make filters part of signature.  Especially model and
    # language filters.

    # TODO: Make sure to create the jumptable so that Resource
    # functions comes last!

    # Remember if the codref already has been added for the function
    my %func_count;

    debug_start( "create_jumptable", ' ', $self );

    if( $DEBUG )
    {
	unless( $node->[IDS] )
	{
	    die "No IDS found for $node->[URISTR]\n";
	}
    }

    # Iterate through every interface and type.
    foreach my $interface ( @{interfaces( $node->[IDS] )} )
    {
	debug "..I ".$interface->[URISTR]."\n", 2;
	foreach my $domain ( sort {length($b) <=> length($a)}
			     keys %{$interface->[MODULE_REG]} )
	{
	    next if $node->[URISTR] !~ /^\Q$domain/;

	    debug "....D $domain\n", 2;

	    my $domain_reg = $interface->[MODULE_REG]{$domain};
	    foreach my $type ( @{$self->type_orderd_list} )
	    {
#		warn "checking $type->[URISTR]...\n";
		if( defined( my $jt = $domain_reg->{ $type->[NODE][URISTR]} ))
		{
		    debug "......T $type->[NODE][URISTR]\n", 2;
		    foreach my $func ( keys %$jt )
		    {
			debug "........F $func()\n", 2;
			# Add The coderefs for this type
			foreach my $coderef ( @{$jt->{$func}} )
			{
			    next if defined $func_count{$func}{$coderef}{$interface};
			    push @{$entry->{$func}}, [$coderef,$interface];
			    $func_count{$func}{$coderef}{$interface}++;
			}
		    }
		}
	    }
	}
    }

    debug_end( "create_jumptable" );

    # Insert the jumptable in shared memory
    $JumpJumpTable{$key}=$entry;
}



1;

