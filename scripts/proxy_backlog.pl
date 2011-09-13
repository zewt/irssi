# this script is still experimental, don't expect it to work as expected :)
# see http://wouter.coekaerts.be/site/irssi/proxy_backlog
use Irssi;
use Irssi::TextUI;

$VERSION = "0.0.0";
%IRSSI = (
	authors         => "Wouter Coekaets",
	contact         => "coekie@irssi.org",
	name            => "proxy_backlog",
	url             => "http://wouter.coekaerts.be/site/irssi/proxy_backlog",
	description     => "sends backlog from irssi to clients connecting to irssiproxy",
	license         => "GPL",
	changed         => "2004-09-10"
);

my $privmsg_buffer = [];

use Data::Dumper;
sub sendbacklog {
	my ($client) = @_;
	foreach my $line (@privmsg_buffer) {
		Irssi::signal_emit('proxy client dump', $client, $line . "\n");
	}
}

Irssi::signal_add_last("proxy client logged in", sub {
	my ($client) = @_;
	#print Dumper($rec->{server});
	sendbacklog($client);
});

# Store recent messages in a circular buffer.
sub privmsg
{
	my ($server, $msg, $nick, $address, $target) = @_;
	my $data = ":$nick!$address PRIVMSG $target :$msg";
	push @privmsg_buffer, $data;
	while($#privmsg_buffer > 20) {
		pop @privmsg_buffer;
	}
}

# Capture incoming and outbound messages, and forward them in a more sane way to
# privmsg.
Irssi::signal_add('message own_private', sub {
	my ($server, $msg, $target) = @_;
	privmsg($server, $msg, $server->{'nick'}, $server->{'userhost'}, $target);
});

Irssi::signal_add('message own_public', sub {
	my ($server, $msg, $target, $orig_target) = @_;
	privmsg($server, $msg, $server->{'nick'}, $server->{'userhost'}, $target);
});

Irssi::signal_add('message private', sub {
	my ($server, $msg, $nick, $address) = @_;
	privmsg($server, $msg, $nick, $address, $server->{'nick'});
});

Irssi::signal_add('message public', sub {
	my ($server, $msg, $nick, $address, $target) = @_;
	privmsg($server, $msg, $nick, $address, $target);
});

Irssi::signal_add_first('message irc notice', sub {
	my ($server, $msg, $nick, $address, $target) = @_;
	if($nick == $server->{'nick'} and $target == $server->{'nick'}) {
		if($msg =~ "LAGCHK .*") {
			privmsg($server, $msg, $server->{'nick'}, $server->{'userhost'}, $target);
			Irssi::signal_stop();
		}
	}
});

Irssi::signal_add('proxy command', sub {
	my ($client, $cmd, $args, $data) = @_;
	if($cmd eq "LOG") {
		Irssi::signal_stop();
		sendbacklog($client);
	}
});
