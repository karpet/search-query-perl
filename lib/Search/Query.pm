package Search::Query;

use warnings;
use strict;
use Search::Query::Parser;

our $VERSION = '0.05';

=head1 NAME

Search::Query - polyglot query parsing, with dialects

=head1 SYNOPSIS

 use Search::Query;
 
 my $parser = Search::Query->parser();
 my $query  = $parser->parse('+hello -world now');
 print $query;  # same as print $query->stringify;

=cut

=head1 DESCRIPTION

This class provides documentation and a single class method.

This module started as a fork of the excellent Search::QueryParser module
and was then rewritten to provide support for alternate query dialects.

=head1 METHODS

=head2 parser

Returns a Search::Query::Parser object.

=cut

sub parser {
    my $class = shift;
    return Search::Query::Parser->new(@_);
}

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

1;    # End of Search::Query
