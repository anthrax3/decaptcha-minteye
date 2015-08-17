use strict;
use warnings;

use Config;
use Devel::CheckLib;
# MIN_PERL_VERSION needs 6.48, and CONFIGURE_REQUIRES needs 6.52.
use ExtUtils::MakeMaker 6.52;

check_lib_or_exit(
    lib     => [qw(opencv_core opencv_highgui)],
    libpath => [ split ' ', $Config{loclibpth} ],
    header  => ['opencv/cv.h', 'opencv/highgui.h'],
    incpath => [ split ' ', $Config{locincpth} ],
);

my %conf = (
    NAME               => 'Decaptcha::Minteye',
    AUTHOR             => 'gray <gray@cpan.org>',
    LICENSE            => 'perl',
    VERSION_FROM       => 'lib/Decaptcha/Minteye/Image.pm',
    ABSTRACT_FROM      => 'lib/Decaptcha/Minteye/Image.pm',
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 6.52, },
    PREREQ_PM => {
        'Inline::C'            => 0,
        'JSON'                 => 0,
        'Moo'                  => 0,
        'Path::Tiny'           => 0,
        'URI'                  => 0,
        'namespace::autoclean' => 0,
    },
    MIN_PERL_VERSION   => '5.010',
    META_MERGE         => {
        resources => {
            repository => 'https://github.com/gray/decaptcha-minteye',
        },
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'Decaptcha-Minteye-*' },
);

my $eumm_version =  do {
    no warnings 'numeric';
    eval $ExtUtils::MakeMaker::VERSION;
};
$conf{PREREQ_PM} = {
    %{ $conf{PREREQ_PM} || {} }, %{ delete $conf{BUILD_REQUIRES} },
} if ($conf{BUILD_REQUIRES} and $eumm_version < 6.5503);

WriteMakefile(%conf);


sub MY::postamble {
    return <<"    MAKE_FRAG";
authortest:
\t\$(MAKE) -e \$(TEST_TYPE) TEST_FILES="xt/*.t"
    MAKE_FRAG
}

sub MY::dist_test {
    my $self = shift;
    return $self->MM::dist_test . <<"    MAKE_FRAG";
\tcd \$(DISTVNAME) && \$(MAKE) authortest \$(PASTHRU)
    MAKE_FRAG
}
