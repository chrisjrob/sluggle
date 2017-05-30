package utility;

use strict;
use Exporter;

my @functions = qw(
    superchomp
    validate_address
    check_for_server_ip 
);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = @functions;
our %EXPORT_TAGS = (
    DEFAULT => [@functions],
    ALL     => [@functions],
);


# Chomp to cope with Windows line endings

sub superchomp {
    my $string = shift;
    return if (not defined $string);
    $string =~ s/[\r\n]//g;
    return $string;
}


# Validate URL and return any error
# Includes important security checks

sub validate_address {
    my $request = shift;

    my $count = (my @elements) = split(/\s+/, $request);

    my $retcode = 1; # success
    my $error;

    # Basic checks
    if ($count > 1) {
        $retcode = 0;
        $error = 'Spaces are not permitted';
        return $retcode, $error;

    } elsif ($request !~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|) {
        $retcode = 0;
        $error = 'That does not look like a URL';
        return $retcode, $error;

    }

    use Regexp::IPv6 qw($IPv6_re);
    use Regexp::Common qw /net/;
    my $IPv4_re = $RE{net}{IPv4};

    use URI::URL;
    my $url = new URI::URL $request;
    my ($host, $port);

    eval { $port = $url->port; };
    warn "Port not found $@" if $@;

    eval { $host = $url->host; };
    warn "Host not found $@" if $@;

    if ($@) {
        $retcode = 0;
        $error = "Host not found $@";

    } elsif ( (defined $port) and ($port ne '80' ) and ($port ne '443') ) {
        $retcode = 0;
        $error = 'Non-standard HTTP ports are not permitted';

    } elsif ( $request =~ m/^(?:https?:\/\/)?$IPv4_re/i ) {
        $retcode = 0;
        $error = 'IP addresses are not permitted';

    } elsif ( $request =~ m/^(?:https?:\/\/)?$IPv6_re/i ) {
        $retcode = 0;
        $error = 'IP addresses are not permitted';

    } elsif ( $request =~ m/^(?:https?:\/\/)?[\/\.]+/i ) {
        $retcode = 0;
        $error = 'URLs starting with a file path are not permitted';

    }

    return $retcode, $error;
}

sub check_for_server_ip {
    my $request = shift;

    use Net::Address::IP::Local;

    my $ipv4 = Net::Address::IP::Local->public_ipv4;
    my $ipv6 = Net::Address::IP::Local->public_ipv6;

    $request =~ s/(?:$ipv4|$ipv6)/censored/gi;

    # That really should be it, but what if the delimiters
    # are changed to dashes or anything
    # Extra check stripping non-alphanumerics

    my $request_an = strip_non_alphanumerics($request);
    my $ipv4_an    = strip_non_alphanumerics($ipv4);
    my $ipv6_an    = strip_non_alphanumerics($ipv6);

    if ($request_an =~ s/(?:$ipv4_an|$ipv6_an)/censored/gi) {
        # If there is still a hidden IP address
        # you'd better return the stripped and 
        # validated output
        return $request_an;
    } else {
        # All good
        return $request;
    }
    
    return;
}

# Internal functions

sub strip_non_alphanumerics {
    my $string = shift;

    my $alphanumerics = $string;
    $alphanumerics =~ s/\W+/-/g;

    return $alphanumerics;
}

