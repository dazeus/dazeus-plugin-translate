#!/usr/bin/perl
use strict;
use warnings;
use WWW::Google::Translate;
use DaZeus;

my ($socket, $key) = @ARGV;
if(!$socket || !$key) {
	warn "Usage: $0 <socket> <Google API translate key>\n";
	warn "For a translate key, visit: https://cloud.google.com/translate/docs\n";
	exit 1;
}

my $wgt = WWW::Google::Translate->new({key => $key});
# Uncomment this if your user-agent cannot establish trusted SSL connections, or give a SSL_ca_path
#$wgt->{ua}->ssl_opts(verify_hostname => 0);

my $r = $wgt->languages({target => "en"});
my %languages;
foreach(@{$r->{'data'}{'languages'}}) {
	my $name = lc $_->{'name'};
	$languages{$name} = $_->{'language'};

	# store "chinese (simplified)" as "chinese" as well, this may overwrite "chinese (traditional)"
	# but user can always specify the version he wants
	if($name =~ /\s/) {
		$name =~ s/\s+.*$//;
		$languages{$name} = $_->{'language'};
	}
}

my $dazeus = DaZeus->connect($socket) or die $!;

sub reply {
        my ($response, $network, $sender, $channel) = @_;

        if ($channel eq $dazeus->getNick($network)) {
                $dazeus->message($network, $sender, $response);
        } else {
                $dazeus->message($network, $channel, $response);
        }
}

$dazeus->subscribe_command("translate" => sub {
	my ($dazeus, $network, $sender, $channel, $command, $args) = @_;
	if(!$args || $args !~ /->/) {
		reply("Come on, give me something to do!", $network, $sender, $channel);
		return;
	}
	reply(translate_pipeline($args), $network, $sender, $channel);
});
while($dazeus->handleEvents()) {}

sub translate_pipeline {
	my ($pipeline) = @_;
	my $string;
	my @commands;

	if($pipeline =~ /^\s*"(.*)"\s+->\s+(.+)$/) {
		$string = $1;
		@commands = split /\s+->\s+/, $2;
	} else {
		@commands = split /\s+->\s+/, $pipeline;
		$string = shift @commands;
	}

	my $language;

	foreach my $command (@commands) {
		if($command =~ /^is(\w+)$/) {
			if(!exists $languages{lc $1}) {
				return "Sorry, I don't know the language '$1' :(\n";
			}
			$language = $languages{lc $1};
		} elsif($command =~ /^to(\w+(?: \(\w+\))?)$/) {
			if(!exists $languages{lc $1}) {
				return "Sorry, I don't know the language '$1' :(\n";
			}
			my $to_language = $languages{lc $1};

			if(!$language) {
				my $r = $wgt->detect({q => $string});
				$language = $r->{'data'}{'detections'}[0][0]{'language'};
			}

			if($language eq $to_language) {
				next;
			}

			my $params = {
				q => $string,
				target => $to_language,
				source => $language,
				format => 'text',
			};

			my $r = $wgt->translate($params);
			$string = $r->{'data'}{'translations'}[0]{'translatedText'};
			if(!$string) {
				return "Failed to translate from '$language' to '$to_language'!\n";
			}
			$language = $to_language;
		} elsif($command eq "detectLanguage") {
			my $r = $wgt->detect({q => $string});
			$language = $r->{'data'}{'detections'}[0][0]{'language'};
		} elsif($command eq "returnLanguage") {
			my $r = $wgt->detect({q => $string});
			my $lang = $r->{'data'}{'detections'}[0][0]{'language'};
			$language ||= "unknown";
			return "[returnLanguage] Active language: $language / Google detected language: $lang\n";
		} else {
			return "I don't know what you meant by '$command' :(\n";
		}
	}

	return $string;
}
