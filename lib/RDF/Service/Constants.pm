#  $Id: Constants.pm,v 1.9 2000/10/20 07:49:15 aigan Exp $  -*-perl-*-

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
use constant TYPE          =>  4; #hash of type_id => { model_id => 1 }
use constant TYPES         =>  5; #array of sorted nodes
use constant REV_TYPE      =>  6;
use constant JUMPTABLE     =>  8; #{function=>[[coderef,interface]]}
use constant NS            =>  9; #node
use constant NAME          => 10; #string
use constant LABEL         => 11; #string
use constant PRIVATE       => 12; #hash of interface=>{%data}
use constant MODEL         => 13; #hash of model_id=>$model
use constant ALIASFOR      => 14; #node
use constant PROPS         => 15; #hash of prop_id=>[$node]
use constant REV_PROPS     => 16;
use constant JTK           => 17; #Jumptable key  (just for debugging)
use constant FACT          => 18; #1/0/undef  ### DEPRECATED

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
use constant INTERFACES    => 45;  # node

# Namespaces
use constant NS_RDF   => "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
use constant NS_RDFS  => "http://www.w3.org/2000/01/rdf-schema#";
use constant NS_L     => "http://uxn.nu/rdf/2000/09/19/local";

# Context wrapper
use constant CONTEXT  => 1;
use constant NODE     => 2;
use constant WMODEL   => 3;  # The working model


my @RESOURCE  = qw( IDS URISTR ID TYPE TYPES REV_TYPE JUMPTABLE NS
		    NAME LABEL PRIVATE ALIASFOR FACT MODEL
		    PROPS REV_PROPS JTK );
my @INTERFACE = qw( PREFIX MODULE_NAME MODULE_REG );
my @LITERAL   = qw( VALUE LANG );
my @MODEL     = qw( CONTENT READONLY UPDATED AGENT SOURCE );
my @STATEMENT = qw( SUBJ PRED OBJ );
my @LI        = qw( MEMBER );
my @RDF       = qw( INTERFACES );
my @NAMESPACE = qw( NS_RDF NS_RDFS NS_L );
my @CONTEXT   = qw( CONTEXT NODE WMODEL );

my @ALL = (@INTERFACE, @RESOURCE, @LITERAL, @MODEL, @STATEMENT, @LI,
	   @RDF, @NAMESPACE, @CONTEXT );

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
    'context'    => [@CONTEXT],
    );

1;
