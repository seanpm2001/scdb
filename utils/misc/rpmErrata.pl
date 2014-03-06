#!/usr/bin/perl
#
# Script to generate a template with one 'pkg_ronly' for each RPM present in
# the specified directory. Optionaly, this script can download the update RPMs
# from a specified location.
#
# Only the most recent version is inserted into the template.
#
# Arguments :
#    - Directory to process
#    - URL where to retrieve RPMs (optional)
#
# STDOUT must be redirected to produce the template.
#
# It is recommended to redirect STDERR to another file as it can produce a lot
# of output, especially if downloading is done at the same time.
#
# Common sources of RPM are :
#    - gLite 3.0 base : http://glitesoft.cern.ch/EGEE/gLite/APT/R3.0/rhel30/RPMS.Release3.0/
#    - gLite 3.0 external packages : http://glitesoft.cern.ch/EGEE/gLite/APT/R3.0/rhel30/RPMS.externals/
#    - gLite 3.0 updates : http://glitesoft.cern.ch/EGEE/gLite/APT/R3.0/rhel30/RPMS.updates/
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr> - 16/7/06
#
# FIXME : still pretty brute force, lacking error control...

use strict;

sub usage {
  print "usage:\trpmUpdates.pl rpm_directory\n";
  print "\n";
  print "STDOUT must be redirected to produce the template.\n";
  print "It is recommended to redirect STDERR to another file as it can produce a lot\n";
  print "of output, especially if downloading is done at the same time.\n";
  exit 0;
}

if ( @ARGV == 0 ) {
  usage();
}

my $repository = @ARGV[0];
my $source_url = undef;


# If a source URL has been specified, load RPMs (only new ones)
if ( defined($source_url) ) {
}

# Process each rpm present in the repository

opendir (REPOS, $repository) || die "Error opening directory $repository";
my @rpms = grep /\.rpm$/, readdir(REPOS);

my %pkglist;

print "# Template to add update RPMs to base configuration\n\n";
print "template rpms/errata;\n\n";

foreach my $rpm (@rpms) {
  print STDERR "Processing $rpm ...";
  my $rpminfo = qx%rpm -qp $repository/$rpm --queryformat '\%{name},\%{version},\%{release},\%{arch},\%{epoch}'%;
  #print STDERR "RPM = $rpminfo\n";
  chomp $rpminfo;
  my ($name, $version, $release, $arch, $epoch) = split /,/, $rpminfo;
  my $namearch = $name . "," . $arch;
  my $internal_name = "$name-$version-$release.$arch.rpm";
  unless ( "$internal_name" eq $rpm ) {
    print STDERR "RPM $rpm internal name ($internal_name) doesn't match RPM file name. Skipped.\n";
    next:
  }

  if ( !exists($pkglist{$namearch}) ) {
    print STDERR "added\n";
    $pkglist{$namearch} = $rpminfo;
  } else {
    my ($cname, $cversion, $crelease, $carch, $cepoch) = split /,/, $pkglist{$namearch};
    # Very ugly hack: compare versions through a python function
    # This should be replaced by RPM4::compare_evr()
    my $ans = qx{python -c "import rpmUtils.miscutils\nprint rpmUtils.miscutils.rangeCheck(('dummy', 'GT', ('$cepoch', '$cversion', '$crelease')), ('dummy', 'src', '$epoch', '$version', '$release'))\n"};
    chomp $ans;
    if ( $ans eq '1' ) {
      print STDERR "added newer version\n";
      $pkglist{$namearch} = $rpminfo;
    } else {
      print STDERR "skipped (newer version present)\n";
    }
  }
}

# Add an entry for the most recent version of every RPM, except kernel.
# Kernel version is defined explicitly in node configuration and must
# not be based on the last one available.
# Kernel modules are added for all possible kernel versions. This is not
# a problem as their name contains the kernel version used and
# will not match an already installed RPM if the kernel version used is not
# matching.

foreach my $namearch (sort(keys(%pkglist))) {
  my ($name, $version, $release, $arch, $epoch) = split /,/, $pkglist{$namearch};
  if ( $name =~ /^kernel(?!-module-)/ && $name !~ /^kernel-utils/ ) {
    print STDERR "Adding commented-out entry for kernel $name version $version-$release arch $arch\n";
    print "#'/software/packages'=pkg_ronly('$name','$version-$release','$arch','multi');\n";
  } else {
    print STDERR "Adding entry for $name version $version-$release arch $arch\n";
    print "'/software/packages'=pkg_ronly('$name','$version-$release','$arch');\n";
  }
}
