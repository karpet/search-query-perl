package Search::Query::Parser;
use strict;
use warnings;
use base qw( Rose::ObjectX::CAF );
use Carp;
use Data::Dump qw( dump );
use Search::Query::Dialect::Native;

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
        query_class
        )
);

__PACKAGE__->mk_ro_accessors(qw( error ));

use constant DEFAULT => {
    term_regex  => qr/[^\s()]+/,
    field_regex => qr/\w+/,

    # longest ops first !
    op_regex => qr/==|<=|>=|!=|=~|!~|[:=<>~#]/,

    # ops that admit an empty left operand
    op_nofield_regex => qr/=~|!~|[~:#]/,

    # case insensitive
    and_regex      => qr/AND|ET|UND|E/i,
    or_regex       => qr/OR|OU|ODER|O/i,
    not_regex      => qr/NOT|PAS|NICHT|NON/i,
    default_field  => "",
    phrase_delim   => q/"/,
    default_boolop => '+',
    query_class    => 'Search::Query::Dialect::Native',
};

=head2 new

The following attributes may be initialized in new().
These are also available as get/set methods on the returned
Parser object.

=over

=item default_boolop

=item term_regex

=item field_regex

=item op_regex

=item op_nofield_regex

=item and_regex

=item or_regex

=item not_regex

=item default_field

=item fields

=item phrase_delim

=item query_class

=back

=head2 init

Overrides the base method to initialize the object.

=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    for my $key ( keys %{&DEFAULT} ) {
        my $val = DEFAULT->{$key};
        if ( !exists $self->{$key} ) {
            $self->{$key} = $val;
        }
    }

    # make sure query class is loaded
    my $qclass = $self->{query_class};
    eval "require $qclass";
    die $@ if $@;
    return $self;
}

=head2 parse( I<string> )

Returns a Search::Query::Dialect object of type
I<query_class>.

If there is a syntax error in I<string>,
parse() will return C<undef> and set error().

=cut

sub parse {
    my $self = shift;
    my $q    = shift;
    croak "query required" unless defined $q;
    my $class = shift || $self->query_class;
    my ($tree) = $self->_parse($q);
    return $tree unless defined $tree;

    #warn "tree: " . dump $tree;
    return bless( $tree, $class );
}

=head2 error

Returns the last error message.

=cut

sub _parse {
    my $self         = shift;
    my $str          = shift;
    my $parent_field = shift;    # only for recursive calls
    my $parent_op    = shift;    # only for recursive calls

    #dump $self;

    my $q                = {};
    my $preBool          = '';
    my $err              = undef;
    my $s_orig           = $str;
    my $phrase_delim     = $self->{phrase_delim};
    my $field_regex      = $self->{field_regex};
    my $and_regex        = $self->{and_regex};
    my $or_regex         = $self->{or_regex};
    my $not_regex        = $self->{not_regex};
    my $op_regex         = $self->{op_regex};
    my $op_nofield_regex = $self->{op_nofield_regex};
    my $term_regex       = $self->{term_regex};

    $str =~ s/^\s+//;    # remove leading spaces

LOOP:
    while ($str) {       # while query string is not empty
        for ($str) {     # temporary alias to $_ for easier regex application
            my $sign  = $self->{default_boolop};
            my $field = $parent_field || $self->{default_field};
            my $op    = $parent_op || ":";

            if (m/^\)/) {
                last LOOP;    # return from recursive call if meeting a ')'
            }

            # try to parse sign prefix ('+', '-' or 'NOT')
            if    (s/^(\+|-)\s*//)         { $sign = $1; }
            elsif (s/^($not_regex)\b\s*//) { $sign = '-'; }

            # try to parse field name and operator
            if (s/^$phrase_delim($field_regex)$phrase_delim\s*($op_regex)\s*// # "field name" and op
                or
                s/^'($field_regex)'\s*($op_regex)\s*//   # 'field name' and op
                or s/^($field_regex)\s*($op_regex)\s*//  # field name and op
                or s/^()($op_nofield_regex)\s*//
                )
            {                                            # no field, just op
                ( $field, $op ) = ( $1, $2 );
                if ($parent_field) {
                    $err = "field '$field' inside '$parent_field'";
                    last LOOP;
                }
            }

            # parse a value (single term or quoted list or parens)
            my $subq = undef;

            if (   s/^(")([^"]*?)"\s*//
                or s/^(')([^']*?)'\s*// )
            {    # parse a quoted string.
                my ( $quote, $val ) = ( $1, $2 );
                $subq = {
                    field => $field,
                    op    => $op,
                    value => $val,
                    quote => $quote
                };
            }
            elsif (s/^\(\s*//) {    # parse parentheses
                my ( $r, $s2 ) = $self->_parse( $str, $field, $op );
                if ( !$r ) {
                    $err = $self->error;
                    last LOOP;
                }
                $str = $s2;
                if ( !( $str =~ s/^\)\s*// ) ) {
                    $err = "no matching ) ";
                    last LOOP;
                }
                $subq = { field => '', op => '()', value => $r };
            }
            elsif (s/^($term_regex)\s*//) {    # parse a single term
                $subq = { field => $field, op => $op, value => $1 };
            }

            # deal with boolean connectors
            my $postBool = '';
            if (s/^($and_regex)\b\s*//) {
                $postBool = 'AND';
            }
            elsif (s/^($or_regex)\b\s*//) {
                $postBool = 'OR';
            }
            if (    $preBool
                and $postBool
                and $preBool ne $postBool )
            {
                $err = "cannot mix AND/OR in requests; use parentheses";
                last LOOP;
            }

            my $bool = $preBool || $postBool;
            $preBool = $postBool;    # for next loop

            # insert subquery in query structure
            if ($subq) {
                $sign = ''  if $sign eq '+' and $bool eq 'OR';
                $sign = '+' if $sign eq ''  and $bool eq 'AND';
                if ( $sign eq '-' and $bool eq 'OR' ) {
                    $err = 'operands of "OR" cannot have "-" or "NOT" prefix';
                    last LOOP;
                }
                push @{ $q->{$sign} }, $subq;
            }
            else {
                if ($_) {
                    $err = "unexpected string in query : $_";
                    last LOOP;
                }
                if ($field) {
                    $err = "missing value after $field $op";
                    last LOOP;
                }
            }
        }
    }

    # TODO allow all negative?
    if ( !exists $q->{'+'} and !exists $q->{''} ) {
        $err ||= "no positive value in query";
    }

    # handle error
    if ($err) {
        $self->{error} = "[$s_orig] : $err";
        $q = undef;
    }

    #dump $q;

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
