package Search::Query::Dialect::Native;
use strict;
use warnings;
use base qw( Search::Query::Dialect );
use Carp;
use Data::Dump qw( dump );

our $VERSION = '0.06';

=head1 NAME

Search::Query::Dialect::Native - the default query dialect

=head1 SYNOPSIS

 my $query = Search::Query->parser->parse('foo');
 print $query;

=head1 DESCRIPTION

Search::Query::Dialect::Native is the default query dialect for Query
objects returned by a Search::Query::Parser instance.

=head1 METHODS

This class is a subclass of Search::Query::Dialect. Only new or overridden
methods are documented here.

=head2 stringify

Returns the Query object as a normalized string.

=cut

sub stringify {
    my $self = shift;
    my $tree = shift || $self;

    my @q;
    foreach my $prefix ( '+', '', '-' ) {
        next if not $tree->{$prefix};
        for my $clause ( @{ $tree->{$prefix} } ) {
            push @q, $prefix . $self->stringify_clause($clause);
        }
    }

    return join " ", @q;
}

=head2 stringify_clause( I<leaf> )

Called by stringify() to handle each Clause in the Query tree.

=cut

sub stringify_clause {
    my $self   = shift;
    my $clause = shift;

    if ( $clause->{op} eq '()' ) {
        return "(" . $self->stringify( $clause->{value} ) . ")";
    }
    my $quote = $clause->{quote} || "";
    return join( '',
        ( defined $clause->{field} ? $clause->{field} : "" ),
        $clause->{op}, $quote, $clause->{value}, $quote );
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
