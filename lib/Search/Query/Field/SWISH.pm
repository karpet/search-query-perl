package Search::Query::Field::SWISH;
use strict;
use warnings;
use base qw( Search::Query::Field );

__PACKAGE__->mk_accessors(qw( type is_int ));

our $VERSION = '0.07';

=head1 NAME

Search::Query::Field::SWISH - query field representing a SWISH MetaName

=head1 SYNOPSIS

 my $field = Search::Query::Field::SWISH->new( 
    name        => 'foo',
    alias_for   => [qw( bar bing )], 
 );

=head1 DESCRIPTION

Search::Query::Field::SWISH implements field
validation and aliasing in SWISH search queries.

=head1 METHODS

This class is a subclass of Search::Query::Field. Only new or overridden
methods are documented here.

=head2 init

Available params are also standard attribute accessor methods.

=over

=item type

The column type.a

=item is_int

Set if C<type> matches m/int|num|date/.

=back

=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->{type} ||= 'char';

    # numeric types
    if ( $self->{type} =~ m/int|date|num/ ) {
        $self->{is_int} = 1;
    }

    # text types
    else {
        $self->{is_int} = 0;
    }

}

1;
