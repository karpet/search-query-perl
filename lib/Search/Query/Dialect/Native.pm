package Search::Query::Dialect::Native;
use strict;
use warnings;
use base qw( Search::Query::Dialect );
use Carp;
use Data::Dump qw( dump );

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
    my $q = shift || $self;

    my @leaves;
    foreach my $prefix ( '+', '', '-' ) {
        next if not $q->{$prefix};
        for my $leaf ( @{ $q->{$prefix} } ) {
            push @leaves, $prefix . $self->stringify_leaf($leaf);
        }
    }

    return join " ", @leaves;
}

=head2 stringify_leaf( I<leaf> )

Called by stringify() to handle each leaf in the Query tree.

=cut

sub stringify_leaf {
    my $self = shift;
    my $leaf = shift;

    return "(" . $self->stringify( $leaf->{value} ) . ")"
        if $leaf->{op} eq '()';
    my $quote = $leaf->{quote} || "";
    return "$leaf->{field}$leaf->{op}$quote$leaf->{value}$quote";
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
