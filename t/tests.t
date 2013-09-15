package TestSimple;
use strict;
use warnings;
our $CALL_COUNTER;
our $AFTER_COUNTER;
our $AFTER_OVERRIDE_COUNTER;
use Exporter 'import';
use constant {
    CONST_OLD_1 => 123,
    CONST_OLD_2 => 456,
};
BEGIN {
    our @EXPORT_OK = qw(CONST_OLD_1 CONST_OLD_2);
}
use Constant::Export::Lazy (
    constants => {
        TEST_CONSTANT_USE_CONSTANT_PM => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('CONST_OLD_1') + $ctx->call('CONST_OLD_2');
        },
        TEST_CONSTANT_CONST => sub {
            $CALL_COUNTER++;
            1;
        },
        TEST_CONSTANT_VARIABLE => sub {
            $CALL_COUNTER++;
            my $x = 1;
            my $y = 2;
            $x + $y;
        },
        TEST_CONSTANT_REQUESTED => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('TEST_CONSTANT_NOT_REQUESTED');

        },
        TEST_CONSTANT_NOT_REQUESTED => sub {
            $CALL_COUNTER++;
            98765;
        },
        TEST_CONSTANT_RECURSIVE => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('TEST_CONSTANT_VARIABLE') + 1;
        },
        TEST_LIST => sub {
            $CALL_COUNTER++;
            wantarray ? (1..2) : [3..4];
        },
        DO_NOT_CALL_THIS => sub {
            $CALL_COUNTER++;
            die "This should not be called";
        },
        TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME => {
            # We should not only call but also intern this constant.
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    return;
                },
                override => sub {
                    my ($ctx, $name) = @_;
                    # We should still call overrides for things that
                    # are called from *other* stuff that's being
                    # overriden.
                    return 1 + $ctx->call($name);
                },
            },
            call => sub {
                $CALL_COUNTER++;
                1;
            },
        },
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME => {
            options => {
                override => sub {
                    my ($ctx, $name) = @_;

                    if (exists $ENV{OVERRIDDEN_ENV_NAME}) {
                        my $value = $ctx->call($name) + $ctx->call('TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME');
                        return $ENV{OVERRIDDEN_ENV_NAME} + $value;
                    }
                    return;
                },
            },
            call => sub {
                $CALL_COUNTER++;
                39;
            },
        },
        TEST_AFTER_OVERRIDE => {
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    $AFTER_OVERRIDE_COUNTER++;
                    return;
                },
                stash => {
                    some_value => 123456,
                },
            },
            call => sub {
                my ($ctx) = @_;
                $CALL_COUNTER++;
                $ctx->stash->{some_value};
            },
        },
        TEST_NO_STASH => {
            call => sub {
                my ($ctx) = @_;
                $CALL_COUNTER++;
                $ctx->stash;
            },
        },
    },
    options => {
        wrap_existing_import => 1,
        override => sub {
            my ($ctx, $name) = @_;

            if (exists $ENV{$name}) {
                my $value = $ctx->call($name);
                return $ENV{$name} * $value;
            }
            return;
        },
        after => sub {
            my ($ctx, $name, $value, $source) = @_;
            $AFTER_COUNTER++;

            return;
        },
    },
);

package TestSimple::Subclass;
use strict;
use warnings;
BEGIN { our @ISA = qw(TestSimple) }

package main;
use strict;
use warnings;
use lib 't/lib';
use Test::More 'no_plan';
BEGIN {
    $ENV{TEST_CONSTANT_VARIABLE} = 2;
    $ENV{OVERRIDDEN_ENV_NAME} = 1;
}
BEGIN {
    TestSimple->import(qw(
        CONST_OLD_1
        CONST_OLD_2
        TEST_CONSTANT_USE_CONSTANT_PM
        TEST_CONSTANT_CONST
        TEST_CONSTANT_VARIABLE
        TEST_CONSTANT_RECURSIVE
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME
        TEST_AFTER_OVERRIDE
        TEST_CONSTANT_REQUESTED
        TEST_LIST
        TEST_NO_STASH
    ))
}

is(CONST_OLD_1, 123, "We got a constant from the Exporter::import");
is(CONST_OLD_2, 456, "We got a constant from the Exporter::import");
is(TEST_CONSTANT_USE_CONSTANT_PM, 123 + 456, "We can use ->call() on Exporter::import constants");
is(TEST_CONSTANT_CONST, 1, "Simple constant sub");
is(TEST_CONSTANT_VARIABLE, 6, "Constant composed with some variables");
is(TEST_CONSTANT_RECURSIVE, 7, "Constant looked up via \$ctx->call(...)");
is(TEST_CONSTANT_OVERRIDDEN_ENV_NAME, 42, "We properly defined a constant with some overriden options");
ok(exists &TestSimple::TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME, "We fleshened unrelated TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME though");
is(TEST_CONSTANT_REQUESTED, 98765, "Our requested constant has the right value");
ok(!exists &TEST_CONSTANT_NOT_REQUESTED, "We shouldn't import TEST_CONSTANT_NOT_REQUESTED into this namespace...");
is(TestSimple::TEST_CONSTANT_NOT_REQUESTED, 98765, "...but it should be defined in TestSimple::* so it'll be re-used as well");
is(join(",", @{TEST_LIST()}), '3,4');
is(TEST_NO_STASH, undef, "We'll return undef if we have no stash");

# Afterwards check that the counters are OK
our $call_counter = 11;
is($TestSimple::CALL_COUNTER, $call_counter, "We didn't redundantly call various subs, we cache them in the stash");
is($TestSimple::AFTER_COUNTER, $TestSimple::CALL_COUNTER, "Our AFTER counter is always the same as our CALL counter, we only call this for interned values");
is(TEST_AFTER_OVERRIDE, 123456, "We have TEST_AFTER_OVERRIDE defined");
is($TestSimple::AFTER_OVERRIDE_COUNTER, 1, "We correctly call 'after' overrides");

package main::frame;
use strict;
use warnings;
BEGIN {
    TestSimple::Subclass->import(qw(
        TEST_CONSTANT_CONST
    ))
}

main::is(TEST_CONSTANT_CONST, 1, "Simple constant sub for subclass testing");

# Afterwards check that the counters are OK
main::is($TestSimple::CALL_COUNTER, $main::call_counter, "We didn't redundantly call various subs, we cache them in the stash, even if someone subclasses the class");
main::is($TestSimple::AFTER_COUNTER, $TestSimple::CALL_COUNTER, "Our AFTER counter is always the same as our CALL counter, we only call this for interned values, even if someone subclasses the class");