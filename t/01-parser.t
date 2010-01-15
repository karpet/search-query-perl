use strict;
use warnings;
use Test::More tests => 28;
use Data::Dump qw( dump );

use_ok('Search::Query');

SKIP: {
    eval { require Search::QueryParser; };
    if ($@) {
        skip "Search::QueryParser required for back compat check", 27;
    }

    my $qp = Search::QueryParser->new(
        rxOr  => qr/OR|OU|ODER|O/i,
        rxAnd => qr/AND|ET|UND|E/i,
        rxNot => qr/NOT|PAS|NICHT|NON/i,
    );
    ok( my $parser = Search::Query->parser, "new parser" );

    my %queries = (

        # string                # object
        '+hello -world now' => '+:hello +:now -:world',
        'foo=bar and color=(red or green)' =>
            '+foo=bar +(color=red color=green)',
        'this is a=bad (query' => '',
        'foo=(this or that)'   => '+(foo=this foo=that)',
        'foo=this or foo=that' =>
            'foo=this foo=that',    # TODO combine like above?

    );

    for my $string ( sort keys %queries ) {
        ok( my ($query) = $parser->parse($string), "parse string" );
        if ( $parser->error ) {
            diag( $parser->error );
            ok( !$query, "no query on error" );
            pass("parser error");
            pass("parser error");
            pass("parser error");
            pass("parser error");
        }
        else {

            ok( my ($old_q) = $qp->parse( $string, 1 ), "old style parse" );
            ok( my $tree = $query->tree, "get tree" );

            #warn "new: " . dump $tree;

            #warn "old: " . dump $old_q;

            is_deeply( $tree, $old_q, "tree struct cmp" );
            is( "$query", $queries{$string}, "stringify" );
        }

    }

}
