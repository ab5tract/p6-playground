#!/usr/bin/env perl6

use JSON::Fast;

sub MAIN ($url) {
	my $youtube-dl = run
						'youtube-dl',
						'-j',
						$url, :out, :err;
	my %results{Hash};
	# $youtube-dl.stdout.tap(-> $v {
	# 	# try {
	# 	# 	my $json = from-json($v);
	# 	# 	%results{$json} = $json;
	# 	# 	CATCH {
	# 	# 		say $v;
	# 	# 		$_.resume;
	# 	# 	}
	# 	# }
	# 	say $v;
	# });
	# await $youtube-dl.start;
	my $stdout = $youtube-dl.out.slurp(:close);
	my $stderr = $youtube-dl.err.slurp(:close);


	try {
		my $exceptions-mentioned;
		my $json = from-json($stdout);
		%results{$json} = $json if $json;

		CATCH {
			say "Nothing found on that page."
				unless $exceptions-mentioned++;
			$_.resume
		}
	}
	if %results.keys {
		say %results;
		say "Wut " ~ +%results.values[0]<formats>;
	}
}
