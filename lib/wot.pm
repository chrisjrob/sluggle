package wot;

use strict;
use Exporter;

my @functions = qw(
    lookup
);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = @functions;
our %EXPORT_TAGS = (
    DEFAULT => [@functions],
    ALL     => [@functions],
);

sub lookup {
    my ($conf, $request) = @_;

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        return "WoT command should be followed by domain to be checked";
    }

    use URI::URL;
    my $url = new URI::URL $request;
    my $host;
    eval { $host = $url->host; };
    warn "Host not found $@" if $@;

    use Net::WOT;
    my $wot = Net::WOT->new;

    my %wot;
    eval {
        %wot = $wot->get_reputation($host);
    };
    warn "Get WoT Reputation failed $@" if $@;

    # the %wot hash seems oddly structured
    my $mywot = {
        'trustworthiness_description'       => $wot->trustworthiness_description,
        'trustworthiness_score'             => $wot->trustworthiness_score,
        'trustworthiness_confidence'        => $wot->trustworthiness_confidence,
        'vendor_reliability_description'    => $wot->vendor_reliability_description,
        'vendor_reliability_score'          => $wot->vendor_reliability_score,
        'vendor_reliability_confidence'     => $wot->vendor_reliability_confidence,
        'privacy_description'               => $wot->privacy_description,
        'privacy_score'                     => $wot->privacy_score,
        'privacy_confidence'                => $wot->privacy_confidence,
        'child_safety_description'          => $wot->child_safety_description,
        'child_safety_score'                => $wot->child_safety_score,
        'child_safety_confidence'           => $wot->child_safety_confidence
    };

    return $mywot;
}

