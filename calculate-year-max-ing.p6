#!/usr/bin/env perl6

use v6.c;
use Text::CSV;

sub MAIN($file, :$bank = 'ABN AMRO', Rat :$start, Rat :$end, :$iban) {
	my ($max, $derived-iban);

	if $bank ~~ /:i 'ing'/ {
		die "Please provide the starting and ending amounts of the account for the year"
			unless $start && $end;

		# Pretty old-school system, but cool to run through the mutations
		# and verify in the end against the numbers on the tax forms.
		#
		# ING does not provide incoming/outgoing account balances for each
		# transaction, meaning we have to go from a start amount and track each
		# mutation over time. The mutation direction is indicated in Dutch.
	    my %ops = 'Bij' => &[+], 'Af' => &[-];

	    my @data = csv(in => $file)[1..*];
		$derived-iban = @data[0][2];

		# Oh, and the mutation timeline is backwards.
	    my @mutations = @data[*;5].reverse;
	    my @amounts   = @data[*;6].reverse.map:
							*.subst(q{.},q{}).subst(q{,},q{.}).Rat;

	    $max = max $start, $end;

	    my $running = $start;
	    for @mutations Z @amounts -> ($op, $amount) {
	        my &op = %ops{$op}; # What does the op op when the op op ops? :D
	        $running = op($running, $amount);
	        if $running > $max {
	            $max = $running;
	        }
	    }

		if $running != $end {
			say "ERROR!! The run of the mutations does not result in the provided end amount.";
			say "\tExpected: $end\tGot: $running\n";
		}
	} elsif $bank ~~ /:i 'abn'/ {
		# ABN makes it nice and easy by providing the in-going and outgoing
		# balances per-transaction (which is important, because they don't keep
		# their transaction histories accessible for as long into the past as
		# ING does, increasing your likelihood of having a truncated list of
		# annual transactions).
		my @data = csv(in => $file, sep => "\t");
		my @amounts = @data[*;3];

		# Convert from European decimals to American decimals
		$max = max @amounts.map: *.subst(q{,},q{.}).Rat;
	}

	if $derived-iban && $iban && $derived-iban != $iban {
		say "WARNING!! The IBAN derived from the data does not match the IBAN provided on the command-line.";
		say "\tDerived IBAN:$derived-iban\n\tProvided IBAN: $iban\n";
	}

	my $final-iban = $derived-iban || $iban;

	say "Bank:\t\t{$bank.uc}";
	say "IBAN:\t\t{$final-iban.subst(q{ },q{}, :g)}"
		if $final-iban;
	say "Max. Balance:\t$max";
}
