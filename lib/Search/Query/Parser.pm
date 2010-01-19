package Search::Query::Parser;
use strict;
use warnings;
use base qw( Rose::ObjectX::CAF );
use Carp;
use Data::Dump qw( dump );
use Search::Query::Dialect::Native;
use Search::Query::Clause;
use Scalar::Util qw( blessed );

our $VERSION = '0.04';

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
        phrase_delim
        query_class
        field_class
        clause_class
        )
);

__PACKAGE__->mk_ro_accessors(qw( error ));

my %DEFAULT = (
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
    field_class    => 'Search::Query::Field',
    clause_class   => 'Search::Query::Clause',

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

=item fields

=item phrase_delim

=item query_class

=item field_class

=item clause_class

=back

=head2 init

Overrides the base method to initialize the object.

=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    for my $key ( keys %DEFAULT ) {
        my $val = $DEFAULT{$key};
        if ( !exists $self->{$key} ) {
            $self->{$key} = $val;
        }
    }

    # make sure classes are loaded
    for my $class (qw( query_class field_class clause_class )) {
        my $c = $self->{$class};
        eval "require $c";
        die $@ if $@;
    }

    $self->set_fields( $self->{fields} ) if $self->{fields};

    return $self;
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
                $fields{ $name->{name} } = bless( $name, $field_class );
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
                $obj = bless( $val, $field_class );
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
    my ($query) = $self->_parse( $q, 0, 0, $class );
    return $query unless defined $query;

    if ( $self->{fields} ) {
        $self->_expand($query);
        $self->_validate($query);
    }
    return $query;
}

sub _expand {
    my ( $self, $query ) = @_;

    return if !exists $self->{_fields};
    my $fields      = $self->{_fields};
    my $query_class = $self->{query_class};

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
            if ( !exists $fields->{ $clause->field } ) {
                return;
            }
            my $field = $fields->{ $clause->field };
            if ( $field->alias_for ) {
                my @aliases
                    = ref $field->alias_for
                    ? @{ $field->alias_for }
                    : ( $field->alias_for );

                #warn "match field $field->{name} aliases: " . dump \@aliases;

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
            my $field_name  = $clause->field;
            my $field_value = $clause->value;
            my $field       = $fields->{ $clause->field }
                or croak "No such field: " . $clause->field;
            if ( !$field->validate($field_value) ) {
                my $err = $field->error;
                croak
                    "Invalid field value for $field_name: $field_value ($err)";
            }
        }
    };
    $query->walk($validator);
}

=head2 error

Returns the last error message.

=cut

sub _parse {
    my $self         = shift;
    my $str          = shift;
    my $parent_field = shift;    # only for recursive calls
    my $parent_op    = shift;    # only for recursive calls
    my $query_class  = shift;

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
    my $clause_class     = $self->{clause_class};

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
            my $clause = undef;

            if (   s/^(")([^"]*?)"\s*//
                or s/^(')([^']*?)'\s*// )
            {    # parse a quoted string.
                my ( $quote, $val ) = ( $1, $2 );
                $clause = bless(
                    {   field => $field,
                        op    => $op,
                        value => $val,
                        quote => $quote
                    },
                    $clause_class

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
                if ( !( $str =~ s/^\)\s*// ) ) {
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
                    op    => $op,
                    value => $1,
                );
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

    return ( defined $q ? bless( $q, $query_class ) : $q, $str );
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
