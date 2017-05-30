#!/usr/bin/perl
#
# A simple IRC searchbot

# Copyright (C) 2016 Christopher Roberts
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;

use config.pm;

use POE;
use POE::Component::IRC;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;

use vars qw( $CONF $LAG $REC );

if ( (defined $ARGV[0]) and (-r $ARGV[0]) ) {
    $CONF = get_config($ARGV[0]);
} else {
    print "USAGE: sluggle.pl sluggle.conf\n";
    exit;
}

# Set the Ping delay
$LAG = 300;

# Set the Reconnect delay
$REC = 60;

my @channels = $CONF->param('channels');

# We create a new PoCo-IRC object
my $irc = POE::Component::IRC::State->spawn(
   nick     => $CONF->param('nickname'),
   ircname  => $CONF->param('ircname'),
   server   => $CONF->param('server'),
) or die "Oh noooo! $!";

# Commands
POE::Session->create(
    package_states => [
        main => [ qw(
            _default 
            _start 
            lag_o_meter
            irc_001 
            irc_invite
            irc_kick
            irc_botcmd_find 
            irc_botcmd_wot
            irc_botcmd_op
            irc_botcmd_wolfram
            irc_botcmd_ignore
            irc_botcmd_wikipedia
            irc_public
        ) ],
    ],
    heap => { irc => $irc },
);

$poe_kernel->run();

# Start of IRC Bot Commands
# declared in POE::Session->create

sub _default {
    my ($kernel, $event, $args) = @_[KERNEL, ARG0 .. $#_];
    my @output = ( "$event: " );

    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        }
        else {
            push ( @output, "'$arg'" );
        }
    }

    print join ' ', @output, "\n";

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    # retrieve our component's object from the heap where we stashed it
    my $irc = $heap->{irc};

    $heap->{connector} = POE::Component::IRC::Plugin::Connector->new(
        delay       => $LAG,
        reconnect   => $REC,
    );
    $irc->plugin_add( 'Connector' => $heap->{connector} );

    # Commands
    $irc->plugin_add('BotCommand',
        POE::Component::IRC::Plugin::BotCommand->new(
            Commands => {
                find        => 'A simple Internet search, takes one argument - a string to search.',
                wikipedia   => 'Looks up search terms on Wikipedia, takes one argument.',
                wot         => 'Looks up WoT Web of Trust reputation, takes one argument - an http web address.',
                wolfram     => 'A simple Wolfram Alpha search, takes one argument - a string to search.',
                op          => 'Currently has no other purpose than to tell you if you are an op or not!',
                ignore      => 'Maintain nick ignore list for bots - takes two arguments - add|del|list <nick>',
            },
            In_channels     => 1,
            In_private      => $CONF->param('private'),
            Auth_sub        => \&check_if_bot,
            Ignore_unauthorized => 1,
            Addressed       => $CONF->param('addressed'),
            Prefix          => $CONF->param('prefix'),
            Eat             => 1,
            Ignore_unknown  => 1,
        )
    );

    $irc->yield( register => 'all' );
    $irc->yield( connect => { } );

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub lag_o_meter {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $time = localtime;
    print 'Time: ' . $time . ' Lag: ' . $heap->{connector}->lag() . "\n";

    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_001 {
    my ($kernel, $sender) = @_[KERNEL, SENDER];

    # Since this is an irc_* event, we can get the component's object by
    # accessing the heap of the sender. Then we register and connect to the
    # specified server.
    my $irc = $sender->get_heap();

    print "Connected to ", $irc->server_name(), "\n";

    # we join our channels
    $irc->yield( join => $_ ) for @channels;

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_invite {
    my ($kernel, $who, $where) = @_[KERNEL, ARG0 .. ARG1];
    my $nick = ( split /!/, $who )[0];

    if ($CONF->param('invites') == 0) {
        warn "Invites not permitted - invitation by $who to join $where was ignored";
        $irc->yield( privmsg => $nick => "My apologies but current configuration is to ignore invitations" );
        return;
    }

    # Add the channel to the list
    $CONF = add_channel($CONF, $where);

    # we join our channels
    $irc->yield( join => $where );

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_kick {
    my ($kernel, $kicker, $where, $kicked) = @_[KERNEL, ARG0 .. ARG2];

    # Remove the channel from the list
    $CONF = remove_channel($CONF, $where);

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_find {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command find should be followed by text to be searched.");
        return;
    }

    my $response = find($request);

    # If response is a wikipedia response, use wikipedia
    my ($type, $lines) = is_wikipedia($request, $response);
    if ($type eq 'wikipedia') {
        $irc->yield( privmsg => $channel => "$nick: " . $$lines[0]);
        if (defined $$lines[1]) {
            $irc->yield( privmsg => $channel => $$lines[1]);
        }

    # Return the original result
    } else {
        $irc->yield( privmsg => $channel => "$nick: " . $response);

    }

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_wot {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    warn "========================= $request =======================";

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command WoT should be followed by domain to be checked.");
        return;

    } elsif ($request !~ /^https?:\/\//i) {
        $request = 'http://' . $request;

    }

    my ($retcode, $error) = validate_address($request);
    if ($retcode == 0) {
        $irc->yield( privmsg => $channel => "$nick: $error");
        return;
    }

    my $wot;
    eval { $wot = wot($request); };
    $error = $@;
    warn "WoT $error" if $error;

    if ((defined $wot) and ($wot->{trustworthiness_score} =~ /\d/) ) {
        $irc->yield( privmsg => $channel => "$nick: Site reputation is "
           . $wot->{trustworthiness_description}
           . ' (' 
           . $wot->{trustworthiness_score} 
           . ').'
        );

    } elsif ((defined $error) and ($error ne '')) {
        $irc->yield( privmsg => $channel => "$nick: WoT $error.");

    } else {
        $irc->yield( privmsg => $channel => "$nick: WoT did not return any site reputation.");
    }

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_op {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    if ( check_if_op($channel, $nick) ) {
        $irc->yield( privmsg => $channel => "$nick: You are indeed a might op!");
    } else {
        $irc->yield( privmsg => $channel => "$nick: Only channel operators may do that!");
    } 

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;

}

sub irc_botcmd_wolfram {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command Wolfram should be followed by text to be searched.");
        return;
    }

    my $response = wolfram($request);
    $irc->yield( privmsg => $channel => "$nick: $response.");

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_ignore {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick            = ( split /!/, $who )[0];
    my ($action, $bot)  = split(/\s+/, $request);

    unless ( ( check_if_op($channel, $nick) ) or ($nick eq $bot) ) {
        $irc->yield( privmsg => $channel => "$nick: Only channel operators may do that!");
        return;
    }

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command ignore should be followed by a nick.");
        return;
    }

    my $bots;
    if ($action =~ /^add$/i) {
        $bots = add_bot($CONF, $bot);
    } elsif ($action =~ /^(?:del|delete|remove)$/i) {
        $bots = remove_bot($CONF, $bot);
    } else {
        $bots = list_bots();
    }

    $irc->yield( privmsg => $channel => "$nick: Bots - $bots");

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_wikipedia {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command Wikipedia should be followed by text to be searched.");
        return;
    }

    my ($extract, $response) = mediawiki($request);
    my $title = $response->{'Title'};
    $title =~ s/\s+\-.+$//;

    if ( (defined $response->{'Title'}) and (defined $response->{'Url'}) ) {
        $irc->yield( privmsg => $channel => "$nick: $title - $response->{'Url'}");
        $irc->yield( privmsg => $channel => $extract);
    } else {
        $irc->yield( privmsg => $channel => "$nick: $extract");
    }

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_public {
    my ($kernel, $sender, $who, $where, $what) = @_[KERNEL, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    unless (check_if_bot('', $nick) ) {
        return;
    }

    # Ignore sluggle: commands - handled by botcommand plugin
    my $whoami = $CONF->param('nickname');
    my $prefix = $CONF->param('prefix');

    # Cope with commands that are followed only with a space
    # This is a bug I think in botcommand plugin
    if (my ($command) = $what =~ /^(?:$prefix|$whoami:)\s*(find|wot|op|wolfram|wikipedia|ignore|help)\s+$/i) {
        warn "==================================== A ==================================";
        $irc->yield( privmsg => $channel => "$nick: $command followed by whitespace only is invalid.");

    # Do nothing - these requests being handled by irc_command_*
    } elsif ($what =~ /^(?:$prefix|$whoami:)\s*(?:find|wot|op|wolfram|wikipedia|ignore|help)/i) {
        warn "==================================== B ==================================";

    # Default find command
    } elsif ( (my $request) = $what =~ /^(?:$whoami[:,])\s*(.+)$/i) {
        warn "==================================== C ==================================";

        if ((not defined $request) or ($request =~ /^\s*$/)) {
            $irc->yield( privmsg => $channel => "$nick: You haven't asked me anything!");
            return;

        # If there are URLs in the search - use them
        } elsif ( (my @requests) = $what =~ /\b(https?:\/\/[^ ]+)\b/g ) {
            foreach my $request (@requests) {
                my $response = find($request);
                $irc->yield( privmsg => $channel => "$nick: " . $response);
            }

        # Otherwise search the whole string
        } else {
            my $response = find($request);

            # If response is a wikipedia response, use wikipedia
            my ($type, $lines) = is_wikipedia($request, $response);
            if ($type eq 'wikipedia') {
                $irc->yield( privmsg => $channel => "$nick: " . $$lines[0]);
                if (defined $$lines[1]) {
                    $irc->yield( privmsg => $channel => $$lines[1]);
                }

            # Return the original result
            } else {
                $irc->yield( privmsg => $channel => "$nick: " . $response);

            }
        }

    # Shorten links and return title
    } elsif ( (my @requests) = $what =~ /
        \b
        (https?:\/\/[^ ]+)
        (?:
            [\s\(\)\[\]]
            |
            $
        )
        /gx ) {
        warn "==================================== D ==================================";
        foreach my $request (@requests) {
            my $response = find($request);
            $irc->yield( privmsg => $channel => "$nick: " . $response);
        }
    }

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

# End of IRC Bot Commands

# Start of IRC slave functions

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

# If response is a Wikipedia link, then do a 
# Wikimedia lookup instead

sub is_wikipedia {
    my ($request, $result) = @_;

    # Evaluate response and if wikipedia return wikipedia response else return unchanged
    unless ($result =~ /wikipedia/) {
        return 'normal', $result;
    }

    my ($extract, $response) = mediawiki($request);
    my $title = $response->{'Title'};
    $title =~ s/\s+\-.+$//;

    my @lines;
    if ( (defined $response->{'Title'}) and (defined $response->{'Url'}) ) {
        push(@lines, "$title - $response->{'Url'}");
    }
    push(@lines, $extract);

    return 'wikipedia', \@lines;
}

sub wolfram {
    my $request = shift;

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        return "Command Wolfram should be followed by a request";
    }

    use Net::WolframAlpha; 
    use Text::Unaccent::PurePerl;

    # Instantiate WA object with your appid.
    my $wa = Net::WolframAlpha->new (
        appid => $CONF->param('wolfram_appid')
    );

    # Send any inputs paramters in input hash (unescaped).
    my $query = $wa->query(
        'input' =>  unac_string('utf-8',$request),
        'scantimeout' => 3,
    );

    my $response;

    if ($query->success) {

        # Interpretation
        my $pod                 = $query->pods->[0];
        my $subpod              = $pod->subpods->[0];
        my $search_plaintext    = superchomp( $subpod->plaintext );

        if (defined $search_plaintext) {
            $response = "Interpreted as $search_plaintext ";
        } else {
            $response = "Unable to interpret request ";
        }

        my ($result_title, $result_subtitle, $result_plaintext);

        # Results
        $pod = $query->pods->[1];

        if (defined $pod) {
            $result_title        = $pod->title;
            $subpod              = $pod->subpods->[0];
            $response .= $result_title . ' ';
        }

        if (defined $subpod) {
            $result_subtitle     = $subpod->title;
            $result_plaintext    = superchomp( $subpod->plaintext );
            $response .= $result_subtitle . ' '
                    . $result_plaintext;
        }

    # No success, but no error either.
    } elsif (!$query->error) {
        if ($query->didyoumeans->count) {
            my $didyoumean = $query->didyoumeans->didyoumean->[0];
            $response = 'Did you mean: ' . $didyoumean->text->{content};
        } else {
            $response =  "No results.";
        }

    # Error contacting WA.
    } elsif ($wa->error) {
        $response = "Net::WolframAlpha error: "
                    . $wa->errmsg;

    # Error returned by WA.    
    } elsif ($query->error) {
        $response = "WA error "
                    . $query->error->code
                    . ": "
                    . $query->error->msg;

    }

    $response =~ s/\s{2,}/ /g;

    return $response;
}

sub strip_non_alphanumerics {
    my $string = shift;

    my $alphanumerics = $string;
    $alphanumerics =~ s/\W+/-/g;

    return $alphanumerics;
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

sub find {
    my $request = shift;

    my ($url, $title, $shorten, $wot, $error, $response);
    my $retcode = 1;

    # Web address search
    if ($request =~ /^https?:\/\//i) {
        ($retcode, $error) = validate_address($request);
        if ($retcode == 0) {
            return $error;
        }

        $url     = $request;
        $title   = get_data($request);
        $shorten = shorten($url);
        $wot     = wot($url);

    # Assume string search
    } else {
        ($retcode, $response) = search($request);
        $url     = $response->{'Url'};
        $title   = $response->{'Title'};
        $error   = $response->{'Error'};
        $shorten = $url; # Important - don't shorten URL on plain web search
    }

    if ($retcode == 0) {
        if (defined $error) {
            return "There were no search results - $error";
        } else {
            return "There were no search results!";
        }
    }

    my @elements;
    if (defined $shorten) {
        push(@elements, $shorten);
    } else {
        push(@elements, 'URL shortener failed');
    }

    if (defined $title) {
        push(@elements, $title);
    } else {
        push(@elements, 'Title lookup failed');
    }

    if ((defined $wot) and ($wot->{trustworthiness_score} =~ /^\d+$/) and ($wot->{trustworthiness_score} < 60)) {
        push(@elements, '*** Warning WoT is ' 
            . $wot->{trustworthiness_description}
            . ' ('
            . $wot->{trustworthiness_score}
            . ') ***'
        );
    } else {
        # push(@elements, 'WoT lookup failed');
    }

    my $count = @elements;
    if ($count != 0) {
        my $message = join(' - ', @elements);
        $message = check_for_server_ip($message);
        return ($message . '.');
    } else {
        # Do nothing, hopefully no-one will notice
    }

    return;

}

sub wot {
    my $request = shift;

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

sub shorten {
    my $query = shift;

    use WWW::Shorten 'TinyURL';

    # Eval required as WWW::Shorten falls over if service unavailable
    my $short;
    eval {
        $short = makeashorterlink($query);
    };
    warn "URL shortener failed $@" if $@;

    # Stop using shortened address if it's actually longer!
    if ((not defined $short) or ( length($short) >= length($query) )) {
        $short = $query;
    }

    return $short;
}

sub magick_data {
    my $file = shift;

    use Graphics::Magick;
    
    my $img = Graphics::Magick->new;

    my $status = $img->Read($file);
    warn "$status" if "$status";

    my ($width, $height, $quality, $type, $magick) = $img->Get(qw(width height quality type magick));
    my ($lat, $lon) = exif_data($file);

    my $imgdata = {
        'width'     => $width,
        'height'    => $height,
        'type'      => $type,
        'magick'    => $magick,
        'quality'   => $quality,
        'lat'       => $lat,
        'long'      => $lon,
    };

    unlink($file) or warn "Unable to unlink $file: $!";

    return $imgdata;
}

sub exif_data {
    my $file = shift;

    use Image::ExifTool;

    my $exif = Image::ExifTool->new();
    my $hash = $exif->ImageInfo($file);

    my $lat = $exif->GetValue('GPSLatitude', 'PrintConv');
    my $lon = $exif->GetValue('GPSLongitude', 'PrintConv');
    my $pos = $exif->GetValue('GPSPosition', 'PrintConv');

    if (defined $lat) {
        $lat = latlong($lat);
    }
    if (defined $lon) {
        $lon = latlong($lon);
    }

    return($lat, $lon);
}

sub gmap {
    my $gps = shift;

    # GPS 40°43'22.48"N 74°3'6.59"W.

    $gps =~ s/\s+/+/g;

    my $url = 'https://www.google.co.uk/maps/place/' .
        $gps;

    return $url;
}

sub latlong {
    # Works for lat or long

    my $lat = shift;

    # See for format of coordinates
    # https://support.google.com/maps/answer/18539?co=GENIE.Platform%3DDesktop&hl=en

    # 40 deg 43' 22.48" N

    $lat =~ s/\s+//g;
    $lat =~ s/deg/°/;

    # 40°43'22.48"N

    return $lat;
}

sub download_file {
    my $content = shift;

    use File::Temp 'tempfile';
    my ($fh, $file) = tempfile();

    # Dump file
    open( $fh, '>', $file) or
        die "Cannot write to $file: $!";
    binmode $fh;
    print $fh $content;
    close($fh) or die "Cannot close $file: $!";

    return $file;
}

sub filename {
    my $request = shift;

    use URI::URL;
    my $url = new URI::URL $request;
    my $path;
    eval { $path = $url->path; };
    warn "Path not found $@" if $@;

    # Remove path
    $path =~ s/^.+\///g;

    # Untaint
    $path =~ s/[^a-z0-9\.\-]/_/g;
    $path =~ s/_+/_/g;

    return $path; 
}

sub get_data {
    my $query = shift;

    use LWP::UserAgent;
    use Encode;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(20);
    $ua->protocols_allowed( [ 'http', 'https'] );
    $ua->max_size(1024 * 1024 * 8);
    $ua->agent('sluggle/0.1.1 https://github.com/chrisjrob/sluggle');
    $ua->env_proxy;

    my $response = $ua->get($query);

    unless ($response->is_success) {
        return $response->status_line;
    }

    my $type     = $response->header('content-type');

    # Simple HTML page
    if ($type =~ m/^text\/html/i) {
        my $title = decode_utf8( $response->header('Title') );
        return $title;

    # Images handled by graphicsmagick
    } elsif ($type =~ m/^image\/(?:jpg|jpeg|png|bmp|gif|jng|miff|pcx|pgm|pnm|ppm|tif|tiff)/i) {
        my $saved   = download_file($response->decoded_content( charset => 'none' ));
        my $imgdata = magick_data($saved);
        my $file  = filename($query);
        my $response = "$imgdata->{type} $imgdata->{magick} ($imgdata->{quality}) $imgdata->{width}x$imgdata->{height}";

        if ((defined $imgdata->{lat}) and (defined $imgdata->{long})) {
            # $response .= " :: GPS $imgdata->{lat} $imgdata->{long}";
            my $gmap = gmap("$imgdata->{lat} $imgdata->{long}");
            $response .= ' :: ' . $gmap;
        }

        return $response;

    # As yet unhandled file type
    } else {
        warn "\n==================== DEBUG =====================";
        warn "Unhandled file type is $type";

        return "File type $type";
    }

}

sub mediawiki {
    my $request = shift;

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        return "Wikipedia command should be followed by text to be searched";
    }

    my ($retcode, $response) = search('site:en.wikipedia.org ' . $request);

    my $url     = $response->{'Url'};
    my $title   = $response->{'Title'};
    my $error   = $response->{'Error'};

    unless (defined $url) {
        if (defined $error) {
            return "There were no search results - $error";
        } else {
            return "There were no search results!";
        }
    }

    my $apiurl = mediawiki_api_url($url);

    use LWP::UserAgent;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(20);
    $ua->env_proxy;

    my $req = HTTP::Request->new( GET => $apiurl );
    my $response2 = $ua->request( $req );

    use JSON;

    my $ref;
    eval { $ref = JSON::decode_json( $response2->{'_content'} ); };

    if ( $@ ) {
        warn "\n\n-------------- DEBUG ------------------\n";
        warn "Wikipedia has returned a malformed JSON response\n";
        warn "Query: $apiurl\n";
        warn "Response: $@\n";

        $response->{'Error'} = "Wikipedia returned $@";
        return $response;
    }

    my $pageid = (keys %{ $ref->{'query'}->{'pages'} })[0];

    my $extract = ($ref->{'query'}->{'pages'}->{$pageid}->{'extract'});
    $extract =~ s/[\r\n]+/ /g;
    $extract =~ s/[^[:ascii:]]//g;

    return ($extract, $response);

}

sub mediawiki_api_url {
    my $request = shift;

    # https://en.wikipedia.org/wiki/Withdrawal_from_the_European_Union
    my ($title) = $request =~ m/\/wiki\/(\w+)/;

    use URI::URL;
    my $url = new URI::URL $request;
    my ($host, $scheme);

    eval { $scheme = $url->scheme; };
    warn "Scheme not found $@" if $@;

    eval { $host = $url->host; };
    warn "Host not found $@" if $@;

    my $path = '/w/api.php?format=json&action=query&prop=extracts&exintro=&explaintext=&titles=';

    my $apiurl = $scheme . '://' . $host . $path . $title;

    return $apiurl;
} 

sub search {
    my $query = shift;

    my $retcode = 1;

    # Remove any non-ascii characters
    $query =~ s/[^[:ascii:]]//g;

    my $account_key = $CONF->param('key');
    my $serviceurl  = $CONF->param('url');
    my $searchurl   = $serviceurl . '%27' . $query . '%27';

    use LWP::UserAgent;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(20);
    $ua->env_proxy;

    my $req = HTTP::Request->new( GET => $searchurl );
    $req->authorization_basic('', $account_key);
    my $response = $ua->request( $req );

    # use Data::Dumper;
    # warn Dumper( $response->{'_content'} );

# RAW

# '_content' => '{
#   "d":{
#       "results":
#           [
#               {
#                   "__metadata": {
#                       "uri":"https://api.datamarket.azure.com/Data.ashx/Bing/SearchWeb/v1/Web?Query=\\u0027Surrey LUG\\u0027&Latitude=51.2362&Longitude=-0.5704&$skip=# 0&$top=1",
#                       "type":"WebResult"
#                   },
#                   "ID":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#                   "Title":"Surrey Linux User Group",
#                   "Description":"Surrey LUG is a friendly Linux user group. If you have any interest in Linux, GNU (or related systems such as *BSD, Solaris, OpenSolaris, etc) and are based in Surrey ...",
#                   "DisplayUrl":"surrey.lug.org.uk",
#                   "Url":"http://surrey.lug.org.uk/"
#               }
#           ],
#           "__next":"https://api.datamarket.azure.com/Data.ashx/Bing/SearchWeb/v1/Web?Query=\\u0027Surrey%20LUG\\u0027&Latitude=51.2362&Longitude=-0.5704&$skip=1&$top=1"
#       }
#   }',

    use JSON;

    my $ref;
    eval { $ref = JSON::decode_json( $response->{'_content'} ); };

    if ( $@ ) {
        warn "\n\n-------------- DEBUG ------------------\n";
        warn "Bing has returned a malformed JSON response\n";
        warn "Query: $query\n";
        warn "Response: $@\n";

        $retcode = 0;
        $response->{'Error'} = "Bing returned $@";

        return $retcode, $response;
    }

    # warn Dumper( $ref );

# JSON:

#$VAR1 = { 
#          'd' => { 
#                   '__next' => 'https://api.datamarket.azure.com/Data.ashx/Bing/SearchWeb/v1/Web?Query=\'Surrey%20LUG\'&Latitude=51.2362&Longitude=-0.5704&$skip=1&$top=1',
#                   'results' => [ 
#                                  { 
#                                    'ID' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
#                                    '__metadata' => { 
#                                                      'type' => 'WebResult',
#                                                      'uri' => 'https://api.datamarket.azure.com/Data.ashx/Bing/SearchWeb/v1/Web?Query=\'Surrey LUG\'&Latitude=51.2362&Longitude=-0.5704&$skip=0&$top=1'
#                                                    },
#                                    'Url' => 'http://surrey.lug.org.uk/',
#                                    'Description' => 'Surrey LUG is a friendly Linux user group. If you have any interest in Linux, GNU (or related systems such as *BSD, Solaris, OpenSolaris, etc) and are based in Surrey ...',
#                                    'DisplayUrl' => 'surrey.lug.org.uk',
#                                    'Title' => 'Surrey Linux User Group'
#                                  }
#                                ]
#                 }
#        };

    return( $retcode, $ref->{'d'}{'results'}[0] );

}

sub check_if_bot {
    my ($object, $nick, $where, $command, $args) = @_;

    if ( is_bot($CONF, $nick) ) {
        warn "Blocked";
        return 0;
    }

    return 1;
}

sub check_if_op {
  my ($chan, $nick) = @_;
  return 0 unless $nick;
  if (($irc->is_channel_operator($chan, $nick)) or 
      ($irc->nick_channel_modes($chan, $nick) =~ m/[aoq]/)) {
    return 1;
  }
  else {
    return 0;
  }
}

# Chomp to cope with Windows line endings

sub superchomp {
    my $string = shift;
    return if (not defined $string);
    $string =~ s/[\r\n]//g;
    return $string;
}

