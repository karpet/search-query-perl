use strict;
use warnings;
use Test::More tests => 19;
use Data::Dump qw( dump );

use_ok('Search::Query');

ok( my $parser = Search::Query->parser, "new parser" );

my %queries = (

    # string                # object
    '+hello -world now'                => '+hello +now -world',
    'foo=bar and color=(red or green)' => '+foo=bar +(color=red color=green)',
    'this is a=bad (query'             => '',
    'foo=(this or that)'               => '+(foo=this foo=that)',
    'foo=this or foo=that' => 'foo=this foo=that',  # TODO combine like above?

);

for my $string ( sort keys %queries ) {
    ok( my ($query) = $parser->parse($string), "parse string" );
    if ( $parser->error ) {
        diag( $parser->error );
        ok( !$query, "no query on error" );
        pass("parser error");
        pass("parser error");
        pass("parser error");
    }
    else {
        ok( my $tree = $query->tree, "get tree" );
        is( "$query", $queries{$string}, "stringify" );
    }

}
