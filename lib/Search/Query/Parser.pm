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

our $VERSION = '0.06';

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
        default_op
        phrase_delim
        query_class
        field_class
        clause_class
        query_class_opts
        croak_on_error
        )
);

__PACKAGE__->mk_ro_accessors(qw( error ));

my %DEFAULT = (
    term_regex  => qr/[^\s()]+/,
    field_regex => qr/[\.\w]+/,    # match prefix.field: or field

    # longest ops first !
    op_regex => qr/~\d+|==|<=|>=|!=|=~|!~|[:=<>~#]/,

    # ops that admit an empty left operand
    op_nofield_regex => qr/=~|!~|[~:#]/,

    # case insensitive
    and_regex        => qr/AND|ET|UND|E/i,
    or_regex         => qr/OR|OU|ODER|O/i,
    not_regex        => qr/NOT|PAS|NICHT|NON/i,
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
    and_regex      => qr/AND|ET|UND|E/i,
    or_regex       => qr/OR|OU|ODER|O/i,
    not_regex      => qr/NOT|PAS|NICHT|NON/i,

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

Applied to all terms where no field is defined. The default value is undef (no default).

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
    if ( !exists $self->{_fields}->{$name} ) {
        return undef;
    }
    return $self->{_fields}->{$name};
}

=head2 fields

Returns the I<fields> structure set by set_fields().

=cut

sub fields {
    return shift->{_fields};
}

=head2 set_fields( I<fields> )

Set the I<fields> structure. Called internally by init()
if you pass a C<fields> key/value pair to new().

=cut

sub set_fields {
    my $self = shift;
    my $origfields = shift || $self->{fields};
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

    $self->{_fields} = \%fields;
    return $self->{_fields};
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
    my ($query) = $self->_parse( $q, undef, undef, $class );
    if ( !defined $query ) {
        croak $self->error if $self->croak_on_error;
        return $query;
    }

    if ( $self->{fields} ) {
        $self->_expand($query);
        $self->_validate($query);
    }
    $query->{_parser} = $self;
    weaken( $query->{_parser} );

    return $query;
}

sub _expand {
    my ( $self, $query ) = @_;

    return if !exists $self->{_fields};
    my $fields        = $self->{_fields};
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
                        _parser => $self );

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

    my $fields    = $self->{_fields};
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

            # try to parse sign prefix ('+', '-' or 'NOT')
            if    (s/^(\+|-)\s*//)         { $sign = $1; }
            elsif (s/^($not_regex)\b\s*//) { $sign = '-'; }

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

            if (   s/^(")([^"]*?)"\s*//
                or s/^(')([^']*?)'\s*// )
            {    # parse a quoted string.
                my ( $quote, $val ) = ( $1, $2 );
                $clause = $clause_class->new(
                    field => $field,
                    op    => ( $op || $parent_op || ( $field ? ":" : "" ) ),
                    value => $val,
                    quote => $quote
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
                $clause = $clause_class->new(
                    field => $field,
                    op    => ( $op || $parent_op || ( $field ? ":" : "" ) ),
                    value => $1,
                );
            }

            # deal with boolean connectors
            my $post_bool = '';
            if (s/^($and_regex)\b\s*//) {
                $post_bool = 'AND';
            }
            elsif (s/^($or_regex)\b\s*//) {
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

    if ( !defined $q ) {
        return ( $q, $str );
    }
    my $query
        = $query_class->new( %{ $self->query_class_opts }, _parser => $self );
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
