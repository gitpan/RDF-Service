#  $Id: Constants.pm,v 1.5 2000/09/23 12:38:13 aigan Exp $  -*-perl-*-

package RDF::Service::Constants;

#=====================================================================
#
# DESCRIPTION
#   Export the constants used in Resource objects
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
use vars qw( @EXPORT_OK %EXPORT_TAGS );


# The constant list should be orderd by frequency, in order to shorten
# the average array lenght.

# Resouce
use constant IDS           =>  1; #Interface Domain Signature
use constant URISTR        =>  2;
use constant ID            =>  3;
use constant TYPE          =>  4; #hash of id => { interfaces id => 1 }
use constant TYPES         =>  5; #array of sorted nodes
use constant JUMPTABLE     =>  6; #{function=>[[coderef,interface]]}
use constant NS            =>  7; #node
use constant NAME          =>  8; #string
use constant LABEL         =>  9; #string
use constant PRIVATE       => 10; #hash of interface=>{%data}
use constant MODEL         => 11; #hash of node_id => node ??
use constant FACT          => 12; #1/0/undef
use constant ALIASFOR      => 13; #node

use constant PROPS         => 14;
#hash of prop->[[noderef, arcid, model, private]]


# Resource li
use constant MEMBER        => 20;

# Resource Statement
use constant PRED          => 25; #node
use constant SUBJ          => 26; #node
use constant OBJ           => 27; #node

# Resource Literal
use constant VALUE         => 30; #ref to string
use constant LANG          => 31; #node

# Resource Model
use constant CONTENT       => 35;  # list of interfaces
use constant READONLY      => 36;
use constant UPDATED       => 37;  # timestamp
use constant AGENT         => 38;
use constant SOURCE        => 39;

# Resource Interface
use constant PREFIX        => 40;
use constant MODULE_NAME   => 41;
use constant MODULE_REG    => 42; #hash of prefix => {typeURI => JUMPTABLE}

# Service
use constant INTERFACES    => 45;

# Namespaces
use constant NS_RDF   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
use constant NS_RDFS  => "http://www.w3.org/2000/01/rdf-schema#";
use constant NS_L     => "http://uxn.nu/rdf/2000/09/19/local";


my @RESOURCE  = qw( IDS URISTR ID TYPE TYPES JUMPTABLE NS 
		    NAME LABEL PRIVATE ALIASFOR FACT MODEL
		    PROPS );
my @INTERFACE = qw( PREFIX MODULE_NAME MODULE_REG );
my @LITERAL   = qw( VALUE LANG );
my @MODEL     = qw( CONTENT READONLY UPDATED AGENT SOURCE );
my @STATEMENT = qw( SUBJ PRED OBJ );
my @LI        = qw( MEMBER );
my @RDF       = qw( INTERFACES );
my @NAMESPACE = qw( NS_RDF NS_RDFS NS_L );

my @ALL = (@INTERFACE, @RESOURCE, @LITERAL, @MODEL, @STATEMENT, @LI,
	   @RDF, @NAMESPACE );

@EXPORT_OK = ( @ALL );
%EXPORT_TAGS = ( 
    'all'        => [@ALL],
    'resource'   => [@RESOURCE],
    'interface'  => [@RESOURCE,@INTERFACE],
    'literal'    => [@RESOURCE,@LITERAL],
    'model'      => [@RESOURCE,@MODEL],
    'statement'  => [@RESOURCE,@STATEMENT],
    'li'         => [@RESOURCE,@LI],
    'rdf'        => [@RESOURCE, @RDF],
    'namespace'  => [@NAMESPACE],
    );

1;
