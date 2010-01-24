package Search::Query::Clause;
use strict;
use warnings;
use Carp;
use base qw( Rose::ObjectX::CAF );
use Scalar::Util qw( blessed );

our $VERSION = '0.05';

__PACKAGE__->mk_accessors(qw( field op value quote ));

=head1 NAME

Search::Query::Clause - part of a Dialect

=head1 SYNOPSIS

 my $clause = Search::Query::Clause->new(
    field => 'color',
    op    => '=',
    value => 'green',
 );
 my $query = Search::Query->parser->parse("color=red");
 $query->add_or_clause( $clause );
 print $query; # +color=red color=green

=head1 DESCRIPTION

A Clause object represents a leaf in a Query Dialect tree.

=head1 METHODS

This class is a subclass of Rose::ObjectX::CAF. Only new or overridden
methods are documented here.

=head2 field

=head2 op

=head2 value

=head2 quote

=head2 is_tree

Returns true if the Clause has child Clauses.

=cut

sub is_tree {
    my $self = shift;
    return blessed( $self->{value} );
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


=head1 ACKNOWLEDGEMENTS

This module started as a fork of Search::QueryParser by
Laurent Dami.

=head1 COPYRIGHT & LICENSE

Copyright 2010 Peter Karman.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
