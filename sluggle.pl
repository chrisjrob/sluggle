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

use POE;
use POE::Component::IRC;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;

use lib './lib';
use config;
use image;
use mediawiki;
use search;
use wot;
use wolfram;
use utility;

use vars qw( $CONF $LAG $REC );

if ( (defined $ARGV[0]) and (-r $ARGV[0]) ) {
    $CONF = config::get_config($ARGV[0]);
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
            Auth_sub        => \&is_not_bot,
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
    $CONF = config::add_channel($CONF, $where);

    # we join our channels
    $irc->yield( join => $where );

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_kick {
    my ($kernel, $kicker, $where, $kicked) = @_[KERNEL, ARG0 .. ARG2];

    # Remove the channel from the list
    $CONF = config::remove_channel($CONF, $where);

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

    my ($retcode, $error) = utility::validate_address($request);
    if ($retcode == 0) {
        $irc->yield( privmsg => $channel => "$nick: $error");
        return;
    }

    my $wot;
    eval { $wot = wot::lookup($CONF, $request); };
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

    if ( is_op($channel, $nick) ) {
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

    my $response = wolfram::lookup($CONF, $request);
    $irc->yield( privmsg => $channel => "$nick: $response.");

    # Restart the lag_o_meter
    $kernel->delay( 'lag_o_meter' => $LAG );

    return;
}

sub irc_botcmd_ignore {
    my ($kernel, $who, $channel, $request) = @_[KERNEL, ARG0 .. ARG2];
    my $nick            = ( split /!/, $who )[0];
    my ($action, $bot)  = split(/\s+/, $request);

    unless ( ( is_op($channel, $nick) ) or ($nick eq $bot) ) {
        $irc->yield( privmsg => $channel => "$nick: Only channel operators may do that!");
        return;
    }

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        $irc->yield( privmsg => $channel => "$nick: Command ignore should be followed by a nick.");
        return;
    }

    my $bots;
    if ($action =~ /^add$/i) {
        $bots = config::add_bot($CONF, $bot);
    } elsif ($action =~ /^(?:del|delete|remove)$/i) {
        $bots = config::remove_bot($CONF, $bot);
    } else {
        $bots = config::list_bots($CONF);
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

    if ( config::is_bot($CONF, $nick) ) {
        warn "blocked";
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

# If response is a Wikipedia link, then do a 
# Wikimedia lookup instead

# Cannot properly test this function and related mediawiki module 
# until search api is working

sub mediawiki {
    my $request = shift;

    if ((not defined $request) or ($request =~ /^\s*$/)) {
        return "Wikipedia command should be followed by text to be searched";
    }

    my ($retcode, $search_response) = search::duckduckgo($CONF, 'site:en.wikipedia.org ' . $request);

    my $url     = $search_response->{'url'};
    my $title   = $search_response->{'title'};
    my $error   = $search_response->{'error'};

    unless (defined $url) {
        if (defined $error) {
            return "There were no search results - $error";
        } else {
            return "There were no search results!";
        }
    }
    
    my ($extract, $response) = mediawiki::lookup($url);

    return($extract, $response);
}

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

sub find {
    my $request = shift;

    my ($url, $title, $shorten, $wot, $error, $response);
    my $retcode = 1;

    # Web address search
    if ($request =~ /^https?:\/\//i) {
        ($retcode, $error) = utility::validate_address($request);
        if ($retcode == 0) {
            return $error;
        }

        $url     = $request;
        $title   = get_data($request);
        $shorten = shorten($url);
        $wot     = wot::lookup($CONF, $url);

    # Assume string search
    } else {
        ($retcode, $response) = search::duckduckgo($CONF, $request);
        $url     = $response->{'url'};
        $title   = $response->{'title'};
        $error   = $response->{'error'};
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
        $message = utility::check_for_server_ip($message);
        return ($message . '.');
    } else {
        # Do nothing, hopefully no-one will notice
    }

    return;

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

    # Images 
    } elsif ($type =~ m/^image\/(?:jpg|jpeg|png|bmp|gif|jng|miff|pcx|pgm|pnm|ppm|tif|tiff)/i) {
        my $response = image::lookup($response->decoded_content( charset => 'none' ), $query);
        return $response;

    # As yet unhandled file type
    } else {
        warn "\n==================== DEBUG =====================";
        warn "Unhandled file type is $type";

        return "File type $type";
    }

}

sub is_not_bot {
    my ($object, $nick, $where, $command, $args) = @_;

    if ( config::is_bot($CONF, $nick) ) {
        warn "blocked";
        return 0;
    }

    return 1;
}

sub is_op {
    my ($chan, $nick) = @_;

    return 0 unless $nick;
  
    if (
            ($irc->is_channel_operator($chan, $nick))
            or (($irc->nick_channel_modes($chan, $nick) =~ m/[aoq]/))
    ) {

        return 1;

  }

  return 0;
}

