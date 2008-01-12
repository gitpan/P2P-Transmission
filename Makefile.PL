use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> 'P2P::Transmission',
	VERSION_FROM	=> 'lib/P2P/Transmission.pm',
	PREREQ_PM	=> { Convert::Bencode => 1.03,
                     IO::Socket::UNIX => 1.00 },
	# following keywords are supported from 5.005
	($] >= 5.005 ?
		(ABSTRACT_FROM	=> 'lib/P2P/Transmission.pm',
		 AUTHOR		=> 'Brandon Gilmore <brandon@mg2.org>') : ())
);

