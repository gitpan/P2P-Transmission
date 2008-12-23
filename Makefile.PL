use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> 'P2P::Transmission',
	VERSION_FROM	=> 'lib/P2P/Transmission.pm',
	PREREQ_PM	=> { JSON => 2,
                     MIME::Base64 => 3,
                     LWP::UserAgent => 2 },
    
	# following keywords are supported from 5.005
	($] >= 5.005 ?
		(ABSTRACT_FROM	=> 'lib/P2P/Transmission.pm',
		 AUTHOR		=> 'Brandon Gilmore <brandon@mg2.org>') : ())
);

