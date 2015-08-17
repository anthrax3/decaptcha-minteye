Decaptcha-Minteye
=================

Minteye was a flawed captcha that was crackable in several different ways. The
company appears to have recently ceased operations, so I'm finally releasing
my solution. It was able to solve 100% of all captchas, as long as the "hard
mode" wasn't triggered.

SYNOPSIS

    use Decaptcha::Minteye;
    my $c = Decaptcha::Minteye::Image->new(
        id      => $id,
        key     => $key,
        referer => $ref
    );

    $c->request or die $c->error;
    # $c->read(file => $file, tiles => $tiles) or die $c->error;

    $c->solve or die $c->error;
    say $c->challenge;
    say $c->response;

    $c->save(file => '/tmp/sprite.jpg') or die $c->error;
    # or $c->save(dir => '/tmp/sprites/') or die $c->error;

DEPENDENCIES

    opencv
    perl 5.10
    Inline::C
    JSON
    Moo
    Path::Tiny
    URI
    namespace::autoclean

A C compiler is required to build this module.

COPYRIGHT AND LICENCE

Copyright (C) 2012-2015 by gray <gray@cpan.org>
