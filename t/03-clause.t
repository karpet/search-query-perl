#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 6;

use_ok('Search::Query');
use_ok('Search::Query::Clause');

ok( my $clause = Search::Query::Clause->new(
        field => 'color',
        op    => '=',
        value => 'green',
    ),
    "create clause"
);
ok( my $query = Search::Query->parser->parse("color=red"), "parse query" );
ok( $query->add_or_clause($clause), "add_or_clause" );
is( "$query", "+color=red color=green", "stringify" );
