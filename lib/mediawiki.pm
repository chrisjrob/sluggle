package mediawiki;

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

