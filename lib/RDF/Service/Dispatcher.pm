#  $Id: Dispatcher.pm,v 1.7 2000/09/23 16:10:30 aigan Exp $  -*-perl-*-

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
use RDF::Service::Cache qw( interfaces uri2id );
use Data::Dumper;
use Carp;

our $DEBUG = 0;


# Every resource can only belong to one dispatcher. This should change
# in a future version.

sub go
{
    my( $self, $call, @args ) = @_;

#    my $uri = $self->[URISTR] || '(anonymous resource)';
    my $uri = $self->[URISTR] or confess "Call to $call from anonymous obj";
    if( $DEBUG )
    {
	my $args_str = join ", ", map $_?"'$_'":"''", $call, @args;
	warn "${uri}->go($args_str)\n";
    }

    # Todo: optimize for common case
    #
    if( not defined $self->[JUMPTABLE] )
    {
	# Select a jumptable

	my $prefix_key = $self->[IDS].'/'.$self->find_prefix_id;

	unless( defined $self->[TYPES] )
	{
	    # Create a temporary JUMPTABLE in order to call the
	    # init_types() function in the correct interfaces

	    # Set the first type: Resource. It will not be bound to
	    # any interface explicitly. But is implicitly bound to the
	    # Base interface.
	    #
	    my $c_Resource = $self->get_node( NS_RDFS.'Resource' );
	    $self->[TYPES][0] = $c_Resource;

	    if(not defined $JumpJumpTable{$prefix_key})
	    {
		# Create the jumptable
		&create_jumptable($self, $prefix_key);
	    } 
	    $self->[JUMPTABLE] = $JumpJumpTable{$prefix_key};

	    # This will call go() the second time.  This time with the
	    # temporary JUMPTABLE.  Since JUMPTABLE is defined, this
	    # part will not be called a second time.  The interfaces
	    # init_types functions will be called.  After this, the
	    # real JUMPTABLE will be defined and the original function
	    # called.


	    &go($self, 'init_types');
	    die "No types found for $self->[URISTR]\n " 
		unless defined $self->[TYPES][0];
	}

	if( $DEBUG )
	{
	    warn "Types for $uri:\n";
	    foreach my $type ( @{$self->[TYPES]} )
	    {
		warn "\t$type->[ID] : $type->[URISTR]\n";
	    }
	    warn "\n";
	}

	# Defines the TYPES list
	#
	my $key = $prefix_key.'/'.join('-', map $_->[ID], @{$self->[TYPES]});
	warn "Jumptable for $uri is defined to $key\n" if $DEBUG;

	if(not defined $JumpJumpTable{$key})
	{
	    # Create the jumptable
	    &create_jumptable($self, $key);
	}

	$self->[JUMPTABLE] = $JumpJumpTable{$key};
    }



    ### Dispatch to the handling interfaces
    ###

    if( defined(my $coderef = $self->[JUMPTABLE]{$call}) )
    {
	warn "Dispatching $call...\n\n" if $DEBUG;

	# Return a object or a list ref.
	#  Arg 1: the return value
	#  Arg 2: Action
	#         undef = Ignore this result; call next
	#         1     = Final; Return result
	#         2     = Part; Append and call next
	#         3     = Successful. Call next

	my $success = 0;

	for( my $i=0; $i<= $#$coderef; $i++ )
	{
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
		return $res;
	    }
	    elsif( $action == 2 )
	    {
		die "Not implemented";
	    }
	    elsif( $action == 3)
	    {
		$success += 1;
	    }
	    else
	    {
		confess "Action ($action) not implemented";
	    }
	}
	return $success;
    }

#    warn " Dumping info for $self\n";
#    warn $self->to_string;
    my @types = map "\t".$_->uri."\n", @{$self->[TYPES]};
    die("\nNo function named '$call' defined for $uri\n@types\n");
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

    warn "Constructing $key jumptable\n" if $DEBUG;

    # Iterate through every interface and type.
    foreach my $interface ( @{interfaces( $self->[IDS] )} )
    {
	warn "\tI ".$interface->[URISTR]."\n" if $DEBUG;
	foreach my $domain ( sort {length($b) <=> length($a)} 
			     keys %{$interface->[MODULE_REG]} )
	{
	    next if $self->[URISTR] !~ /^\Q$domain/;

	    warn "\t\tD $domain\n" if $DEBUG;

	    my $domain_reg = $interface->[MODULE_REG]{$domain};
	    foreach my $type ( @{$self->[TYPES]} )
	    {
#		warn "checking $type->[URISTR]...\n";
		if( defined( my $jt = $domain_reg->{ $type->[URISTR]} ))
		{
		    warn "\t\t\tT $type->[URISTR]\n" if $DEBUG;
		    foreach my $func ( keys %$jt )
		    {
			warn "\t\t\t\tF $func()\n" if $DEBUG;
			# Add The coderefs for this type
			foreach my $coderef ( @{$jt->{$func}} )
			{
			    next if defined $func_count{$func}{$coderef};
			    push @{$entry->{$func}}, [$coderef,$interface];
			    $func_count{$func}{$coderef}++;
			}
		    }
		}
	    }
	}
    }

    # Insert the jumptable in shared memory
    $JumpJumpTable{$key}=$entry;
}


sub to_string
{
    my( $self ) = @_;

    my $str = "";
    no strict 'refs';

    {
	my @urilist = map( $_->[URISTR], @{ $self->[TYPES] });
	$str.="TYPES\t: @urilist\n";
    }


    foreach my $attrib (qw( IDS URISTR ID NAME LABEL VALUE FACT PREFIX MODULE_NAME ))
    {
	$self->[&{$attrib}] and $str.="$attrib\t:".
	    $self->[&{$attrib}] ."\n";
    }

    foreach my $attrib (qw( NS MODEL ALIASFOR LANG PRED SUBJ OBJ ))
    {
#	my $dd = Data::Dumper->new([$self->[&{$attrib}]]);
#	$str.=Dumper($dd->Values)."\n\n\n";
#	$self->[&{$attrib}] and $str.="$attrib\t:".Dumper($self->[&{$attrib}])."\n";
	$self->[&{$attrib}] and $str.="$attrib\t:".
	    ($self->[&{$attrib}][URISTR]||"no value")."\n";
    }

    return $str;
}

1;

