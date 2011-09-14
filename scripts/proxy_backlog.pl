# this script is still experimental, don't expect it to work as expected :)
# see http://wouter.coekaerts.be/site/irssi/proxy_backlog
use strict;
use Irssi;
use Irssi::TextUI;

my $VERSION = "0.0.0";
my %IRSSI = (
	authors         => "Wouter Coekaets",
	contact         => "coekie\@irssi.org",
	name            => "proxy_backlog",
	url             => "http://wouter.coekaerts.be/site/irssi/proxy_backlog",
	description     => "sends backlog from irssi to clients connecting to irssiproxy",
	license         => "GPL",
	changed         => "2004-09-10"
);

my %privmsg_buffer = ();
my $message_sequence = 0;
my %known_clients = ();
use vars qw(%privmsg_buffer $message_sequence %known_clients);

use Data::Dumper;
sub sendbacklog {
	my ($client) = @_;

	my $known_client = $known_clients{$client->{'client_username'}};
	my $mrm = $$known_client{'last_sequence'};
	print "Sending messages >= $mrm";

	while(my ($target, $data) = each(%privmsg_buffer)) {
		print "target: $target";
		foreach my $item (@$data) {
			if($$item{'sequence'} < $mrm) {
				print "Skipping old message " . $$item{'sequence'};
				next;
			}

			my $target = $$item{'target'};
			if($target eq "user") {
				# If the target is "user", it's a message to the user.  Change the target to the
				# actual nick we have now.
				my $server = $client->{'server'}->{'nick'};
			}
			my $privmsg = ":$$item{'nick'}!$$item{'address'} PRIVMSG $target :$$item{'msg'}";
			print $privmsg;
			Irssi::signal_emit('proxy client dump', $client, $privmsg . "\n");
		}
	}

	# Update the client's sequence number, so we don't send these messages again.
	$$known_client{'last_sequence'} = $message_sequence;
}

Irssi::signal_add_last("proxy client logged in", sub {
	my ($client) = @_;

	print "Logged in: " . $client->{'client_username'};
	#print Dumper($rec->{server});

	if(!$known_clients{$client->{'client_username'}}) {
		$known_clients{$client->{'client_username'}} = {'last_sequence'=>0};
	}
	my $known_client = $known_clients{$client->{'client_username'}};

	$$known_client{'logged_in'} = 1;

	sendbacklog($client);
});

Irssi::signal_add_last("proxy client disconnected", sub {
	my ($client) = @_;
	print "Logged out: " . $client->{'client_username'};
	my $known_client = $known_clients{$client->{'client_username'}};
	$$known_client{'logged_in'} = 0;
});


# Store recent messages in a circular buffer.
sub privmsg
{
	my ($server, $msg, $nick, $address, $target) = @_;

	# Coalesce private messages.
	if($target eq $server->{'nick'}) {
		$target = "user";
	}

	my %data = (
		"sequence", $message_sequence++,
		"msg", $msg,
		"nick", $nick,
		"address", $address,
		"target", $target
	);

	$privmsg_buffer{$target} ||= [];
	my $output = $privmsg_buffer{$target};
	push @$output, \%data;

	# Cull old messages for this target.
	while(scalar(@$output) > 20) {
		shift @$output;
	}

	# Update the last_sequence for all connected clients, so this message isn't sent
	# to them again.
	while(my ($username, $known_client) = each(%known_clients)) {	
		print "connected: $username, $$known_client{'logged_in'}";
		# If this client isn't logged in, leave its sequence number alone.
		if(!$$known_client{'logged_in'}) { next; }

		$$known_client{'last_sequence'} = $message_sequence;
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

# When parting a channel, remove all buffered messages for that channel.  Don't do this
# on kicks.
Irssi::signal_add("message part", sub {
	my ($server, $channel, $nick, $address, $reason) = @_;
	print "Removing logs for channel $channel";
	delete $privmsg_buffer{$channel};
});

#Irssi::signal_add('proxy command', sub {
#	my ($client, $cmd, $args, $data) = @_;
#	if($cmd eq "LOG") {
#		Irssi::signal_stop();
#		sendbacklog($client);
#	}
#});
