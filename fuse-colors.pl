#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use File::Which;
use Fuse;
use POSIX 'EINVAL';

my $mountpoint = shift || die "Usage: $0 /path/to/mount/at <template>";
$mountpoint =~ s|/$||;

# get a sane list of paths
my @paths = get_path();

# get a list of binaries that use ncurses
my $bad_list = get_curses(@paths);

# try to get a template from them, otherwise lolcat
my $command_template = shift;
unless ($command_template) {
	my $lolcat = get_lolcat();
	$command_template = "__command__ | $lolcat";
}
print "Going to be running the following command for most commands\n";
print "\t$command_template\n";
print "Mounting now. Go ahead and use fuse-colors!\n";

# mount the needful
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
	my $result = _get_executable_script($file);

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
	my $filename = _filename_fixup(shift);

	my $size = length(_get_executable_script($filename));

	# dev,ino,modes,nlink,uid,gid,rdev,size,atime,mtime,ctime,blksize,blocks
	if ($filename eq '/') {
		return (0, 0, 0040755, 1, 0, 0, 0, 0, 0, 0, 0, 4096, 0);
	} else {
		return (0, 0, 0100777, 1, 0, 0, 0, $size, 0, 0, 0, 4096, 0);
	}
}

sub fuse_readlink {
	my $path = shift;
	return $path;
}

sub fuse_getdir {
	# the refresh-ncurses-cache file can be read to regen the
	# list of bad files
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

	my $tool = _get_ncurses_tool() || return {};

	my @paths = @_ ;
	my @files;
	find( {
		wanted => sub {
			push @files, $File::Find::name;
		},
		preprocess => sub {
			# we only want binary executable files/links
			# since this strips dirs, it's maxdepth=1, which we want
			return grep { (-r -x $_) && (-f $_ || -l $_) } @_;
		},
	}, @paths);

	# do them all of them at once instead of spinning 1000+ procs
	open my $fh, '-|', "$tool->{location} $tool->{flags} " . join(' ', @files) . ' 2>&1';

	my $ret = {};

	# parse dat output
	my $current_cmd;
	while (my $line = <$fh>) {
		# actually got pretty lucky here since otool and ldd are identical in this regard
		if ($line =~ m|([^/]*?):$|) {
			$current_cmd = $1;
		} elsif ($line =~ /libncurses/) {
			$ret->{$current_cmd}++;
		}
	}

	print "List initialization finished, starting fuse mount\n";
	return $ret;
}

sub _get_executable_script {
	my $file = shift;

    # both scenarios use this part of the template
    my $result = qq{#!/usr/bin/perl
use strict;
use warnings;

my \$input = join(' ', \@ARGV);

exec qq!PATH='} . join(':', @paths) . "' ";

    (my $real_command = $command_template) =~ s/__command__/$file \$input/g;

    # if we're execing an ncurses binary, don't colorize it
    if (exists($bad_list->{$file})) {
        $result .= "$file \$input!;\n";
    } elsif ($file eq 'refresh-ncurses-cache') {
        $bad_list = get_curses(@paths);
        return 'finished';
    } else {
        $result .= qq{bash <<__BASH_END__
($real_command)
__BASH_END__!
};
    }

	return $result;
}

sub _get_ncurses_tool {
	my $tool;
	if ($^O eq 'linux') {
		$tool->{name} = 'ldd';
		$tool->{flags} = '';
	} elsif ($^O eq 'darwin') {
		$tool->{name} = 'otool';
		$tool->{flags} = '-L';
	} else {
		print "Can't determine your OS, so I can't guess which binaries use ncurses.\n";
		print "Continuing anyway, just don't use those binaries <3\n";
		return;
	}

	$tool->{location} = which($tool->{name});
	unless ($tool->{location}) {
		print "Can't find $tool->{name}, so I can't determine which binaries come with ncurses.\n";
		print "Continuing anyway, just don't use those binaries <3 \n";
		return;
	}
	return $tool;
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

		print STDERR "fuse-colors is going to use the following:\n";
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

=head1 Fuse-colors

fuse-colors.pl - automatically make most commands colorful

=begin HTML

<img src="http://i.imgur.com/z2d2jov.png" width="858" height="171" alt="fuse-colors" />

=end HTML

=head1 USAGE

	./fuse-colors.pl /tmp/fuse
	./fuse-colors.pl /tmp/fuse '__command__ && echo "haha"'

=head1 DESCRIPTION

This script helps you by automatically appending " | lolcat" to most commands.

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

fuse-colors optionally takes a second argument describing the command you
want to run when something is requested. "__command__" will be replaced with
the file of the thing being requested and any parameters to that command. It
tries to find "lolcat" if no template is passed.

=head1 DEPENDENCIES

fuse-colors depends on the Fuse module, ldd, and lolcat:

https://github.com/busyloop/lolcat

lolcat is like the `cat` command, except its output is very colorful. On Debian,
the dependencies can be installed by running:

	apt-get install fuse fuse-utils libfuse-perl libfile-which-perl
	gem install lolcat

Newer Ubuntu systems have a package for lolcat.

=head1 EXAMPLES

Get set up by making a directory and mounting fuse-colors there:

	mkdir /tmp/fuse
	./fuse-colors.pl /tmp/fuse
	# either in a new window, or after backgrounding fuse-colors:
	bash
	PATH=/tmp/fuse

You could technically keep your PATH on the end (PATH=/tmp/fuse:$PATH),
but it's less exciting that way. Then run whatever you'd normally run, or
whatever generates lots of pretty words.

	yes "this is awesome"
	ls -lha

You can force the ncurses cache to update by running (assuming your mount is /tmp/fuse):

	cat /tmp/fuse/refresh-ncurses-cache

You can make fuse-colors do anything you want. To automatically append "haha"
to the output of every command, start fuse-colors with something like:

	./fuse-colors.pl /tmp/fuse '__command__ && echo "haha"'

Here's a makeshift command-logger:

	./fuse-colors.pl ~/fuse 'echo "Command is: __command__" >> /tmp/commands.txt; __command__ | tee -a /tmp/commands.txt'

Be safe!

=head1 BUGS

I'm not aware of any outstanding bugs at this time, although there are parts
of the code I'd like to make more resilient. Properly daemonizing fuse-colors
may be helpful in the event that this turns out to be exciting for people.

If you ctrl-c out of fuse-colors, please note that you'll need to unmount the
path you specified originally before remounting. If you launched it as root,
you can just umount it, otherwise use 'fusermount -u'

=head1 AUTHOR

Stan Schwertly (http://www.schwertly.com)

