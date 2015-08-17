package Decaptcha::Minteye::Image::Solver::OpenCV;

use 5.010;
use Moo::Role;
use namespace::autoclean -also => qr/^_/;

requires qw(image tiles response);

sub solve {
    my $self = shift;

    my $tile = _pick_tile($self->image, $self->tiles);
    if (-1 == $tile) {
        $self->error('Failed to decode captcha image');
        return;
    }

    $self->response($tile);
    return 1;
}


use Inline Config => DIRECTORY => '/tmp';
use Inline C => Config => LIBS => '-lopencv_core -lopencv_highgui';
use Inline C => <<'EOF';

#include <opencv/cv.h>
#include <opencv/highgui.h>

int
_pick_tile (SV *sv, int count) {
    STRLEN src_len;
    char *src = SvPVbyte(sv, src_len);
    int i, tile, height, max_spike = 0, gradient[count];

    CvMat *mat = cvCreateMat(1, src_len, CV_8UC1);
    mat->data.ptr = (unsigned char *)src;

    /* Convert the image to greyscale */
    IplImage *img = cvDecodeImage(mat, 0);
    cvReleaseMat(&mat);
    if (! img) return -1;

    height = img->height / count;

    /* Determine the gradient for each tile. */
    for (i = count - 1; 0 <= i; i--) {
        int size = 0, top = height * i;
        cvSetImageROI(img, cvRect(0, top, img->width, height));
        cvSobel(img, img, 1, 1, 3);
        size = cvSum(img).val[0];
        gradient[i] = size;
    }

    cvReleaseImage(&img);

    /*
     * The undistorted image has a higher contrast than the surrounding
     * distorted images; search for the largest spike in gradient size.
     */
    for (i = count - 2; 0 < i; i--) {
        int spike = abs(2 * gradient[i] - gradient[i-1] - gradient[i+1]);
        if (spike > max_spike) {
            max_spike = spike;
            tile = i;
        }
    }

    return tile;
}


EOF


1;
