package Search::Query::Dialect;
use strict;
use warnings;
use Carp;
use Data::Dump qw( dump );
use overload
    '""'     => sub { $_[0]->stringify; },
    'bool'   => sub {1},
    fallback => 1;

use base qw( Rose::ObjectX::CAF );
use Data::Transformer;
use Scalar::Util qw( blessed );

our $VERSION = '0.04';

=head1 NAME

Search::Query::Dialect - query dialect base class

=head1 SYNOPSIS

 my $query = Search::Query->parser->parse('foo');
 print $query;

=head1 DESCRIPTION

Search::Query::Dialect is the base class from which all query dialects
inherit.

A Dialect subclass must implement at least two methods:

=over

=item stringify

Returns the serialized query tree.

=item stringify_clause( I<leaf> )

Returns one clause of a serialized query tree.

=back

See Search::Query::Dialect::Native for a working example.

=head1 METHODS

This class is a subclass of Rose::ObjectX::CAF. Only new or overridden
methods are documented here.

=head2 stringify

All subclasses must override this method. The default behavior is to croak.

=cut

sub stringify { croak "must implement stringify() in $_[0]" }

=head2 tree

Returns the query Dialect instance as a hashref structure, similar
to that of Search::QueryParser.

=cut

sub tree {
    my $self = shift;
    my %tree = %$self;
    my $transformer;
    $transformer = Data::Transformer->new(
        array => sub {
            for my $obj ( @{ $_[0] } ) {
                $obj = {%$obj};
            }
        },
        hash => sub {
            my $h = shift;
            if ( blessed( $h->{value} ) ) {
                $h->{value} = $h->{value}->tree;
            }
        },
    );
    $transformer->traverse( \%tree );
    return \%tree;
}

=head2 walk( I<CODE> )

Traverse a Dialect object, calling I<CODE> on each Clause.
The I<CODE> reference should expect 4 arguments:

=over

=item

The Clause object.

=item

The Dialect object.

=item

The I<CODE> reference.

=item

The prefix ("+", "-", and "") for the Clause.

=back

=cut

sub walk {
    my $self = shift;
    my $code = shift;
    if ( !$code or !ref($code) or ref($code) ne 'CODE' ) {
        croak "CODE ref required";
    }
    my $tree = shift || $self;
    foreach my $prefix ( '+', '', '-' ) {
        next if !exists $tree->{$prefix};
        for my $clause ( @{ $tree->{$prefix} } ) {

            #warn "clause: " . dump $clause;
            $code->( $clause, $tree, $code, $prefix );
        }
    }
    return $tree;
}

=head2 add_or_clause( I<clause> )

Add I<clause> as an "or" leaf to the Dialect object.

=cut

sub add_or_clause {
    my $self = shift;
    my $clause = shift or croak "Clause object required";
    push( @{ $self->{""} }, $clause );
}

=head2 add_and_clause( I<clause> )

Add I<clause> as an "and" leaf to the Dialect object.

=cut

sub add_and_clause {
    my $self = shift;
    my $clause = shift or croak "Clause object required";
    push( @{ $self->{"+"} }, $clause );
}

=head2 add_not_clause( I<clause> )

Add I<clause> as a "not" leaf to the Dialect object.

=cut

sub add_not_clause {
    my $self = shift;
    my $clause = shift or croak "Clause object required";
    push( @{ $self->{"-"} }, $clause );
}

1;

__END__

=head1 AUTHOR

Peter Karman, C<< <karman at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-search-query at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Search-Query>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Search::Query


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Search-Query>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Search-Query>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Search-Query>

=item * Search CPAN

L<http://search.cpan.org/dist/Search-Query/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2010 Peter Karman.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
