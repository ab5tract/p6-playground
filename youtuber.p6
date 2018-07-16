#!/usr/bin/env perl6

class Download::YouTube {
	use JSON::Fast;
	has $.url is rw;
	method cmd-args { 'youtube-dl', '-j', $!url };

	method check-for-video {
		return Failure.new("You need a URL")
			unless $!url;

		my $downloader = run self.cmd-args, :out, :err;

		my $stdout = $downloader.out.slurp(:close);
		my $stderr = $downloader.err.slurp(:close);

		my $json;
		try {
			return from-json($stdout);

			CATCH {
				return Failure.new("Invalid JSON (usually implies no video).\nSTDERR from youtube-dl: $stderr.");
			}
		}
	}
}


sub MAIN ($url) {

	my %results{Hash};

	my $dl = Download::YouTube.new: :$url;
	say $dl.check-for-video;
}
