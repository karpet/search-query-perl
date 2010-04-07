package Search::Query::Parser;
use strict;
use warnings;
use base qw( Rose::ObjectX::CAF );
use Carp;
use Data::Dump qw( dump );
use Search::Query;
use Search::Query::Dialect::Native;
use Search::Query::Clause;
use Search::Query::Field;
use Scalar::Util qw( blessed weaken );

our $VERSION = '0.13';

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
        near_regex
        range_regex
        default_field
        default_op
        phrase_delim
        query_class
        field_class
        clause_class
        query_class_opts
        croak_on_error
        )
);

__PACKAGE__->mk_ro_accessors(qw( error fields ));

my %DEFAULT = (
    term_regex  => qr/[^\s()]+/,
    field_regex => qr/[\.\w]+/,    # match prefix.field: or field

    # longest ops first !
    op_regex => qr/~\d+|==|<=|>=|!=|=~|!~|[:=<>~#]/,

    # ops that admit an empty left operand
    op_nofield_regex => qr/=~|!~|[~:#]/,

    # case insensitive
    and_regex        => qr/\&|AND|ET|UND|E/i,
    or_regex         => qr/\||OR|OU|ODER|O/i,
    not_regex        => qr/NOT|PAS|NICHT|NON/i,
    near_regex       => qr/NEAR\d+/i,
    range_regex      => qr/\.\./,
    default_field    => undef,
    default_op       => ':',
    phrase_delim     => q/"/,
    default_boolop   => '+',
    query_class      => 'Search::Query::Dialect::Native',
    field_class      => 'Search::Query::Field',
    clause_class     => 'Search::Query::Clause',
    query_class_opts => {},
    croak_on_error => 0,    # TODO make it stricter

);

my %SQPCOMPAT = (
    rxAnd       => 'and_regex',
    rxOr        => 'or_regex',
    rxNot       => 'not_regex',
    defField    => 'default_field',
    rxTerm      => 'term_regex',
    rxField     => 'field_regex',
    rxOp        => 'op_regex',
    rxOpNoField => 'op_nofield_regex',
    dialect     => 'query_class',        # our own compat
);

=head1 NAME

Search::Query::Parser - convert query strings into query objects

=head1 SYNOPSIS

 use Search::Query;
 my $parser = Search::Query->parser(
    term_regex  => qr/[^\s()]+/,
    field_regex => qr/\w+/,
    op_regex    => qr/==|<=|>=|!=|=~|!~|[:=<>~#]/,

    # ops that admit an empty left operand
    op_nofield_regex => qr/=~|!~|[~:#]/,

    # case insensitive
    and_regex        => qr/\&|AND|ET|UND|E/i,
    or_regex         => qr/\||OR|OU|ODER|O/i,
    not_regex        => qr/NOT|PAS|NICHT|NON/i,

    default_field  => "",
    phrase_delim   => q/"/,
    default_boolop => '+',
    query_class    => 'Search::Query::Dialect::Native',
    field_class    => 'Search::Query::Field',
    query_class_opts => {
        default_field => 'foo',
    },
 );

 my $query = $parser->parse('+hello -world now');
 print $query;

=head1 DESCRIPTION

Search::Query::Parser is a fork of Search::QueryParser
that supports multiple query dialects.

The Parser class transforms a query string into a Dialect object structure
to be handled by external search engines.

The query string can contain simple terms, "exact phrases", field
names and comparison operators, '+/-' prefixes, parentheses, and
boolean connectors.

The parser can be customized using regular expressions for specific
notions of "term", "field name" or "operator"  -- see the L<new>
method.

The Dialect object resulting from a parsed query is a tree of terms
and operators. Each Dialect can be re-serialized as a string
using the stringify() method, or simply by printing the Dialect object,
since the string-related Perl operations are overloaded using stringify().

=head1 QUERY STRING

The query string is decomposed into Clause objects, where
each Clause has an optional sign prefix,
an optional field name and comparison operator,
and a mandatory value.

=head2 Sign prefix

Prefix '+' means that the item is mandatory.
Prefix '-' means that the item must be excluded.
No prefix means that the item will be searched
for, but is not mandatory.

See also section L<Boolean connectors> below, which is another
way to combine items into a query.

=head2 Field name and comparison operator

Internally, each query item has a field name and comparison
operator; if not written explicitly in the query, these
take default values C<''> (empty field name) and
C<':'> (colon operator).

Operators have a left operand (the field name) and
a right operand (the value to be compared with);
for example, C<foo:bar> means "search documents containing
term 'bar' in field 'foo'", whereas C<foo=bar> means
"search documents where field 'foo' has exact value 'bar'".

Here is the list of admitted operators with their intended meaning:

=over

=item C<:>

treat value as a term to be searched within field.
This is the default operator.

=item C<~> or C<=~>

treat value as a regex; match field against the regex. 

Note that C<~>
after a phrase indicates a proximity assertion:

 "foo bar"~5

means "match 'foo' and 'bar' within 5 positions of each other."

=item C<!~>

negation of above

=item C<==> or C<=>, C<E<lt>=>, C<E<gt>=>, C<!=>, C<E<lt>>, C<E<gt>>

classical relational operators

=item C<#>

Inclusion in the set of comma-separated integers supplied
on the right-hand side.

=back

Operators C<:>, C<~>, C<=~>, C<!~> and C<#> admit an empty
left operand (so the field name will be C<''>).
Search engines will usually interpret this as
"any field" or "the whole data record". But see the B<default_field>
feature.

=head2 Value

A value (right operand to a comparison operator) can be

=over

=item *

A term (as recognized by regex C<term_regex>, see L<new> method below).

=item *

A quoted phrase, i.e. a collection of terms within
single or double quotes.

Quotes can be used not only for "exact phrases", but also
to prevent misinterpretation of some values : for example
C<-2> would mean "value '2' with prefix '-'",
in other words "exclude term '2'", so if you want to search for
value -2, you should write C<"-2"> instead.

Note that C<~>
after a phrase indicates a proximity assertion:

 "foo bar"~5

means "match 'foo' and 'bar' within 5 positions of each other."

=item *

A subquery within parentheses.
Field names and operators distribute over parentheses, so for
example C<foo:(bar bie)> is equivalent to
C<foo:bar foo:bie>.

Nested field names such as C<foo:(bar:bie)> are not allowed.

Sign prefixes do not distribute : C<+(foo bar) +bie> is not
equivalent to C<+foo +bar +bie>.

=back

=head2 Boolean connectors

Queries can contain boolean connectors 'AND', 'OR', 'NOT'
(or their equivalent in some other languages -- see the *_regex
features in new()).
This is mere syntactic sugar for the '+' and '-' prefixes :
C<a AND b> is equivalent to C<+a +b>;
C<a OR b> is equivalent to C<(a b)>;
C<NOT a> is equivalent to C<-a>.
C<+a OR b> does not make sense,
but it is translated into C<(a b)>, under the assumption
that the user understands "OR" better than a
'+' prefix.
C<-a OR b> does not make sense either,
but has no meaningful approximation, so it is rejected.

Combinations of AND/OR clauses must be surrounded by
parentheses, i.e. C<(a AND b) OR c> or C<a AND (b OR c)> are
allowed, but C<a AND b OR c> is not.

The C<NEAR> connector is treated like the proximity phrase assertion.

 foo NEAR5 bar

is treated as if it were:

 "foo bar"~5

See the B<near_regex> option.

=head1 METHODS

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

=item near_regex

=item range_regex

=item default_field

Applied to all terms where no field is defined. 
The default value is undef (no default).

=item default_op

The operator used when default_field is applied.

=item fields

=item phrase_delim

=item query_class

C<dialect> is an alias for C<query_class>.

=item field_class

=item clause_class

=item query_class_opts

Will be passed to I<query_class> new() method each time a query is parse()'d.

=item croak_on_error

Default value is false (0). Set to true to automatically throw an exception
via Carp::croak() if parse() would return undef.

=back

=head2 init

Overrides the base method to initialize the object.

=cut

sub init {
    my $self = shift;

    # Search::QueryParser compatability
    my %args = @_;
    for my $key ( keys %args ) {
        if ( exists $SQPCOMPAT{$key} ) {
            $args{ $SQPCOMPAT{$key} } = delete $args{$key};
        }
    }

    $self->SUPER::init(%args);
    for my $key ( keys %DEFAULT ) {
        my $val = $DEFAULT{$key};
        if ( !exists $self->{$key} ) {
            $self->{$key} = $val;
        }
    }

    # query class can be shortcut
    $self->{query_class}
        = Search::Query->get_query_class( $self->{query_class} );

    # use field class if query class defines one
    $self->{field_class} = $self->{query_class}->field_class
        if $self->{query_class}->field_class;

    $self->set_fields( $self->{fields} ) if $self->{fields};

    return $self;
}

=head2 error

Returns the last error message.

=cut

=head2 get_field( I<name> )

Returns Field object for I<name> or undef if there isn't one
defined.

=cut

sub get_field {
    my $self = shift;
    my $name = shift or croak "name required";
    if ( !exists $self->{fields}->{$name} ) {
        return undef;
    }
    return $self->{fields}->{$name};
}

=head2 set_fields( I<fields> )

Set the I<fields> structure. Called internally by init()
if you pass a C<fields> key/value pair to new().

The structure of I<fields> may be one of the following:

 my $fields = {
    field1 => 1,
    field2 => { alias_for => 'field1' },
    field3 => Search::Query::Field->new( name => 'field3' ),
    field4 => { alias_for => [qw( field1 field3 )] },
 };

 # or

 my $fields = [
    'field1',
    { name => 'field2', alias_for => 'field1' },
    Search::Query::Field->new( name => 'field3' ),
    { name => 'field4', alias_for => [qw( field1 field3 )] },
 ];


=cut

sub set_fields {
    my $self       = shift;
    my $origfields = shift;
    if ( !defined $origfields ) {
        croak "fields required";
    }

    my %fields;
    my $field_class = $self->{field_class};

    my $reftype = ref($origfields);
    if ( !$reftype or ( $reftype ne 'ARRAY' and $reftype ne 'HASH' ) ) {
        croak "fields must be an ARRAY or HASH ref";
    }

    # convert simple array to hash
    if ( $reftype eq 'ARRAY' ) {
        for my $name (@$origfields) {
            if ( blessed($name) ) {
                $fields{ $name->name } = $name;
            }
            elsif ( ref($name) eq 'HASH' ) {
                if ( !exists $name->{name} ) {
                    croak "'name' required in hashref: " . dump($name);
                }
                $fields{ $name->{name} } = $field_class->new(%$name);
            }
            else {
                $fields{$name} = $field_class->new( name => $name, );
            }
        }
    }
    elsif ( $reftype eq 'HASH' ) {
        for my $name ( keys %$origfields ) {
            my $val = $origfields->{$name};
            my $obj;
            if ( blessed($val) ) {
                $obj = $val;
            }
            elsif ( ref($val) eq 'HASH' ) {
                if ( !exists $val->{name} ) {
                    $val->{name} = $name;
                }
                $obj = $field_class->new(%$val);
            }
            elsif ( !ref $val ) {
                $obj = $field_class->new( name => $name );
            }
            else {
                croak
                    "field value for $name must be a field name, hashref or Field object";
            }
            $fields{$name} = $obj;
        }
    }

    $self->{fields} = \%fields;
    return $self->{fields};
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
    $q = $class->preprocess($q);
    my ($query) = $self->_parse( $q, undef, undef, $class );
    if ( !defined $query ) {
        croak $self->error if $self->croak_on_error;
        return $query;
    }

    if ( $self->{fields} ) {
        $self->_expand($query);
        $self->_validate($query);
    }
    $query->{parser} = $self;

    #weaken( $query->{parser} );    # TODO leaks possible?

    return $query;
}

sub _expand {
    my ( $self, $query ) = @_;

    return if !exists $self->{fields};
    my $fields        = $self->{fields};
    my $query_class   = $self->{query_class};
    my $default_field = $self->{default_field};

    #dump $fields;

    $query->walk(
        sub {
            my ( $clause, $tree, $code, $prefix ) = @_;

            #warn "code clause: " . dump $clause;

            #warn "code tree: " . dump $tree;

            if ( $clause->is_tree ) {
                $clause->value->walk($code);
                return;
            }
            if ( !defined $clause->field && !defined $default_field ) {
                return;
            }
            if ( defined $default_field && !defined $clause->field ) {
                $clause->field($default_field);
                if ( !$clause->op ) {
                    $clause->op( $self->default_op );
                }
            }
            my $field_name = $clause->field || $default_field;
            if ( !exists $fields->{$field_name} ) {
                return;
            }
            my $field = $fields->{$field_name};
            if ( $field->alias_for ) {
                my @aliases
                    = ref $field->alias_for
                    ? @{ $field->alias_for }
                    : ( $field->alias_for );

                #warn "match field $field aliases: " . dump \@aliases;

                if ( @aliases > 1 ) {

                    # turn $clause into a tree
                    my $class = blessed($clause);
                    my $op    = $clause->op;

                    #warn "before tree: " . dump $tree;

                    #warn "code clause: " . dump $clause;
                    my @newfields;
                    for my $alias (@aliases) {
                        push(
                            @newfields,
                            $class->new(
                                field => $alias,
                                op    => $op,
                                value => $clause->value,
                            )
                        );
                    }

                    # OR the fields together. TODO optional?

                    # we must bless here because
                    # our bool op keys are not methods.
                    my $newfield
                        = bless( { "" => \@newfields }, $query_class );
                    $newfield->init( %{ $self->query_class_opts },
                        parser => $self );

                    $clause->op('()');
                    $clause->value($newfield);

                    #warn "after tree: " . dump $tree;

                }
                else {

                    # simple this-for-that
                    $clause->field( $aliases[0] );
                }

            }
            return $clause;
        }
    );
}

sub _validate {
    my ( $self, $query ) = @_;

    my $fields    = $self->{fields};
    my $validator = sub {
        my ( $clause, $tree, $code, $prefix ) = @_;
        if ( $clause->is_tree ) {
            $clause->value->walk($code);
        }
        else {
            return unless defined $clause->field;
            my $field_name  = $clause->field;
            my $field_value = $clause->value;
            my $field       = $fields->{$field_name}
                or croak "No such field: $field_name";
            if ( !$field->validate($field_value) ) {
                my $err = $field->error;
                croak
                    "Invalid field value for $field_name: $field_value ($err)";
            }
        }
    };
    $query->walk($validator);
}

sub _parse {
    my $self         = shift;
    my $str          = shift;
    my $parent_field = shift;    # only for recursive calls
    my $parent_op    = shift;    # only for recursive calls
    my $query_class  = shift;

    #warn "_parse: " . dump [ $str, $parent_field, $parent_op, $query_class ];

    #dump $self;

    my $q                = {};
    my $pre_bool         = '';
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
    my $near_regex       = $self->{near_regex};
    my $range_regex      = $self->{range_regex};
    my $clause_class     = $self->{clause_class};

    $str =~ s/^\s+//;    # remove leading spaces

LOOP:
    while ($str) {       # while query string is not empty
        for ($str) {     # temporary alias to $_ for easier regex application

            #warn "LOOP start: " . dump [ $str, $parent_field, $parent_op ];

            my $sign  = $self->{default_boolop};
            my $field = $parent_field;
            my $op    = $parent_op || "";

            #warn "LOOP after start: " . dump [ $sign, $field, $op ];

            if (m/^\)/) {
                last LOOP;    # return from recursive call if meeting a ')'
            }

            # try to parse sign prefix ('+', '-' or '!|NOT')
            if    (s/^(\+|-)\s*//)         { $sign = $1; }
            elsif (s/^($not_regex)\b\s*//) { $sign = '-'; }

            # special check because of \b above
            elsif (s/^\!\s*([^:=~])/$1/) { $sign = '-'; }

            # try to parse field name and operator
            if (s/^"($field_regex)"\s*($op_regex)\s*//   # "field name" and op
                or
                s/^'?($field_regex)'?\s*($op_regex)\s*// # 'field name' and op
                or s/^()($op_nofield_regex)\s*//         # no field, just op
                )
            {
                ( $field, $op ) = ( $1, $2 );

                #warn "matched field+op = " . dump [ $field, $op ];
                if ($parent_field) {
                    $err = "field '$field' inside '$parent_field' (op=$op)";
                    last LOOP;
                }
            }

            # parse a value (single term or quoted list or parens)
            my $clause = undef;

            if (   s/^(")([^"]*?)"~(\d+)\s*//
                or s/^(")([^"]*?)"\s*//
                or s/^(')([^']*?)'\s*// )
            {    # parse a quoted string.
                my ( $quote, $val, $proximity ) = ( $1, $2, $3 );
                $clause = $clause_class->new(
                    field => $field,
                    op    => ( $op || $parent_op || ( $field ? ":" : "" ) ),
                    value => $val,
                    quote => $quote,
                    proximity => $proximity
                );
            }
            elsif (s/^\(\s*//) {    # parse parentheses
                my ( $r, $s2 )
                    = $self->_parse( $str, $field, $op, $query_class );
                if ( !$r ) {
                    $err = $self->error;
                    last LOOP;
                }
                $str = $s2;
                if ( !defined($str) or !( $str =~ s/^\)\s*// ) ) {
                    $err = "no matching ) ";
                    last LOOP;
                }

                $clause = $clause_class->new(
                    field => '',
                    op    => '()',
                    value => bless( $r, $query_class ),    # re-bless
                );

            }
            elsif (s/^($term_regex)\s*//) {    # parse a single term
                my $term = $1;
                if ( $term =~ m/^($term_regex)$range_regex($term_regex)$/ ) {
                    my $t1 = $1;
                    my $t2 = $2;

                    #warn "found range ($op $parent_op): $term => $t1 .. $t2";
                    my $this_op = $op =~ m/\!/ ? '!..' : '..';
                    $clause = $clause_class->new(
                        field => $field,
                        op    => $this_op,
                        value => [ $t1, $t2 ],
                    );
                }
                else {

                    $clause = $clause_class->new(
                        field => $field,
                        op => ( $op || $parent_op || ( $field ? ":" : "" ) ),
                        value => $term,
                    );

                }
            }

            if (s/^($near_regex)\s+//) {

                # modify the existing clause
                # and treat what comes next like a phrase
                # matching the syntax "foo bar"~\d+
                my ($prox_match) = ($1);
                my ($proximity)  = $prox_match;
                $proximity =~ s/\D+//;    # leave only number
                if (s/^($term_regex)\s*//) {
                    my $term = $1;
                    $clause->{value} .= ' ' . $term;
                    $clause->{proximity} = $proximity;
                    $clause->{quote}     = '"';
                }
                else {
                    $err = "missing term after $prox_match";
                    last LOOP;
                }

            }

            # deal with boolean connectors
            my $post_bool = '';
            if (s/^($and_regex)\s+//) {
                $post_bool = 'AND';
            }
            elsif (s/^($or_regex)\s+//) {
                $post_bool = 'OR';
            }

            if (    $pre_bool
                and $post_bool
                and $pre_bool ne $post_bool )
            {
                $err = "cannot mix AND/OR in requests; use parentheses";
                last LOOP;
            }

            my $bool = $pre_bool || $post_bool;
            $pre_bool = $post_bool;    # for next loop

            # insert clause in query structure
            if ($clause) {
                $sign = ''  if $sign eq '+' and $bool eq 'OR';
                $sign = '+' if $sign eq ''  and $bool eq 'AND';
                if ( $sign eq '-' and $bool eq 'OR' ) {
                    $err = 'operands of "OR" cannot have "-" or "NOT" prefix';
                    last LOOP;
                }
                push @{ $q->{$sign} }, $clause;
            }
            else {
                if ($_) {
                    $err = "unexpected string in query: '$_'";
                    last LOOP;
                }
                if ($field) {
                    $err = "missing value after $field $op";
                    last LOOP;
                }
            }
        }
    }

    # handle error
    if ($err) {
        $self->{error} = "[$s_orig] : $err";
        $q = undef;
    }

    #dump $q;

    if ( !defined $q ) {
        return ( $q, $str );
    }
    my $query
        = $query_class->new( %{ $self->query_class_opts }, parser => $self );
    $query->{$_} = $q->{$_} for keys %$q;
    return ( $query, $str );
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
