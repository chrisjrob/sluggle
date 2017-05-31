package search;

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
    my ($conf, $query) = @_;

    # my ($retcode, $results) = bing($conf, $query);
    my ($retcode, $results) = duckduckgo($conf, $query);
    # my ($retcode, $results) = ddg($conf, $query);

    return( $retcode, $results );
}

sub bing {
    my ($conf, $query) = @_;

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

sub ddg {
    my ($conf, $query) = @_;

    my $retcode = 1;

    # Remove any non-ascii characters
    $query =~ s/[^[:ascii:]]//g;

    warn "Query: $query";

    my $searchurl = 
       'https://'
       . 'api.duckduckgo.com'
       . '/?q='
       . $query
       . '&format=json&pretty=1&no_html=1&skip_disambig=1';

    warn "$searchurl";

    if ($searchurl !~ /microsoft/i) {
        die;
    }

    use LWP::UserAgent;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(20);
    $ua->env_proxy;

    my $req = HTTP::Request->new( GET => $searchurl );
    my $response = $ua->request( $req );

    use Data::Dumper;
    warn Dumper( $response->{content} );

    use JSON;

    my $ref;
    eval { $ref = JSON::decode_json( $response->{content} ); };

    my $error;
    if ( $@ ) {
        warn "\n\n-------------- DEBUG ------------------\n";
        warn "DuckDuckGo has returned a malformed JSON response\n";
        warn "Query: $query\n";
        warn "Response: $@\n";

        $retcode = 0;
        $error = "DuckDuckGo returned $@";

        return $retcode, $response;
    }

    my $results = {
        url         => $ref->{AbstractURL},
        title       => $ref->{Heading},
        error       => $error,
    };

    return( $retcode, $results );
}

sub duckduckgo {
    my ($conf, $query) = @_;

    my $retcode = 1;

    # Remove any non-ascii characters
    $query =~ s/[^[:ascii:]]//g;

    use WWW::DuckDuckGo;
    my $duck = WWW::DuckDuckGo->new;
    my $zeroclickinfo;
    eval { $zeroclickinfo = $duck->zeroclickinfo($query); };

    # use Data::Dumper;
    # warn Dumper( $zeroclickinfo );

    my $results;
    if ( $zeroclickinfo->has_results ) {

        my @results = @{ $zeroclickinfo->results };
        
        $results = {
            url         => $results[0]->first_url,
            title       => $results[0]->text,
            error       => '',
        };

    } elsif ( $zeroclickinfo->has_abstract ) {

        $results = {
            url         => $zeroclickinfo->abstract_url,
            title       => $zeroclickinfo->heading,
            error       => '',
        };


    } else {
        $retcode = 0;
        $results = {
            error       => 'DuckDuckGo returned no results',
        };
    }

    return( $retcode, $results );
}

