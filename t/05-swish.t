#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 31;
use Data::Dump qw( dump );

use_ok('Search::Query::Parser');

ok( my $parser = Search::Query::Parser->new(
        fields         => [qw( foo color name )],
        default_field  => 'name',
        dialect        => 'SWISH',
        croak_on_error => 1,
    ),
    "new parser"
);

#dump $parser;

ok( my $query1 = $parser->parse('foo=bar'), "query1" );

is( $query1, qq/foo="bar"/, "query1 string" );

ok( my $query2 = $parser->parse('foo:bar'), "query2" );

is( $query2, qq/foo="bar"/, "query2 string" );

ok( my $query3 = $parser->parse('foo bar'), "query3" );

is( $query3, qq/name="foo" AND name="bar"/, "query3 string" );

my $str = '-color:red (name:john OR foo:bar)';

ok( my $query4 = $parser->parse($str), "query4" );

#dump $query4;

is( $query4,
    qq/(name="john" OR foo="bar") AND color=(NOT "red")/,
    "query4 string"
);

ok( my $parser2 = Search::Query::Parser->new(
        fields         => [qw( first_name last_name email )],
        dialect        => 'SWISH',
        croak_on_error => 1,
        default_boolop => '',
    ),
    "parser2"
);

ok( my $query5 = $parser2->parse("joe smith"), "query5" );

is( $query5,
    qq/(email="joe" OR first_name="joe" OR last_name="joe") OR (email="smith" OR first_name="smith" OR last_name="smith")/,
    "query5 string"
);

ok( my $query6 = $parser2->parse('"joe smith"'), "query6" );

is( $query6,
    qq/(email="joe smith" OR first_name="joe smith" OR last_name="joe smith")/,
    "query6 string"
);

ok( my $parser3 = Search::Query::Parser->new(
        fields           => [qw( foo bar )],
        query_class_opts => { quote_fields => '`', },    # should be ignored
        dialect          => 'SWISH',
        croak_on_error   => 1,
    ),
    "parser3"
);

ok( my $query7 = $parser3->parse('green'), "query7" );

is( $query7, qq/(bar="green" OR foo="green")/, "query7 string" );

ok( my $parser4 = Search::Query::Parser->new(
        fields           => [qw( foo )],
        query_class_opts => { croak_on_error => 1, },
        dialect          => 'SWISH',
        croak_on_error   => 1,
    ),
    "strict parser4"
);

eval { $parser4->parse('bar=123') };
my $errstr = $@;
ok( $errstr, "croak on invalid query" );
like( $errstr, qr/No such field: bar/, "caught exception we expected" );

ok( my $parser5 = Search::Query::Parser->new(
        fields => {
            foo => { type => 'char' },
            bar => { type => 'int' },
        },
        dialect          => 'SWISH',
        query_class_opts => {
            like           => 'like',
            fuzzify        => 1,
            croak_on_error => 1,
        },
        croak_on_error => 1,
    ),
    "parser5"
);

ok( my $query8 = $parser5->parse('foo:bar'), "query8" );

is( $query8, qq/foo="bar*"/, "query8 string" );

ok( $query8 = $parser5->parse('bar=1*'), "query8 fuzzy int with wildcard" );

is( $query8, qq/bar="1*"/, "query8 fuzzy int with wildcard string" );

ok( $query8 = $parser5->parse('bar=1'), "query8 fuzzy int no wildcard" );

is( $query8, qq/bar="1*"/, "query8 fuzzy int no wildcard string" );

ok( my $parser6 = Search::Query::Parser->new(
        fields           => [qw( foo )],
        dialect          => 'SWISH',
        query_class_opts => {
            like           => 'like',
            fuzzify2       => 1,
            croak_on_error => 1,
        },
        croak_on_error => 1,
    ),
    "parser6"
);

ok( my $query9 = $parser6->parse('foo:bar'), "query9" );

is( $query9, qq/foo="bar*"/, "query9 string" );
