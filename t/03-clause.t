#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 8;
use Data::Dump qw( dump );

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
ok( $query->add_sub_clause( $query->parser->parse("color=(blue OR yellow)") ),
    "add sub_clause"
);
is( "$query",
    qq/+color=red +(color=blue color=yellow) color=green/,
    "sub_clause stringify"
);
