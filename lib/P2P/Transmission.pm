package P2P::Transmission;

=head1 NAME

P2P::Transmission - Interface to the Transmission BitTorrent client

=head1 SYNOPSIS

  use P2P::Transmission;

  my $client = P2P::Transmission->new(socket => '/path/to/socket');
  $client->add( file => 'freebsd6.2release.torrent', autostart => 0 );
  $client->downlimit(512);
  $client->uplimit(128);
  ...

=head1 DESCRIPTION

C<P2P::Transmission> can be used to control the popular cross-platform
B<Transmission> BitTorrent client. The module supports both the common
GUI-based client as well as the lesser-known B<transmission-daemon>.

Control of the client is achieved using a UNIX-socket provided by the
client itself. The module supports the documented 1.00 command set.

=cut

use Carp;
use Convert::Bencode ':all';
use IO::Socket::UNIX;
use P2P::Transmission::Torrent;
use strict;

our $VERSION = '0.04';
our $AUTOLOAD;
our @SIMPLE = qw/automap autostart directory downlimit
                 encryption pex port uplimit/;

###
### PUBLIC METHODS
###

sub new {
    my ($class, %data) = @_;
    my $self = bless(\%data, $class);
    croak('no control socket specified') unless $self->{socket};
    
    # create connection to running process
    $self->{_socket} = IO::Socket::UNIX->new( Type => SOCK_STREAM,
                                              Peer => $self->{socket} );
    croak("connection failed: $!") unless $self->{_socket};
    $self->{_socket}->autoflush(1);
    
    # send version packet (restrict to version 2)
    $self->_send({ version => { min => 2, max => 2 } });
    $self->{_serverinfo} = $self->_recv->{version};
    
    # verify that the server supports protocol 2
    if (($self->{_serverinfo}->{min} > 2)
     or ($self->{_serverinfo}->{max} < 2)) {
        croak('specified server not supported');
    }
    
    if ($self->{debug}) {
        print "--- [connected to: " . $self->{_serverinfo}->{label} . "]\n";
    }
    
    return $self;
}

sub add {
    my $self  = shift;
    my %param = @_;
    my $args  = {};
    
    # perform manual key copies to avoid message contamination
    foreach ('file', 'data', 'directory', 'autostart') {
        if (exists $param{$_}) {
            $args->{$_} = $param{$_};
        }
    }
    
    # check for required keys
    if ((exists $param{file}) and (exists $param{data})) {
        croak('add: file and data are mutually exclusive');
    } 
    elsif (! ((exists $param{file}) or (exists $param{data}))) {
        croak('add: either file or data must be specified');
    }
    else {
        $self->_send([ 'addfile-detailed', $args, 1 ]);
        return ($self->_recv->[0] eq 'succeeded') ? 1 : undef
    }
}

sub lookup {
    my ($self, $hash) = @_;
    
    $self->_send(['lookup', [ $hash ], 1]);
    my $r = $self->_recv;
    
    if ($r->[0] ne 'info') {
        return undef;
    } else {
        if ($r->[1][0]->{id} < 1) {
            return undef;
        } else {
            return P2P::Transmission::Torrent->new(parent => $self,
                                                     info => $r->[1][0]);
        }
    }
}

sub shutdown {
    my $self = shift;
    $self->_send(['quit', '', '1']);
    $self->{_socket}->close();
    return 1;
}

sub start_all {
    my $self = shift;

    $self->_send(['start-all', '', 1]);
    return ($self->_recv->[0] eq 'succeeded') ? 1 : undef
}

sub stop_all {
    my $self = shift;

    $self->_send(['stop-all', '', 1]);
    return ($self->_recv->[0] eq 'succeeded') ? 1 : undef
}

sub torrents {
    my $self = shift;
    my @tlst = ();
    
    $self->_send(['get-info-all', [ 'hash' ], 1]);
    my $r = $self->_recv;
    
    if ($r->[0] ne 'info') {
        return undef;
    } else {
        foreach my $info (@{$r->[1]}) {
            push(@tlst, 
                 P2P::Transmission::Torrent->new(parent => $self,
                                                   info => $info));
        }
    }
    
    return @tlst;
}

###
### PRIVATE METHODS
###

# _send takes a list of values that are passed to Convert::Bencode
# and then sent as a specially prefixed command string.
sub _send {
    my $self = shift;
    my $msg;
    
    while (my $cmd = shift) {
        $msg .= bencode($cmd);
    }
    
    $self->{_socket}->send(sprintf("%08X%s", length($msg), $msg));
    if ($self->{debug}) { print ">>> $msg\n"; }
}

# _recv handles the UNIX socket IO and prefix removal and returns
# a bdecoded hashref
sub _recv {
    my $self = shift;
    my ($length, $response);
    
    $self->{_socket}->recv($length, 8);
    $self->{_socket}->recv($response, hex($length));
    if ($self->{debug}) { print "<<< $response\n"; }
    
    return bdecode($response);
}

# AUTOLOAD handles the remaining "simple" accessors that would
# otherwise be numerous blocks of nearly identical code
sub AUTOLOAD {
    # get bare method name
    my ($key) = ($AUTOLOAD) =~ /^.*::(\w+)$/;
    
    # check method name against list of valid accessors
    if (! grep $_ eq $key, @SIMPLE) {
        croak("Can't locate object method \"$key\""
            . " via package " . __PACKAGE__);
    }
    
    # -- begin accessor --
    my $self  = shift;
    my $value = undef;
    
    if (@_) {
        $value = shift;
        $self->_send([$key, $value, 1]);
        if ($self->_recv->[0] ne 'succeeded') {
            $value = undef;
        }
    } else {
        $self->_send(["get-$key", 1]);
        my $r = $self->_recv;
        if ($r->[0] eq $key) {
            $value = $r->[1];
        }
    }
    
    return $value;    
    # -- end accessor --
}

sub DESTROY {
    my $self = shift;
    if ($self->{_socket}) {
        $self->{_socket}->close();
    }
}

1;

__END__

=head1 METHODS

=over 4

=item C<new({ ... })>

Constructs and returns a new P2P::Transmission object. Takes the 
following hash keys as parameters:

  socket      path to controlling UNIX socket (required)
  debug       print network traffic to stdout (0|1, optional)
  
=item C<add({ ... })>

Instruct Transmission to add a torrent to its active list. Returns C<1>
for success and C<undef> on failure. Takes the following hash keys 
as parameters:

  data        contents of torrent file      (required *)
  file        path to torrent file          (required *)
  autostart   begin downloading immediately (0|1, optional)
  directory   directory to download into    (optional)
  
  * data and file are mutually exclusive
  
=item C<automap(1|0)>

Get or set the state of automatic port mapping via NAT-PMP and UPnP

=item C<autostart(1|0)>

Get or set the preference to automatically start downloading new
torrents when added.

=item C<directory()>

Get or set the default directory used for saving new torrent data

=item C<downlimit()>

Get or set the maximum total download speed in kilobytes per second

  Note: pass -1 to remove all rate limiting

=item C<encryption()>

Get or set the state of encryption use. Valid parameters are:

  required    require the use of encryption by peers
  preferred   use encryption when available
  plaintext   do not use encryption
  
=item C<lookup()>

Takes a sha1 hash argument and returns the corresponding
L<P2P::Transmission::Torrent> object for the active torrent 
identified by that hash. If none exists, C<undef> is returned

=item C<pex(1|0)>

Get or set the global preference to use peer exchange

=item C<port()>

Get or set the port used to listen for incoming peer connections

=item C<shutdown>

Instructs the Transmission program to quit

  Note: any calls made after shutdown will case a fatal error

=item C<start_all>

Starts all paused torrents

Returns C<1> for success or C<undef> for failure

=item C<stop_all>

Stops all running torrents

Returns C<1> for success or C<undef> for failure

=item C<torrents>

Returns an array of L<P2P::Transmission::Torrent> objects for each
of the currently active torrents 

=item C<uplimit>

Get or set the maximum total upload speed in kilobytes per second

  Note: pass -1 to remove all rate limiting

=back

=head1 BUGS AND CAVEATS

=over 4

=item C<pex()> always returns C<undef> with Transmission 1.00

This is a problem with the OSX IPC handler (see Transmission bug #588)

=item C<add()> always returns C<undef> with Transmission 1.00

This is a problem with the OSX IPC handler (see Transmission bug #600)

=item B<NOTE>

The 0.04 release of this module was only tested using the OSX version of
Transmission 1.00. Further testing against B<transmission-daemon> and the
GTK version will be performed before the next module release.

=back

=head1 SEE ALSO

=over 4

=item * L<P2P::Transmission::Torrent>

=item * Transmission (http://www.transmissionbt.com/)

=back

=head1 AUTHOR

Brandon Gilmore, E<lt>brandon@mg2.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 Brandon Gilmore

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
