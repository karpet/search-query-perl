package Search::Query::SubQuery;
use strict;
use warnings;
use Carp;
use base qw( Rose::ObjectX::CAF );
use Scalar::Util qw( blessed );

our $VERSION = '0.02';

__PACKAGE__->mk_accessors(qw( field op value quote ));

sub is_tree {
    my $self = shift;
    return blessed( $self->{value} );
}

1;
