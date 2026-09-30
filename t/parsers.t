#!/usr/bin/perl
# Regression tests for Pisg::Parser::Format::* modules.
#
# Each module in t/fixtures/<parser>.pl returns an arrayref of test cases:
#   { method => 'normalline'|'actionline'|'thirdline',
#     line   => 'raw log line',
#     expect => { field => value, ... } | undef }
# expect => undef means the line is expected NOT to match (parser returns undef).
#
# To add coverage for another Format module, drop a new fixtures file next
# to the existing ones - this script picks up every t/fixtures/*.pl file
# automatically, no registration needed.

use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../modules";

my @fixture_files = glob("$FindBin::Bin/fixtures/*.pl");

plan skip_all => 'no fixtures found in t/fixtures/' unless @fixture_files;

for my $file (sort @fixture_files) {
    my ($parser_name) = $file =~ m{([^/]+)\.pl$};
    my $module = "Pisg::Parser::Format::$parser_name";

    subtest $parser_name => sub {
        my $cases = do $file;
        die "failed to load fixture $file: $@" if $@;
        die "fixture $file did not return an arrayref" unless ref $cases eq 'ARRAY';

        require_ok($module) or return;
        my $parser = $module->new(cfg => {});
        isa_ok($parser, $module);

        for my $case (@$cases) {
            my $method = $case->{method};
            my $line   = $case->{line};
            my $expect = $case->{expect};

            my $got = $parser->$method($line);

            my $label = "$method: " . (length($line) > 60 ? substr($line, 0, 57) . '...' : $line);

            if (!defined $expect) {
                ok(!defined $got, "$label (should not match)");
            } else {
                is_deeply($got, $expect, $label);
            }
        }
    };
}

done_testing();
