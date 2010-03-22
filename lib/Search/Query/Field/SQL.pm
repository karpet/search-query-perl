package Search::Query::Field::SQL;
use strict;
use warnings;
use base qw( Search::Query::Field );

__PACKAGE__->mk_accessors(
    qw( type fuzzy_op fuzzy_not_op is_int ));

our $VERSION = '0.11';

=head1 NAME

Search::Query::Field::SQL - query field representing a database column

=head1 SYNOPSIS

 my $field = Search::Query::Field::SQL->new( 
    name        => 'foo',
    alias_for   => [qw( bar bing )], 
 );

=head1 DESCRIPTION

Search::Query::Field::SQL implements field
validation and aliasing in SQL search queries.

=head1 METHODS

This class is a subclass of Search::Query::Field. Only new or overridden
methods are documented here.

=head2 init

Available params are also standard attribute accessor methods.

=over

=item type

The column type.

=item fuzzy_op

=item fuzzy_not_op

=item is_int

Set if C<type> matches m/int|float|bool|time|date/.

=back

=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    $self->{type} ||= 'char';

    # numeric types
    if ( $self->{type} =~ m/int|float|bool|time|date/ ) {
        $self->{fuzzy_op}     ||= '>=';
        $self->{fuzzy_not_op} ||= '! >=';
        $self->{is_int} = 1;
    }

    # text types
    else {
        $self->{fuzzy_op}     ||= 'ILIKE';
        $self->{fuzzy_not_op} ||= 'NOT ILIKE';
        $self->{is_int} = 0;
    }

}

1;
