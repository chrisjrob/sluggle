package search;

use strict;
use Exporter;

my @functions = qw(
    bing
    duckduckgo
);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = @functions;
our %EXPORT_TAGS = (
    DEFAULT => [@functions],
    ALL     => [@functions],
);

sub bing {
    my ($conf, $query) = shift;

    my $retcode = 1;

    # Remove any non-ascii characters
    $query =~ s/[^[:ascii:]]//g;

    my $account_key = $conf->param('key');
    my $serviceurl  = $conf->param('url');
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

    use JSON;

    my $ref;
    eval { $ref = JSON::decode_json( $response->{'_content'} ); };

    my $error;
    if ( $@ ) {
        warn "\n\n-------------- DEBUG ------------------\n";
        warn "Bing has returned a malformed JSON response\n";
        warn "Query: $query\n";
        warn "Response: $@\n";

        $retcode = 0;
        $error = "Bing returned $@";

        return $retcode, $response;
    }

    my $results = {
        url         => $ref->{d}{results}[0]{Url},
        title       => $ref->{d}{results}[0]{Title},
        error       => $error,
    };

    return( $retcode, $results );
}

sub duckduckgo {
    my ($conf, $query) = shift;

    my $retcode = 1;

    # Remove any non-ascii characters
    $query =~ s/[^[:ascii:]]//g;

    use WWW::DuckDuckGo;
    my $duck = WWW::DuckDuckGo->new;
    my $zeroclickinfo;
    eval { $zeroclickinfo = $duck->zeroclickinfo($query); };

    warn "Query: $query";

    use Data::Dumper;
    warn Dumper( $zeroclickinfo );

    use JSON;

    my $ref;
    eval { $ref = JSON::decode_json( $zeroclickinfo ); };

    my $error;
    if ( $@ ) {
        warn "\n\n-------------- DEBUG ------------------\n";
        warn "DuckDuckGo has returned a malformed JSON response\n";
        warn "Query: $query\n";
        warn "Response: $@\n";

        $retcode = 0;
        $error = "DuckDuckGo returned $@";

        return $retcode, { error => $error };
    }

    my $results = {
        url         => $ref->{Results}[0]{FirstURL},
        title       => $ref->{Results}[0]{Text},
        error       => $error,
    };

    return( $retcode, $results );
}

