#!/usr/bin/perl -w

#  $Id: person.cgi,v 1.9 2000/10/22 10:59:00 aigan Exp $  -*-perl-*-

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

use CGI::Debug;
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
our $VERSION = v0.0.2;
our $result = new Wraf::Result;
warn "\n\n\n\n\n";
our $s = new RDF::Service( NS_L."/service/R1" );

{
    $|=1;

    warn "Conneting to the schema\n";
    $s->connect("RDF::Service::Interface::Schema::RDFS_200001");

    our $ia = $s->connect("RDF::Service::Interface::DBI::V01",
			{
			    connect => "dbi:Pg:dbname=wraf_v01a",
			    name =>    "wwwdata",
			});

    our $ib = $s->connect("RDF::Service::Interface::DBI::V01",
			{
			    connect => "dbi:Pg:dbname=wraf_v01b",
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
	'ia'       => $ia,
	'ib'       => $ib,

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

    my $person = $model->get();


    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

#    my $l_fn = $model->create_literal(NS_L.'#Person_1-fn', \$r_fn);
#    my $l_ln = $model->create_literal(NS_L.'#Person_1-ln', \$r_ln);
    my $l_fn = $model->create_literal(undef, \$r_fn);
    my $l_ln = $model->create_literal(undef, \$r_ln);

    my $types = [$model->get(NS_L.'/Class#Person')];
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
    my $person = $s->get($r_person);
    my $model = $s->get_model(NS_L.'#M1');
    $person->delete( $model );
    return "Deleted person";
}

sub do_initiate_db
{
    my $model = $s->get_model(NS_L.'#M1');
#    my $model = $s->create_model();

    my $c_person = $model->get(NS_L.'/Class#Person');
    $c_person->set( $model, [NS_RDFS.'Class'] );

    return "DB initiated";
}

sub do_person_edit
{
    warn "*** get person\n";
    my $r_person = $q->param('r_person') or die "No node specified";
    my $person = $s->get($r_person);
    warn "*** get model\n";
    my $model = $s->get_model(NS_L.'#M1');

    my $r_fn = $q->param('r_fn') or die "No first name specified";
    my $r_ln = $q->param('r_ln') or die "No last name specified";

    warn "*** Set fn\n";
    $person->arc_obj(NS_L.'/Property#first_name')->li->set_literal($model, \$r_fn);
    warn "*** Set ln\n";
    $person->arc_obj(NS_L.'/Property#last_name')->li->set_literal($model, \$r_ln);

    warn "*** DONE\n";

    return "Person edited";
}
