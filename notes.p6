
my @notes = <C C# D D# E F F# G G# A A# B>;

my @all = do for (^128).rotor(12,:partial) -> @subset {
    state $counter //= -2;
    |my @seq = @notes X~ $counter++;
}

@all = @all.splice(0,128);

multi sub MAIN('bridge', :$indent = 0) {
    my @note_keys;
    my @interloper = do for @all -> $note {
        @note_keys.push: my $note_key = $note.subst("#","_sharp").subst("-","_minus").lc;
        my $indents = ("   " xx $indent).join;
        qq<$indents$note_key = jbox.string\{\n$indents    default = "$note"\n$indents\},>
    }
    say @interloper.join("\n");
    say @note_keys.rotor(2).map({"\"/custom_properties/@_[0]\", \"/custom_properties/@_[1]\","}).join("\n");
}

multi sub MAIN() { 
    for @all.map({ qq<"$_"> }).rotor(9,:partial) -> @a {
        say @a.join(",") ~ ",";
    }
}

#multi sub MAIN($style where * ~~ "ui_text") {
#    say "jbox.ui_selector\{";
#    say @all.map({ qq<\tjbox.ui_text("$_"),> }).join("\n");
#    say "}";
#}
