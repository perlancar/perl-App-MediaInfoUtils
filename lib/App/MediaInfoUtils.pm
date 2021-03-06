package App::MediaInfoUtils;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Perinci::Exporter;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Utilities related to getting (metadata) information from '.
        'media files',
};

our %arg0_media_multiple = (
    media => {
        summary => 'Media files/URLs',
        schema => ['array*' => of => 'filename*'], # XXX filename_or_url
        req => 1,
        pos => 0,
        greedy => 1,
    },
);

our %arg0_media_single = (
    media => {
        summary => 'Media file/URL',
        schema => ['filename*'], # XXX filename_or_url
        req => 1,
        pos => 0,
    },
);

our %argopt_backend = (
    backend => {
        summary => 'Choose a specific backend',
        schema  => ['str*', match => '\A\w+\z'],
        completion => sub {
            require Complete::Module;
            my %args = @_;
            Complete::Module::complete_module(
                word => $args{word},
                ns_prefix => "Media::Info",
            );
        },
    },
);

our %argopt_quiet = (
    quiet => {
        summary => "Don't output anything on command-line, ".
            "just return appropriate exit code",
        schema => 'true*',
        cmdline_aliases => {q=>{}, silent=>{}},
    },
);

$SPEC{media_info} = {
    v => 1.1,
    summary => 'Get information about media files/URLs',
    args => {
        %arg0_media_multiple,
        %argopt_backend,
    },
};
sub media_info {
    require Media::Info;

    my %args = @_;

    my $media = $args{media};

    my @rows;
    for my $m (@$media) {
        log_info "Getting media info for %s ...", $m;
        my $res = Media::Info::get_media_info(
            media => $m,
            (backend => $args{backend}) x !!(defined $args{backend}),
        );
        unless ($res->[0] == 200) {
            warn "Can't get media info for '$m': $res->[1] ($res->[0])\n";
            next;
        }
        my $row = {
            media => $m,
            %{$res->[2]},
        };
        push @rows, $row;
        if (@$media == 1) {
            return [200, "OK", $row];
        }
    }
    [200, "OK", \@rows];
}

$SPEC{media_summary_by_type} = {
    v => 1.1,
    summary => 'Summarize media by types (from filenames)',
    args => {
        %arg0_media_multiple,
    },
};
sub media_summary_by_type {
    require Media::Info;

    my %args = @_;

    my $media = $args{media};

    my %filesize_by_type;
    my %filecount_by_type;
    for my $file (@$media) {
        my $type = Media::Info::_type_from_name($file);
        $filesize_by_type{$type} += (-s $file);
        $filecount_by_type{$type}++;

        if ($type eq 'audio' || $type eq 'image' || $type eq 'video') {
            $filesize_by_type{"audio+image+video"} += (-s $file);
            $filecount_by_type{"audio+image+video"}++;
        }

        if ($type eq 'image' || $type eq 'video') {
            $filesize_by_type{"image+video"} += (-s $file);
            $filecount_by_type{"image+video"}++;
        }

        $filesize_by_type{"ALL"} += (-s $file);
        $filecount_by_type{"ALL"}++;
    }

    my @rows;
    for my $type (sort keys %filecount_by_type) {
        push @rows, {type=>$type, count=>$filecount_by_type{$type}, total_size=>$filesize_by_type{$type}};
    }

    [200, "OK", \@rows, {
        'table.fields'=>[qw/type count total_size/],
        'table.field_formats'=>[undef, undef, 'filesize'],
        'table.field_aligns' =>[undef, 'right', 'right'],
    }];
}


$SPEC{media_is_portrait} = {
    v => 1.1,
    summary => 'Return exit code 0 if media is portrait',
    description => <<'_',

Portrait is defined as having 'rotate' metadata of 90 or 270 when the width >
height. Otherwise, media is assumed to be 'landscape'.

_
    args => {
        %arg0_media_single,
        %argopt_backend,
        %argopt_quiet,
    },
    examples => [
        {
            summary => 'Move all portrait videos to portrait/',
            src => 'for f in *.mp4;do [[prog]] -q "$f" && mv "$f" portrait/; done',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub media_is_portrait {
    my %args = @_;

    my $res = media_info(media => [$args{media}], backend=>$args{backend});
    return $res unless $res->[0] == 200;

    my $rotate = $res->[2]{rotate} // 0;
    my $width  = $res->[2]{video_width}  // $res->[2]{width};
    my $height = $res->[2]{video_height} // $res->[2]{height};
    return [412, "Can't determine video width x height"] unless $width && $height;
    my $is_portrait = ($rotate == 90 || $rotate == 270 ? 1:0) ^ ($width <= $height ? 1:0) ? 1:0;

    [200, "OK", $is_portrait, {
        'cmdline.exit_code' => $is_portrait ? 0:1,
        'cmdline.result' => $args{quiet} ? '' :
            "Media is ".
            ($is_portrait ? "portrait" : "NOT portrait (landscape)"),
    }];
}

$SPEC{media_is_landscape} = {
    v => 1.1,
    summary => 'Return exit code 0 if media is landscape',
    description => <<'_',

Portrait is defined as having 'rotate' metadata of 90 or 270. Otherwise, media
is assumed to be 'landscape'.

_
    args => {
        %arg0_media_single,
        %argopt_backend,
        %argopt_quiet,
    },
    examples => [
        {
            summary => 'Convert all landscape mkv videos to mp4',
            src => 'for f in *.mkv;do [[prog]] -q "$f" && ffmpeg -i "$f" "$f.mp4"; done',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub media_is_landscape {
    my %args = @_;

    my $res = media_info(media => [$args{media}], backend=>$args{backend});
    return $res unless $res->[0] == 200;

    my $rotate = $res->[2]{rotate} // 0;
    my $width  = $res->[2]{video_width}  // $res->[2]{width};
    my $height = $res->[2]{video_height} // $res->[2]{height};
    return [412, "Can't determine video width x height"] unless $width && $height;
    my $is_landscape = ($rotate == 90 || $rotate == 270 ? 1:0) ^ ($width <= $height ? 1:0) ? 0:1;

    [200, "OK", $is_landscape, {
        'cmdline.exit_code' => $is_landscape ? 0:1,
        'cmdline.result' => $args{quiet} ? '' :
            "Media is ".
            ($is_landscape ? "landscape" : "NOT landscape (portrait)"),
    }];
}

$SPEC{media_orientation} = {
    v => 1.1,
    summary => "Return orientation of media ('portrait' or 'landscape')",
    description => <<'_',

Portrait is defined as having 'rotate' metadata of 90 or 270. Otherwise, media
is assumed to be 'landscape'.

_
    args => {
        %arg0_media_single,
        %argopt_backend,
    },
};
sub media_orientation {
    my %args = @_;

    my $res = media_info(media => [$args{media}], backend=>$args{backend});
    return $res unless $res->[0] == 200;

    my $rotate = $res->[2]{rotate} // 0;
    my $width  = $res->[2]{video_width}  // $res->[2]{width};
    my $height = $res->[2]{video_height} // $res->[2]{height};
    return [412, "Can't determine video width x height"] unless $width && $height;
    my $orientation = ($rotate == 90 || $rotate == 270 ? 1:0) ^ ($width <= $height ? 1:0) ? "portrait" : "landscape";

    [200, "OK", $orientation];
}

1;
# ABSTRACT:
