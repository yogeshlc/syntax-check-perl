use strict;
use warnings;
use Capture::Tiny 'capture_merged';
use Checker;
use Checker::Impl::Compile ();
use File::Spec             ();
use JSON::PP 'decode_json';

use Test::More;
use Test::Differences qw( eq_or_diff );
use Test::Fatal qw( exception );

my $ref_warn = $] >= 5.022 ? "single ref" : "reference";

subtest basic => sub {
    my $checker = Checker->new;
    my @err;
    @err = $checker->_run("t/file/cpanfile", "t/file/cpanfile");
    is @err, 0 or do { diag explain $_ for @err };

    @err = $checker->_run("t/file/alienfile", "t/file/alienfile");
    is @err, 0;

    @err = $checker->_run("t/file/use_fail.pl", "t/file/use_fail.pl");
    is @err, 2;
    like $err[0]{message}, qr/Can't locate FOOOOOOOO.pm/;
    is $err[0]{line}, 5;

    @err = $checker->_run("t/file/warn.pl", "t/file/warn.pl");
    is_deeply \@err, [
        {
            from    => "Checker::Impl::Compile",
            line    => 7,
            message => "Subroutine foo redefined",
            type    => "WARN",
        },
        {
            from    => "Checker::Impl::Compile",
            line    => 10,
            message => "Useless use of $ref_warn constructor in void context",
            type    => "WARN",
        },
        {
            from    => "Checker::Impl::Compile",
            line    => 12,
            message => "Bareword \"oooooops\" not allowed while \"strict subs\" in use",
            type    => "ERROR",
        },
    ];

    @err = $checker->_run("t/file/invalid.pl", "t/file/invalid.pl");
    is @err, 1;
    is_deeply $err[0], { type => 'ERROR', message => 'syntax error, near "ff', line => 4, from => 'Checker::Impl::Compile' };
};

subtest skip => sub {
    my $checker = Checker->new(config => {
        compile => {
            skip => [ qr/Subroutine \S+ redefined/ ],
        },
    });
    my @err = $checker->_run("t/file/warn.pl", "t/file/warn.pl");
    is_deeply \@err, [
        {
            from    => "Checker::Impl::Compile",
            line    => 10,
            message => "Useless use of $ref_warn constructor in void context",
            type    => "WARN",
        },
        {
            from    => "Checker::Impl::Compile",
            line    => 12,
            message => "Bareword \"oooooops\" not allowed while \"strict subs\" in use",
            type    => "ERROR",
        },
    ];
};

subtest custom => sub {
    my $checker = Checker->new(config => {
        custom => {
            check => [
                sub {
                    my ($line, $filename) = @_;
                    if ($filename =~ m{t/file/todo\.pl}
                        && $line =~ /TODO/) {
                        return { type => 'WARN', message => 'TODO must be resolved' };
                    }
                },
            ],
        },
    });
    my @err = $checker->_run("t/file/todo.pl", "t/file/todo.pl");
    is_deeply \@err, [
        {
            from => "Checker::Impl::Custom",
            line => 5,
            message => "TODO must be resolved",
            type => "WARN"
        }
    ];
    @err = $checker->_run("t/file/todo_skip.pl", "t/file/todo_skip.pl");
    is @err, 0;
};

subtest output => sub {
    my $checker = Checker->new;
    my ($merged) = capture_merged { $checker->run("t/file/alienfile", "t/file/alienfile") };
    is $merged, "";

    ($merged) = capture_merged { $checker->run("--format", "json", "t/file/use_fail.pl") };
    my $decoded = decode_json($merged);
    like $decoded->[0]{message}, qr/Can't locate FOOOOOOOO.pm/;
    is $decoded->[0]{line}, 5;
};

subtest config_file_does_not_exist => sub {
    my $checker = Checker->new( config_file => 'does_not_exist.pl' );
    like(
        exception( sub { $checker->_load_config } ),
        qr{No such file or directory}, 'exception on config file not found'
    );
};

subtest custom_config_file => sub {
    my $checker = Checker->new( config_file => 't/config/custom.pl' );
    $checker->_load_config;
    eq_or_diff(
        $checker->{config},
        {
            compile => {
                inc => {
                    libs    => [ 't/lib', 'lib', 'local/lib/perl5', ],
                    replace => 0,
                }
            }
        },
        'config loaded'
    );

    my $compile
        = Checker::Impl::Compile->new( %{ $checker->{config}->{compile} } );

    my @inc = @{ $compile->_inc };
    eq_or_diff(
        _get_children( \@inc ), [ 'syntax-check-perl/extlib', 't/lib', 'syntax-check-perl/lib' ],
        'default folders added to inc'
    );

    my @cmd = @{ $compile->_cmd };

    eq_or_diff(
        _get_children( [ @cmd[ 1, 2, 3 ] ] ),
        [ 'syntax-check-perl/extlib', 't/lib', 'syntax-check-perl/lib' ],
        'default folders added to inc in command'
    );
};

subtest custom_config_file_with_replace => sub {
    local $ENV{REPLACE_LIBS} = 1;
    my $checker = Checker->new( config_file => 't/config/custom.pl' );
    $checker->_load_config;
    eq_or_diff(
        $checker->{config},
        {
            compile => {
                inc => {
                    libs    => [ 't/lib' ],
                    replace => 1,
                }
            }
        },
        'config loaded'
    );

    my $compile
        = Checker::Impl::Compile->new( %{ $checker->{config}->{compile} } );

    my @inc = @{ $compile->_inc };
    eq_or_diff(
        _get_children( \@inc ), [ 'syntax-check-perl/extlib', 't/lib', ],
        'folders added to inc'
    );

    my @cmd = @{ $compile->_cmd };

    eq_or_diff(
        _get_children( [ @cmd[ 1, 2 ] ] ),
        [ 'syntax-check-perl/extlib', 't/lib' ],
        'folders added to inc in command'
    );
};

subtest no_config_file => sub {
    my $checker = Checker->new;
    $checker->_load_config;
    eq_or_diff(
        $checker->{config},
        { compile => { inc => { libs => [ 'lib', 'local/lib/perl5', ] } } },
        undef,
        'default config loaded'
    );

    my $compile
        = Checker::Impl::Compile->new( %{ $checker->{config}->{compile} } );

    my @inc = @{ $compile->_inc };
    eq_or_diff(
        _get_children( \@inc ),
        [ 'syntax-check-perl/extlib', 'syntax-check-perl/lib', ],
        'default folders added to inc'
    );

    my @cmd = @{ $compile->_cmd };
    eq_or_diff(
        _get_children( [ @cmd[ 1, 2 ] ] ),
        [ 'syntax-check-perl/extlib', 'syntax-check-perl/lib' ],
        'default folders added to inc in command'
    );
};

sub _get_children {
    my $paths = shift;

    my @libs;
    for my $path ( @{$paths} ) {
        my @dirs = File::Spec->splitdir($path);
        push @libs, @dirs > 1 ? join '/', @dirs[-2,-1] : $dirs[0];
    }

    # Strip -I switch from relative paths.
    for my $lib (@libs) {
        $lib =~ s{\A\-I}{};
    }
    return \@libs;
}

done_testing;
