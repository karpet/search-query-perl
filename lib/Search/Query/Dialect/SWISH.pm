package Search::Query::Dialect::SWISH;
use strict;
use warnings;
use base qw( Search::Query::Dialect );
use Carp;
use Data::Dump qw( dump );
use Search::Query::Field::SWISH;

our $VERSION = '0.08';

__PACKAGE__->mk_accessors(
    qw(
        wildcard
        fuzzify
        )
);

=head1 NAME

Search::Query::Dialect::SWISH - Swish query dialect

=head1 SYNOPSIS

 my $query = Search::Query->parser( dialect => 'SWISH' )->parse('foo');
 print $query;

=head1 DESCRIPTION

Search::Query::Dialect::SWISH is a query dialect for Query
objects returned by a Search::Query::Parser instance.

The SWISH dialect class stringifies queries to work with Swish-e
and Swish3 Native search engines.

=head1 METHODS

This class is a subclass of Search::Query::Dialect. Only new or overridden
methods are documented here.

=cut

=head2 init

Overrides base method and sets SWISH-appropriate defaults.
Can take the following params, also available as standard attribute
methods.

=over

=item wildcard

Default is '*'.

=item fuzzify

If true, a wildcard is automatically appended to each query term.

=back

=cut

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    #carp dump $self;
    $self->{wildcard} = '*';

    $self->{default_field} ||= $self->parser->default_field
        || 'swishdefault';

    my $swishdefault_field;
    eval { $swishdefault_field = $self->parser->get_field('swishdefault'); };
    if ( !$swishdefault_field ) {
        $self->parser->{fields}->{swishdefault}
            = Search::Query::Field::SWISH->new( name => 'swishdefault' );
    }

    if ( $self->{default_field} and !ref( $self->{default_field} ) ) {
        $self->{default_field} = [ $self->{default_field} ];
    }

    return $self;
}

=head2 stringify

Returns the Query object as a normalized string.

=cut

my %op_map = (
    '+' => 'AND',
    ''  => 'OR',
    '-' => 'NOT',
);

sub stringify {
    my $self = shift;
    my $tree = shift || $self;

    my @q;
    foreach my $prefix ( '+', '', '-' ) {
        my @clauses;
        my $joiner = $op_map{$prefix};
        next unless exists $tree->{$prefix};
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

    # normalize wildcard
    my $wildcard = $self->wildcard;
    $value =~ s/[\*\%]/$wildcard/g;

    return $value;
}

=head2 stringify_clause( I<leaf>, I<prefix> )

Called by stringify() to handle each Clause in the Query tree.

=cut

sub stringify_clause {
    my $self   = shift;
    my $clause = shift;
    my $prefix = shift;

    #warn dump $clause;
    #warn "prefix = '$prefix'";

    if ( $clause->{op} eq '()' ) {
        if ( $clause->has_children and $clause->has_children == 1 ) {
            return $self->stringify( $clause->{value} );
        }
        else {
            return
                ( $prefix eq '-' ? 'NOT ' : '' ) . "("
                . $self->stringify( $clause->{value} ) . ")";
        }
    }

    # make sure we have a field
    my @fields
        = $clause->{field}
        ? ( $clause->{field} )
        : ( @{ $self->_get_default_field } );

    # what value
    my $value
        = ref $clause->{value}
        ? $clause->{value}
        : $self->_doctor_value($clause);

    my $wildcard = $self->wildcard;

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

    my $quote = $clause->quote || '';

    my @buf;
NAME: for my $name (@fields) {
        my $field = $self->_get_field($name);

        if ( defined $field->callback ) {
            push( @buf, $field->callback->( $field, $op, $value ) );
            next NAME;
        }

        #warn dump [ $name, $op, $quote, $value ];

        # invert fuzzy
        if ( $op eq '!~' ) {
            $value .= $wildcard unless $value =~ m/\Q$wildcard/;
            push( @buf,
                join( '', 'NOT ', $name, '=', qq/$quote$value$quote/ ) );
        }

        # fuzzy
        elsif ( $op eq '~' ) {
            $value .= $wildcard unless $value =~ m/\Q$wildcard/;
            push( @buf, join( '', $name, '=', qq/$quote$value$quote/ ) );
        }

        # invert
        elsif ( $op eq '!=' ) {
            push( @buf,
                join( '', 'NOT ', $name, '=', qq/$quote$value$quote/ ) );
        }

        # range
        elsif ( $op eq '..' ) {
            if ( ref $value ne 'ARRAY' or @$value != 2 ) {
                croak "range of values must be a 2-element ARRAY";
            }

            # we support only numbers at this point
            for my $v (@$value) {
                if ( $v =~ m/\D/ ) {
                    croak "non-numeric range values are not supported: $v";
                }
            }

            my @range = ( $value->[0] .. $value->[1] );
            push( @buf,
                join( '', $name, '=', '(', join( ' OR ', @range ), ')' ) );

        }

        # invert range
        elsif ( $op eq '!..' ) {
            if ( ref $value ne 'ARRAY' or @$value != 2 ) {
                croak "range of values must be a 2-element ARRAY";
            }

            # we support only numbers at this point
            for my $v (@$value) {
                if ( $v =~ m/\D/ ) {
                    croak "non-numeric range values are not supported: $v";
                }
            }

            my @range = ( $value->[0] .. $value->[1] );
            push(
                @buf,
                join( '',
                    'NOT ', $name, '=', '( ', join( ' ', @range ), ' )' )
            );
        }

        # standard
        else {
            push( @buf, join( '', $name, '=', qq/$quote$value$quote/ ) );
        }
    }
    my $joiner = $prefix eq '-' ? ' AND ' : ' OR ';
    return
          ( scalar(@buf) > 1 ? '(' : '' )
        . join( $joiner, @buf )
        . ( scalar(@buf) > 1 ? ')' : '' );
}

=head2 field_class

Returns "Search::Query::Field::SWISH".

=cut

sub field_class {'Search::Query::Field::SWISH'}

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
