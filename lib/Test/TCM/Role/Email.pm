package Test::TCM::Role::Email;

=head1 NAME

Test::TCM::Role::Email - role to test email sending.

=head1 SYNOPSIS

    use Test::Class::Moose;
    with qw(Test::TCM::Role::Email);

    sub test_emails_sent ($test, $) {
        $test->expect_emails(
            {
                name => 'my_template',
                to   => 'someone@example.com',
                html => '<b>Hello!</b>',
                text => 'Hello!',
            }
        );

        # ... code that should send emails ...

        $test->emails_ok;
    }

=cut

use Moose::Role;

use Carp qw(croak);
use Email::Address;
use Email::Sender::Simple;
use String::Util qw(trim);
use Test::More;
use Test::Differences qw(eq_or_diff);

=head1 METHODS

=head2 expect_emails

    In: @emails - array of emails in the order as they are being sent. Each
        email is a hashref with the following fields:
          name - email name, e.g. 'Change password email'; required
          to   - email address of a recipient - string or regexp; optional
          subject - expected email subject content or regexp; optional
          html - expected html content or regexp to match against; optional
          text - expected text content or regexp to match against; optional

Set emails we expect to send in the forthcoming code.
Either C<to> or C<html>, or C<text> part of expected email must be present.
C<@emails> may be empty to indicate that we are not expecting any email sending.

=cut

has '_expected_emails' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has '_testing_email' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has '_transport_from_env' => (
    is      => 'rw',
    isa     => 'Str',
    default => $ENV{EMAIL_SENDER_TRANSPORT},
);

sub expect_emails {
    my ( $test, @emails ) = @_;

    for my $email (@emails) {
        if ( ref($email) ne 'HASH' ) {
            croak 'Email must be a hashref';
        }
        if (   !exists $email->{html}
            && !exists $email->{text}
            && !exists $email->{to} )
        {
            croak q{One of 'to', 'html' or 'text' fields must be specified};
        }
        if ( !$email->{name} ) {
            croak 'name must be specified';
        }

        my %expect_email = (
            name => $email->{name},
            exists $email->{to} ? ( to => $email->{to} ) : (),
        );
        for my $field (qw(text html)) {
            if ( exists $email->{$field} ) {
                $expect_email{$field}
                  = ref( $email->{$field} )
                  ? $email->{$field}
                  : $email->{$field} =~ s/\r?\n/\r\n/gr;
            }
        }

        if (   exists $email->{subject}
            && defined $email->{subject}
            && length $email->{subject} )
        {
            $expect_email{subject} = trim( $email->{subject} );
        }

        $expect_email{text} = trim( $expect_email{text} );
        push @{ $test->_expected_emails }, \%expect_email;
    }
    $ENV{EMAIL_SENDER_TRANSPORT} = 'Test';
    $test->_testing_email(1);
}

=head2 emails_ok

Check that we've sent emails we expected to send.

This method B<MUST> be called after the code that is supposed to send a email -
not doing so makes test to fail.

=cut

sub emails_ok {
    my ($test) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    if ( !$test->_testing_email ) {
        fail q{Seems like you've forgotten to call expect_email() before};
    }

    my @deliveries = Email::Sender::Simple->default_transport->deliveries;
    my $sent_emails_count     = scalar @deliveries;
    my $expected_emails_count = scalar @{ $test->_expected_emails };
    is( $sent_emails_count,
        $expected_emails_count,
        "We've sent $expected_emails_count email(s), as expected"
    );

    for my $expected_email ( @{ $test->_expected_emails } ) {
        $test->_email_is( shift @deliveries, $expected_email );
    }
    $test->_expected_emails( [] );
    $test->_testing_email(0);

    # Clean up after ourselves
    Email::Sender::Simple->default_transport->clear_deliveries;
    Email::Sender::Simple->reset_default_transport;
    $ENV{EMAIL_SENDER_TRANSPORT} = $test->_transport_from_env;
}

sub _email_is ( $test, $delivery, $expected_email ) {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $name      = $expected_email->{name};
    my $got_email = $delivery->{email};
    ok( $got_email, "$name has been sent" );
    $delivery->{failures} //= [];
    ok( !@{ $delivery->{failures} }, '...without failures' );

    if ( exists $expected_email->{to} ) {
        if ( ref( $expected_email->{to} ) eq 'Regexp' ) {
            like(
                $got_email->get_header('To'),
                $expected_email->{to},
                "...to address that matches: $expected_email->{to}"
            );
        }
        else {
            is( $got_email->get_header('To'),
                $expected_email->{to},
                "...to the proper address: $expected_email->{to}"
            );
        }
    }

    if ( exists $expected_email->{subject} ) {
        if ( ref( $expected_email->{subject} ) eq 'Regexp' ) {
            like(
                $got_email->get_header('Subject'),
                $expected_email->{subject},
                "...subject matches: $expected_email->{subject}"
            );
        }
        else {
            is( $got_email->get_header('Subject'),
                $expected_email->{subject},
                "...subject equals: $expected_email->{subject}"
            );
        }
    }

    my @parts = $got_email->object->subparts;

    if ( exists $expected_email->{html} ) {
        my ($html_part) = grep { $_->content_type =~ m{text/html} } @parts;
        if ( ref( $expected_email->{html} ) eq 'Regexp' ) {
            like(
                $html_part->body_str, $expected_email->{html},
                "...its HTML part contains expected HTML code"
            );
        }
        else {
            eq_or_diff(
                $html_part->body_str, $expected_email->{html},
                "...its HTML part contains expected HTML code"
            );
        }
    }

    if ( exists $expected_email->{text} ) {
        my ($text_part) = grep { $_->content_type =~ m{text/plain} } @parts;
        if ( ref( $expected_email->{text} ) eq 'Regexp' ) {
            like(
                $text_part->body_str, $expected_email->{text},
                "...and text part contains expected text"
            );
        }
        else {
            eq_or_diff(
                $text_part->body_str, $expected_email->{text},
                "...and text part contains expected text"
            );
        }
    }
}

# Clean default transport before every test method to avoid collisions.
# Email::Sender::Simple stores default transport in package-scoped variable, so
# it persists between calls to send().
after test_setup => sub ( $test, $ ) {
    Email::Sender::Simple->reset_default_transport;
    $ENV{EMAIL_SENDER_TRANSPORT} = $test->_transport_from_env;
};

before test_teardown => sub {
    my ($test) = @_;

    if ( $test->_testing_email ) {
        fail q{Seems like you've forgotten to call $test->emails_ok() in }
          . $test->test_report->current_method->name;
    }
};

=head1 CREDITS

Many thanks to All Around the World SASU L<https://allaroundtheworld.fr> for
sponsoring creation of this module.

=cut

1;
