#!/usr/bin/env perl 
use strict;
use warnings;
use Search::Query;
use Test::More tests => 3;

ok( my $parser = Search::Query->parser(
        term_expander => sub {
            my ($term) = @_;
            return ( qw( one two three ), $term );
        }
    ),
    "new parser with term_expander"
);

ok( my $query = $parser->parse("foo=bar"), "parse foo=bar" );
is( "$query", qq/+foo=(one OR two OR three OR bar)/, "query expanded" );

