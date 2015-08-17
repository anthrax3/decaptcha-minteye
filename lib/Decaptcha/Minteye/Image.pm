package Decaptcha::Minteye::Image;
use 5.010;
use Moo;

use namespace::autoclean;
use Digest::MD5 qw(md5_hex);
use JSON;
use Path::Tiny;
use Scalar::Util qw(blessed);
use Time::HiRes qw(gettimeofday);
use URI;

has id  => (is => 'ro', required => 1);
has key => (is => 'ro', required => 1);
has referer => (
    is       => 'ro',
    required => 1,
    coerce   => sub { URI->new($_[0]) },
    isa      => sub {
        die "$_[0] is not a URI" unless blessed $_[0]
            and ($_[0]->isa('URI::http') or $_[0]->isa('URI::https'));
    },
);
has solver => (
    is      => 'ro',
    default => __PACKAGE__ . '::Solver::OpenCV',
);
has ua => (
    is  => 'lazy',
    isa => sub {
        my $mod = 'LWP::UserAgent';
        die "$_[0] is not a $mod" unless blessed $_[0] and $_[0]->isa($mod);
        die "'ua' needs a cookie_jar" unless $_[0]->cookie_jar;
    },
);

has error     => (is => 'rw');
has challenge => (is => 'rw');

has _domain => (
    is      => 'lazy',
    lazy    => 1,
    builder => sub { return $_[0]->referer->host },
);
has _nonce => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { return substr 100_000 * gettimeofday, 0, 13 },
);
has image  => (is => 'rw');
has tiles  => (is => 'rw');
has response => (is => 'rw');

sub _build_ua {
    require LWP::UserAgent::Determined;
    my $ua = LWP::UserAgent::Determined->new(
        agent => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4)'
            . ' AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.94'
            . ' Safari/537.36',
        timeout         => 30,
        ssl_opts        => { verify_hostname => 0 },
        cookie_jar      => {},
        default_headers => HTTP::Headers->new(
            accept => 'text/html,application/xhtml+xml,application/xml;'
                . 'q=0.9,*/*;q=0.8',
            accept_language => 'en-US,en;q=0.5',
            accept_encoding => 'gzip,deflate',
            connection      => 'keep-alive',
        ),
        requests_redirectable => [qw( GET HEAD POST )],
    );
    $ua->codes_to_determinate()->{400} = 1;
    return $ua;
}

sub BUILD {
    # Allows for dynamic class composition.
    with $_[0]->solver;
}


sub request {
    my $self = shift;

    $self->_reset;

    my $uri = URI->new('http://api.minteye.com/Get.aspx');
    $uri->query_form(
        CaptchaId => $self->id,
        PublicKey => $self->key,
        Dummy     => time,
    );

    my $res = $self->ua->get($uri, referer => $self->referer);
    $self->error($res->status_line), return
        unless $res->is_success;

    my $content = $res->decoded_content // $res->content;
    $self->error('No content'), return unless $content;
    s/^[^{]+//, s/[^}]+$// for $content;  # Convert JSONP to JSON
    my $data = eval { from_json $content } or say(__LINE__), $self->error($@), return;
    my $err = $data->{description} // $data->{result} // '';
    $err =~ tr/\r\n/ /, $self->error($err), return if $err =~ /error/i;
    my $challenge = $data->{challenge};
    $self->error('No challenge id found'), return
        unless defined $challenge;
    $self->challenge($challenge);

    my $expando = 'jQuery1910' . substr(rand, 2) . int rand 100;

    my $datr = md5_hex rand;
    substr $datr, $_, 0, '-' for 9, 14, 19, 24;
    $self->ua->cookie_jar->set_cookie(0, datr => $datr, '/', $self->_domain);

    $uri = URI->new('http://api.minteye.com/slider/sliderdata.ashx');
    $uri->query_form(
        callback  => $expando . '_' . $self->_nonce($self->_nonce + 1),
        datr      => $datr,
        cid       => $challenge,
        captchaId => $self->id,
        publicKey => $self->key,
        w         => 180,
        h         => 150,
        s         => undef,
        demo      => undef,
        adId      => undef,
        _         => time,
    );
    $res = $self->ua->get($uri, referer => $self->referer);
    $self->error($res->status_line), return
        unless $res->is_success;

    $content = $res->decoded_content // $res->content;
    $self->error('No content'), return unless $content;
    s/^[^{]+//, s/[^}]+$// for $content;  # Convert JSONP to JSON
    $data = eval { from_json $content } or $self->error($@), return;
    $err = $data->{description} // $data->{result} // '';
    $err =~ tr/\r\n/ /, $self->error($err), return if $err =~ /error/i;
    $self->error('No tile count'), return
        unless $data->{count};
    $self->tiles($data->{count});
    $self->error('No sprite url'), return
        unless $data->{spriteUrl};
    $uri = URI->new($data->{spriteUrl});
    $uri->scheme('http');

    $res = $self->ua->get($uri, referer => $self->referer);
    $self->error($res->status_line), return
        unless $res->is_success;
    $self->error('Not a valid image'), return
        unless 'image/jpeg' eq $res->content_type;

    $content = $res->decoded_content // $res->content;
    $self->error("empty image from $uri"), return
        unless defined $content and length $content;

    $self->image($content);

    return 1;
}


sub read {
    my ($self, %params) = @_;

    $self->_reset;

    $self->error('Missing "tiles"'), return unless $params{tiles};
    $self->tiles($params{tiles});

    my $file = $params{file};
    $self->error('Missing "file"'), return unless defined $file;
    my $img = eval { path($file)->slurp_raw };
    $self->error("$file: $!"), return unless $img;
    $self->image($img);

    return 1;
}
*load = *load = \&read;


sub save {
    my ($self, %params) = @_;

    my $file = $params{file};
    my $dir = $params{dir} // $params{directory};

    unless ($file or $dir) {
        $self->error('Missing "file" or "dir"');
        return;
    }

    unless ($file) {
        my $res = $self->response;
        $file = sprintf '%s/%d-%s-%d%s.jpg', $dir, time,
            md5_hex($self->image), $self->tiles, $res ? "-$res" : '';
    }

    my $ok = eval { path($file)->spew_raw($self->image) };
    return $ok if $ok;

    $self->error("$file: $!");
    return;
}


sub _reset {
    $_[0]->$_(undef) for qw(error image challenge response);
}


1;
