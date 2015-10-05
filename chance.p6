
use v6;

module Chance {
    my @faces = '⚀', '⚁', '⚂', '⚃', '⚄', '⚅';

    # only 'identifier' characters, as defined in Unicode,
    # are allowed to be used in names. 'punctuation' marks
    # are, in the long tradition of programming, reserved
    # for operators.
    #
    # in thise case, we define an operator into the 'term'
    # context, as that is the context which matches a
    # subroutine with no arguments.
    sub term:<¿>() is export {
        @faces.roll;
    }

    sub texas-chance() is export(:texas) {
        ¿;
    }

}

import Chance;

say ¿;

import Chance :texas;

say texas-chance;
