package Test::TCM::Role::SQL;

use Moose::Role;
requires 'schema';

use Types::Common::Numeric qw(PositiveOrZeroInt);

use Scalar::Util qw(weaken);
use Test::More;

=head1 NAME

Test::TCM::Role::SQL - test number of SQL queries performed via DBIx::Class.

=head1 SYNOPSIS

    package My::Test;
    use Test::Class::Moose;
    with qw(Test::TCM::Role::SQL);

    sub test_something ( $test, $ ) {
        $test->expect_sql_count(0);
        some_code();
        $test->sql_count_ok("some_code() did't call database");
    }

=cut

has '_old_debug' => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub ($test) {
        $test->schema->storage->debug;
    },
);

has '_old_debugcb' => (
    is      => 'ro',
    isa     => 'CodeRef',
    default => sub ($test) {
        $test->schema->storage->debugcb || sub { };
    },
);

# Expected count of SQL queries
has '_expected_sql_count' => (
    is        => 'rw',
    isa       => PositiveOrZeroInt,
    predicate => '_has_expected_sql_count',
    clearer   => '_clear_expected_sql_count',
);

# Count of SQL queries actually performed
has '_sql_count' => (
    is      => 'ro',
    traits  => ['Counter'],
    isa     => PositiveOrZeroInt,
    default => 0,
    handles => {
        _inc_sql_count   => 'inc',
        _reset_sql_count => 'reset',
    },
);

# An array of SQL queries performed
has '_queries' => (
    is      => 'ro',
    traits  => ['Array'],
    isa     => 'ArrayRef',
    default => sub { [] },
    handles => {
        _add_sql_call => 'push',
        _has_queries  => 'count',
    },
    clearer => '_clear_queries',
);

=head1 METHODS

=head2 expect_sql_count($expect_sql_count)

Expect C<$expect_sql_count> SQL queries.

=cut

sub expect_sql_count ( $test, $expected_sql_count ) {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    $test->_expected_sql_count($expected_sql_count);

    my $storage = $test->schema->storage;
    $storage->debug(1);
    weaken( my $weak_test = $test );
    $storage->debugcb(
        sub {
            my ( $op, $info ) = @_;
            $weak_test->_inc_sql_count;
            $weak_test->_old_debugcb->(@_);
            $weak_test->_add_sql_call($info);
        }
    );
}

=head2 sql_count_ok($title = 'SQL count is as expected')

Finish test and check how many SQL queries were executed.

=cut

sub sql_count_ok ( $test, $title = '' ) {
    if ( !$test->_has_expected_sql_count ) {
        croak 'expect_sql_count() must be called before sql_count_ok()';
    }

    my $result = is(
        $test->_sql_count,
        $test->_expected_sql_count,
        $title || 'SQL count is as expected'
    );
    if ( !$result ) {
        if ( $test->_has_queries ) {
            diag "Performed SQL queries: [\n"
              . join( "\n", @{ $test->_queries } ) . "\n";
        }
    }

    $test->_reset_sql_count;
    $test->_clear_expected_sql_count;
    $test->_clear_queries;
    $test->schema->storage->debug( $test->_old_debug );
    $test->schema->storage->debugcb( $test->_old_debugcb );
}

before 'test_teardown' => sub {
    my ($test) = @_;

    if ( $test->_has_expected_sql_count ) {
        fail q{Seems like you've forgotten to call $test->sql_count_ok() in }
          . $test->test_report->current_method->name;
    }
};

=head1 CREDITS

Many thanks to the following people and organizations:

=over

=item David Cantrell L<david@cantrell.org.uk>

For the idea and first implementation which proved that idea useful.

=item All Around the World SASU L<https://allaroundtheworld.fr>

For sponsoring creation of this module.

=back

=cut

1;
