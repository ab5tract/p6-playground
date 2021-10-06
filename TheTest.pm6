
use v6.c;

my $b;
my %c;

package TheTest { 
    our sub a {
            say 1;
    }
    
    our sub b {
            say "b";
    }
    
    our sub c {
            say 3.14159;
    }

}

sub EXPORT(*@a) {
        dd @a;
        %(
                '&a'       => sub { |@a }
        )
}

