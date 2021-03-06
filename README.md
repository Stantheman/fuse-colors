# Fuse-colors

fuse-colors.pl - automatically make most commands colorful

<img src="http://i.imgur.com/z2d2jov.png" width="858" height="171" alt="fuse-colors" />

# USAGE

	./fuse-colors.pl /tmp/fuse
	./fuse-colors.pl /tmp/fuse '__command__ && echo "haha"'

# DESCRIPTION

This script helps you by automatically appending " | lolcat" to most commands.

I was in \#climagic on Freenode when "adprice" asked if there was a way to
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
want to run when something is requested. "\_\_command\_\_" will be replaced with
the file of the thing being requested and any parameters to that command. It
tries to find "lolcat" if no template is passed.

# DEPENDENCIES

fuse-colors depends on the Fuse module, ldd, and lolcat:

https://github.com/busyloop/lolcat

lolcat is like the \`cat\` command, except its output is very colorful. On Debian,
the dependencies can be installed by running:

	apt-get install fuse fuse-utils libfuse-perl libfile-which-perl
	gem install lolcat

Newer Ubuntu systems have a package for lolcat.

# EXAMPLES

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

# BUGS

I'm not aware of any outstanding bugs at this time, although there are parts
of the code I'd like to make more resilient. Properly daemonizing fuse-colors
may be helpful in the event that this turns out to be exciting for people.

If you ctrl-c out of fuse-colors, please note that you'll need to unmount the
path you specified originally before remounting. If you launched it as root,
you can just umount it, otherwise use 'fusermount -u'

# AUTHOR

Stan Schwertly (http://www.schwertly.com)
