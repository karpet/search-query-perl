package Search::Query::Field;
use strict;
use warnings;
use Carp;
use base qw( Rose::ObjectX::CAF );

our $VERSION = '0.02';

__PACKAGE__->mk_accessors(qw( name alias_for ));

1;
