package config;

use strict;
use Exporter;
use Config::Simple;
use URI;
use Carp;

my @functions = qw(
    get_config
    validate_config
    add_channel
    remove_channel
    list_bots
    add_bot
    remove_bot
    is_bot
);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = @functions;
our %EXPORT_TAGS = (
    DEFAULT => [@functions],
    ALL     => [@functions],
);

sub get_config {
    my $file = shift;
    my $conf = new Config::Simple($file);

    return $conf;
}

# Check our configuration is sensible and normalise things where possible.
# Arguments:
# - Reference to Config::Simple object.
# Returns:
# - Same Config::Simple refernece with any changes.
sub validate_config {
    my ($conf) = @_;

    if (defined $conf->param('twitter_frontend')) {
        my $fe_uri = URI->new($conf->param('twitter_frontend'));

        if (not defined $fe_uri or not $fe_uri->has_recognized_scheme) {
            croak "twitter_frontend '" . $conf->param('twitter_frontend')
                . "' doesn't look like a valid URI";
        }

        if ($fe_uri->scheme !~ /^https?$/) {
            croak "twitter_frontend scheme must be 'http' or 'https'";
        }

        if ($fe_uri->path !~ m|/$|) {
            carp "Appending '/' to your twitter_frontend '"
                . $fe_uri->as_string . "'";
            $fe_uri->path($fe_uri->path . '/');
            $conf->param('twitter_frontend', $fe_uri->as_string);
        }
    }

    return $conf;
}

sub add_channel {
    my ($conf, $where) = @_;

    my @channels = $conf->param('channels');
    push(@channels, $where);

    $conf->param('channels', \@channels);

    $conf->save();

    return $conf;
}

sub remove_channel {
    my ($conf, $where) = @_;

    # Remove the channel to the list
    my @channels = $conf->param('channels');

    my @newchannels;
    foreach my $channel (@channels) {
        if ($channel eq $where) {
            next;
        } else {
            push(@newchannels, $channel);
        }
    }

    my $count = @newchannels;
    if ($count == 0) {
        $conf->delete('channels');
    } else {
        $conf->param('channels', \@newchannels);
    }

    $conf->save();

    return $conf;
}

# Takes the bots array from the configuration file
# and returns comma delimited list scalar

sub list_bots {
    my $conf = shift;

    my @bots = $conf->param('bots');
    my $bots = join(', ', @bots);

    return $bots;
}

# Adds bot to the list of nicks to be ignored
# and saves it back to the configuration file
#
# This is intended to prevent bot wars
# but equally could be used to stop a particular nick
# from using the bot

sub add_bot {
    my ($conf, $request) = @_;

    my @bots = $conf->param('bots');

    my @unique = filter_unique(@bots, $request);

    $conf->param('bots', \@unique);
    $conf->save();

    my $bots = join(', ', @unique);

    return $bots;
}

# Removes bot from list of nicks to be ignored
# and saves the revised list back to configuration.

sub remove_bot {
    my ($conf, $request) = @_;

    my @bots = $conf->param('bots');

    my @newbots = grep { $_ ne $request } @bots;

    $conf->param('bots', \@newbots);
    $conf->save();

    my $bots = join(', ', @newbots);

    return $bots;
}

# Simple boolean lookup
# if nick is on bot list then returns 1
# otherwise returns 0

sub is_bot {
    my ($conf, $nick) = @_;

    my @bots = $conf->param('bots');
    my $bots = join('|', @bots );

    if ($nick =~ /^(?:$bots)\b/i) {
        return 1;
    } else {
        return 0;
    }
}

#
# Internal module functions
#

sub filter_unique {
    my @array = @_;

    my %unique;
    foreach my $element (@array) {
        $unique{$element} = 1;
    }

    my @unique = sort keys %unique;

    return @unique;
}

