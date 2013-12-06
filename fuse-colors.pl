#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use File::Which;
use Fuse;
use POSIX 'EINVAL';

my $mountpoint = shift || die "Usage: $0 /path/to/mount/at";
$mountpoint =~ s|/$||;

die "lolfs must be run as root in order to mount FUSE" unless ($< == 0);

# get a sane list of paths
my @paths = get_path();

# get a list of binaries that use ncurses
my $bad_list = get_curses(@paths);

my $lolcat = get_lolcat();

Fuse::main(
	mountpoint => $mountpoint,
	# let other users see this mount
	mountopts  => "allow_other",
	getattr    => "main::fuse_getattr",
	readlink   => "main::fuse_readlink",
	getdir     => "main::fuse_getdir",
	open       => "main::fuse_open",
	read       => "main::fuse_read",
);

# when someone asks for a file, hand out a perl script
# if the binary doesn't use curses, pipe it into lolcat
# otherwise just exec and move on
sub fuse_read {
	my ($file) = _filename_fixup(shift);
	my ($size, $offset, $fh) = @_;

	# both scenarios use this perl
	my $result = qq{#!/usr/bin/perl
use strict;
use warnings;

my \$input = join(' ', \@ARGV);

exec "PATH='} . join(':', @paths) . qq{' $file \$input};

	# if we're execing an ncurses binary, don't colorize it
	if (exists($bad_list->{$file})) {
		$result .= '";' . "\n";
	} elsif ($file eq 'refresh-ncurses-cache') {
		$bad_list = get_curses(@paths);
		return 'finished';
	}
	else {
		$result .= qq{ | $lolcat";
};
	}

	# from Fuse example, modified
	return -EINVAL() if $offset > length($result);
	return 0 if $offset == length($result);
	return substr($result,$offset,$size);
}

sub fuse_open {
	return 0;
}

# show the user stuff that looks real
sub fuse_getattr {
	my $filename = shift;

	# dev,ino,modes,nlink,uid,gid,rdev,size,atime,mtime,ctime,blksize,blocks
	if ($filename eq '/') {
		return (0, 0, 0040755, 1, 0, 0, 0, 0, 0, 0, 0, 4096, 0);
	} else {
		# this is actually funny, the file size used to be 100 bytes, but
		# my meta perl scripts got larger than that, so I bumped to 400
		return (0, 0, 0100777, 1, 0, 0, 0, 400, 0, 0, 0, 4096, 0);
	}
}

sub fuse_readlink {
	my $path = shift;
	return $path;
}

sub fuse_getdir {
	return ('.', 'refresh-ncurses-cache', 0);
}

# taken from the Fuse example code
sub _filename_fixup {
	my ($file) = shift;
	$file =~ s,^/,,;
	$file = '.' unless length($file);
	return $file;
}

# piping vim into a variant of cat isn't fun, so grab every ncurses binary
# and put it on a bad list
sub get_curses {
	print "Creating a list of ncurses binaries to leave alone\n";

	my $ldd = which('ldd');
	unless ($ldd) {
		print "Can't find ldd, so I can't determine which binaries come with ncurses.\n";
		print "Continuing anyway, just don't use those binaries <3 \n";
		return {};
	}

	my @paths = @_ ;
	my @files;
	find( sub {
		# we only want binary executable files/links
		return unless (-f $_ || -l $_);
		return unless -X $_;
		push @files, $File::Find::name;
	}, @paths);

	# objdump all of them at once instead of spinning 1000+ objdump procs
	# turns 10s into <1s
	open my $fh, '-|', "$ldd " . join(' ', @files) . ' 2>&1';

	my $ret = {};

	# parse dat output
	my $current_cmd;
	while (my $line = <$fh>) {
		if ($line =~ m|([^/]*?):$|) {
			$current_cmd = $1;
		} elsif ($line =~ /libncurses.*?=>/) {
			$ret->{$current_cmd}++;
		}
	}

	print "List created, starting\n";
	# return a hash of short names of commands that are not lolcat friendly
	return $ret;
}

# you wouldn't believe how un-fun debugging becomes when you start
# this script with your PATH set to your mountpoint. silly convenience sub
sub get_path {
	my @current_path = grep { -d $_ } split(':', $ENV{PATH});
	my @default_path = grep { -d $_ } qw(/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin);

	if ( (!scalar(@current_path)) || ($ENV{PATH} eq $mountpoint) ) {
		print STDERR "This won't be fun without a sensible path.\n";

		# is this likely? probably not
		unless (scalar(@default_path)) {
			print STDERR "Couldn't figure out a single sensible path. Bailing\n";
			die;
		}

		print STDERR "lolfs is going to use the following:\n";
		print STDERR "\t$_\n" foreach(@default_path);
		return @default_path;
	}

	return @current_path;
}

sub get_lolcat {
	# http://superuser.com/questions/321757/where-can-i-find-the-rails-executable-in-debian
	chomp(my ($lolcat) = `ruby -rubygems -e 'puts Gem.default_bindir'`);
	if (-e $lolcat . '/lolcat') {
		return $lolcat . '/lolcat';
	}
	print "I couldn't find your lolcat! Bailing";
	die;
}

__END__

=head1 NAME

fuse-colors.pl - automatically make most commands colorful

=head1 USAGE

	mkdir /tmp/fuse-colors
	./fuse-colors.pl /tmp/fuse-colors
	PATH=/tmp/fuse-colors

=head1 DESCRIPTION

This script helps you to automatically append " | lolcat" to most commands.

I was in #climagic on Freenode when "adprice" asked if there was a way to
have bash automatically append " | lolcat" to all of his commands. The channel
discussed different solutions for a bit before I decided to make fuse-colors.
When you mount fuse-colors to a directory, the next immediate step should be to
set your PATH=/that/directory. Once this step is complete, all of your command output
will be very pretty.

fuse-colors attempts to mimic your PATH, so when you set your PATH=/directory, you'll
still be able to run any of the commands that were in your path previously. Behind
the scenes, fuse-colors hands out mini perl scripts for any file requested. It
shells out to the command requested (the "filename"), appending lolcat. fuse-colors
respects all arguments passed and allows for the shell to continue using built-ins
and so on.

Unfortunately, running vim with an automatic pipe was not as pretty. On startup,
fuse-colors builds a list of binaries that have been linked to ncurses. Any
request for these files will be run without the " | lolcat" command.

=head1 DEPENDENCIES

fuse-colors depends on the Fuse module, the "objdump" command, and lolcat:

https://github.com/busyloop/lolcat

lolcat is like the `cat` command, except its output is very colorful. On Debian,
the dependencies can be installed by running:

	apt-get install libfuse-perl binutils
	gem install lolcat

Newer Ubuntu systems have a package for lolcat.

=head1 BUGS

I'm not aware of any outstanding bugs at this time, although there are parts of the
code I'd like to make more resilient. Properly daemonizing fuse-colors
may be helpful in the event that this turns out to be exciting for people. If you
ctrl-c out of fuse-colors, please note that you'll need to unmount the path you
specified originally before remounting.

=head1 AUTHOR

Stan Schwertly (http://www.schwertly.com)

