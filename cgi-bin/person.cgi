#!/usr/bin/perl -w

#  $Id: person.cgi,v 1.4 2000/09/24 16:53:32 aigan Exp $  -*-perl-*-

#=====================================================================
#
# DESCRIPTION
#   CGI frontend for person records
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
use FindBin;
use lib "$FindBin::Bin/../lib";
use RDF::Service;
use RDF::Service::Constants qw( :all );
use Data::Dumper;

use CGI;
use Template 2;
use Wraf::Result;

our $DEBUG = 0;
our $q = new CGI;
our $VERSION = v0.0.1;
our $result = new Wraf::Result;
our $s = new RDF::Service( NS_L."/service/R1" );

{
    $|=1;

    my $i_dbi = $s->connect("RDF::Service::Interface::DBI::V01",
			    {
				connect => "dbi:Pg:dbname=wraf_v01a",
				name =>    "wwwdata",
			    });


    my( $me ) = $0 =~ m!/([^/]+)$!; # The name of the program
    my $params = 
    {
	'cgi'      => $q,
	'me'       => $me, 
	'result'   => $result,
	'ENV'      => \%ENV,
	'VERSION'  => $VERSION,
	's'        => $s,

	'NS_L'     => NS_L,
	'NS_RDF'   => NS_RDF,
	'NS_RDFS'  => NS_RDFS,

	'dump'    => \&Dumper,
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


    my $th = Template->new(
			   INTERPOLATE => 1,
			   INCLUDE_PATH => 'tmpl',
			   PRE_PROCESS => 'header',
			   POST_PROCESS => 'footer',
			   );


    # Construct and return the response (handler) page
    #
    print $q->header;
    my $handler_file = $handler; #.'.html';
    $th->process($handler_file, $params)
      or do
      {
	  warn "$$: Oh no!\n" if $DEBUG; #Some error sent to browser
	  my $error = $th->error();
	  if( ref $error )
	  {
	      $result->error($error->type(),
			     $error->info()
#				   .$error->text()
			    );
	  }
	  else
	  {
	      $result->error('funny', $error);
	  }
	  $th->process('error', $params)
	    or die( "Fatal template error: ".
		    $th->error()."\n");
      };

    warn "$$: End\n\n\n" if $DEBUG;

}
exit;


########  Action functions  #########################

sub do_person_add
{
    my $model = $s->get_model(NS_L.'#M1');
#    my $model = $s->create_model();

    my $person = $model->get_node();

    my $types = [$model->get_node(NS_L.'/Class#Person')];

    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

#    my $l_fn = $model->create_literal(NS_L.'#Person_1-fn', \$r_fn);
#    my $l_ln = $model->create_literal(NS_L.'#Person_1-ln', \$r_ln);
    my $l_fn = $model->create_literal(undef, \$r_fn);
    my $l_ln = $model->create_literal(undef, \$r_ln);

    my $props =
    {
	NS_L.'/Property#first_name' => [$l_fn],
	NS_L.'/Property#last_name'  => [$l_ln],
    };

    $person->set( $model, $types, $props );

    return "Person created";
}

sub do_person_delete
{
    my $r_person = $q->param('r_person') or die "No node specified";
    my $person = $s->get_node($r_person);
    my $model = $s->get_model(NS_L.'#M1');
    $person->delete( $model );
    return "Deleted person";
}

sub do_initiate_db
{
    my $model = $s->get_model(NS_L.'#M1');
#    my $model = $s->create_model();

    my $c_person = $model->get_node(NS_L.'/Class#Person');
    my $c_class = $model->get_node(NS_RDFS.'Class');

    $c_person->set( $model, [$c_class] );

    return "DB initiated";
}

sub do_person_edit
{
    my $r_person = $q->param('r_person') or die "No node specified";
    my $person = $s->get_node($r_person);
    my $model = $s->get_model(NS_L.'#M1');

    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

    my $p_fn = $s->get_node(NS_L.'/Property#first_name');
    my $p_ln = $s->get_node(NS_L.'/Property#last_name');

    $person->get_objects_list($p_fn)->[0]->set_literal($model, \$r_fn);
    $person->get_objects_list($p_ln)->[0]->set_literal($model, \$r_ln);

    return "Person edited";
}
