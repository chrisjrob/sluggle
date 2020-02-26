package image;

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
    my ($content, $query) = @_;

    my $saved   = download_file($content);
    my $imgdata = magick_data($saved);
    my $file    = filename($query);

    my $response = "$imgdata->{type} $imgdata->{magick} ($imgdata->{quality}) $imgdata->{width}x$imgdata->{height}";

    if ((defined $imgdata->{lat}) and (defined $imgdata->{long})) {
        # $response .= " :: GPS $imgdata->{lat} $imgdata->{long}";
        my $gmap = image::gmap("$imgdata->{lat} $imgdata->{long}");
        $response .= ' :: ' . $gmap;
    }

    return $response;
}

sub magick_data {
    my $file = shift;

    use Graphics::Magick;
    
    my $img = Graphics::Magick->new;

    my $status = $img->Read($file);

    # Stop processing if you can't read the file
    # fixme: return undef here leaves an ugly
    # http://tinyurl.com/wzrvx8q -   () x.
    # response
    return undef if "$status"; # Stop processing

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

