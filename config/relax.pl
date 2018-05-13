use strict;
use warnings;

my $filename = $ENV{PERL_SYNTAX_CHECK_FILENAME} || "";

# XXX cache
my @required_module;

my $config = {
    compile => {
        skip => [
            qr/^Subroutine \S+ redefined/,
            qr/^Name "\S+" used only once/,
            $filename =~ /\.psgi$/
                ? (qr/^Useless use of single ref constructor in void context/)
                : (),
        ],
        use_module => [
            [ "indirect", "-M-indirect=fatal" ],
        ],
    },
    regexp => {
        check => [
            qr/^ \s* my \s* \( (.*?) \) \s* = \s* shift/x,
            qr/pakcage/, # no syntax check
        ],
    },
    custom => {
        check => [
            sub {
                my ($line, $filename, $lines) = @_;
                if (my ($found) = $line =~ /\b([a-zA-Z0-9_:]+)->new/) {
                    if (!@required_module) {
                        for my $l (@$lines) {
                            if (my ($m) = $l =~ /\b(?:use|require)\s+([a-zA-Z0-9_:]+)/) {
                                push @required_module, $m;
                            }
                        }
                    }
                    if (!grep { $_ eq $found } @required_module) {
                        return "miss use $found";
                    }
                }
                return;
            },
        ]
    },
};
