#!/usr/bin/perl -w

#  $Id: serv1.pl,v 1.2 2000/11/12 23:25:03 aigan Exp $  -*-perl-*-

#=====================================================================
#
# DESCRIPTION
#   CGI server for person records
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

use 5.006;
use strict;
use POSIX;
use IO::Socket 1.18;
use IO::Select;
use Socket;
use Data::Dumper;
use Carp;
use Time::HiRes qw( time );
use CGI;
use Template 2;
use FreezeThaw qw( thaw );

# use FindBin; use lib $FindBin::Bin; # Gives tainted data!
use lib "../lib";

use Wraf::Result;
use RDF::Service;
use RDF::Service::Constants qw( :all );

our $VERSION = 0.02;

our $DEBUG = 0;
our $q = undef;
our $s = undef;

our $th = Template->new(
      INTERPOLATE => 1,
      INCLUDE_PATH => 'tmpl',
      PRE_PROCESS => 'header',
      POST_PROCESS => 'footer',
     );


{
    my $port=7788;

    # Set up the tcp server. Must do this before chroot.
    my $server= IO::Socket::INET->new(
	  LocalPort => $port,
	  Proto => 'tcp',
	  Listen => 10,
	  Reuse => 1,
	 ) or (die "Cannot connect to socket $port: $@\n");

    print("Connected to port $port.\n");


    my %inbuffer=();
    my %length=();
    NonBlock($server);
    my $select=IO::Select->new($server);

    print("Setup complete, accepting connections.\n");

    open STDERR, ">/tmp/RDF-Service.log" or die $!;

  main_loop:
    while (1)
    {
	# The algorithm was adopted from perlmoo by Joey Hess
	# <joey@kitenet.net>.



	#    warn "...\n";
	#    my $t0 = [gettimeofday];

	my $client;
	my $rv;
	my $data;

	# See if clients have sent any data.
	#    my @client_list = $select->can_read(1);
	#    print "T 1: ", tv_interval ( $t0, [gettimeofday]), "\n";

	foreach $client ($select->can_read(5))
	{
	    if ($client == $server)
	    {
		# New connection.
		my($iaddr, $address, $port, $peer_host);
		$client = $server->accept;
		if(!$client)
		{
		    warn("Problem with accept(): $!");
		    next;
		}
		($port, $iaddr) = sockaddr_in(getpeername($client));
		$peer_host = gethostbyaddr($iaddr, AF_INET) || inet_ntoa($iaddr);
		$select->add($client);
		NonBlock($client);

		warn "\n\nNew client connected\n" if $DEBUG;
	    }
	    else
	    {
		# Read data from client.
		$data='';
		$rv = $client->recv($data,POSIX::BUFSIZ, 0);

		warn "Read data...\n" if $DEBUG;

		unless (defined $rv && length $data)
		{
		    # EOF from client.
		    CloseCallBack($client,'eof');
		    warn "End of file\n";
		    next;
		}

		$inbuffer{$client} .= $data;
		unless( $length{$client} )
		{
		    warn "Length of record?\n" if $DEBUG;
		    # Read the length of the data string
		    #
		    if( $inbuffer{$client} =~ s/^(\d+)\x00// )
		    {
			warn "Setting length to $1\n" if $DEBUG;
			$length{$client} = $1;
		    }
		}

		if( $length{$client} )
		{
		    warn "End of record?\n" if $DEBUG;
		    # Have we read the full record of data?
		    #
		    if( length $inbuffer{$client} >= $length{$client} )
		    {
			warn "The whole length read\n" if $DEBUG;
			handle_request( $client, \$inbuffer{$client} );
			$inbuffer{$client} = '';
			$length{$client} = 0;
			CloseCallBack($client);
		    }
		}
	    }
	}
    }



    sub NonBlock
    {
	my $socket=shift;

	# Set a socket into nonblocking mode.  I guess that the 1.18
	# defaulting to autoflush makes this function redundant

	use Fcntl;
	my $flags= fcntl($socket, F_GETFL, 0) 
	  or die "Can't get flags for socket: $!\n";
	fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
	  or die "Can't make socket nonblocking: $!\n";
    }

    sub CloseCallBack
    {
	my( $client, $reason ) = @_;

	# Someone disconnected or we want to close the i/o channel.

	delete $inbuffer{$client};
	$select->remove($client);
	close($client);
    }
}

sub handle_request
{
    my( $client, $recordref ) = @_;

    my( $me );

    my( $value ) = thaw( $$recordref );

#    warn Dumper $value;
#    return;

    ($q, $me ) = @$value;


    if( $DEBUG > 2 )
    {
	$client->send( $q->header );
	$client->send( "<h1>Got something!</h1>" );
	$client->send("<plaintext>\n");
	foreach my $key ( $q->param() )
	{
	    my $value = $q->param($key);
	    $value =~ s/\x00/?/g;
	    $client->send("   $key:\t$value\n");
	}
    }




    warn "Constructing RDF::Service object\n";
    my $offset = &dlines();

    $s = new RDF::Service( NS_LD."/service/R1" );

#    $s->connect("RDF::Service::Interface::DBI::V01",
#	      {
#		  connect => "dbi:Pg:dbname=wraf_v01b",
#		  name =>    "wwwdata",
#	      });

    $s->connect("RDF::Service::Interface::DBI::V01",
	      {
		  connect => "dbi:Pg:dbname=wraf_v01a",
		  name =>    "wwwdata",
	      });

    my $result = new Wraf::Result;

    my $params =
    {
	'cgi'      => $q,
	'me'       => $me,
	'result'   => $result,
	'ENV'      => \%ENV,
	'VERSION'  => $VERSION,
	's'        => $s,

	'NS_LS'     => NS_LS,
	'NS_LD'     => NS_LD,
	'NS_RDF'   => NS_RDF,
	'NS_RDFS'  => NS_RDFS,

	'dump'    => \&Dumper,
	'offset'  => $offset,
	'dlines'  => \&dlines,
    };


    # Performe the actions (anything that changes the database)
    #
    my $action = $q->param('action');
    if( $action )
    {
	eval
	{
	    no strict 'refs';
	    $result->message( &{'do_'.$action} );
	    ### Other info is stored in $result->{'info'}
	    1;
	}
	or $result->exception($@);
    }


    # Set the handler depending of the action result
    #
    my $handler = "";
    $handler = $q->param('previous') if $result->{'error'};
    $handler ||= ($q->param('handler')||'menu');
    $params->{'handler'} = $handler;
    warn "$$: Porcessing template $handler\n" if $DEBUG;


    # Construct and return the response (handler) page
    #
    warn "Returning page\n";
    $client->print( $q->header );
    my $handler_file = $handler; #.'.html';
    $th->process($handler_file, $params, $client)
      or do
      {
	  warn "$$: Oh no!\n" if $DEBUG; #Some error sent to browser
	  my $error = $th->error();
	  if( ref $error )
	  {
	      $result->error($error->type(),
			     $error->info()
			    );
	  }
	  else
	  {
	      $result->error('funny', $error);
	  }
	  $th->process('error', $params, $client)
	    or die( "Fatal template error: ".
		      $th->error()."\n");
      };


    warn "Done!\n\n";
}


########  Action functions  #########################

sub do_person_add
{
    my $model = $s->get_model(NS_LD.'#M1');
#    my $model = $s->create_model();

    my $person = $model->get();


    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

#    my $l_fn = $model->create_literal(NS_LD.'#Person_1-fn', \$r_fn);
#    my $l_ln = $model->create_literal(NS_LD.'#Person_1-ln', \$r_ln);
    my $l_fn = $model->create_literal(undef, \$r_fn);
    my $l_ln = $model->create_literal(undef, \$r_ln);

    my $types = [$model->get(NS_LD.'/Class#Person')];
    my $props =
    {
	NS_LD.'/Property#first_name' => [$l_fn],
	NS_LD.'/Property#last_name'  => [$l_ln],
    };

    $person->set( $types, $props );

    return "Person created";
}

sub do_person_delete
{
    my $r_person = $q->param('r_person') or die "No node specified";
    my $model = $s->get_model(NS_LD.'#M1');
    my $person = $model->get($r_person);
    $person->delete();
    return "Deleted person";
}

sub do_initiate_db
{
    my $model = $s->get_model(NS_LD.'#M1');
#    my $model = $s->create_model();

    my $c_person = $model->get(NS_LD.'/Class#Person');
    $c_person->set( [NS_RDFS.'Class'] );

    return "DB initiated";
}

sub do_person_edit
{
    warn "*** get person\n";
    my $r_person = $q->param('r_person') or die "No node specified";
    my $person = $s->get($r_person);
    warn "*** get model\n";
    my $model = $s->get_model(NS_LD.'#M1');

    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

    warn "*** Set fn\n";
    $person->arc_obj(NS_LD.'/Property#first_name')->li->set_literal(\$r_fn);
    warn "*** Set ln\n";
    $person->arc_obj(NS_LD.'/Property#last_name')->li->set_literal(\$r_ln);

    warn "*** DONE\n";

    return "Person edited";
}

use Fcntl;
our $llines = 0;
our $loffset = 0;
sub dlines
{
    open FILE, "/tmp/RDF-Service.log" or die $!;

    unless( seek FILE, $loffset, SEEK_SET )
    {
	$llines = 0;
	$loffset = 0;
    }
    while( <FILE> )
    {
	$llines++;
	$loffset += length;
    }
    close FILE;
    return $llines;
}
