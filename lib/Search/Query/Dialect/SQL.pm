package Search::Query::Dialect::SQL;
use strict;
use warnings;
use base qw( Search::Query::Dialect );
use Carp;
use Data::Dump qw( dump );
use Search::Query::Field::SQL;

__PACKAGE__->mk_accessors(
    qw( wildcard quote_fields default_field fuzzify fuzzify2 croak_on_error like )
);

our $VERSION = '0.06';

=head1 NAME

Search::Query::Dialect::SQL - SQL query dialect

=head1 SYNOPSIS

 my $query = Search::Query->parser( dialect => 'SQL' )->parse('foo');
 print $query;

=head1 DESCRIPTION

Search::Query::Dialect::SQL is a query dialect for Query
objects returned by a Search::Query::Parser instance.

The SQL dialect class stringifies queries to work as SQL WHERE
clauses. This behavior is similar to Search::QueryParser::SQL.

=head1 METHODS

This class is a subclass of Search::Query::Dialect. Only new or overridden
methods are documented here.

=cut

=head2 init

Overrides the base method. Can accept the following params, which
are also standard attribute accessors:

=over

=item wildcard

Default value is C<%>.

=item quote_fields

Default value is "". Set to (for example) C<`> to quote each field name
in stringify() as some SQL variants require that syntax (e.g. mysql).

=item default_field

Override the default field set in Search::Query::Parser.

=item fuzzify

Append wildcard() to all terms.

=item fuzzify2

Prepend and append wildcard() to all terms.

=item like

The SQL reserved word for wildcard comparison. Default value is C<ILIKE>.

=item croak_on_error

Croak if any field validation fails.

=back

=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    #carp dump $self;
    $self->{wildcard} ||= '%';
    $self->{quote_fields} = '' unless exists $self->{quote_fields};
    $self->{default_field} ||= $self->{_parser}->default_field
        || [ sort keys %{ $self->{_parser}->fields } ];
    if ( $self->{default_field} and !ref( $self->{default_field} ) ) {
        $self->{default_field} = [ $self->{default_field} ];
    }
    $self->{like} ||= 'ILIKE';
    return $self;
}

=head2 stringify

Returns the Query object as a normalized string.

=cut

my %op_map = (
    '+' => 'AND',
    ''  => 'OR',
    '-' => 'AND',    # operator is munged
);

sub stringify {
    my $self = shift;
    my $tree = shift || $self;

    my @q;
    foreach my $prefix ( '+', '', '-' ) {
        my @clauses;
        my $joiner = $op_map{$prefix};
        next if not $tree->{$prefix};
        for my $clause ( @{ $tree->{$prefix} } ) {
            push( @clauses, $self->stringify_clause( $clause, $prefix ) );
        }
        next if !@clauses;

        push @q, join( " $joiner ", grep { defined and length } @clauses );
    }

    return join " AND ", @q;
}

sub _doctor_value {
    my ( $self, $clause ) = @_;

    my $value = $clause->{value};

    if ( $self->fuzzify ) {
        $value .= '*' unless $value =~ m/[\*\%]/;
    }
    elsif ( $self->fuzzify2 ) {
        $value = "*$value*" unless $value =~ m/[\*\%]/;
    }

    # normalize wildcard
    my $wildcard = $self->wildcard;
    $value =~ s/\*/$wildcard/g;

    return $value;
}

=head2 stringify_clause( I<leaf>, I<prefix> )

Called by stringify() to handle each Clause in the Query tree.

=cut

sub stringify_clause {
    my $self   = shift;
    my $clause = shift;
    my $prefix = shift;

    return "(" . $self->stringify( $clause->{value} ) . ")"
        if $clause->{op} eq '()';

    # optional
    my $quote_fields = $self->quote_fields;

    # make sure we have a field
    my @fields
        = $clause->{field}
        ? ( $clause->{field} )
        : ( @{ $self->_get_default_field } );

    # what value
    my $value = $self->_doctor_value($clause);

    # normalize operator
    my $op = $clause->{op} || "=";
    if ( $op eq ':' ) {
        $op = '=';
    }
    if ( $prefix eq '-' ) {
        $op = '!' . $op;
    }
    if ( $value =~ m/\%/ ) {
        $op = $prefix eq '-' ? '!~' : '~';
    }

    my @buf;
NAME: for my $name (@fields) {
        my $field = $self->_get_field($name);
        $value =~ s/\%//g if $field->is_int;
        my $this_op;

        # whether we quote depends on the field (column) type
        my $quote = $field->is_int ? "" : "'";

        # fuzzy
        if ( $op =~ m/\~/ ) {

            # negation
            if ( $op eq '!~' ) {
                if ( $field->is_int ) {
                    $this_op = $field->fuzzy_not_op;
                }
                else {
                    $this_op = ' ' . $field->fuzzy_not_op . ' ';
                }
            }

            # standard fuzzy
            else {
                if ( $field->is_int ) {
                    $this_op = $field->fuzzy_op;
                }
                else {
                    $this_op = ' ' . $field->fuzzy_op . ' ';
                }
            }
        }
        else {
            $this_op = $op;
        }

        if ( defined $field->callback ) {
            push( @buf, $field->callback->( $field, $this_op, $value ) );
            next NAME;
        }

        #warn dump [ $quote_fields, $name, $this_op, $quote, $value ];

        push(
            @buf,
            join( '',
                $quote_fields, $name,  $quote_fields, $this_op,
                $quote,        $value, $quote )
        );

    }
    my $joiner = $prefix eq '-' ? ' AND ' : ' OR ';
    return
          ( scalar(@buf) > 1 ? '(' : '' )
        . join( $joiner, @buf )
        . ( scalar(@buf) > 1 ? ')' : '' );
}

sub _get_field {
    my $self  = shift;
    my $name  = shift or croak "field name required";
    my $field = $self->{_parser}->get_field($name);
    if ( !$field ) {
        if ( $self->croak_on_error ) {
            croak "invalid field name: $name";
        }
        $field = $self->field_class->new( name => $name );
    }

    # fix up the operator based on our like() setting
    $field->fuzzy_op( $self->like ) if !$field->is_int;
    $field->fuzzy_not_op( 'NOT ' . $self->like ) if !$field->is_int;

    return $field;
}

sub _get_default_field {
    my $self = shift;
    my $field = $self->default_field || $self->{_parser}->default_field;
    if ( !$field ) {
        croak "must define a default_field";
    }
    return ref $field ? $field : [$field];
}

=head2 field_class

Returns "Search::Query::Field::SQL".

=cut

sub field_class {'Search::Query::Field::SQL'}

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
