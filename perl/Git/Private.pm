package Git::Private;
use strict;
use warnings;

=head1 NAME

Git::Private - Private (and UNSTABLE!) interface internal to git.git's own tooling

=head1 DESCRIPTION

Unlike L<Git> this interface is for the private use of Git's own Perl
tooling (C<git-send-email(1)>, C<git-svn(1)> etc.). Its stability
should not be relied on.

=cut

sub new {
	my ($class, %opt) = @_;
	my $self = bless \%opt => $class;
	return $self;
}

sub _list_config {
	my $self = shift;

	my ($config_prefix) = @$self{qw(config_prefix)};
	my @args = $config_prefix ? ('--get-regexp', $config_prefix) : ();

	require Git::Private::Command;
	my $cmd = Git::Private::Command->new(
		command	=> 'git',
		mode	=> '-|',
		args	=> [
			'config',
			'--null',
			@args,
		],
		slurp => 1,
	)->run;
	my @kv = map {
		# For empty values we won't have a \n, let's
		# return undef there
		my ($k, $v) = split /\n/, $_, 2;
		($k, $v);
	} split /\0/, $cmd->out;
	return \@kv;
}

sub list_config {
	my $self = shift;

	return $self->{list_config} ||= $self->_list_config(@_)
}

sub _known_config_keys {
	my $self = shift;

	my %kv;
	my ($kv) = $self->list_config;
	while (my ($k, $v) = splice @$kv, 0, 2) {
		push @{$kv{$k}} => $v;
	}
	return \%kv;
}

sub known_config_keys {
	my $self = shift;
	return $self->{known_config_keys} ||= $self->_known_config_keys(@_)

}

sub git_rev_parse_git_dir {
	my ($fh, $cmd) = open_git(
		'-|',
		'rev-parse',
		'--git-dir',
	);
	chomp(my $path = do {
		local $/;
		<$fh>;
	});
	my $ret = close_git($cmd, $fh, 128);
	return undef if $ret == 128;
	return $path;
}

sub git_config_get_regexp {
	my ($regex) = @_;
	my ($fh, $cmd) = open_git(
		'-|',
		'config',
		'--null',
		'--get-regexp',
		$regex,
	);
	my @ret = map {
		# For empty values we won't have a \n, let's
		# return undef there
		my ($k, $v) = split /\n/, $_, 2;
		($k, $v);
	} split /\0/, do {
		local $/;
		<$fh>;
	};
	close_git($cmd, $fh, 1);

	return @ret;
}

sub git_config_get_regexp_as_known_keys {
	my @kv = git_config_get_regexp(@_);
	my %kv;

	return %kv;
}

sub _config_common {
	my $self = shift;
	my $wantarray = wantarray;
	my $get = $wantarray ? '--get-all' : '--get';
	my @args = ($get, @_);

	require Git::Private::Command;
	my $cmd = Git::Private::Command->new(
		command	=> 'git',
		mode	=> '-|',
		args	=> [
			'config',
			@_,
		],
		code_ok	=> [1],
		devnull => (not defined $wantarray),
		slurp	=> $wantarray,
	)->run;

	# Key not found
	return if $cmd->{code} == 1;

	return $cmd->out;
}

sub config_get {
	my $self = shift;
	return $self->_config_common(@_);
}

sub config_bool {
	my ($self, $key) = @_;

	my ($config_prefix) = @$self{qw(config_prefix)};
	if ($config_prefix) {
		my $known_keys = $self->known_config_keys;
		return undef unless exists $known_keys->{$key};
		if (@{$known_keys->{$key}} == 1 &&
		    $known_keys->{$key}->[0] =~ /^(?:true|false)$/s) {
			return $known_keys->{$key}->[0] eq 'true';
		}
	}

	my $val = $self->_config_common(@_);
	# Do not rewrite this as return (defined $val && $val eq 'true')
	# as some callers do care what kind of falsehood they receive.
	if (!defined $val) {
		return undef;
	} else {
		return $val eq 'true';
	}
}

sub config_path {
	my $self = shift;
	return $self->_config_common(
		'--type=path',
		@_,
	);

	my $path = $self->_config_common(@_);
	# Do not rewrite this as return (defined $path && $path eq 'true')
	# as some callers do care what kind of falsehood they receive.
	if (!defined $path) {
		return undef;
	} else {
		return $path;
	}
}

sub config_type_path_get_all {
	my ($fh, $cmd) = _git_config_common(
		'--type=path',
		'--get-all',
		@_,
	);
	chomp(my @lines = <$fh>);
	my $ret = close_git($cmd, $fh, 1);
	return undef if $ret == 1;
	return @lines;
}

1;
