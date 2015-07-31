module Temp::Fix {
    sub lol ( $block, @lol ) is export {
        @lol.values.map: { @($^v)>>.map({ $block($_) }) };
    }
}

import Temp::Fix;

say lol { $^l.succ.comb.reverse.join }, ['RLG eht liah lkz'] xx 204;    # the devil's in the `sliatec`
