#  $Id: Dispatcher.pm,v 1.15 2000/10/21 12:59:48 aigan Exp $  -*-perl-*-

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

    my $uri = $self->[NODE][URISTR] or
      confess "Call to $call from anonymous obj";

    # Todo: optimize for common case
    #
    if( not defined $self->[NODE][JUMPTABLE] )
    {
	# Select a jumptable

	my $prefix_key = $self->[NODE][IDS].'/'.$self->[NODE]->find_prefix_id;

	unless( defined $self->[NODE][TYPES] )
	{
	    # Create a temporary JUMPTABLE in order to call the
	    # init_types() function in the correct interfaces

	    # Set the first type: Resource. It will not be bound to
	    # any interface explicitly. But is implicitly bound to the
	    # Base interface.
	    #
	    $self->[NODE][TYPES][0] = $self->get( NS_RDFS.'Resource' );

	    if(not defined $JumpJumpTable{$prefix_key})
	    {
		# Create the jumptable
		&create_jumptable($self, $prefix_key);
	    }
	    $self->[NODE][JUMPTABLE] = $JumpJumpTable{$prefix_key};

	    # This will call go() the second time.  This time with the
	    # temporary JUMPTABLE.  Since JUMPTABLE is defined, this
	    # part will not be called a second time.  The interfaces
	    # init_types functions will be called.  After this, the
	    # real JUMPTABLE will be defined and the original function
	    # called.


	    &go($self, 'init_types');
	    die "No types found for $self->[NODE][URISTR]\n "
		unless defined $self->[NODE][TYPES][0];
	}

	if( $DEBUG > 1 )
	{
	    debug "D Types for $uri:\n";
	    foreach my $type ( @{$self->[NODE][TYPES]} )
	    {
		debug "..$type->[NODE][ID] : $type->[NODE][URISTR]\n";
	    }
	    debug "\n";
	}

	# Defines the TYPES list
	#
	my $key = $prefix_key.'/'.join('-', map $_->[NODE][ID],
				       @{$self->[NODE][TYPES]});
	debug "Jumptable for $uri is defined to $key\n", 2;

	if(not defined $JumpJumpTable{$key})
	{
	    # Create the jumptable
	    &create_jumptable($self, $key);
	}

	$self->[NODE][JUMPTABLE] = $JumpJumpTable{$key};
	$self->[NODE][JTK] = $key;
    }



    ### Dispatch to the handling interfaces
    ###

    if( defined(my $coderef = $self->[NODE][JUMPTABLE]{$call}) )
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

    my @types = map "\t".$_->uri."\n", @{$self->[NODE][TYPES]};
    $self->[NODE][JTK] ||= "--no JTK--";
    die("\nNo function named '$call' defined for $uri ".
	  "($self->[NODE][JTK])\n@types\n");
}

sub create_jumptable
{
    my( $self, $key ) = @_;

    my $entry = {};

    # TODO: Make filters part of signature.  Especially model and
    # language filters.

    # TODO: Make sure to create the jumptable so that Resource
    # functions comes last!

    # Remember if the codref already has been added for the function
    my %func_count;

    debug "Constructing $key jumptable\n", 2;

    # Iterate through every interface and type.
    foreach my $interface ( @{interfaces( $self->[NODE][IDS] )} )
    {
	debug "..I ".$interface->[URISTR]."\n", 2;
	foreach my $domain ( sort {length($b) <=> length($a)}
			     keys %{$interface->[MODULE_REG]} )
	{
	    next if $self->[NODE][URISTR] !~ /^\Q$domain/;

	    debug "....D $domain\n", 2;

	    my $domain_reg = $interface->[MODULE_REG]{$domain};
	    foreach my $type ( @{$self->[NODE][TYPES]} )
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

    # Insert the jumptable in shared memory
    $JumpJumpTable{$key}=$entry;
}



1;

