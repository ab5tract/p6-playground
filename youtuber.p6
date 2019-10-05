#!/usr/bin/env perl6

class Download::YouTube {
	use JSON::Fast;
	has $.url is rw;
	has @!args = 'youtube-dl', '-j';

	method cmd-args(:$check) {
		return 	@!args[0],
				$check 	?? @!args[1]
						!! (),
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
				say "Something went wrong parsing the JSON.";
				say "`youtube-dl` STDERR: $stderr";
				say "Code exception:\n $_";
				return Nil;
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
