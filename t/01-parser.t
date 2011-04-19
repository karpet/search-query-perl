#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 46;
use Data::Dump qw( dump );

use_ok('Search::Query');

ok( my $parser = Search::Query->parser, "new parser" );

my %queries = (

    # string                # object
    '+hello -world now'                => '+hello +now -world',
    'foo=bar and color=(red or green)' => '+foo=bar +(color=red color=green)',
    'this is a=bad (query'             => '',
    'foo=(this or that)'               => '+(foo=this foo=that)',

    # TODO combine like above?
    'foo=this or foo=that' => 'foo=this foo=that',

    # proximity
    '"foo bar"~5 and foo=bar'        => '+"foo bar"~5 +foo=bar',
    qq/foo="blue red"~5 and foo=bar/ => qq/+foo="blue red"~5 +foo=bar/,

    # alternate proximity
    'foo NEAR5 bar and foo=bar' => '+"foo bar"~5 +foo=bar',

);

for my $string ( sort keys %queries ) {
    ok( my ($query) = $parser->parse($string), "parse string: $string" );
    if ( $parser->error ) {

        #diag( $parser->error );
        ok( !$query, "no query on error" );
        pass("parser error");
        pass("parser error");
        pass("parser error");
    }
    else {
        ok( my $tree = $query->tree, "get tree" );
        if ( !is( "$query", $queries{$string}, "stringify" ) ) {
            diag( dump($query) );
        }
    }

}

#######################################################
# features that extend Search::QueryParser syntax
#
#

# range expansion
ok( my $range_parser = Search::Query::Parser->new(
        fields        => [qw( date swishdefault )],
        default_field => 'swishdefault',
    ),
    "range_parser"
);

ok( my $range_query = $range_parser->parse("date=(1..10)"), "parse range" );

#dump $range_query;

is( $range_query, qq/+date=(1 2 3 4 5 6 7 8 9 10)/, "range expanded" );

ok( my $range_not_query = $range_parser->parse("date!=( 1..3 )"),
    "parse !range" );

#dump $range_not_query;
is( $range_not_query, qq/+date!=(1 2 3)/, "!range exanded" );

# operators
ok( my $or_pipe_query = $range_parser->parse("date=( 1 | 2 )"),
    "parse piped OR" );

#dump $or_pipe_query;
is( $or_pipe_query, qq/+(date=1 date=2)/, "or_pipe_query $or_pipe_query" );

ok( my $and_amp_query = $range_parser->parse("date=( 1 & 2 )"),
    "parse ampersand AND" );

is( $and_amp_query, qq/+(+date=1 +date=2)/, "and_amp_query $and_amp_query" );

ok( my $not_bang_query = $range_parser->parse(qq/! date=("1 3" | 2)/),
    "parse bang NOT" );

#dump $not_bang_query;

is( $not_bang_query,
    qq/-(date="1 3" date=2)/,
    "not_bang_query $not_bang_query"
);

## sloppy
ok( my $sloppy_parser = Search::Query::Parser->new(
        sloppy           => 1,
        default_boolop   => '',
        query_class_opts => { default_field => [qw( color )] },
        fields           => [qw( color )],
    ),
    "sloppy_parser"
);

ok( my $slop = $sloppy_parser->parse(
        'and one:two foo and -- (not OR AND near5 bar or'),
    "parse nonsense with a sloppy sense of style"
);

#diag( $sloppy_parser->error );
#diag( dump $slop );

is( "$slop", "one two foo bar", "just non-boolean terms parsed" );

ok( my $tilde_slop = $sloppy_parser->parse('~~~~~~~'), "parse tildes" );

is( "$tilde_slop", "~~~~~~~", "tildes slop" );

#diag( dump $tilde_slop );
#diag("$tilde_slop");

ok( my $invalid_field_slop = $sloppy_parser->parse('foo:bar'),
    "parse invalid field" );

is( "$invalid_field_slop", "foo bar", "invalid field slop" );

#diag( dump $invalid_field_slop );
