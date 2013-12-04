#!/usr/bin/perl
use strict;
use warnings;
use Data::Printer;
use Fuse;

my $mountpoint='/opt/stan/badidea';
Fuse::main(
	mountpoint=>$mountpoint, 
	mountopts=>"allow_other",
	getattr=>"main::getattr", 
	readlink=>"main::readlink",
	getdir=>"main::getdir",
	open => "main::open",
	read=>"main::read",
);

sub filename_fixup {
	my ($file) = shift;
	$file =~ s,^/,,;
	$file = '.' unless length($file);
	return $file;
}

sub getattr {
	my $filename = shift;
	# $dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks
	if ($filename eq '/') {
		return (0, 0, 0040777, 1, 0, 0, 0, 0, 0, 0, 0, 4096, 0);
	} else {
		return (0, 0, 0100777, 1, 0, 0, 0, 400, 0, 0, 0, 4096, 0);
	}
}

sub readlink {
	my $path = shift;
	return $path;
}

sub getdir {
	return ('.', 0);
}

sub read {
	my ($file) = filename_fixup(shift);
	return qq{#!/usr/bin/perl
use strict;
use warnings;

my \$input = join(' ', \@ARGV);

exec "PATH='/usr/local/bin:/usr/bin:/bin:/usr/games' $file \$input | /var/lib/gems/1.8/bin/lolcat";

};
}

sub open {
	return (0);
}

