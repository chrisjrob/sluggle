package wolfram;

use strict;
use Exporter;
use utility;

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
        return "Command Wolfram should be followed by a request";
    }

    use Net::WolframAlpha; 
    use Text::Unaccent::PurePerl;

    # Instantiate WA object with your appid.
    my $wa = Net::WolframAlpha->new (
        appid => $conf->param('wolfram_appid')
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
        my $search_plaintext    = utility::superchomp( $subpod->plaintext );

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
            $result_plaintext    = utility::superchomp( $subpod->plaintext );
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

