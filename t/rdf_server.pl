### This is code from an earlier RDF prototype. This has nothing to do
### with the present Wraf RDF::Service module


#!/usr/bin/perl -w
use strict;
use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;
use CGI;
use Data::Dumper;
use Carp;
use Time::HiRes qw( time );
# use FindBin; use lib $FindBin::Bin; # Gives tainted data!
use lib "../lib";
use RDF_020::Schema::Model;
use vars qw( $q $rdf $VERSION $CCLIENT $port);

{
    $port=7788;
    $VERSION = 0.20;

    $rdf = new RDF_020::Schema::Model('DBI', "dbi:Pg:dbname=wraf013", "wwwdata");



# Set up the tcp server. Must do this before chroot.
my $server= IO::Socket::INET->new(
	LocalPort => $port,
	Proto => 'tcp',
	Listen => 10,
	Reuse => 1,
) or (die "Cannot connect to socket $port: $@\n");
print("Connected to port $port.\n");


my %inbuffer=();
NonBlock($server);
my $select=IO::Select->new($server);


# Main loop.
print("Setup complete, accepting connections.\n");
main:
while (1) 
{

#    warn "...\n";
#    my $t0 = [gettimeofday];

    my $client;
    my $rv;
    my $data;
    
    # See if clients have sent any data.
#    my @client_list = $select->can_read(1);
#    print "T 1: ", tv_interval ( $t0, [gettimeofday]), "\n";
    
    foreach $client ($select->can_read(1)) 
    {
	if ($client == $server) 
	{
	    # New connection.
	    my($iaddr, $address, $port, $peer_host);
	    $client=$server->accept;
	    if(!$client)
	    {
		warn("Problem with accept(): $!");
		next;
	    }	
	    ($port,$iaddr)=sockaddr_in(getpeername($client));
	    $peer_host = gethostbyaddr($iaddr, AF_INET) || inet_ntoa($iaddr);
	    $select->add($client);
	    NonBlock($client);
	}
	else 
	{
	    # Read data from client.
	    $data='';
	    $rv=$client->recv($data,POSIX::BUFSIZ, 0);
	    
	    unless (defined $rv && length $data) 
	    {
		# EOF from client.
		CloseCallBack($client,'eof');
		next;
	    }
	    
	    $inbuffer{$client}.=$data;

	    # Do we have a full record of data? (Recieved \x00)
	    if( substr( $inbuffer{$client}, -1, 1) eq "\x00" )
	    {
		chop $inbuffer{$client};
		$CCLIENT = $client;
		handle_record( $client, \$inbuffer{$client} );
		$inbuffer{$client} = '';
		CloseCallBack($client);
	    }
	}
    }
}



# Set a socket into nonblocking mode.
sub NonBlock 
{
    my $socket=shift;
    my $flags= fcntl($socket, F_GETFL, 0) 
	or die "Can't get flags for socket: $!\n";
    fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
	or die "Can't make socket nonblocking: $!\n";
}

# Someone disconnected or we want to close the i/o channel.
sub CloseCallBack 
{
    my $client=shift;
    my $reason=shift; # optional, why did we close it?
    
    delete $inbuffer{$client};
    $select->remove($client);
    close($client);
}


}

sub handle_record
{
    my( $client, $recordref ) = @_;

    use Storable qw( thaw );
    $q = thaw( $$recordref );

    $CCLIENT->send( $q->header );

    my $state = $q->param('state') || 'class_list';

    {
	no strict;
	&{"a_$state"};
    }
}

sub a_back
{
    my $history = $q->param('history')
	|| confess "No history?!?";

    warn "History: $history\n";
    
    my @history = split "\n", $history;
    my( $state, $uri ) = split " ", pop @history;

    $q->param('history', join "\n", @history);
    $q->param('state', $state );
    $q->param('uri', $uri ) if $uri;

    {
	no strict;
	&{"a_$state"};
	1;
    }
}


sub a_class_list
{
    $CCLIENT->send( $q->start_html('Class list'));
    $CCLIENT->send( $q->h1('Class list'));

    my $classes = $rdf->get_top_classes;


    $CCLIENT->send( "<table>\n");
    foreach my $class ( @$classes )
    {
	my $desig = $class->desig;
	my $uri   = $q->escape( $class->uri );

	$CCLIENT->send( "<tr><td><a href=\"rdf.cgi?state=inventory&uri=$uri&history=class_list\">$desig</a>\n");
    }
    $CCLIENT->send( "</table>\n");

#    $CCLIENT->send( "<p><a href=\"rdf.cgi?state=add_aboutEachPrefix&history=class_list\">Add aboutEachPrefix</a>\n");
    $CCLIENT->send( $q->end_html);
}

sub a_inventory
{
    my $uri = $q->param('uri');
    my $res = $rdf->get_node_by_uri( $uri );

    &a_class_list unless $res;
    if( $res->is_instance_of( $rdf->rdfs('Class') ) )
    {
	&class_inventory( $res );
    }
    else
    {
	&node_inventory( $res );
    }
}


sub class_inventory
{
    my( $class ) = @_;

    my $desig = $class->desig;
    $CCLIENT->send( $q->start_html("Class inventory for $desig"));
    $CCLIENT->send( $q->h1("Class inventory for $desig"));

	my $euri = $q->escape( $class->uri );
	my $ehistory = $q->escape( $q->param('history') )||"";
	$CCLIENT->send( "<p><a href=\"rdf.cgi?state=add_form&rclass=$euri");
	$CCLIENT->send( "&previous=inventory+$euri&history=$ehistory\">Add a new object of type $desig</a></p>\n");

    my $eclass_uri = $q->escape( $class->uri );

  PARENTS:
    {
	$CCLIENT->send( $q->h2('Parents'));
	$CCLIENT->send( "<table>\n");
	my $parent_list = $class->get_objects( $rdf->rdfs('subClassOf') );
	foreach my $res ( @$parent_list )
	{
	    my $desig = $res->desig;
	    my $euri =  $q->escape( $res->uri );
	    
	    $CCLIENT->send( "<tr><td><a href=\"rdf.cgi?");
	    $CCLIENT->send( "state=inventory&uri=$euri&history=inventory+$eclass_uri\">$desig</a>\n");
	}
	$CCLIENT->send( "</table>\n");
    }

  CHILDS:
    {
	$CCLIENT->send( $q->h2('Childs'));
	$CCLIENT->send( "<table>\n");
	my $child_list = $class->get_subjects( $rdf->rdfs('subClassOf') );
	foreach my $res ( @$child_list )
	{
	    my $desig = $res->desig;
	    my $euri =  $q->escape( $res->uri );
	    
	    $CCLIENT->send( "<tr><td><a href=\"rdf.cgi?");
	    $CCLIENT->send( "state=inventory&uri=$euri&history=inventory+$eclass_uri\">$desig</a>\n");
	}
	$CCLIENT->send( "</table>\n");
    }

  PROPERTIES:
    {
	$CCLIENT->send( $q->h2('is the domain for'));
	$CCLIENT->send( "<table><tr><th>Property <th>Range\n");
	my $prop_list = $class->get_subjects( $rdf->rdfs('domain') );
	foreach my $res ( @$prop_list )
	{
	    my $propl =  $res->desig;
	    my $eprop =  $q->escape( $res->uri );
	    
	    $CCLIENT->send( "<tr><td><a href=\"rdf.cgi?");
	    $CCLIENT->send( "state=inventory&uri=$eprop&history=inventory+$eclass_uri\">$propl</a>\n");

	    my $range_obj = $res->get_objects( $rdf->rdfs('range') );
	    if( $range_obj->[0] )
	    {
		my $rangel = $range_obj->[0]->label || $range_obj->[0]->uri;
		my $erange = $q->escape( $range_obj->[0]->uri );
	    
		$CCLIENT->send( "<td><a href=\"rdf.cgi?");
		$CCLIENT->send( "state=inventory&uri=$erange&history=inventory+$eclass_uri\">$rangel</a>\n");
	    }

	}
	$CCLIENT->send( "</table>\n");
	
	$CCLIENT->send( "<p>Add a property  (not implemented)</p>\n");

	my $euri = $q->escape($class->uri);
	$CCLIENT->send( "<p><a href=\"rdf.cgi?state=edit_form&uri=$euri\">Edit</a> |\n");
	my $ehistory = $q->escape( $q->param('history') ) ||"";
	$CCLIENT->send( "<a href=\"rdf.cgi?state=delete_confirm&uri=$euri&");
	$CCLIENT->send( "history=$ehistory\">Delete</a> $desig\n");
    }

  NODES:
    {
	$CCLIENT->send( $q->h2('Nodes of this type'));
	$CCLIENT->send( "<table>\n");
	my $res_list = $rdf->get_nodes_of_type_nonrecursively( $class );
	
	foreach my $res ( @$res_list )
	{
	    my $hdesig = $q->escapeHTML($res->desig);
	    my $euri =  $q->escape( $res->uri );
	    
	    $CCLIENT->send( "<tr><td><a href=\"rdf.cgi?");
	    $CCLIENT->send( "state=inventory&uri=$euri&history=inventory+$eclass_uri\">$hdesig</a>\n");
	}
	$CCLIENT->send( "</table>\n");

    }

    $CCLIENT->send( &footer );
    $CCLIENT->send( $q->end_html);
}

sub footer
{
    return("<hr>\n".
	   "<p><a href=\"rdf.cgi\">Home...</a>\n");
}

sub node_inventory
{
    my( $subj ) = @_;

    my $uri = $subj->uri;
    my $desig = $subj->desig;
    my $esubj_uri = $q->escape( $uri );

    $CCLIENT->send( $q->start_html("Node inventory for $desig"));
    $CCLIENT->send( $q->h1("Node inventory for $desig"));

  PROPERTIES:
    {
	$CCLIENT->send( $q->h2('Properties'));
	$CCLIENT->send( "<table border>\n");
	my $stalist = $subj->get_arcs_by_subject;
	foreach my $sta ( @$stalist )
	{
	    my $pred_desig = $sta->pred->desig;
	    my $epred_uri = $q->escape( $sta->pred->uri );
	    $CCLIENT->send( "<tr><td valign=top> ");
	    $CCLIENT->send( "<a href=\"rdf.cgi?state=inventory&uri=$epred_uri");
	    $CCLIENT->send( "&history=inventory+$esubj_uri\">$pred_desig</a> <td>");
	    if( $sta->obj->is_instance_of( $rdf->rdfs('Container') ) )
	    {
#	    $CCLIENT->send( "<ul>" );
		foreach my $obj ( @{ $sta->obj->get_membership_objects } )
		{
		    my $value = $obj->value;
		    if( $value )
		    {
			$CCLIENT->send( $q->li($value));
		    }
		    else
		    {
			my $desig = $obj->desig;
			my $euri =  $q->escape( $obj->uri );
			$CCLIENT->send( "<li><a href=\"rdf.cgi?history=inventory+$esubj_uri&");
			$CCLIENT->send( "state=inventory&uri=$euri\">$desig</a>\n");
		    }
		}
#	    $CCLIENT->send( "</ul>\n");
	    }
	    else
	    {
		my $value = $sta->obj->value;
		if( $value )
		{
		    my $hvalue = $q->escapeHTML($value);
		    $CCLIENT->send( "<pre>$hvalue</pre>" );
		}
		else
		{
		    my $desig = $sta->obj->desig;
		    my $euri =  $q->escape( $sta->obj->uri );
		    $CCLIENT->send( ": <a href=\"rdf.cgi?history=inventory+$esubj_uri&" );
		    $CCLIENT->send( "state=inventory&uri=$euri\">$desig</a>\n");
		}
	    }
	}
	$CCLIENT->send( "</table>\n" );

	my $euri = $q->escape($uri);
	$CCLIENT->send( "<p><a href=\"rdf.cgi?state=edit_form&uri=$euri\">Edit</a> |\n");
	my $ehistory = $q->escape( $q->param('history') ) ||"";
	$CCLIENT->send( "<a href=\"rdf.cgi?state=delete_confirm&uri=$euri");
	$CCLIENT->send( "&history=$ehistory\">Delete</a> $desig\n");
    }

  REFERER:
    {
	$CCLIENT->send( $q->h2('Referer'));
	$CCLIENT->send( "<table border>\n");
	my $stalist = $subj->get_arcs_by_object;
	foreach my $sta ( @$stalist )
	{
	    my $pred_uri = $sta->pred->uri;
	    my $value = $sta->subj->value;
	    $CCLIENT->send( "<tr><td>");
	    if( $value )
	    {
		$CCLIENT->send( "$value\n");
	    }
	    else
	    {
		my $uri =  $sta->subj->uri;
		my $euri =  $q->escape( $uri );
		$CCLIENT->send( "<a href=\"rdf.cgi?history=inventory+$esubj_uri&");
		$CCLIENT->send( "state=inventory&uri=$euri\">$uri</a>\n");
	    }
	    $CCLIENT->send( "<td>: $pred_uri\n");
	}
	$CCLIENT->send( "</table>\n");
    }
    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
}

sub new_history
{
    my( $here ) = @_;
    $here ||= "";

    my $history = $q->param('history') || "";
    my $previous = $q->param('previous');

    if( $history and $previous and $previous ne $here )
    {
	$history .= "\n$previous";
    }
    elsif( $previous and $previous ne $here )
    {
	$history = $previous;
    }
    return $history;
}

sub a_delete_confirm
{
    my $subj_uri = $q->param('uri');
    my $subj = $rdf->get_node_by_uri( $subj_uri );
    my $subj_desig = $subj->desig;

    $CCLIENT->send( $q->start_html("Confirmation: Delete $subj_desig?"));
    $CCLIENT->send( $q->h1("Confirmation: Delete $subj_desig?"));
    $CCLIENT->send( $q->p('This will delete (the representation for) '.
		'the resource, its property statements, '.
		'and all statement objects not shared by any other statements.'));

    my $euri = $q->escape( $subj_uri );

    my $ehistory = $q->escape( &new_history );
    $CCLIENT->send( "<p align=center><a href=\"rdf.cgi?state=delete_cascade&uri=$euri");
    $CCLIENT->send( "&history=$ehistory\">Delete</a>\n");
    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
    
}

sub a_delete_confirm_arc
{
    my $arc_uri = $q->param('uri');
    my $arc = $rdf->get_arc_by_uri( $arc_uri );
    my $harc_uri = $q->escapeHTML( $arc_uri );

    $CCLIENT->send( $q->start_html("Confirmation: Delete arc $harc_uri?"));
    $CCLIENT->send( $q->h1("Confirmation: Delete arc $harc_uri?"));
    $CCLIENT->send( $q->p('This will delete (the representation for) '.
		'the arc '.
		'and all statement objects not shared by any other statements.'));

    my $earc_uri = $q->escape( $arc_uri );

    my $ehistory = $q->escape( &new_history );
    $CCLIENT->send( "<p align=center><a href=\"rdf.cgi?state=delete_cascade_arc&uri=$earc_uri");
    $CCLIENT->send( "&history=$ehistory\">Delete</a>\n");
    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
    
}

sub a_delete_cascade_arc
{
    my $arc_uri = $q->param('uri');
    my $arc = $rdf->get_arc_by_uri( $arc_uri );
    $q->param( 'uri', $arc->obj->uri );
    $arc->delete;
    &a_delete_cascade;
}

sub a_delete_cascade
{
    my $subj_uri = $q->param('uri');
    my $subj = $rdf->get_node_by_uri( $subj_uri );
    my $subj_desig = $subj->desig;

    $CCLIENT->send( $q->start_html("Results for cascade deletion of $subj_desig?"));
    $CCLIENT->send( $q->h1("Results for cascade deletion of $subj_desig?"));

    $CCLIENT->send( "<ul>\n");
    $CCLIENT->send( &delete_recurse( $subj ));
    $CCLIENT->send( "</ul>\n");

    my $ehistory = $q->escape( $q->param('history') );
    $CCLIENT->send( "<p><a href=\"rdf.cgi?state=back&history=$ehistory\">Done!</a>\n");

    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
}

sub delete_recurse
{
    my( $subj ) = @_;
    my $text = "";

    my $arcs = $subj->get_arcs_by_object;
    if( @$arcs )
    {
	$text .= "<li>Will not remove ".$subj->desig;
	$text .= "<br>referenced by \n";
	$text .= "<ol>\n";
	
	foreach my $arc ( @$arcs )
	{
	    my $euri = $q->escape( $arc->subj->uri );
	    my $etarget = $q->escape( $q->param('uri') );
	    my $desig = $arc->subj->desig;
	    my $ehistory = $q->escape( $q->param('history') );
	    $text .= "<li><a href=\"rdf.cgi?state=edit_form&uri=$euri";
	    $text .= "&previous=delete_cascade+$etarget&history=$ehistory\">$desig</a>\n";
	}
	$text .= "</ol>\n";
    }
    else
    {
	my $arcs = $subj->get_arcs_by_subject;

	$text .= "<ul>\n";
	foreach my $arc ( @$arcs )
	{
	    my $obj = $arc->obj;
	    my $pred = $arc->pred;
	    $arc->delete;
	    
	    next if $pred->uri eq $rdf->rdf('type')->uri; 
	    
	    my $hpred = $q->escapeHTML( $pred->desig );
	    $text .= "<li><em>$hpred</em>\n";
	    $text .= &delete_recurse( $obj );
	}
	$text .= "</ul>\n";
	$text .= "<li>Removed ".$subj->desig."\n";
	$subj->delete;
    }
    return $text;
}

sub a_add_form
{
    my $class_uri = $q->param('rclass');
    my $class = $rdf->get_node_by_uri( $class_uri );
    my $class_desig = $class->desig;

    my $hhistory = $q->escapeHTML( &new_history );

    $CCLIENT->send( $q->start_html("Add a new object of type $class_desig"));
    $CCLIENT->send( $q->h1("Add a new object of type $class_desig"));
    $CCLIENT->send( $q->p('We have to first create the object. '.
		'You will then be able to update it with more data.'));

    $CCLIENT->send( $q->p('Non of the fields has to be filled in. '.
		'An empty uri will prompt the program to generate a local uri.'));
    $CCLIENT->send( "<form method=post>\n" );
    $CCLIENT->send( "<table>\n");
    $CCLIENT->send( "<tr><td>uri <td><input name=uri size=60>\n");
    $CCLIENT->send( "<tr><td>label <td><input name=label>\n");
    $CCLIENT->send( "<tr><td>comment <td><input name=comment size=60>\n");
    $CCLIENT->send( "</table>\n");
    $CCLIENT->send( "<input type=hidden name=state value=add_result>\n");
    $CCLIENT->send( "<input type=hidden name=type value=\"$class_uri\">\n");
    $CCLIENT->send( "<input type=hidden name=history value=\"$hhistory\">\n");


    $CCLIENT->send( "<p><input type=submit>\n");
    $CCLIENT->send( "</form>\n");
    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
}

sub a_add_result
{
    my $class_uri = $q->param('type') or die "no type";

    my $res_uri = $q->param('uri') || undef;
    if( $res_uri )
    {
	if( $rdf->node_exist_with_uri( $res_uri ) )
	{
	    $CCLIENT->send( $q->start_html('Creation failed'));
	    $CCLIENT->send( $q->h1('Creation failed'));
	    $CCLIENT->send( $q->p("$res_uri already exists!"));
	    $CCLIENT->send( $q->end_html);
	    return undef;
	}
    }

    my $res = $rdf->add_node( $res_uri );
    $res_uri = $res->uri; # update with real value

    my $class = $rdf->get_node_by_uri( $class_uri );

    $rdf->add_arc( $rdf->rdf('type'), $res, $class );

    if( $q->param('label') )
    {
	my $label = $rdf->add_node( undef, $q->param('label') );
	$rdf->add_arc( $rdf->rdfs('label'), $res, $label );
    }

    if( $q->param('comment') )
    {
	my $comment = $rdf->add_node( undef, $q->param('comment') );
	$rdf->add_arc( $rdf->rdfs('comment'), $res, $comment );
    }

    $q->param('uri', $res_uri);
    $q->param('previous', "inventory ".$res_uri); 
    &a_edit_form;
}

sub a_edit_save
{
    my( @first, @last );
    foreach( $q->param )
    {
	next unless /^value .*? (\w+)/;
	if( $1 eq 'lit' or $1 eq 'obj' )
	{
	    push @first, $_;
	}
	else
	{
	    push @last, $_;
	}
    }
    
    my %new_arc; # $new_arc{$subj_uri}{$pred_uri} = $arc

    foreach my $key ( @first, @last )
    {
	next unless $key =~ /^value (.*?) (\w+) (\w+) (.*?) (.*)/;

	my $subj_uri = $1;
	my $action = $2; # arc | new
	my $type = $3;   # lit | obj | pred | lang | con
	my $uri = $4;    # arc_uri | pred_uri
	my $old = $5;

	next if defined $old and $q->param($key) eq $old;

	if( $action eq 'arc' )
	{
	    my $arc = $rdf->get_arc_by_uri( $uri );
	    my $node = $arc->obj;

	    if( $type eq 'lit' )
	    {
		if( $q->param($key) eq "" )
		{
		    $node->delete;
		    $arc->delete;
		}
		else
		{
		    $node->value( $q->param($key) );
		    $node->store;
		}
	    }
	    elsif( $type eq 'res' )
	    {
		if( $q->param($key) eq "" )
		{
		    $arc->delete;
		    # How do I delete the node?
		}
		else
		{
		    my $pred = $arc->pred;
		    my $subj = $arc->subj;

		    $arc->delete;
		    # How do I delete the node?

		    my $obj;
		    if( $rdf->node_exist_with_uri( $q->param($key) ) )
		    {
			$obj = $rdf->get_node_by_uri( $q->param($key) );
		    }
		    else
		    {
			$obj = $rdf->add_node( $q->param($key) );
		    }
		    $rdf->add_arc( $pred, $subj, $obj );
		}
	    }
	    elsif( $type eq 'obj' )
	    {
		if( $q->param($key) eq "" )
		{
		    $arc->delete;
		}
		else
		{
		    my $obj = $rdf->get_node_by_uri( $q->param($key) );
		    
		    $arc->obj( $obj );
		    $arc->store;
		}
	    }
	    elsif( $type eq 'pred' )
	    {
		$q->param($key) =~ /^(\d+)$/ or next; # Should give warning
		my $pred = $rdf->get_ContainerMembershipProperty( $1 );
		
		$arc->pred( $pred );
		$arc->store;
	    }
	    else
	    {
		die "Faulty key: $key";
	    }
	}
	elsif( $action eq 'new' )
	{
	    my $pred = $rdf->get_node_by_uri( $uri );
	    my $subj = $rdf->get_node_by_uri( $subj_uri );
	    if( $type eq 'lit' )
	    {
		my $obj = $rdf->add_node( undef, $q->param($key) );
		$new_arc{$subj_uri}{$uri} = $rdf->add_arc( $pred, $subj, $obj );
	    }
	    elsif( $type eq 'res' )
	    {
		my $obj;
		if( $rdf->node_exist_with_uri( $q->param($key) ) )
		{
		    $obj = $rdf->get_node_by_uri( $q->param($key) );
		}
		else
		{
		    $obj = $rdf->add_node( $q->param($key) );
		}
		$rdf->add_arc( $pred, $subj, $obj );
	    }
	    elsif( $type eq 'obj' )
	    {
		my $obj = $rdf->get_node_by_uri( $q->param($key) );
		$new_arc{$subj_uri}{$uri} = $rdf->add_arc( $pred, $subj, $obj );
	    }
	    elsif( $type eq 'pred' )
	    {
		$q->param($key) =~ /^(\d+)$/ or next; # Should give warning
		my $pred = $rdf->get_ContainerMembershipProperty( $1 );

		my $arc = $new_arc{$subj_uri}{$uri} or next;
		$arc->pred( $pred );
		$arc->store;
	    }
	    elsif( $type eq 'con' )
	    {
		my $node = $rdf->add_node;
		my $con = $rdf->get_node_by_uri( $q->param($key) );
		$rdf->add_arc( $pred, $subj, $node );
		$rdf->add_arc( $rdf->rdf('type'), $node, $con );
	    }
	    else
	    {
		die "Faulty key: $key";
	    }
	}
	else
	{
	    die "Faulty key: $key";
	}
    }
    
    my $next = $q->param('next');
#    warn "Next: $next\n";

    {
	no strict;
	&{"a_$next"};
	1;
    }
}

sub a_edit_form
{
    my $subj_uri = $q->param('uri');
    my $subj = $rdf->get_node_by_uri( $subj_uri );
    my $subj_desig = $subj->desig;

    $q->param('history') or $q->param('history', "inventory $subj_uri"); # default
    # add previous to history if previous ne this_place
    my $this_place = "edit_form $subj_uri";
    my $history = &new_history( $this_place );
    


    $CCLIENT->send( $q->start_html("Edit node $subj_desig"));
    $CCLIENT->send( $q->h1("Edit node $subj_desig"));
    $CCLIENT->send( $q->p('Leve a field blank, to not add it as a property. '.
		'Empty a field to delete it.'.
		'The + button will actualy submit any changes made.'.
		'There will always be exactly one extra field per property.'));

  PROPERTIES:
    {
	$CCLIENT->send( "<form method=post action=\"rdf.cgi\" name=f>\n");
	$CCLIENT->send( "<table border><tr><th>Property <th>Range <th>Value ");
	$CCLIENT->send( "<th>Lang <th colspan=2>Add a new item <th>Comment\n");
	my @prop_list = sort by_class_uri values %{$subj->get_domain_properties};
	foreach my $entry ( @prop_list )
	{
	    my $prop = $entry->{'prop'};
	    my $class = $entry->{'class'};

	    my $prop_desig =  $prop->desig;
	    my $eprop_uri =  $q->escape( $prop->uri );
	    
	    $CCLIENT->send( "<tr><td><a href=\"rdf.cgi?");
	    $CCLIENT->send( "state=inventory&uri=$eprop_uri\">$prop_desig</a>\n");

	    if( my $range_list = $prop->get_objects( $rdf->rdfs('range') ) )
	    {
		my $range = $range_list->[0] || $rdf->rdfs('Resource');
		my $rangel = $range->label || $range->uri;
		my $erange = $q->escape( $range->uri );
		$CCLIENT->send( "<td><a href=\"rdf.cgi?");
		$CCLIENT->send( "state=inventory&uri=$erange\">$rangel</a>  ");
	
		&form_view_value( $subj, $prop, $range );
	    }
	    else
	    {
		$CCLIENT->send( "<td><em>anything</em> ");
		$CCLIENT->send( "<td colspan=4>Edit the property to specify the range\n");
	    }
	}
	$CCLIENT->send( "</table>\n");
    }

    
    my $huri = $q->escapeHTML( $subj_uri );
    $CCLIENT->send( "<input type=hidden name=uri value=\"$huri\">\n");
    $CCLIENT->send( "<input type=hidden name=state value=\"edit_save\">\n");
    $CCLIENT->send( "<input type=hidden name=next value=\"edit_form\">\n");

    my $hhistory = $q->escapeHTML( $history );
    my $hprevious = $q->escapeHTML( $this_place );
    $CCLIENT->send( "<input type=hidden name=history value=\"$hhistory\">\n");
    $CCLIENT->send( "<input type=hidden name=previous value=\"$hprevious\">\n");

    $CCLIENT->send( "<input type=hidden name=rclass value=\"\">\n");
    
    $CCLIENT->send( "<p><input type=button value=\" Done! \" 
            onClick=\"document.f.next.value='back';document.f.submit()\"></p>\n");

    $CCLIENT->send( "</form>\n");

    $CCLIENT->send( &footer);
    $CCLIENT->send( $q->end_html);
}

sub by_class_uri { $a->{'class'}->uri cmp $b->{'class'}->uri; }

sub form_view_value
{
    my( $subj, $prop, $range ) = @_;

    my $is_lit = $range->is_Class_or_subClassOf( $rdf->rdfs('Literal') );
    my $is_res = ( $range->uri eq $rdf->rdfs('Resource')->uri );
    
    my $row = 1;
    my $arcs = $subj->get_arcs_by_subject( $prop );
#    warn "Nr: $#$arcs\n"; ###
#    if( $#$arcs == 0 ) { warn Dumper $arcs }
    foreach my $arc ( @$arcs )
    {
	if( $arc->obj->is_instance_of( $rdf->rdfs('Container') ) )
	{
	    $CCLIENT->send( "<tr><td><td>") unless $row==1;
	    if( $is_lit )
	    {
		&form_value_lit_con( $arc->obj, $prop, $range, $arc );
	    }
	    elsif( $is_res )
	    {
		&form_value_res_con( $arc->obj, $prop, $range, $arc );
	    }
	    else
	    {
		&form_value_obj_con( $arc->obj, $prop, $range, $arc );
	    }
	    $CCLIENT->send( "<td>");
	}
	else
	{
	    $CCLIENT->send( "<tr><td><td>") unless $row==1;
	    if( $is_lit )
	    {
		&form_value_lit( $subj, $prop, $range, $arc );
	    }
	    elsif( $is_res )
	    {
		&form_value_res( $subj, $prop, $range, $arc );
	    }
	    else
	    {
		&form_value_obj( $subj, $prop, $range, $arc );
	    }
	    $CCLIENT->send( "<td colspan=2>");
	}

	if( $row == 1 )
	{
	    my $rows = $#$arcs + 2; # No container support
	    $CCLIENT->send( "<td rowspan=$rows>");
	    &form_view_comment( $prop );
	}
	$CCLIENT->send( "\n");
	$row ++;
    }
  EMPTY:
    {
	$CCLIENT->send( "<tr><td><td>") unless $row==1;
	if( $is_lit )
	{
	    &form_value_lit($subj, $prop, $range );
	}
	elsif( $is_res )
	{
	    &form_value_res($subj, $prop, $range );
	}
	else
	{
	    &form_value_obj($subj, $prop, $range );
	}

	$CCLIENT->send( "<td><input type=submit value=\" + \">");

	my $containers = $rdf->get_subclasses_for( $rdf->rdfs('Container') );

	my $hsubj_uri = $q->escapeHTML( $subj->uri );
	my $hprop_uri = $q->escapeHTML( $prop->uri );
	$CCLIENT->send( "<td><select name=\"value $hsubj_uri new con $hprop_uri \">");
	$CCLIENT->send( "<option value=\"\">&nbsp;");
	foreach my $con ( @$containers )
	{
	    my $hcon_uri = $q->escapeHTML( $con->uri );
	    $CCLIENT->send( "<option value=\"$hcon_uri\">".$con->desig);
	}
	$CCLIENT->send( "</select>\n");

	if( $row == 1 )
	{
	    $CCLIENT->send( "<td>");
	    &form_view_comment( $prop );
	}
    }
    $CCLIENT->send( "\n" );
}

sub form_value_lit
{
    my( $subj, $prop, $range, $arc ) = @_;

    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my( $name, $hvalue );
    if( $arc )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	$hvalue = $q->escapeHTML( $arc->obj->value );
	$name = "value $hsubj_uri arc lit $harc_uri $hvalue";
    }
    else
    {
	my $hprop_uri = $q->escapeHTML( $prop->uri );
	$name = "value $hsubj_uri new lit $hprop_uri "; #Last space must be there
	$hvalue = "";
    }

    # $CCLIENT->send( "<td><input size=40 name=\"$name\" value=\"$hvalue\"> ");
    my $rows = $hvalue =~ y/\n//;
    $rows = 3 if $rows < 3;
    $CCLIENT->send( "<td><textarea wrap=virtual cols=40 rows=$rows name=\"$name\">$hvalue</textarea>");
    $CCLIENT->send( "<td><input size=5>");
}

sub form_value_res
{
    my( $subj, $prop, $range, $arc ) = @_;

    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my( $name, $hvalue );
    if( $arc )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	$hvalue = $q->escapeHTML( $arc->obj->uri );
	$name = "value $hsubj_uri arc res $harc_uri $hvalue";
    }
    else
    {
	my $hprop_uri = $q->escapeHTML( $prop->uri );
	$name = "value $hsubj_uri new res $hprop_uri "; #Last space must be there
	$hvalue = "";
    }

    $CCLIENT->send( "<td><input size=40 name=\"$name\" value=\"$hvalue\"> ");
    $CCLIENT->send( "<td><input type=button value=\"search\">");
}

sub form_value_obj
{
    my( $subj, $prop, $range, $arc ) = @_;


#    warn $range->uri."\n";
   
    

    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my( $name, $hvalue );
    if( $arc )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	$hvalue = $q->escapeHTML( $arc->obj->uri );
	$name = "value $hsubj_uri arc obj $harc_uri $hvalue";
    }
    else
    {
	my $hprop_uri = $q->escapeHTML( $prop->uri );
	$name = "value $hsubj_uri new obj $hprop_uri "; #Last space must be there
	$hvalue = "";
    }

#	warn "\t".(time-$time)."\n";
#    my $time = time;

    $CCLIENT->send( "<td><select name=\"$name\">\n");
    $CCLIENT->send( "<option value=\"\">&nbsp;\n");
    my @subject_list = @{$rdf->get_nodes_of_type($range, {order => 'by_label'})};


#	warn "\t".(time-$time)."\n";

    foreach my $subj ( @subject_list )
    {
	my $hlabel = $q->escapeHTML( $subj->label||$subj->uri );
	my $huri = $q->escapeHTML( $subj->uri );

	$CCLIENT->send( "<option value=\"$huri\" ");
	$CCLIENT->send( "selected") if $subj->uri eq $hvalue;
	$CCLIENT->send( ">$hlabel\n");
    }
    $CCLIENT->send( "</select>\n");
    my $jhrange_uri = &escapeJS($q->escapeHTML( $range->uri ));

    $CCLIENT->send( "<td><input type=button value=\"new\"
           onClick=\"document.f.next.value='add_form';
           document.f.rclass.value='$jhrange_uri';
           document.f.submit()\">\n");
}

sub escapeJS
{
    ( $_ ) = @_;
    s/\'/\\\'/g;
    $_;
}

sub form_value_lit_con
{
    my( $subj, $prop, $range, $arc ) = @_;

    my $harc_uri = $q->escapeHTML( $arc->uri );
    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my $con = $arc->obj;
    my $con_uri = $con->uri;
    my $hcon_uri = $q->escapeHTML( $con_uri );
    my $type = $con->get_objects( $rdf->rdf('type') )->[0];
    my $type_uri = $type->uri;

    $CCLIENT->send( "<td align=right>$con_uri <td>$type_uri ");
#    $CCLIENT->send( "<input type=hidden name=conuri value=\"$hcon_uri\"> ");
    $CCLIENT->send( "<td><input type=button value=\" - \" ");
    $CCLIENT->send( "onClick=\"document.f.next.value='delete_confirm_arc';");
    $CCLIENT->send( "document.f.uri.value='$harc_uri';");
    $CCLIENT->send( "document.f.submit()\">\n");

    my $arc_list = $con->get_membership_arcs;
    my $cnt = 1;
    foreach my $arc (  @$arc_list )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
	my $name = "value $hsubj_uri arc pred $harc_uri $cnt";
	$CCLIENT->send( "<tr><td><td align=right>");
	$CCLIENT->send( "<input size=4 name=\"$name\" value=\"$cnt\"> ");
	&form_value_lit( $subj, $new_prop, $range, $arc );
	$cnt++;
    }

    my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
    my $hprop_uri = $q->escapeHTML( $new_prop->uri );
    my $name = "value $hsubj_uri new pred $hprop_uri $cnt";
    $CCLIENT->send( "<tr><td><td align=right>");
    $CCLIENT->send( "<input size=4 name=\"$name\" value=\"$cnt\"> ");
    &form_value_lit($subj, $new_prop, $range );
    $CCLIENT->send( "<td><input type=submit value=\" + \">");
}


sub form_value_res_con
{
    my( $subj, $prop, $range, $arc ) = @_;

    my $harc_uri = $q->escapeHTML( $arc->uri );
    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my $con = $arc->obj;
    my $con_uri = $con->uri;
    my $hcon_uri = $q->escapeHTML( $con_uri );
    my $type = $con->get_objects( $rdf->rdf('type') )->[0];
    my $type_uri = $type->uri;

    $CCLIENT->send( "<td align=right>$con_uri <td>$type_uri ");
#    $CCLIENT->send( "<input type=hidden name=conuri value=\"$hcon_uri\"> ");
    $CCLIENT->send( "<td><input type=button value=\" - \" ");
    $CCLIENT->send( "onClick=\"document.f.next.value='delete_confirm_arc';");
    $CCLIENT->send( "document.f.uri.value='$harc_uri';");
    $CCLIENT->send( "document.f.submit()\">\n");

    my $arc_list = $con->get_membership_arcs;
    my $cnt = 1;
    foreach my $arc (  @$arc_list )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
	my $name = "value $hsubj_uri arc pred $harc_uri $cnt";
	$CCLIENT->send( "<tr><td><td align=right>");
	$CCLIENT->send( "<input size=4 name=\"$name\" value=\"$cnt\"> ");
	&form_value_res( $subj, $new_prop, $range, $arc );
	$cnt++;
    }

    my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
    my $hprop_uri = $q->escapeHTML( $new_prop->uri );
    my $name = "value $hsubj_uri new pred $hprop_uri $cnt";
    $CCLIENT->send( "<tr><td><td align=right>");
    $CCLIENT->send( "<input size=4 name=\"$name\" value=\"$cnt\"> ");
    &form_value_res($subj, $new_prop, $range );
    $CCLIENT->send( "<td><input type=submit value=\" + \">");
}


sub form_value_obj_con
{
    my( $subj, $prop, $range, $arc ) = @_;

    my $hsubj_uri = $q->escapeHTML( $subj->uri );
    my $con = $arc->obj;
    my $con_uri = $con->uri;
    my $hcon_uri = $q->escapeHTML( $con_uri );
    my $type = $con->get_objects( $rdf->rdf('type') )->[0];
    my $type_uri = $type->uri;

    $CCLIENT->send( "<td align=right>$con_uri <td>$type_uri ");
    $CCLIENT->send( "<td><input type=button value=\" - \" ");
    $CCLIENT->send( "onClick=\"document.f.next.value='delete_confirm';");
    $CCLIENT->send( "document.f.uri.value=document.f.conuri.value;");
    $CCLIENT->send( "document.f.submit()\">\n");

    my $arc_list = $con->get_membership_arcs;
    my $cnt = 1;
    foreach my $arc (  @$arc_list )
    {
	my $harc_uri = $q->escapeHTML( $arc->uri );
	my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
	my $name = "value $hsubj_uri arc pred $harc_uri $cnt";
	$CCLIENT->send( "<tr><td><td align=right>");
	$CCLIENT->send( "<input size=4 name=\"$name\"value=\"$cnt\"> ");
	&form_value_obj( $subj, $new_prop, $range, $arc );
	$cnt++;
    }

    my $new_prop = $rdf->get_ContainerMembershipProperty( $cnt );
    my $hprop_uri = $q->escapeHTML( $new_prop->uri );
    my $name = "value $hsubj_uri new pred $hprop_uri $cnt";
    $CCLIENT->send( "<tr><td><td align=right>");
    $CCLIENT->send( "<input size=4 name=\"$name\" value=\"$cnt\"> ");
    &form_value_obj($subj, $new_prop, $range );
    $CCLIENT->send( "<td><input type=submit value=\" + \">");
}


# Time sucker!!!
#
#sub by_label { ($a->label||$a->uri) cmp ($b->label||$b->uri) }


sub form_view_comment
{
    my( $prop ) = @_;

    my $comment = $prop->get_objects( $rdf->rdfs('comment') )->[0];

    $CCLIENT->send( $comment ? $comment->value : "");
}








