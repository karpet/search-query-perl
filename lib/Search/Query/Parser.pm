package Search::Query::Parser;
use strict;
use warnings;
use base qw( Rose::ObjectX::CAF );
use Carp;
use Data::Dump qw( dump );

__PACKAGE__->mk_accessors(
    qw(
        default_boolop
        term_regex
        field_regex
        op_regex
        op_nofield_regex
        and_regex
        or_regex
        not_regex
        default_field
        fields
        phrase_delim
        )
);

__PACKAGE__->mk_ro_accessors(qw( error ));

sub parse {
    my $self         = shift;
    my $str          = shift;
    my $implicitPlus = shift;
    my $parentField  = shift;    # only for recursive calls
    my $parentOp     = shift;    # only for recursive calls

    my $q       = {};
    my $preBool = '';
    my $err     = undef;
    my $s_orig  = $str;

    $str =~ s/^\s+//;            # remove leading spaces

LOOP:
    while ($str) {               # while query string is not empty
        for ($str) {    # temporary alias to $_ for easier regex application
            my $sign = $implicitPlus ? "+" : "";
            my $field = $parentField || $self->{default_field};
            my $op    = $parentOp    || ":";

            last LOOP if m/^\)/; # return from recursive call if meeting a ')'

            # try to parse sign prefix ('+', '-' or 'NOT')
            if    (s/^(\+|-)\s*//)             { $sign = $1; }
            elsif (s/^($self->{rxNot})\b\s*//) { $sign = '-'; }

            # try to parse field name and operator
            if (s/^"($self->{rxField})"\s*($self->{rxOp})\s*// # "field name" and op
                or
                s/^'($self->{rxField})'\s*($self->{rxOp})\s*// # 'field name' and op
                or
                s/^($self->{rxField})\s*($self->{rxOp})\s*//   # field name and op
                or s/^()($self->{rxOpNoField})\s*//
                )
            {    # no field, just op
                $err = "field '$1' inside '$parentField'", last LOOP
                    if $parentField;
                ( $field, $op ) = ( $1, $2 );
            }

            # parse a value (single term or quoted list or parens)
            my $subQ = undef;

            if (   s/^(")([^"]*?)"\s*//
                or s/^(')([^']*?)'\s*// )
            {    # parse a quoted string.
                my ( $quote, $val ) = ( $1, $2 );
                $subQ = {
                    field => $field,
                    op    => $op,
                    value => $val,
                    quote => $quote
                };
            }
            elsif (s/^\(\s*//) {    # parse parentheses
                my ( $r, $s2 )
                    = $self->parse( $str, $implicitPlus, $field, $op );
                $err = $self->err, last LOOP if not $r;
                $str = $s2;
                $str =~ s/^\)\s*// or $err = "no matching ) ", last LOOP;
                $subQ = { field => '', op => '()', value => $r };
            }
            elsif (s/^($self->{rxTerm})\s*//) {    # parse a single term
                $subQ = { field => $field, op => $op, value => $1 };
            }

            # deal with boolean connectors
            my $postBool = '';
            if    (s/^($self->{rxAnd})\b\s*//) { $postBool = 'AND' }
            elsif (s/^($self->{rxOr})\b\s*//)  { $postBool = 'OR' }
            $err = "cannot mix AND/OR in requests; use parentheses", last LOOP
                if $preBool
                    and $postBool
                    and $preBool ne $postBool;
            my $bool = $preBool || $postBool;
            $preBool = $postBool;    # for next loop

            # insert subquery in query structure
            if ($subQ) {
                $sign = ''  if $sign eq '+' and $bool eq 'OR';
                $sign = '+' if $sign eq ''  and $bool eq 'AND';
                $err = 'operands of "OR" cannot have "-" or "NOT" prefix',
                    last LOOP
                    if $sign eq '-' and $bool eq 'OR';
                push @{ $q->{$sign} }, $subQ;
            }
            else {
                $err = "unexpected string in query : $_", last LOOP if $_;
                $err = "missing value after $field $op",  last LOOP if $field;
            }
        }
    }

    $err ||= "no positive value in query" unless $q->{'+'} or $q->{''};
    $self->{err} = $err ? "[$s_orig] : $err" : "";
    $q = undef if $err;
    return ( $q, $str );
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
