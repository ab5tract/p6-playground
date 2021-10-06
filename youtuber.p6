#!/usr/bin/env perl6

class Download::YouTube {
	use JSON::Fast;

	has $.url is rw;
	has %!args =	cmd => 'youtube-dl',
					check => '-j';

	method cmd-args(*%commands) {
		return 	%!args<cmd>,
				%!args{$_} for %commands.keys,
				$!url;
	}

	method check-for-video {
		return Failure.new("You need a URL")
			unless $!url;

		my $downloader = run self.cmd-args(:check), :out, :err;

		my $stdout = $downloader.out.slurp(:close);
		my $stderr = $downloader.err.slurp(:close);

		try {
			return	$stdout	?? from-json($stdout)
			 				!! Nil;

			CATCH {
				fail X::ParseError::JSON.new:
						"Something went wrong parsing the JSON",
						:$stderr,
						:exception($_);
			}
		}
	}
}


sub MAIN ($url) {
	my $dl = Download::YouTube.new: :$url;
	with $dl.check-for-video -> $video {
		say $video;
	} else {
		say "No video found";
	}
}
