# sluggle

## Name

sluggle - A Simple IRC Searchbot

## Important

As usually happens with search APIs - the Bing search API has been deprecrated. 
Until such time as I rewrite this for other APIs, or write some dodgy scraper, 
this bot is not usable at least for search functions.

## Usage

In default search mode (assumes find command):

    sluggle: year of linux desktop

In addressed mode:

    sluggle: find year of linux desktop
    sluggle: find http://example.com
    sluggle: wolfram 2+4
    sluggle: wot http://example.com

In command mode:

    !find year of linux desktop
    !find http://example.com
    !wolfram 2+4
    !wot http://example.com

## Description

Sluggle is a fairly typical POE::Component::IRC script. 
Sluggle is currently designed to work with the following services:

 * Bing Search
 * Wolfram Alpha
 * Web of Trust (WoT)
 * TinyURL web shortener 

## Configuration

The following IRC commands exist for configuration:

 * ignore {add|del|list} nick
 * op

The ignore command enables existing bots (or nicks) to be ignored. 
This is a sensible precaution against bot wars.
Run without arguments to show a list of bots currently ignored.

The op command simply responds depending on whether or not you are a channel op, it currently has no other purpose.

All other configuration is done via the config files, which must be unique for each IRC server to which you will be connecting.

Both Bing and Wolfram Alpha require API keys, which should be included in the config file.

When running sluggle, it takes the config file as argument, enabling you to run the bot multiple times for different IRC servers. 
Each session can work for multiple channels inside the given server.

There are two modes - address mode and command mode, and this is set in the conf file:

    addressed 0 (for !find)
    addressed 1 (for sluggle: find)

These two modes cannot be used simultaneously, owing to a limitation (possibly a bug) in POE::Component::IRC.

## Installation

 1. You will Perl 5 along with the following CPAN modules:

  * Config::Simple
  * Encode
  * File::Temp 'tempfile'
  * Graphics::Magick
  * Image::ExifTool
  * JSON
  * LWP::UserAgent
  * Net::Address::IP::Local
  * Net::WOT
  * Net::WolframAlpha; 
  * POE::Component::IRC::Plugin::BotCommand
  * POE::Component::IRC::State
  * POE::Component::IRC
  * POE
  * Regexp::Common
  * Regexp::IPv6
  * Text::Unaccent::PurePerl
  * URI::URL
  * WWW::Shorten::TinyURL

 2. Clone or save the repository.

 3. Obtain yourself a Bing Search API key, currently freely available for 5000 searches per month.

 4. Obtain yourself a Wolfram Alpha API key, currently freely available for 2000 searches per month.

 5. Rename `sluggle.conf.template` to something like `sluggle-freenode.conf` and update the contents see [Configuration](#configuration) above.

 6. Run sluggle.pl specifying config file:

First argument is the configuration file:

    $ ./sluggle.pl sluggle-freenode.conf

