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

use WWW::WolframAlpha;
use Text::Unaccent::PurePerl;

sub lookup {
    my ($conf, $request) = @_;

    return "Command Wolfram should be followed by a request"
        if not defined $request or $request =~ /^\s*$/;

    my $wa = WWW::WolframAlpha->new(
        appid => $conf->param('wolfram_appid')
    );

    my $query = $wa->query({
        input => unac_string('utf-8', $request),
        scantimeout => 3,
    });

    my $response;

    if ($query->success) {
        my $pod = $query->pods->[0];
        my $subpod = $pod->subpods->[0];
        my $search_plaintext = utility::superchomp($subpod->plaintext);

        $response = defined $search_plaintext
            ? "Interpreted as $search_plaintext "
            : "Unable to interpret request ";

        $pod = $query->pods->[1];
        if ($pod) {
            my $result_title = $pod->title;
            my $subpod = $pod->subpods->[0];
            my $result_plaintext = utility::superchomp($subpod->plaintext);
            $response .= "$result_title $result_plaintext";
        }

    } elsif (!$query->error) {
        if (my $dyms = $query->didyoumeans) {
            $response = "Did you mean: " . $dyms->[0]->text;
        } else {
            $response = "No results.";
        }

    } elsif ($wa->error) {
        $response = "WolframAlpha error: " . $wa->errmsg;

    } elsif ($query->error) {
        $response = "WA error " . $query->error->code . ": " . $query->error->msg;
    }

    $response =~ s/\s{2,}/ /g;
    return $response;
}

