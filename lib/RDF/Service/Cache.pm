#  $Id: Cache.pm,v 1.8 2000/10/21 12:59:48 aigan Exp $  -*-perl-*-

package RDF::Service::Cache;

#=====================================================================
#
# DESCRIPTION
#   Exports access functions to cached data
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
use base 'Exporter';
use vars qw( $uri2id $id2uri $ids @EXPORT_OK %EXPORT_TAGS $create_cnt
	     $create_time $prefixlist $node %fc );
use RDF::Service::Constants qw( :resource :interface :context );
use Carp;

our $DEBUG = 1;
our $Level = 0;

{
    # If the hash and array gets to large, they should be tied to a
    # dbm database.

    # These id's are internal and can be used for diffrent uri's if
    # the server is restarted. They should not be used to store data
    # in interfaces, such as the standard DBI interface.

    # %fc is the function counter.  Used for debugging

    $uri2id = {};
    $id2uri = [undef]; #First slot reserved

    $prefixlist = {};

    $ids =
    {
     '' => [],
    };

    $create_time = 0;

    my @ALL = qw( uri2id id2uri generate_ids interfaces get_unique_id
    list_prefixes debug $Level $DEBUG debug_start debug_end );
    @EXPORT_OK = ( @ALL );
    %EXPORT_TAGS = ( 'all'        => [@ALL],
		     );
}

sub debug
{
    my( $msg, $verbose ) = @_;
    $verbose ||= 0;

    if( $verbose <= $DEBUG )
    {
	$msg =~ s/^/'|  'x$Level/gem;
	warn( $msg );
    }
}

sub debug_start
{
    my( $call, $no, $res ) = @_;
    return unless $DEBUG;

    die "Recursive loop detected. Bailing out!\n" if $Level >= 15;

    $no = ' ' unless defined $no;
    $fc{$call}++;
    my $msg = '|  'x$Level;
    $msg .= "/-- $no $call       $fc{$call}\n";
    warn $msg;
    $Level++;
    debug( $res->[NODE][URISTR]."\n", 1) if $res;
}

sub debug_end
{
    my( $call, $no ) = @_;
    return unless $DEBUG;
    $no = ' ' unless defined $no;
    $Level--;
    my $msg = '|  'x$Level;
    $msg .= "\\__ $no $call\n";
    warn $msg;
}

sub uri2id
{
    # $_[0] is the uri. (How much faster is this?)

    confess unless defined $_[0];

    # Todo: Normalize the uri and consider aliases
    #
    my $id = $uri2id->{$_[0]};
    return $id if defined $id;

    $id = $#$id2uri+1; #No threads here!

    $id2uri->[$id] = $_[0];
    $uri2id->{$_[0]} = $id;

    return $id;
}

sub id2uri
{
    return $id2uri->[$_[0]];
}

sub generate_ids
{
    # $_[0] is a ref to array of interface objects

    my $key = join('-', map uri2id($_->[URISTR]), @{$_[0]});
    $ids->{$key} = $_[0];
    return $key;
}

sub interfaces
{
    # Return ref to array of inteface object

#    carp "*** interfaces @{$ids->{$_[0]}} ***\n";
    return $ids->{$_[0]} or die "IDS $_[0] does not exist\n";
}

sub get_unique_id
{
    # Return a unique id.  This depends on
    # usage in a ns owned by the server process. I.e: only one process
    # allowed, unless combined with the PID.

    # Remember the number of objects created this second
    #
    my $time = time;
    if( $time != $create_time )
    {
	$create_time = $time;
	$create_cnt = 1;
    }
    else
    {
	$create_cnt++;
    }

    # Normally not more than 1000 objects created per second
    #
    use POSIX qw( strftime );
    return strftime( "%Y%m%dT%H%M%S", localtime($time)).
	sprintf('-%.3d', $create_cnt);
}

sub list_prefixes
{
    my( $ids ) = @_;

    debug "Creating a prefixlist for IDS $ids\n", 2;

    return @{ $prefixlist->{$ids} ||= [sort {length($b) <=> length($a)} 
				       map( keys %{$_->[MODULE_REG]},
					    @{interfaces($ids)}),'' ] };
}

1;
