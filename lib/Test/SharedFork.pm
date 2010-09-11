package Test::SharedFork;
use strict;
use warnings;
use base 'Test::Builder::Module';
our $VERSION = '0.12';
use Test::Builder 0.32; # 0.32 or later is needed
use Test::SharedFork::Scalar;
use Test::SharedFork::Array;
use Test::SharedFork::Store;
use 5.008000;

my $STORE;

BEGIN {
    my $builder = __PACKAGE__->builder;

    if (Test::Builder->VERSION > 2.00) {
        # new Test::Builder
        $STORE = Test::SharedFork::Store->new();

        our $level = 0;
        for my $class (qw/Test::Builder2::History Test::Builder2::Counter/) {
            my $meta = $class->meta;
            my @methods = $meta->get_method_list;
            my $orig =
                $class eq 'Test::Builder2::History'
              ? $builder->{History}
              : $builder->{History}->counter;
            $orig->{hacked}++;
            $STORE->set($class => $orig);
            for my $method (@methods) {
                next if $method =~ /^_/;
                next if $method eq 'meta';
                next if $method eq 'create';
                next if $method eq 'singleton';
                $meta->add_around_method_modifier(
                    $method => sub {
                        my ($code, $orig_self, @args) = @_;
                        return $orig_self->$code(@args) if (! ref $orig_self) || ! $orig_self->{hacked};

                        my $lock = $STORE->get_lock();
                        local $level = $level + 1;
                        my $self =
                          $level == 1 ? $STORE->get($class) : $orig_self;
                        if (wantarray) {
                            my @ret = $code->($self, @args);
                            $STORE->set($class => $self);
                            return @ret;
                        } else {
                            my $ret = $code->($self, @args);
                            $STORE->set($class => $self);
                            return $ret;
                        }
                    },
                );
            }
        }
    } else {
        # older Test::Builder
        $STORE = Test::SharedFork::Store->new(
            cb => sub {
                my $store = shift;
                tie $builder->{Curr_Test}, 'Test::SharedFork::Scalar',
                $store, 'Curr_Test';
                tie @{ $builder->{Test_Results} },
                'Test::SharedFork::Array', $store, 'Test_Results';
            },
            init => +{
                Test_Results => $builder->{Test_Results},
                Curr_Test    => $builder->{Curr_Test},
            },
        );
    }

    # make methods atomic.
    no strict 'refs';
    no warnings 'redefine';
    for my $name (qw/ok skip todo_skip current_test/) {
        my $orig = *{"Test::Builder::${name}"}{CODE};
        *{"Test::Builder::${name}"} = sub {
            local $Test::Builder::Level += 3;
            my $lock = $STORE->get_lock(); # RAII
            $orig->(@_);
        };
    };

}

{
    # backward compatibility method
    sub parent { }
    sub child  { }
    sub fork   { fork() }
}

1;
__END__

=head1 NAME

Test::SharedFork - fork test

=head1 SYNOPSIS

    use Test::More tests => 200;
    use Test::SharedFork;

    my $pid = fork();
    if ($pid == 0) {
        # child
        ok 1, "child $_" for 1..100;
    } elsif ($pid) {
        # parent
        ok 1, "parent $_" for 1..100;
        waitpid($pid, 0);
    } else {
        die $!;
    }

=head1 DESCRIPTION

Test::SharedFork is utility module for Test::Builder.
This module makes forking test!

This module merges test count with parent process & child process.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom  slkjfd gmail.comE<gt>

yappo

=head1 THANKS TO

kazuhooku

konbuizm

=head1 SEE ALSO

L<Test::TCP>, L<Test::Fork>, L<Test::MultipleFork>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
